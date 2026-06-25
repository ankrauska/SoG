# SoG — Solve-or-Guess screening validation kit

A starter kit for validating an LLM abstract-screener against several human
reviewers **without a gold standard**, using the solve-or-guess model. It is the
runnable machinery behind the worked example in `paper.pdf` (a CONSORT-eligibility
screening study); swap in your own abstracts, reviewers, and codebook to run your
own study.

## What's here

| Path | Purpose |
|---|---|
| `paper.pdf` | The write-up of the worked example. Read it first for the method and framing. |
| `prompts/` | The screening codebook prompt (`screen_v1_codebook.txt`) and its JSON output schema. This is what the LLM runs. |
| `experiments/` | One YAML per run (model, temperature, prompt, inputs). `exp_001_codebook.yaml` is the worked example; `example_persona_ab.yaml` is a template. |
| `code/` | The pipeline (run in order). |
| `data/inputs/` | Raw reviewer files and the screening corpus the LLM sees. |
| `data/derived/` | Merged human labels. |
| `runs/` | Raw LLM decisions, one JSON per abstract, per experiment/condition. |
| `results/` | Fitted estimates per experiment: solving probabilities, kappa-ratios, pairwise kappa, rank-one diagnostic. |

`data/`, `runs/`, and `results/` hold the worked example so the pipeline runs
end to end as a demo. Replace the `data/` files with your own to run a new study.

## Pipeline

1. `code/01_merge_human_reviewers.R` — merge the per-reviewer CSVs into one table.
2. `code/02_build_screening_corpus.R` — strip labels to build the abstract corpus the LLM sees.
3. `code/03_run_screening.py` — run the codebook prompt on each abstract; write one JSON per call to `runs/`.
4. `code/04_run_solve_or_guess.R` — fit the solve-or-guess model to all raters; write solving probabilities, kappa-ratios, and pairwise kappa to `results/`.
5. `code/05_rank_one_diagnostic.R` — parametric-bootstrap rank-one model-fit check.

## Dependencies

- **Python** (for `code/03`): `pip install -r requirements.txt` (anthropic, jsonschema, pandas, pyyaml, python-dotenv; pinned to the versions that produced the bundled outputs).
- **R** (for `code/01,02,04,05`): `tidyverse`, `here`, `jsonlite`. The vendored estimator also uses `dplyr`/`tidyr`/`tibble`, which ship with `tidyverse`.
- **Solve-or-guess estimator** (vendored, no external setup): the EM fit, spectral initializer, and nonparametric bootstrap are included under `code/em/` (verbatim from the published method, Rohe et al.; see `code/em/SOURCE.md`). `code/04` and `code/05` load them automatically.
- **API key**: `code/03` reads `ANTHROPIC_API_KEY` from a `.env` file in the project
  root. Create your own; no key ships with this kit.

> **Run every script from the `SoG/` root** (e.g. `Rscript code/04_run_solve_or_guess.R`). The R scripts resolve paths with `here()`, which anchors on the `.here` file at the root, so the working directory must be inside the kit.

## Running the worked example

`runs/` and `results/` are already populated, so you can run `code/04` and `code/05`
on the included data without any API calls (only the solve-or-guess estimator path
and the R packages are needed). To regenerate the LLM decisions, set your API key
and run `code/03` against `experiments/exp_001_codebook.yaml`.

## Running your own study

1. Put your reviewers' labeled abstracts in `data/inputs/` (match the column shape in `data/README.md`), and rebuild the merged table and corpus with `code/01` and `code/02`.
2. Edit or add an experiment YAML in `experiments/` (model, prompt, inputs).
3. Run `code/03` → `code/04` → `code/05`.
4. Read `results/<experiment>/` and compare against the worked example in `paper.pdf`.
