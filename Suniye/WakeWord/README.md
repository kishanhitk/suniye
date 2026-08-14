# Wake-word and VAD models

Bundled as a folder reference (see `project.yml`).

- `kws-*`: sherpa-onnx keyword spotting, zipformer, English, int8.
  Source: sherpa-onnx release `kws-models`,
  package `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01` (Apache-2.0).
- `silero_vad.onnx`: Silero VAD v4 from the sherpa-onnx `asr-models` release (MIT).

The keyword list for "Hey Suniye" is code, not data: see `WakeWordDetector.swift`.
Keyword token sequences were precomputed with the model's `bpe.model`.
