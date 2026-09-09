# Data

The abstracts being screened, and the human labels the LLM is validated against.

```
data/
  inputs/     reviewer files, and the blinded corpus the LLM sees
  derived/    the merged label table  (regenerable — delete and rerun code/01)
```

Files in `inputs/` are source material you provide. Files in `derived/` are
built by the pipeline and can always be rebuilt.

---

## What ships here

| File | Built by | Contents |
|---|---|---|
| `inputs/reviewer{A,B,C}.csv` | you | Each reviewer's decisions: `Title`, `Abstract`, `CONSORT flag`, `Reasoning`, `Difficulty`. |
| `inputs/screening_corpus.csv` | `code/02` | `case_id`, `title`, `abstract`. **No labels** — this is what the LLM sees. |
| `derived/human_reviewer_labels_merged.csv` | `code/01` | All reviewers joined on title, label columns suffixed `_A` / `_B` / `_C`. |

## The shape your reviewer files need

One row per abstract, one file per reviewer. Three columns are required; the
**names are yours to choose** and are mapped in the experiment YAML under
`inputs.reviewer_columns`.

| Role | Required | Contents |
|---|---|---|
| title | yes | The join key. Must be identical across every reviewer's file. |
| abstract | yes | The text being screened. |
| label | yes | This reviewer's decision. |
| reasoning | no | Free text. Carried through for provenance; not modelled. |
| difficulty | no | Carried through; not used by the homogeneous fit. |

A row from the worked example, abridged:

```csv
Title,Abstract,CONSORT flag,Reasoning,Difficulty
Resin Infiltration for Masking Post-Orthodontic White Spot Lesions: A Systematic Review and Meta-Analysis,"Background: White spot lesions (WSLs) affect up to 95%...",Exclude,Systematic review,0
```

### Four rules

**1. Every reviewer labels every abstract.** The model needs a complete design —
all raters, all items — because it works from pairwise agreement rates. `code/01`
checks this and stops if the files disagree, naming the mismatched titles.

**2. Titles must match exactly across files.** The join is a literal string
comparison. Export all reviewer files from the same source snapshot; do not
retype titles, and beware spreadsheet software silently converting straight
quotes to curly ones. This is the most common way to break the pipeline.

**3. Use a consistent label vocabulary.** `Include` and `include` are two
different labels to the estimator. Decide the vocabulary before labelling. 
Consider using value validation to prevent misspellings or alternatives. 

**4. Reviewers must label independently.** No conferring, no reviewing each
other's decisions. Shared influence is indistinguishable from shared competence
to this model, and it inflates every estimate. This is a property of how you
collect the data — no amount of downstream processing can repair it.

### Using a different number of reviewers

Nothing is hardcoded. Add or remove entries under `inputs.reviewers` in the
experiment YAML; the file names and rater ids are yours. The model needs
**three or more raters in total**, so excluding the LLM, that means two or more
humans.

## The blinded corpus

`code/02` builds `screening_corpus.csv` by selecting only title and abstract
from the canonical reviewer's file — an explicit whitelist, so a new column
added to a reviewer's spreadsheet cannot leak into the prompt.

This is the mechanism that keeps the LLM independent of the humans, so be 
sure to double check. Open the file: if it contains a decision
column, the validation is compromised, because the LLM's agreement with the
humans would partly reflect having been shown their answers.

`case_id` (`case_001`, `case_002`, …) is assigned by row order and is the stable
handle for an abstract through the rest of the pipeline: it names the run files
and is the `item_id` the estimator groups on. Rebuilding the corpus from a
reordered source file will reassign case_ids, so rerun `code/03` if you do.

**The worked example.** The corpus is the 100 most recent medRxiv preprints
whose title or abstract contains the word "random", retrieved 1 May 2026; posting
dates run 11–30 April 2026. Three experienced reviewers each labelled all 100
abstracts Include or Exclude, working from the same codebook as the LLM. Their
decisions were collected in Google Sheets and exported to
`inputs/reviewer{A,B,C}.csv`, so the analysis runs from a fixed snapshot rather
than a live document.

One property of this corpus is worth copying: the abstracts postdate the model's
training cutoff, so the LLM cannot have seen these papers during training. Its
agreement with the humans cannot be an artifact of memorization. Validating a
screener on newly posted preprints gives you that for free.

## Gitignore policy

If your inputs are large or licence-restricted, gitignore the data files and
commit a description of what was used instead. **A reader should always be able
to see *what* data was used, even when they cannot access the bytes.**

The worked example's data is committed so the pipeline runs end to end as a
demo.
