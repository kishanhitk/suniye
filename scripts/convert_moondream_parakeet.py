#!/usr/bin/env python3
"""Convert Moondream's Parakeet Ultra / Redux checkpoints into the sherpa-onnx NeMo
transducer layout (encoder/decoder/joiner ONNX + tokens.txt) that the app already
runs for Parakeet TDT 0.6B v3.

Both checkpoints are NVIDIA's parakeet-tdt-0.6b-v3 architecture saved with Hugging
Face transformers' `ParakeetForTDT` tensor names. Redux additionally stores every
encoder Linear and pointwise conv as ternary codes (`thrush-ternary-v2`, documented
in its `ternary.json`): w = scale[row, col // 128] * (code - 1).

Pipeline:
  1. Restore NVIDIA's v3 `.nemo` for the module tree, featurizer and vocabulary.
  2. Rename the checkpoint back to NeMo names (inverse of transformers'
     `convert_nemo_to_hf.py`) and load it with strict=True. Redux is dequantized
     for the load, which is exact.
  3. Export encoder/decoder/joiner the way sherpa-onnx exports v3
     (scripts/nemo/parakeet-tdt-0.6b-v3/export_onnx.py), with the same metadata.
  4. Quantize the encoder to com.microsoft.MatMulNBits (block 128, int8 compute):
     Redux's ternary weights become exact 4-bit blocks built from the checkpoint's
     own codes and scales; every other encoder matrix becomes symmetric 8-bit. The
     decoder and joiner get upstream v3's dynamic int8 recipe.
  5. Check the quantized encoder against the PyTorch encoder on real audio, decode
     the clip with sherpa-onnx, and write a manifest with sizes and SHA-256s.

The app bundles ONNX Runtime 1.23.2, whose CPU MatMulNBits kernel supports 4 and
8 bits only, so the 2-bit packing that would halve Redux again cannot run there.

Setup (Python 3.12):
    pip install -r scripts/convert_moondream_parakeet.requirements.txt

    python scripts/convert_moondream_parakeet.py --variant ultra \
        --nemo parakeet-tdt-0.6b-v3.nemo --wav en.wav --out-dir build/parakeet-ultra
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import shutil
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import onnx
import soundfile
import torch
from onnx import helper, numpy_helper
from onnxruntime.quantization import QuantType, quantize_dynamic
from safetensors.torch import load_file

BLOCK_SIZE = 128
# NVIDIA's parakeet-tdt-0.6b-v3 tokenizer.json; both Moondream checkpoints ship it
# byte for byte, which is what lets tokens.txt come from the v3 vocabulary.
V3_TOKENIZER_SHA256 = "bd321b096832a3f270bd3b2a88823957920f1a5c5ada71114a26ea729d0cbe91"


@dataclass(frozen=True)
class Variant:
    repo: str
    revision: str
    ternary: bool


VARIANTS = {
    "ultra": Variant("moondream/parakeet-ultra", "73175eb7aeb0d82f1e2a6b53b3aabc10a90bcd0b", ternary=False),
    "redux": Variant("moondream/parakeet-redux", "2bf128600aac4b16946f7ed8372e56117fe5e23b", ternary=True),
}

# Inverse of NEMO_TO_HF_WEIGHT_MAPPING + NEMO_TDT_WEIGHT_MAPPING in transformers'
# models/parakeet/convert_nemo_to_hf.py. Dot-anchored so `relative_k_proj` can
# never be caught by the `k_proj` rule.
HF_TO_NEMO = [
    (r"^encoder\.subsampling\.layers\.", "encoder.pre_encode.conv."),
    (r"^encoder\.subsampling\.linear\.", "encoder.pre_encode.out."),
    (r"^(encoder\.layers\.\d+\.conv)\.norm\.", r"\1.batch_norm."),
    (r"\.relative_k_proj\.", ".linear_pos."),
    (r"\.q_proj\.", ".linear_q."),
    (r"\.k_proj\.", ".linear_k."),
    (r"\.v_proj\.", ".linear_v."),
    (r"\.o_proj\.", ".linear_out."),
    (r"\.bias_([uv])$", r".pos_bias_\1"),
    (r"^decoder\.embedding\.", "decoder.prediction.embed."),
    (r"^decoder\.lstm\.", "decoder.prediction.dec_rnn.lstm."),
    (r"^decoder\.decoder_projector\.", "joint.pred."),
    (r"^encoder_projector\.", "joint.enc."),
    (r"^joint\.head\.", "joint.joint_net.2."),
]
# Photon's voice-activity head: no counterpart in the NeMo graph, unused by sherpa.
DROPPED_PREFIXES = ("vad_head.",)
# The mel featurizer is not in the Moondream checkpoints; v3's is used unchanged.
FEATURIZER_KEYS = ("preprocessor.featurizer.window", "preprocessor.featurizer.fb")


def hf_download(variant: Variant, filename: str, cache_dir: Path) -> Path:
    path = cache_dir / variant.repo.replace("/", "--") / variant.revision / filename
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://huggingface.co/{variant.repo}/resolve/{variant.revision}/{filename}"
        print(f"downloading {url}")
        partial = path.with_suffix(path.suffix + ".partial")
        with urllib.request.urlopen(url) as response, open(partial, "wb") as out:
            shutil.copyfileobj(response, out)
        partial.rename(path)
    return path


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# Checkpoint loading


@dataclass(frozen=True)
class TernaryWeight:
    codes: np.ndarray  # uint8 [out, in], values 0/1/2 meaning -1/0/+1
    scales: np.ndarray  # float32 [out, in // BLOCK_SIZE]

    def dequantized(self) -> np.ndarray:
        return self.scales.repeat(BLOCK_SIZE, axis=1) * (self.codes.astype(np.float32) - 1)


def unpack_ternary(qweight: np.ndarray, in_features: int) -> np.ndarray:
    """Base-3 digits, five per byte, least significant first (ternary.json `packing`)."""
    digits = np.empty((qweight.shape[0], qweight.shape[1] * 5), dtype=np.uint8)
    value = qweight.astype(np.uint16)
    for i in range(5):
        digits[:, i::5] = value % 3
        value //= 3
    return digits[:, :in_features]


def load_checkpoint(variant: Variant, cache_dir: Path) -> tuple[dict[str, torch.Tensor], dict[str, TernaryWeight]]:
    """Returns float32 tensors under HF names plus, for Redux, the raw ternary weights."""
    tokenizer = hf_download(variant, "tokenizer.json", cache_dir)
    if sha256_of(tokenizer) != V3_TOKENIZER_SHA256:
        raise SystemExit(f"{variant.repo} tokenizer differs from parakeet-tdt-0.6b-v3; tokens.txt would be wrong")

    tensors = load_file(hf_download(variant, "model.safetensors", cache_dir))
    ternary: dict[str, TernaryWeight] = {}
    if variant.ternary:
        manifest = json.loads(hf_download(variant, "ternary.json", cache_dir).read_text())
        if manifest["format"] != "thrush-ternary-v2" or manifest["quant"]["group_size"] != BLOCK_SIZE:
            raise SystemExit(f"unsupported ternary format: {manifest['format']} / {manifest['quant']}")
        for module in manifest["quantized_modules"]:
            name = module["name"]
            weight = TernaryWeight(
                codes=unpack_ternary(tensors.pop(f"{name}.qweight").numpy(), module["in_features"]),
                scales=tensors.pop(f"{name}.scales").float().numpy(),
            )
            if weight.codes.shape != (module["out_features"], module["in_features"]) or weight.codes.max() > 2:
                raise SystemExit(f"{name}: unexpected ternary payload")
            dense = torch.from_numpy(weight.dequantized())
            tensors[f"{name}.weight"] = dense.unsqueeze(-1) if module["as_conv1d"] else dense
            ternary[name] = weight

    stray = [key for key in tensors if key.endswith((".qweight", ".scales"))]
    if stray:
        raise SystemExit(f"ternary tensors not listed in ternary.json: {stray[:5]}")
    return {key: value.float() if value.is_floating_point() else value for key, value in tensors.items()}, ternary


def nemo_name(hf_name: str) -> str:
    for pattern, replacement in HF_TO_NEMO:
        hf_name = re.sub(pattern, replacement, hf_name)
    return hf_name


def load_into_nemo(model, hf_tensors: dict[str, torch.Tensor]) -> None:
    reference = model.state_dict()
    state = {nemo_name(k): v for k, v in hf_tensors.items() if not k.startswith(DROPPED_PREFIXES)}
    for key in FEATURIZER_KEYS:
        state[key] = reference[key]

    missing = sorted(set(reference) - set(state))
    unexpected = sorted(set(state) - set(reference))
    mismatched = sorted(k for k in set(state) & set(reference) if state[k].shape != reference[k].shape)
    if missing or unexpected or mismatched:
        raise SystemExit(f"name mapping failed: missing={missing[:5]} unexpected={unexpected[:5]} shape={mismatched[:5]}")
    model.load_state_dict(state, strict=True)


# ---------------------------------------------------------------------------
# Export


class PointwiseAsLinear(torch.nn.Module):
    """A kernel-1 Conv1d over [B, C, T] written as a Linear over C, so it exports as
    MatMul and gets block-quantized like every other encoder matrix."""

    def __init__(self, conv: torch.nn.Conv1d):
        super().__init__()
        if conv.kernel_size != (1,) or conv.groups != 1 or conv.bias is not None:
            raise SystemExit(f"not a bias-free pointwise conv: {conv}")
        self.weight = torch.nn.Parameter(conv.weight.detach()[:, :, 0].clone())

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return torch.nn.functional.linear(x.transpose(1, 2), self.weight).transpose(1, 2)


def pointwise_convs_as_linear(model) -> None:
    for layer in model.encoder.layers:
        layer.conv.pointwise_conv1 = PointwiseAsLinear(layer.conv.pointwise_conv1)
        layer.conv.pointwise_conv2 = PointwiseAsLinear(layer.conv.pointwise_conv2)


def export(model, work_dir: Path) -> None:
    """sherpa-onnx's v3 recipe: NeMo's own per-module ONNX export."""
    with torch.no_grad():
        model.encoder.export(str(work_dir / "encoder.onnx"))
        model.decoder.export(str(work_dir / "decoder.onnx"))
        model.joint.export(str(work_dir / "joiner.onnx"))


def sherpa_metadata(model, variant: Variant) -> dict[str, str]:
    """The keys sherpa-onnx reads from a NeMo transducer encoder, valued as upstream v3."""
    normalize_type = model.cfg.preprocessor.normalize
    return {
        "vocab_size": str(model.decoder.vocab_size),
        "normalize_type": "" if normalize_type == "NA" else normalize_type,
        "pred_rnn_layers": str(model.decoder.pred_rnn_layers),
        "pred_hidden": str(model.decoder.pred_hidden),
        "subsampling_factor": "8",
        "model_type": "EncDecRNNTBPEModel",
        "version": "2",
        "model_author": "Moondream (post-train of NVIDIA parakeet-tdt-0.6b-v3)",
        # sherpa-onnx decides TDT vs plain RNN-T by looking for "tdt" in this URL
        # (offline-transducer-nemo-model.cc); without it the recognizer refuses the
        # 8198-wide joiner and exits the process. It names the architecture, so the
        # weights' own source goes in weights_url.
        "url": "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3",
        "weights_url": f"https://huggingface.co/{variant.repo}/tree/{variant.revision}",
        "comment": "Converted by Suniye scripts/convert_moondream_parakeet.py; only the transducer branch is exported",
        "feat_dim": "128",
    }


def write_tokens(model, path: Path) -> None:
    vocabulary = list(model.joint.vocabulary)
    lines = [f"{piece} {index}" for index, piece in enumerate(vocabulary)]
    lines.append(f"<blk> {len(vocabulary)}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Quantization


def pack_nbits(levels: np.ndarray, bits: int) -> np.ndarray:
    """uint8 levels [N, K] -> MatMulNBits B [N, K / BLOCK_SIZE, BLOCK_SIZE * bits / 8],
    element k of a byte group in the low bits first."""
    per_byte = 8 // bits
    n, k = levels.shape
    grouped = levels.reshape(n, k // per_byte, per_byte).astype(np.uint16)
    packed = np.zeros(grouped.shape[:2], dtype=np.uint16)
    for i in range(per_byte):
        packed |= grouped[:, :, i] << (bits * i)
    return packed.astype(np.uint8).reshape(n, k // BLOCK_SIZE, BLOCK_SIZE * bits // 8)


def ternary_blocks(weight: TernaryWeight) -> tuple[np.ndarray, np.ndarray, int]:
    # MatMulNBits' default 4-bit zero point is 8, so level = code + 7 decodes to code - 1.
    return pack_nbits(weight.codes + 7, 4), weight.scales, 4


def symmetric_int8_blocks(weight_nk: np.ndarray) -> tuple[np.ndarray, np.ndarray, int]:
    n, k = weight_nk.shape
    blocks = weight_nk.reshape(n, k // BLOCK_SIZE, BLOCK_SIZE)
    scales = np.abs(blocks).max(axis=2) / 127
    safe = np.where(scales == 0, 1, scales)
    levels = np.clip(np.rint(blocks / safe[:, :, None]), -127, 127) + 128  # default zero point 128
    return pack_nbits(levels.reshape(n, k).astype(np.uint8), 8), scales.astype(np.float32), 8


def quantize_encoder(src: Path, dst: Path, ternary: dict[str, TernaryWeight], metadata: dict[str, str]) -> None:
    model = onnx.load(str(src))
    graph = model.graph
    initializers = {init.name: init for init in graph.initializer}
    # Redux weights are found by value: the exporter renames and transposes them, but
    # the dequantized float32 bits survive unchanged.
    by_content = {weight.dequantized().T.tobytes(): (name, weight) for name, weight in ternary.items()}
    matched: set[str] = set()
    counts = {4: 0, 8: 0}

    for index, node in enumerate(graph.node):
        if node.op_type != "MatMul" or node.input[1] not in initializers:
            continue
        weight_kn = numpy_helper.to_array(initializers[node.input[1]])
        if weight_kn.ndim != 2 or weight_kn.shape[0] % BLOCK_SIZE:
            continue
        k, n = weight_kn.shape
        hit = by_content.get(np.ascontiguousarray(weight_kn, dtype=np.float32).tobytes())
        if hit:
            matched.add(hit[0])
            packed, scales, bits = ternary_blocks(hit[1])
        else:
            packed, scales, bits = symmetric_int8_blocks(weight_kn.T)
        counts[bits] += 1

        prefix = node.name or f"matmul_{index}"
        graph.initializer.extend([
            numpy_helper.from_array(packed, f"{prefix}.q{bits}"),
            numpy_helper.from_array(scales.reshape(-1).astype(np.float32), f"{prefix}.scales"),
        ])
        graph.node[index].CopyFrom(helper.make_node(
            "MatMulNBits",
            [node.input[0], f"{prefix}.q{bits}", f"{prefix}.scales"],
            list(node.output),
            name=prefix,
            domain="com.microsoft",
            K=k, N=n, bits=bits, block_size=BLOCK_SIZE, accuracy_level=4,
        ))

    if set(ternary) != matched:
        raise SystemExit(f"ternary weights not found in the exported encoder: {sorted(set(ternary) - matched)[:5]}")

    used = {name for node in graph.node for name in node.input}
    kept = [init for init in graph.initializer if init.name in used]
    del graph.initializer[:]
    graph.initializer.extend(kept)
    if not any(opset.domain == "com.microsoft" for opset in model.opset_import):
        model.opset_import.append(helper.make_opsetid("com.microsoft", 1))
    set_metadata(model, metadata)
    onnx.save(model, str(dst))
    print(f"encoder: {counts[4]} ternary 4-bit, {counts[8]} 8-bit MatMulNBits")


def set_metadata(model: onnx.ModelProto, metadata: dict[str, str]) -> None:
    del model.metadata_props[:]
    for key, value in metadata.items():
        model.metadata_props.add(key=key, value=value)


# ---------------------------------------------------------------------------
# Verification


def load_audio(path: Path, sample_rate: int) -> np.ndarray:
    import librosa

    samples, rate = soundfile.read(str(path), dtype="float32", always_2d=True)
    return librosa.resample(samples.mean(axis=1), orig_sr=rate, target_sr=sample_rate)


def check_encoder(model, encoder_path: Path, wav: Path) -> None:
    import onnxruntime

    audio = torch.from_numpy(load_audio(wav, model.cfg.preprocessor.sample_rate))[None]
    with torch.no_grad():
        features, length = model.preprocessor(input_signal=audio, length=torch.tensor([audio.shape[1]]))
        expected, _ = model.encoder(audio_signal=features, length=length)
    session = onnxruntime.InferenceSession(str(encoder_path), providers=["CPUExecutionProvider"])
    actual = session.run(None, {"audio_signal": features.numpy(), "length": length.numpy()})[0]

    a, b = expected.numpy().ravel(), actual.ravel()
    cosine = float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))
    print(f"encoder vs PyTorch on {wav.name}: cosine={cosine:.5f}")
    if cosine < 0.99:
        raise SystemExit("quantized encoder diverges from the PyTorch encoder")


def decode_with_sherpa(out_dir: Path, wav: Path) -> str:
    import sherpa_onnx

    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(out_dir / "encoder.onnx"),
        decoder=str(out_dir / "decoder.onnx"),
        joiner=str(out_dir / "joiner.onnx"),
        tokens=str(out_dir / "tokens.txt"),
        model_type="nemo_transducer",
        num_threads=4,
    )
    stream = recognizer.create_stream()
    stream.accept_waveform(16_000, load_audio(wav, 16_000))
    recognizer.decode_stream(stream)
    return stream.result.text.strip()


def write_manifest(out_dir: Path, variant: Variant) -> None:
    files = {
        path.name: {"bytes": path.stat().st_size, "sha256": sha256_of(path)}
        for path in sorted(out_dir.iterdir())
        if path.name in ("encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt")
    }
    manifest = {"source": f"https://huggingface.co/{variant.repo}/tree/{variant.revision}", "files": files}
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for name, info in files.items():
        print(f"{name}: {info['bytes']} bytes sha256={info['sha256']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--variant", choices=sorted(VARIANTS), required=True)
    parser.add_argument("--nemo", type=Path, required=True, help="nvidia/parakeet-tdt-0.6b-v3 .nemo archive")
    parser.add_argument("--wav", type=Path, required=True, help="speech clip for the parity check")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--cache-dir", type=Path, default=Path.home() / ".cache" / "suniye-parakeet-conversion")
    args = parser.parse_args()

    import nemo.collections.asr as nemo_asr
    from nemo.utils import logging as nemo_logging

    nemo_logging.setLevel(logging.ERROR)
    variant = VARIANTS[args.variant]
    hf_tensors, ternary = load_checkpoint(variant, args.cache_dir)
    model = nemo_asr.models.ASRModel.restore_from(str(args.nemo), map_location="cpu")
    model.eval()
    load_into_nemo(model, hf_tensors)
    pointwise_convs_as_linear(model)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        export(model, work)
        quantize_encoder(work / "encoder.onnx", args.out_dir / "encoder.onnx", ternary, sherpa_metadata(model, variant))
        for part in ("decoder", "joiner"):
            quantize_dynamic(
                model_input=str(work / f"{part}.onnx"),
                model_output=str(args.out_dir / f"{part}.onnx"),
                weight_type=QuantType.QInt8,
            )
    write_tokens(model, args.out_dir / "tokens.txt")

    check_encoder(model, args.out_dir / "encoder.onnx", args.wav)
    print(f"sherpa-onnx transcript: {decode_with_sherpa(args.out_dir, args.wav)}")
    write_manifest(args.out_dir, variant)


if __name__ == "__main__":
    main()
