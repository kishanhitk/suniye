# Magic Format evals

Run the local Gemma Magic Format eval against the quantized model:

```bash
python3 scripts/eval_magic_format.py
```

The runner starts `llama-server` itself, uses the Gemma-style single user turn, disables reasoning, and sends deterministic generation settings. It requires the local model at:

```text
~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf
```

The default prompt is `evals/prompts/gemma_magic_format_v4.txt`. Earlier prompt files are kept as useful baselines for comparing simple-to-improved prompt behavior.
