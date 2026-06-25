# Data

Source material the LLM screens, and the human-reviewer labels we validate against.

## Layout

```
data/
  inputs/                  # raw reviewer files, plus the screening corpus the LLM sees
  derived/                 # preprocessed tables, e.g. the merged human labels
```

Key files:

- `inputs/reviewer{A,E,H}.csv` — the three reviewers' decisions (Title, Abstract, CONSORT flag, Reasoning, Difficulty).
- `inputs/screening_corpus.csv` — titles and abstracts only, with a stable `case_id`. This is what the LLM sees, built by `code/02_build_screening_corpus.R`.
- `derived/human_reviewer_labels_merged.csv` — the three reviewer files joined on Title, label columns suffixed `_A`/`_E`/`_H`, built by `code/01_merge_human_reviewers.R`.

## Provenance

For a validation study, data origin is load-bearing. For the input set and the reviewer files, record the source (database search query, repository, or institution), the date acquired, licensing and sharing constraints, and any preprocessing applied before it landed here.

## Human reviewer labels

Three human reviewers provided decisions on the candidate abstract set. The source files were Google Sheets, exported to `data/inputs/reviewer{A,E,H}.csv` so the analysis runs from a fixed snapshot rather than the live sheet. All three recorded a binary CONSORT flag, Include or Exclude, on the same 100 abstracts.

## Gitignore policy

If inputs are large or have licensing restrictions, we gitignore the data files and commit a description of what was used. A reader of the repo should always see *what* data was used even if they cannot access the bytes.
