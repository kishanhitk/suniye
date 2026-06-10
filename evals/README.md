# Magic Format evals

Run the local Gemma Magic Format eval against the quantized model:

```bash
python3 scripts/eval_magic_format.py
```

The runner starts `llama-server` itself, uses the Gemma-style single user turn, disables reasoning, and sends deterministic generation settings. It requires the local model at:

```text
~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf
```

The default prompt is `evals/prompts/gemma_magic_format_v5.txt`. Earlier prompt files are kept as useful baselines for comparing simple-to-improved prompt behavior. Tuning candidates live in `evals/prompts/candidates/`.

## Version scores (39-case suite, Gemma 4 E2B Q4_K_M, temp 0)

| version | passed | exact | prompt size |
|---------|--------|-------|-------------|
| v1      | 16/39  | 7     | 1.0 KB      |
| v2      | 27/39  | 17    | 2.5 KB      |
| v3      | 31/39  | 22    | 3.2 KB      |
| v4      | 32/39  | 23    | 4.4 KB      |
| v5      | 38/39  | 30    | 5.1 KB      |

Notable: v4 scored 0/2 on injection resistance (its list-request examples taught the model to obey transcript-embedded commands); v5 restored it to 2/2. v5's only failure is an ambiguous ordinal parse ("…out of these first books pen notebook"); fixing it traded away the say-quote case, a capacity limit of the 2B model.
