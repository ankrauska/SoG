# SoG — Solve-or-Guess screening validation kit

**How good is your LLM screener, when you have multiple humans to grade it against?**

This kit answers that question. It validates an automated screener against
several human reviewers **without a gold standard**, using the solve-or-guess
model of Rohe et al. It is the runnable machinery behind the worked example in
`worked_example_paper.pdf`, a CONSORT-eligibility screening study, and it is
built to be re-pointed at your own abstracts, your own reviewers, and your own
codebook.

If you want to understand the method, read [The problem](#the-problem) and
[How solve-or-guess works](#how-solve-or-guess-works) below. If you just want to
see it run, jump to [Quickstart](#quickstart).

---

## The problem

Every systematic review begins by screening: someone reads a title and abstract
and decides whether the study belongs. It is the most repetitive stage of the
review, and LLMs are now widely used for it. So how do you know whether the LLM
is any good?

The standard answer is to build a gold standard, where you have humans label a sample,
then score the LLM against it with sensitivity, specificity, and F1. That answer
has a hole in it. It assumes the human benchmark is correct. When the LLM
disagrees with the benchmark, the metric records an LLM error, but it cannot
distinguish between *the LLM got it wrong* from *two conscientious reviewers would have
disagreed here*.

That distinction matters more than it sounds. Screening criteria can be genuinely
hard, experienced reviewers disagree with each other routinely, and the gold
standard is usually built by the same reviewers the LLM is later compared
against, which makes the comparison circular. For any criterion where the
humans themselves disagree, this is not an edge case. It is the normal case.

**Solve-or-guess removes the gold standard from the picture entirely.** Instead
of asking "how often does the LLM match the key?", it asks "how often does each
rater, human or machine, actually solve the task?" and answers using nothing
but the raters' agreement with each other.

## How solve-or-guess works

Four ideas. Together they are the whole method.

**1. Each rater is either solving or guessing.**
On any given item, a rater either *solves* it — works out the true label and
reports it, or *guesses*, which may randomly be right. (A rater who is bored, rushed, or out of their depth
still produces a label; it just isn't driven by the truth.) Rater `a` solves
with probability `p_a`. That single number, the **solving probability**, is what
we want to know about each rater.

**2. Agreement has two sources, and the model separates them.**
Two raters can agree because both solved and recovered the same true label — or
because at least one guessed and happened to land on the same answer. Chance
agreement inflates every raw agreement number. Cohen's kappa exists to correct
for it, and under this model kappa turns out to have a remarkably clean form:

```
kappa(a, b) = p_a × p_b
```

Agreement between two raters is just the product of their solving probabilities.

**3. Divide, and the reference rater cancels.** This is the trick everything
rests on. Take any third rater `c` and form the ratio:

```
kappa(a, c)     p_a × p_c     p_a
───────────  =  ─────────  =  ───
kappa(b, c)     p_b × p_c     p_b
```

`p_c` cancels. You just compared rater `a` to rater `b` — and the answer does
not depend on rater `c` being any good, or on anyone knowing the true labels.
**This is why no gold standard is needed.** Nobody has to be right; they only
have to be independent.

We call `p_LLM / p_human` the **kappa-ratio**. Above 1 means the LLM solves the
task more often than that human.

**4. You need at least three raters.** With only two, there is no third rater to
cancel, and the model is not identified — you cannot separate "we agree because
we are both good" from "we agree by chance." Three is the
minimum. The worked example here uses four: three humans and one LLM.

### What this does and does not tell you

It tells you how often each rater solves the task, **relative to the others**.

It does **not** tell you anyone's accuracy against the truth. If every rater
shares the same blind spot, they will agree with each other, and solve-or-guess
will report that they all solve at a high rate. Agreement is evidence of shared
competence only when the raters are independent, so be sure to check the assumptions below.

## Does my study fit?

Check all five before you start. If one fails, the numbers this algorithm produces
will look perfectly reasonable and mean nothing.

- [ ] **Three or more raters.** Including the LLM. One human and one LLM is not enough.
- [ ] **Everyone labels the same items.** A complete design — every rater, every
      item. `code/01` enforces this and will stop if your files disagree.
- [ ] **The raters worked independently.** No conferring, no seeing each other's
      labels, and the LLM must never be shown the humans' decisions. Shared
      influence looks exactly like shared competence to this model, and it will
      inflate every estimate. (`code/02` builds a label-free corpus specifically
      to guarantee this for the LLM.)
- [ ] **A sharp codebook.** The model assumes each item has one correct label
      that careful raters converge on ("solver consensus"). A vague criterion
      lets two good reviewers disagree for good reasons — and then there is no
      single target to recover, so the kappa-ratio measures nothing. **The
      codebook is part of the method, not the setup.** See
      [`prompts/README.md`](prompts/README.md).
- [ ] **Run the diagnostic.** `code/05` tests whether the model actually fits
      your raters. A rejected model (low p-value) means the solving
      probabilities are not trustworthy.

## Replicating the worked example

`data/`, `runs/`, and `results/` ship populated with the worked example, so you
can reproduce the entire analysis **without an API key and without spending a
cent** — the LLM's decisions are already recorded in `runs/`.

```bash
# from the SoG/ root
Rscript code/04_run_solve_or_guess.R     # fit the model      (~5 min, B=1000)
Rscript code/05_rank_one_diagnostic.R    # check it fits      (~20 s)
```

You should see the LLM's solving probability at 0.85, the highest of the four
raters, with every kappa-ratio interval containing 1 — that is, the LLM is
statistically indistinguishable from each human reviewer. Then read
[`results/README.md`](results/README.md) to interpret what you just produced.

To regenerate the LLM decisions themselves you need an API key (see
[Dependencies](#dependencies)); `code/03` is the only stage that costs money.

## The pipeline

```
  data/inputs/reviewer*.csv          three humans' labelled spreadsheets
        │
        ├──01──► data/derived/human_reviewer_labels_merged.csv
        │           all reviewers' labels, one row per abstract
        │
        └──02──► data/inputs/screening_corpus.csv
                    titles + abstracts ONLY — labels stripped, so the
                    LLM cannot see what the humans decided
                        │
                        ├──03──► runs/<experiment>/<condition>/*.json
                        │           one record per API call: the decision,
                        │           the prompt hash, the model, the tokens
                        │              │
  merged labels ────────┴──────────────┴──04──► results/<experiment>/
                                                  solving_probabilities.csv
                                                  kappa_ratios_llm_vs_human.csv
                                                  pairwise_kappa.csv
                                                  rater_labels_long.csv
                                                        │
                                                        └──05──► rank_one_diagnostic.csv
```

| Stage | Does | Needs API? |
|---|---|---|
| `code/01_merge_human_reviewers.R` | Joins the reviewer files; enforces the complete-design check | no |
| `code/02_build_screening_corpus.R` | Strips labels to build the blinded corpus | no |
| `code/03_run_screening.py` | Runs the codebook prompt on every abstract | **yes** |
| `code/04_run_solve_or_guess.R` | Fits the model; solving probabilities and kappa-ratios | no |
| `code/05_rank_one_diagnostic.R` | Tests whether the model fits your raters | no |

Every stage takes the experiment YAML as its one argument and defaults to the
worked example:

```bash
Rscript code/04_run_solve_or_guess.R                            # exp_001_codebook
Rscript code/04_run_solve_or_guess.R experiments/my_study.yaml  # your own
```

> **Run every script from the `SoG/` root.** The R scripts resolve paths with
> `here()`, which anchors on the `.here` file at the root, so the working
> directory must be inside the kit.

## Quickstart: Running your own study

You should not need to edit any R script. Everything that varies between studies
lives in one experiment YAML.

1. **Put your reviewers' files anywhere** under `data/inputs/`. Each needs a
   title, an abstract, and a decision column; the column *names* are yours to
   choose. See [`data/README.md`](data/README.md) for the required shape.
2. **Write your codebook** in `prompts/`, with a JSON schema sidecar.
   [`prompts/README.md`](prompts/README.md) covers what makes a codebook sharp
   enough for this method to work — read it before writing one.
3. **Copy `experiments/exp_001_codebook.yaml`** and edit it: list your
   reviewers and their ids, name your columns, point at your prompt and model.
   Every key is documented in [`experiments/README.md`](experiments/README.md).
4. **Run the stages** against your YAML:
   ```bash
   Rscript code/01_merge_human_reviewers.R  experiments/my_study.yaml
   Rscript code/02_build_screening_corpus.R experiments/my_study.yaml
   python   code/03_run_screening.py        experiments/my_study.yaml --limit 2   # smoke test first
   python   code/03_run_screening.py        experiments/my_study.yaml
   Rscript  code/04_run_solve_or_guess.R    experiments/my_study.yaml
   Rscript  code/05_rank_one_diagnostic.R   experiments/my_study.yaml
   ```
5. **Read `results/<your_experiment>/`**, starting with the rank-one diagnostic.
   If the model is rejected, fix that before interpreting anything else.

Use `--limit 2` on `code/03` the first time. It runs two abstracts instead of
your whole corpus, which catches a malformed prompt or schema before you pay for
a full run.

## Dependencies

- **R** (stages 01, 02, 04, 05): `install.packages(c("tidyverse", "here", "jsonlite", "yaml"))`.
  The vendored estimator also uses `dplyr`/`tidyr`/`tibble`, which ship with `tidyverse`.
- **Python** (stage 03): `pip install -r requirements.txt` — anthropic, jsonschema,
  pandas, pyyaml, python-dotenv, pinned to the versions that produced the bundled outputs.
- **Solve-or-guess estimator**: vendored under `code/em/`, no external setup. The EM
  fit, spectral initializer, and nonparametric bootstrap are included verbatim from
  the published method (Rohe et al.). See [`code/em/SOURCE.md`](code/em/SOURCE.md)
  and [`code/em/GUIDE.md`](code/em/GUIDE.md).
- **API key** (stage 03 only): `code/03` reads `ANTHROPIC_API_KEY` from a `.env`
  file in the project root. Create your own.

## What's here

| Path | Purpose |
|---|---|
| `worked_example_paper.pdf` | The write-up of the worked example — the method, the framing, and the results. |
| `prompts/` | The codebook prompt and its JSON output schema, plus a guide to writing a good codebook. |
| `experiments/` | One YAML per study: raters, corpus, prompt, model, fitting options. The single source of truth for a run. |
| `code/` | The five pipeline stages, plus `config.R` (shared config loader) and `em/` (the vendored estimator). |
| `data/inputs/` | Reviewer files, and the blinded corpus the LLM sees. |
| `data/derived/` | The merged human labels. |
| `runs/` | Raw LLM decisions, one JSON per call. **Append-only.** |
| `results/` | Fitted estimates, one directory per experiment. |

## Reading the paper alongside the repo

The three human reviewers are **A, B, C** in both the paper and the repo, so
their labels carry across directly. Their estimated solving probabilities are
0.81, 0.83, and 0.67.

Where each table in the paper comes from:

| Paper | File |
|---|---|
| Table 1 — Include counts and rates | `results/exp_001_codebook/rater_labels_long.csv` |
| Table 2 — solving probabilities | `results/exp_001_codebook/solving_probabilities.csv` |
| Table 3 — kappa-ratios | `results/exp_001_codebook/kappa_ratios_llm_vs_human.csv` |
| Table 4 — pairwise kappa | `results/exp_001_codebook/pairwise_kappa.csv` |
| §4.5 — model fit | `results/exp_001_codebook/rank_one_diagnostic.csv` |

## Citing the method

The solve-or-guess model is the work of Rohe et al., *The solve or guess model:
Validating automated systems against heterogeneous human raters* (2026). This
kit is an application of it; cite the source for the method itself.

## Licensing

**Free for noncommercial use, including all academic work.**

The kit is licensed by Auden Krauska under
[PolyForm Noncommercial 1.0.0](LICENSE). The solve-or-guess method under
`code/em/` is separately the subject of a pending patent application owned by
Karl Rohe, who has made an irrevocable public covenant not to assert it against
noncommercial use.

Use at a university, charity, or government body counts as noncommercial
regardless of who funds the work. Use by or for a business does not, even if you
are an academic doing it on your own account.

Read [`NOTICE.md`](NOTICE.md) for the full terms, including Karl Rohe's patent
note in his own words. Provenance for the vendored estimator is in
[`code/em/SOURCE.md`](code/em/SOURCE.md).
