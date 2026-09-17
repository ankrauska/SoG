# Experiments — the configuration reference

One YAML per study. This file is the single source of truth for a run: who the
raters are, which abstracts they labelled, which prompt and model produced the
LLM decisions, and how the model is fitted. Every number under
`results/<id>/` traces back to it.

**You should not need to edit any script to run your own study.** If you find
yourself wanting to, that is a gap in this config — worth fixing here rather
than in the R.

To start: copy `exp_001_codebook.yaml`, change the values, and pass your copy to
each stage.

```bash
Rscript code/01_merge_human_reviewers.R experiments/my_study.yaml
```

With no argument, every stage defaults to `exp_001_codebook.yaml`.

---

## Which stage reads what

| Key | Read by |
|---|---|
| `id` | 04, 05 — names the output directory `results/<id>/` |
| `model`, `temperature`, `max_tokens`, `n_runs`, `seed` | 03 |
| `conditions` | 03 (runs each), 04 (via `analysis.condition`) |
| `inputs.reviewers`, `inputs.reviewer_columns` | 01, 02 |
| `inputs.manifest` | 02 writes it, 03 reads it |
| `inputs.merged_labels` | 01 writes it, 04 reads it |
| `analysis.*` | 04, 05 |
| `output.runs_dir` | 03 writes there, 04 reads from there |

## Top level

```yaml
id: exp_001_codebook
description: >
  Baseline run of the codebook prompt on the screening corpus...
```

| Key | Required | Notes |
|---|---|---|
| `id` | yes | Names `results/<id>/`. Use a new id for a variant run so it does not overwrite the original. |
| `description` | no | Prose for humans. Say what makes this run different from its neighbours. |

## The LLM call

```yaml
model: claude-haiku-4-5
temperature: 0.0
max_tokens: 1024
n_runs: 1
seed: 20260604
```

| Key | Default | Notes |
|---|---|---|
| `model` | required | Model id passed straight to the API. **Must support forced tool use** — see below. |
| `temperature` | `0.0` | 0 makes the run as close to deterministic as the API allows. Raise it only if you are deliberately studying run-to-run variance. |
| `max_tokens` | `1024` | Must comfortably fit the codebook's JSON output, including the reasoning field. If responses are truncated, raise it — a truncated tool call fails schema validation. |
| `n_runs` | `1` | Passes per abstract. `> 1` repeats each abstract, which lets you measure the LLM's own variability — but `code/04` expects exactly one record per case, so aggregate first. |
| `seed` | none | Recorded in each run file for provenance. |

> **Model compatibility.** `code/03` gets schema-conforming output by declaring
> the codebook's schema as a tool and setting
> `tool_choice={"type": "tool", "name": "submit_decision"}`. Forced tool use is
> **rejected with a 400 on the newest Claude models** (`tool_choice` `"tool"` and
> `"any"`), so changing `model:` to a current frontier model will fail rather
> than silently degrade.
>
> The worked example uses `claude-haiku-4-5`, which supports it. If you switch to
> a model that does not, adapt `code/03` to one of the current mechanisms —
> structured outputs via `output_config.format`, or `tool_choice: {"type": "auto"}`
> with `strict: true` on the tool and an instruction naming it. Check the current
> API documentation for your model before assuming either works.

### `conditions`

```yaml
conditions:
  - name: baseline
    prompt: prompts/screen_v1_codebook.txt
```

One entry per prompt variant. Each writes its own subdirectory under
`runs_dir`, so an A/B comparison of two prompts is two entries here — not two
experiments — which keeps them on the same corpus.

`code/03` finds each prompt's JSON schema by naming convention: `<stem>.txt`
pairs with `<stem>.schema.json`.

## `inputs`

### `reviewers`

```yaml
reviewers:
  - id: A
    file: data/inputs/reviewerA.csv
    canonical_text: true
  - id: B
    file: data/inputs/reviewerB.csv
  - id: C
    file: data/inputs/reviewerC.csv
```

One entry per **human** rater. The automated rater is not listed here; it is
named by `analysis.system_rater_id`.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Names this rater everywhere downstream — in `rater_labels_long.csv`, `solving_probabilities.csv`, and the kappa tables. Pick ids you want to see in your results. Must be unique, and must not collide with `system_rater_id`. |
| `file` | yes | Path relative to the project root. |
| `canonical_text` | no | Marks the file that supplies title and abstract text to `code/02`. At most one reviewer may set it; if none do, the first is used. |

The number of reviewers is free. **The model needs three or more raters in
total**, so with one LLM that means two or more humans; fewer raises a warning
and the estimates will not be meaningful.

All reviewers must cover exactly the same items — `code/01` enforces this and
names the offending titles if they do not.

### `reviewer_columns`

```yaml
reviewer_columns:
  title: Title
  abstract: Abstract
  label: CONSORT flag
  reasoning: Reasoning
  difficulty: Difficulty
```

Maps your spreadsheet's column names onto the roles the pipeline needs, so a
file whose decision column is called `Decision` needs a change here rather than
in the R.

| Role | Required | Notes |
|---|---|---|
| `title` | yes | The join key between the reviewer files and the LLM's decisions. Matched **exactly**, so it must be identical across files. |
| `abstract` | yes | The text the LLM screens. |
| `label` | yes | The rater's decision. |
| `reasoning` | no | Carried through for provenance; not modelled. |
| `difficulty` | no | Carried through; not used by the homogeneous fit. |

### Paths

```yaml
manifest: data/inputs/screening_corpus.csv
merged_labels: data/derived/human_reviewer_labels_merged.csv
```

| Key | Notes |
|---|---|
| `manifest` | Written by 02, read by 03. The blinded corpus: `case_id`, `title`, `abstract`, no labels. |
| `merged_labels` | Written by 01, read by 04. All reviewers' labels in one table. |

Give these study-specific paths if you are running several studies, so one does
not overwrite another's derived files.

## `analysis`

```yaml
analysis:
  system_rater_id: LLM
  condition: baseline
  human_review_action: include
  bootstrap_B: 1000
  seed_fit: 20260624
  seed_diagnostic: 20260625
```

| Key | Default | Notes |
|---|---|---|
| `system_rater_id` | `LLM` | The automated rater's name, passed to the estimator as `system_rater_id`. Must not collide with a reviewer id. |
| `condition` | first condition | Which condition's runs to analyse. |
| `human_review_action` | `include` | What to do with the codebook's abstain label. See below. |
| `bootstrap_B` | `1000` | Bootstrap replicates for the confidence intervals. Lower is faster and noisier — use ~50 while iterating, 1000+ for anything you report. |
| `seed_fit` | `1` | Seeds `code/04`. |
| `seed_diagnostic` | `2` | Seeds `code/05`. |

### `human_review_action`

The codebook lets the LLM abstain ("Human Review"); the humans in this study
could not. An abstain is a refusal to give an opinion, not a third opinion, so
it has to be resolved before fitting. One of:

| Value | Effect |
|---|---|
| `include` | Collapse to Include. Conservative when screening feeds a downstream human check: abstaining operationally meant "pass it on". |
| `exclude` | Collapse to Exclude. Right if an abstain is closer to "probably not eligible" in your workflow. |
| `keep` | Treat as its own label class. Honest, but only defensible if your humans could also abstain. |
| `drop` | Remove those items. Cleanest, at the cost of sample size and of conditioning the corpus on the LLM's behaviour. |

This is a judgement call, so **report which one you used and show it does not
drive your result.** `results/README.md` has a worked sensitivity table.

## `output`

```yaml
output:
  runs_dir: runs/exp_001_codebook
```

Where `code/03` writes decision records and `code/04` reads them, as
`runs_dir/<condition>/<case_id>__<run>__<timestamp>.json`. Defaults to
`runs/<id>`.

`runs/` is append-only. To rerun a condition, point `runs_dir` somewhere new or
move the old files aside — do not overwrite them.

## Validation

`code/config.R` checks the config before any stage does work, and every error
says what to fix. It will stop on: a missing file; a missing required key;
duplicate reviewer ids; a reviewer id colliding with `system_rater_id`; more
than one `canonical_text`; an unrecognised `human_review_action`; a reviewer
file missing a configured column; and reviewers who did not label the same
items. Fewer than three raters warns rather than stops.
