# Runs

Raw LLM outputs. **Append-only** — never edit a file here. If a run was bad, record why and produce a new run with a new timestamp; do not overwrite.

## Layout

```
runs/
  {experiment_id}/
    {condition}/
      {case_id}__{run_index}__{timestamp}.json
```

Each output file should contain enough metadata to fully reconstruct the call without consulting the experiment config:

```json
{
  "experiment_id": "exp_001_persona",
  "condition": "persona",
  "prompt_id": "extract_v2_persona",
  "prompt_sha": "a1b2c3...",
  "case_id": "case_017",
  "run_index": 3,
  "model": "claude-opus-4-7",
  "temperature": 0.0,
  "seed": 20260501,
  "timestamp": "2026-05-01T14:22:01Z",
  "input": "...",
  "output": "...",
  "usage": {"input_tokens": 1234, "output_tokens": 567}
}
```

The `prompt_sha` lets you detect (and reject) any case where the prompt file was edited after the run.

## Size

If output volume gets large, consider gitignoring `runs/**/*.json` and committing only a per-experiment `summary.csv`. Decide before the directory grows past a few MB; switching later means rewriting history.
