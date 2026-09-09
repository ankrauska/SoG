# Runs — the raw LLM decisions

One JSON file per API call. This is the evidence layer: everything in
`results/` is derived from these files, and stage 03 is the only part of the
pipeline that cannot be re-derived from what is in the repo — it costs money,
depends on a live API, and cannot be replayed after the fact.

> **Append-only. Never edit a file here.** If a run was bad, record why and
> produce a new run with a new timestamp. Do not overwrite.

```
runs/
  {experiment_id}/
    {condition}/
      {case_id}__{run_index}__{timestamp}.json
    run.log
```

The path is built from `output.runs_dir` and the condition name, so comparing
two prompt variants puts them in sibling directories over the same corpus.

---

## What a record looks like

Every file carries enough to reconstruct the call without consulting the
experiment config. A real record from the worked example, abridged:

```json
{
  "experiment_id": "exp_001_codebook",
  "condition": "baseline",
  "prompt_id": "screen_v1_codebook",
  "prompt_sha": "c1572450",
  "case_id": "case_001",
  "run_index": 1,
  "model": "claude-haiku-4-5",
  "temperature": 0.0,
  "seed": 20260604,
  "timestamp": "2026-06-24T10:11:21Z",
  "title": "Resin Infiltration for Masking Post‑Orthodontic White Spot...",
  "abstract": "Background: White spot lesions (WSLs) affect up to 95% of patients... [truncated]",
  "output": {
    "analyzing_data": "Yes",
    "patient_level_health_outcomes": "No",
    "evidence_of_randomization": "The abstract states \"We included randomized controlled trials (RCTs)...\"",
    "intervention_randomized": "No",
    "reasoning": "This manuscript is a systematic review and meta-analysis that aggregates data from 10...",
    "consort_flag": "Exclude"
  },
  "usage": {
    "input_tokens": 3877,
    "output_tokens": 351
  },
  "stop_reason": "tool_use",
  "elapsed_sec": 4.06
}
```

| Field | Why it is there |
|---|---|
| `experiment_id`, `condition` | Which run this belongs to. |
| `prompt_id`, `prompt_sha` | **Which exact prompt produced it.** See below. |
| `case_id` | The stable handle for this abstract; `code/04` joins on it. |
| `run_index` | Which pass, when `n_runs > 1`. |
| `model`, `temperature`, `seed` | The generation settings. |
| `timestamp` | UTC, when the call returned. |
| `title`, `abstract` | The exact text sent, so the input is recoverable from the record alone. |
| `output` | The structured decision, schema-validated. |
| `usage`, `elapsed_sec` | Token counts and latency — what a rerun would cost. |
| `stop_reason` | `tool_use` is normal. `max_tokens` means the reply was truncated and that record should not be trusted. |

## `prompt_sha`

The SHA of the prompt file at the moment of the call. It catches the most
insidious failure in prompt-based research: someone edits the prompt after the
run, and the recorded decisions no longer correspond to the prompt sitting in
the repo — with nothing in the output to reveal it.

To verify a run matches the current prompt file:

```bash
python3 -c "import hashlib;print(hashlib.sha256(open('prompts/screen_v1_codebook.txt','rb').read()).hexdigest()[:8])"
python3 -c "import json;print(json.load(open('runs/exp_001_codebook/baseline/case_001__001__20260624T101121Z.json'))['prompt_sha'])"
```

If they differ, the prompt changed after the run. Either restore it or rerun —
do not report the results as if they came from the current prompt.

## `run.log`

The console output of the stage-03 run, kept as a record of what happened at the
time: per-case decisions and token counts, then a total. The worked example's
run screened 100 abstracts in 383 seconds for 404,705 input and 30,857 output
tokens. Useful for estimating what your own corpus will cost before you run it.

## Size

If output volume grows, consider gitignoring `runs/**/*.json` and committing
only a per-experiment `summary.csv`. **Decide before the directory passes a few
MB** — switching later means rewriting history. Note the tradeoff: the raw
records are what make an individual decision auditable after the fact, so a
summary is a real loss of provenance, not just a smaller file.
