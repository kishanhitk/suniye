# Gemma 4 MLX Feasibility for Suniye

Linear follow-up: [KIS-136](https://linear.app/kishan/issue/KIS-136/evaluate-mlx-native-gemma-4-backend-for-suniye-v2)

## Verdict

Keep v1 on `llama.cpp` with the pinned `Q4_K_M` GGUF. MLX is viable as a v2 experiment only with MLX-native artifacts, not with the tested GGUF as-is.

## Local Benchmark

Machine: Apple M5 MacBook Air, 24 GB RAM, macOS 26.6.

Harness: `benchmarks/local_llm/run_bench.py`, using OpenAI-compatible streaming `/v1/chat/completions`, one warmup, three measured Suniye Magic Format prompts, `max_tokens=128`, `ctx_size=4096`.

Results: `benchmarks/local_llm/results/latest.md` and `latest.json`.

| Backend | Artifact | Size | Startup | Median TTFT | Median Total | Median End-to-End tok/s | Peak Memory |
|---|---:|---:|---:|---:|---:|---:|---:|
| llama.cpp | `gemma-4-e2b-Q4_K_M.gguf` | 3.19 GiB | 7.41s cold-ish Metal load | 0.06s warm | 0.37s | 62.28 | 3.51 GB RSS / 3.82 GiB Metal log |
| MLX-VLM | `mlx-community/gemma-4-e2b-it-4bit` | 3.37 GiB | 2.56s cached | 0.39s | 0.75s | 40.14 | 4.53 GB peak from MLX timings |

Important nuance: MLX's raw decode speed was slightly faster in server timings, about 81 tok/s versus llama.cpp's 73-76 tok/s, but llama.cpp's prompt cache reused the long Magic Format system prompt (`cache_n=615`) after warmup. That makes llama.cpp faster for Suniye's persistent-server workflow.

## Quality Notes

The llama.cpp GGUF followed the Magic Format prompt well:

`Hey Alex, can you review the pricing doc and send me the final number?`

The MLX-native E2B 4-bit artifact often preserved spoken punctuation instead of converting it:

`hey alex comma can you review the pricing doc and send me the final number`

MLX did handle the list prompt better, but still left the dictation lead-in:

`make this a bullet list: ...`

This is a stronger blocker than speed for Suniye unless prompt tuning, a different quant, or a larger MLX artifact fixes quality.

## GGUF-As-Is Feasibility

The pinned GGUF is verified locally:

- Size: `3427873408` bytes
- SHA-256: `d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31`

The installed `mlx-lm 0.31.3` CLI does not load the GGUF file directly; it treats the path as an MLX model directory and fails looking for `config.json`.

Primary MLX GGUF docs say only `Q4_0`, `Q4_1`, and `Q8_0` are supported directly; unsupported quantizations are cast to `float16`. Since `Q4_K_M` is not in that supported set, running this GGUF through MLX would not preserve the tested quantized representation.

Source: https://github.com/ml-explore/mlx-examples/blob/main/llms/gguf_llm/README.md

## Alternative MLX Artifacts

- `mlx-community/gemma-4-e2b-it-4bit`: tested here, 3.37 GiB local snapshot, fastest viable MLX-native baseline.
- `mlx-community/gemma-4-e2b-it-5bit`: likely quality bump, larger artifact.
- `mlx-community/gemma-4-e2b-it-6bit` / `8bit`: progressively larger, worth testing only if 4-bit quality remains poor.
- `mlx-community/gemma-4-e4b-it-4bit`: larger model candidate if E2B quality is the blocker.
- OptiQ variants may be worth a later quality pass, but treat them as a separate dependency/runtime decision.

Sources:

- https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit
- https://huggingface.co/mlx-community/gemma-4-e2b-it-5bit
- https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit
- https://huggingface.co/dahus/gemma-4-e2b-it-Q4_K_M-GGUF

## V2 Path If MLX Remains Interesting

1. Keep llama.cpp as the v1 backend.
2. Add a feature-flagged MLX provider that shells out to `python -m mlx_vlm.server --model <model>`.
3. Do not bundle Python/MLX in v2 until quality beats or matches llama.cpp; start with a developer-only backend.
4. Benchmark `e2b 5bit`, `e2b 6bit`, and `e4b 4bit` against the same harness and prompts.
5. Re-check Swift-native feasibility later. Public `mlx-swift` tracking says Gemma 4 is not registered/supported in Swift MLX yet.

Sources:

- https://github.com/Blaizzy/mlx-vlm
- https://github.com/ml-explore/mlx-swift/issues/389
