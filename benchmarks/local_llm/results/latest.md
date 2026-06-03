# Local LLM Backend Benchmark Results

- Created: `2026-06-03T17:59:12+0530`
- Machine: `macOS-26.6-arm64-arm-64bit-Mach-O`
- CPU: `Apple M5`
- RAM: `24.0 GB`
- Python: `3.14.5`

## Models

- `llama_gguf`: `3.19 GiB`
  - path: `/Users/kishan/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf`
  - sha256: `d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31`
  - matches pinned artifact: `True`
- `mlx_native`: `3.37 GiB`
  - repo: `mlx-community/gemma-4-e2b-it-4bit`

## Summary

| Backend | Startup | Median TTFT | Median Total | Median tok/s | Median RSS |
|---|---:|---:|---:|---:|---:|
| llama_cpp_q4_k_m_gguf | 7.41s | 0.06s | 0.37s | 62.28 | 3508 MB |
| mlx_vlm_e2b_4bit | 2.56s | 0.39s | 0.75s | 40.14 | 4158 MB |

## Samples

### llama_cpp_q4_k_m_gguf

- `warmup` `short_cleanup`: TTFT `1.02s`, total `1.26s`, tokens `17`, tok/s `13.47`, RSS `3508 MB`
  - output: `Hey Alex, can you review the pricing doc and send me the final number?`
- `run` `medium_email`: TTFT `0.07s`, total `0.59s`, tokens `38`, tok/s `64.24`, RSS `3508 MB`
  - output: `Hi Maya, quick update from the call today. We should keep the launch copy short, mention local transcription, and avoid promising cloud sync. Can you send the revised draft by Friday?`
- `run` `list_format`: TTFT `0.06s`, total `0.37s`, tokens `23`, tok/s `62.28`, RSS `3508 MB`
  - output: `- check microphone permission - download the model - hold the hotkey and dictate - paste the result`
- `run` `short_cleanup`: TTFT `0.06s`, total `0.28s`, tokens `17`, tok/s `60.39`, RSS `3508 MB`
  - output: `Hey Alex, can you review the pricing doc and send me the final number?`

### mlx_vlm_e2b_4bit

- `warmup` `short_cleanup`: TTFT `0.43s`, total `0.61s`, tokens `16`, tok/s `26.08`, RSS `4158 MB`
  - output: `hey alex comma can you review the pricing doc and send me the final number`
- `run` `medium_email`: TTFT `0.41s`, total `0.87s`, tokens `39`, tok/s `44.58`, RSS `4158 MB`
  - output: `new paragraph hi maya comma quick update from the call today period we should keep the launch copy short comma mention local transcription comma and avoid promising cloud sync period can you send the revised draft by friday`
- `run` `list_format`: TTFT `0.39s`, total `0.75s`, tokens `30`, tok/s `40.14`, RSS `4158 MB`
  - output: `make this a bullet list: - check microphone permission - download the model - hold the hotkey and dictate - paste the result`
- `run` `short_cleanup`: TTFT `0.39s`, total `0.58s`, tokens `16`, tok/s `27.60`, RSS `4158 MB`
  - output: `hey alex comma can you review the pricing doc and send me the final number`

