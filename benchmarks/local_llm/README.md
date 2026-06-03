# Local LLM Backend Benchmark

Benchmarks Suniye-shaped Magic Format requests against:

- `llama-server` with the pinned GGUF model at `~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf`
- `mlx_vlm.server` with `mlx-community/gemma-4-e2b-it-4bit`

The runner measures server startup separately from request latency, sends OpenAI-compatible streaming chat completions, and writes JSON plus Markdown results.

```bash
python3 -m venv .bench-venv
.bench-venv/bin/python -m pip install -r benchmarks/local_llm/requirements.txt
.bench-venv/bin/python benchmarks/local_llm/run_bench.py --backend both --runs 3 --warmups 1
```

The first MLX run downloads the model into the Hugging Face cache. Download time is not counted as server startup time.
