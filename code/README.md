# Code — the pipeline

Five numbered stages, run in order, plus two supporting pieces.

```
config.R                      shared config loader (not a stage)
01_merge_human_reviewers.R    join the reviewer files
02_build_screening_corpus.R   strip labels -> the corpus the LLM sees
03_run_screening.py           call the model on every abstract   [costs money]
04_run_solve_or_guess.R       fit the model, compare raters
05_rank_one_diagnostic.R      test whether the model fits
em/                           the vendored estimator (do not edit)
```

Every stage takes the experiment YAML as its one argument and defaults to the
worked example. Run them from the `SoG/` root.

```bash
Rscript code/04_run_solve_or_guess.R                            # exp_001_codebook
Rscript code/04_run_solve_or_guess.R experiments/my_study.yaml  # your own
```

Each script's header comment explains what it does and why; this file is the
overview and the troubleshooting reference.

---

## What each stage is for

**01 — merge.** Joins the reviewer spreadsheets into one row per abstract. This
is where the **complete-design assumption is enforced**: every rater must have
labelled every item, or it stops and names the mismatched titles.

**02 — blind.** Builds the corpus the LLM sees: titles and abstracts only, by
explicit whitelist. This is the step that keeps the human labels away from the
model, which is what makes the raters independent — and independence is what
makes agreement mean something. The output is inspectable evidence: open
`screening_corpus.csv` and confirm there are no labels in it.

**03 — screen.** The only stage that needs an API key or costs money. Writes one
JSON record per call, recording the decision alongside the prompt hash, model,
temperature, and token usage. Use `--limit 2` first.

**04 — fit.** Loads every rater's labels, applies the abstain policy, fits the
solve-or-guess model, and writes the solving probabilities and kappa-ratios with
bootstrap intervals.

**05 — diagnose.** Tests whether the model actually describes your raters. Read
its output before trusting stage 04's.

## `config.R`

Not a stage — the shared loader every R script sources. It reads the experiment
YAML, validates it, and derives three things the scripts rely on:

| Derived | Meaning |
|---|---|
| `reviewer_ids` | Human rater ids, in YAML order. |
| `canonical_reviewer` | The reviewer whose file supplies title/abstract text. |
| `rater_order` | Humans first, system rater last. |

`rater_order` matters more than it looks: it fixes the row order of
`rater_labels_long.csv` and the pair order of `pairwise_kappa.csv`. Keeping it
stable keeps results comparable between runs.

## Troubleshooting

**`N abstract(s) have a human label but no matched LLM decision`**
The title join failed. Titles are matched exactly, so the usual causes are the
reviewer file and the corpus being built from different snapshots, or text
differing by whitespace, curly quotes, or unicode dashes. Rerun 02 and 03 from
the current reviewer files. To find the culprits, compare the `title` column of
your merged labels against the `title` field in `runs/<exp>/<condition>/*.json`.

**`Reviewer 'X' does not cover the same abstracts as 'Y'`**
The complete-design check. Someone skipped rows, or a file is a different
export. The message lists example titles from each side of the mismatch.

**`Reviewer 'X' is missing column(s)`**
Your spreadsheet's column names do not match `inputs.reviewer_columns`. The
error lists the columns the file actually has — copy the right names into the
YAML rather than renaming your data.

**`No LLM decision files found`**
Stage 03 has not run for this experiment, or `output.runs_dir` /
`analysis.condition` point somewhere empty.

**`N case_id(s) appear more than once`**
The run directory holds more than one pass over the corpus. `runs/` is
append-only, so move the stale files aside rather than deleting them, or point
`output.runs_dir` at a fresh directory.

**Warning: `Only 2 raters configured`**
The model is not identified with fewer than three raters. It will still produce
numbers; they will not mean anything. Add a reviewer.

**`There are N missing evaluations. Treated as 'MISSING' class`**
From the estimator. It means the item × rater grid has holes, which stage 01
should have caught — check that you did not hand stage 04 a hand-edited
`rater_labels_long.csv`.

**Different numbers from an unchanged input.** Check `analysis.seed_fit`,
`analysis.seed_diagnostic`, `bootstrap_B`, and `human_review_action`. Stages 04
and 05 are seeded and reproduce byte-for-byte otherwise.

**Stage 04 is slow.** It is `B` full EM refits; `B = 1000` takes a few minutes.
Drop `bootstrap_B` to ~50 while iterating, and restore it before reporting.

## A note on editing

`code/em/` is vendored verbatim from the published method — do not edit it. See
`em/SOURCE.md` for provenance and `em/GUIDE.md` for a map of what is inside.

Everything a study needs to vary lives in the experiment YAML. If you find
yourself editing a numbered script to run your own study, that is a gap in the
config worth fixing in `config.R` instead.
