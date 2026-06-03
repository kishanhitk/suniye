# MLX Gemma 4 Feasibility

Linear follow-up: [KIS-136](https://linear.app/kishan/issue/KIS-136/evaluate-mlx-native-gemma-4-backend-for-suniye-v2)

## Verdict

Keep Suniye v1 on `llama.cpp` with the pinned Gemma 4 `Q4_K_M` GGUF. Apple MLX is viable only as a v2 experiment with MLX-native artifacts; it is not a good path for running the tested `Q4_K_M` GGUF as-is.

## Tested Artifacts

### llama.cpp baseline

- Repo: `dahus/gemma-4-e2b-it-Q4_K_M-GGUF`
- File: `gemma-4-e2b-Q4_K_M.gguf`
- Local path: `~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf`
- Size: `3427873408` bytes
- SHA-256: `d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31`
- Local verification: size and SHA matched the pinned artifact.

### MLX baseline

- Repo: `mlx-community/gemma-4-e2b-it-4bit`
- Runtime: `mlx-vlm 0.6.0`
- Local snapshot size: `3613530663` bytes, about `3.37 GiB`
- First download took about `6m48s` through the Hugging Face cache.

## GGUF-As-Is Findings

The pinned GGUF should not be treated as an efficient MLX artifact.

- MLX's documented GGUF example supports only `Q4_0`, `Q4_1`, and `Q8_0` directly.
- Unsupported GGUF quantizations are cast to `float16`; `Q4_K_M` is outside the supported direct set.
- Installed `mlx-lm 0.31.3` did not load the standalone GGUF directly. It treated the file path as an MLX model directory and failed looking for `config.json`.

Source: https://github.com/ml-explore/mlx-examples/blob/main/llms/gguf_llm/README.md

## Benchmark Setup

Benchmark harness: `benchmarks/local_llm/run_bench.py`

Results:

- Markdown: `benchmarks/local_llm/results/latest.md`
- JSON: `benchmarks/local_llm/results/latest.json`
- Logs: `benchmarks/local_llm/results/logs/`

Machine:

- Apple M5 MacBook Air
- 24 GB RAM
- macOS 26.6
- Python 3.14.5

Method:

- OpenAI-compatible streaming `/v1/chat/completions`
- Suniye Magic Format transcript prompt
- `max_tokens=128`
- `ctx_size=4096`
- one warmup request, three measured requests

## Results

| Backend | Artifact | Startup | Median TTFT | Median total | End-to-end tok/s | Memory |
|---|---|---:|---:|---:|---:|---:|
| llama.cpp | `gemma-4-e2b-Q4_K_M.gguf` | `7.41s` cold-ish Metal load | `0.06s` | `0.37s` | `62.28` | `3508 MB` RSS / `3822 MiB` Metal log |
| MLX-VLM | `mlx-community/gemma-4-e2b-it-4bit` | `2.56s` cached | `0.39s` | `0.75s` | `40.14` | `4.53 GB` peak from MLX timings |

Nuance: MLX's raw decode speed was competitive, about `81 tok/s` in server timings versus llama.cpp's `73-76 tok/s`. llama.cpp still won warm end-to-end latency because it reused the long Magic Format system prompt via prompt cache after warmup (`cache_n=615`).

## Quality Findings

llama.cpp followed the Magic Format prompt well:

```text
Hey Alex, can you review the pricing doc and send me the final number?
```

MLX E2B 4-bit often preserved spoken punctuation:

```text
hey alex comma can you review the pricing doc and send me the final number
```

MLX handled the list prompt better, but still retained dictation lead-in text:

```text
make this a bullet list:
- check microphone permission
- download the model
- hold the hotkey and dictate
- paste the result
```

Quality is currently the bigger blocker than speed for Suniye.

## Alternative MLX Artifacts to Test

- `mlx-community/gemma-4-e2b-it-5bit`
- `mlx-community/gemma-4-e2b-it-6bit`
- `mlx-community/gemma-4-e2b-it-8bit`
- `mlx-community/gemma-4-e4b-it-4bit`

Sources:

- https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit
- https://huggingface.co/mlx-community/gemma-4-e2b-it-5bit
- https://huggingface.co/mlx-community/gemma-4-e2b-it-6bit
- https://huggingface.co/mlx-community/gemma-4-e2b-it-8bit
- https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit
- https://huggingface.co/dahus/gemma-4-e2b-it-Q4_K_M-GGUF

## Recommendation

1. Keep llama.cpp as the v1 Local Gemma backend.
2. Do not attempt to reuse the pinned `Q4_K_M` GGUF through MLX.
3. Treat MLX as v2-only and benchmark MLX-native `5bit`, `6bit`, and E4B variants before designing an app provider.
4. If MLX quality becomes acceptable, prototype a feature-flagged provider that launches `python -m mlx_vlm.server` and talks to its OpenAI-compatible endpoint.
5. Revisit Swift-native MLX later; current public `mlx-swift` tracking indicates Gemma 4 is not registered/supported yet.

Sources:

- https://github.com/Blaizzy/mlx-vlm
- https://github.com/ml-explore/mlx-swift/issues/389
