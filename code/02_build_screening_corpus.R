# ---------------------------------------------------------------------------
# Stage 02: build the screening corpus -- the abstracts the LLM will see.
#
# WHAT THIS DOES
#   Takes the canonical reviewer file and strips out everything except the
#   title and abstract, then stamps each row with a stable `case_id`.
#
# WHY IT MATTERS
#   This is the blinding step, and it is not a formality. The reviewer files
#   contain the humans' decisions and their written reasoning. If any of that
#   leaked into the prompt, the LLM's agreement with the humans would partly
#   reflect having been shown their answers, which breaks the conditional
#   independence assumption the whole comparison rests on: agreement is
#   supposed to mean two raters independently recovered the same truth, not
#   that one copied the other. Building the corpus as its own artefact, from
#   an explicit column whitelist, is what makes that guarantee auditable --
#   you can open screening_corpus.csv and see there are no labels in it.
#
#   The `case_id` gives every abstract a short stable handle that follows it
#   through the whole pipeline: it names the run files in runs/, and it is the
#   item_id the estimator groups on. Titles are long and easy to mangle;
#   case_ids are not.
#
# INPUT   the reviewer file marked `canonical_text: true` in the experiment YAML
# OUTPUT  the CSV named in `inputs.manifest`
#
# USAGE
#   Rscript code/02_build_screening_corpus.R                           # worked example
#   Rscript code/02_build_screening_corpus.R experiments/my_study.yaml
#
# ---------------------------------------------------------------------------
# WHAT YOU GET, AND HOW TO CHECK IT
#
# 1. WHAT THIS WRITES
#    Three columns, one row per abstract, and nothing else:
#
#      case_id,title,abstract
#      case_001,Resin Infiltration for Masking Post-Orthodontic White...,"Background: White spot lesions..."
#      case_002,...
#
#    The reviewer file it came from has five columns
#    (Title, Abstract, CONSORT flag, Reasoning, Difficulty). The three label
#    columns are gone. That is the entire job of this stage.
#
#    `case_id` is `case_001` through `case_NNN`, assigned by row order.
#
# 2. VERIFY THE BLINDING -- DO THIS ONCE, FOR REAL
#    The independence assumption is the one you cannot repair after the fact.
#    It costs ten seconds to confirm, so confirm it rather than trusting this
#    script:
#
#      head -1 data/inputs/screening_corpus.csv
#      # must print exactly: case_id,title,abstract
#
#    If you see a decision column, a reasoning column, or anything resembling a
#    label, stop. Any LLM run against that corpus is contaminated, and its
#    agreement with the humans no longer means what the model assumes.
#
#    Checking the header is enough here because the corpus is built from an
#    explicit whitelist: `select(case_id, title, abstract)`. A new column added
#    to a reviewer's spreadsheet cannot leak through, because nothing is
#    dropped by name, only kept by name.
#
# 3. WHICH CONFIG KEYS CONTROL THIS
#      inputs.reviewers[].canonical_text   which reviewer file supplies the text
#      inputs.reviewer_columns.title       the column holding the title
#      inputs.reviewer_columns.abstract    the column holding the abstract
#      inputs.manifest                     where this writes
#
#    Any reviewer file will do as the canonical one: stage 01 has already
#    verified that every reviewer covers the same abstracts, so they all carry
#    the same text. The flag exists so the corpus has one named source rather
#    than an arbitrary one.
#
# 4. IF YOUR CORPUS DOES NOT COME FROM A REVIEWER FILE
#    Some studies have the abstracts as their own file, separate from the
#    reviewers' spreadsheets. You do not have to use this stage. Stage 03 only
#    needs the file at `inputs.manifest` to exist with columns
#    `case_id`, `title`, `abstract` -- so you can write it yourself and skip
#    straight to 03.
#
#    Two obligations if you do. The `title` values must match the reviewer
#    files exactly, since stage 04 joins on title. And the blinding is then
#    yours to guarantee: run the check in step 2 against your own file.
#
# 5. RE-RUNNING THIS
#    `case_id` is assigned by row order, so rebuilding the corpus from a
#    reordered source file reassigns every id. The run files in runs/ are named
#    by the old ids and stage 04 joins on title, not case_id, so nothing breaks
#    loudly -- but your case_ids will no longer point at the abstracts they did
#    before. If you reorder the source, rerun stage 03 as well.
#
# See data/README.md for the full data contract.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})
source(here("code", "config.R"))

cfg  <- load_experiment()
cols <- reviewer_columns(cfg)

# Any reviewer file would do -- they all cover the same abstracts, which
# stage 01 verifies -- but we read from one named file so the corpus has a
# single documented provenance.
source_file <- cfg$canonical_reviewer$file
message("Experiment: ", cfg$id)
message("Building corpus from canonical reviewer '", cfg$canonical_reviewer$id,
        "' (", source_file, ")")

raw <- read_csv(here(source_file), show_col_types = FALSE)

missing <- setdiff(c(cols$title, cols$abstract), names(raw))
if (length(missing) > 0) {
  stop("Canonical reviewer file is missing column(s): ",
       paste(sprintf("'%s'", missing), collapse = ", "),
       "\n  Found: ", paste(names(raw), collapse = ", "), call. = FALSE)
}

# `select()` on an explicit whitelist, rather than dropping the label columns
# by name. A whitelist stays safe when a reviewer adds a column to their
# spreadsheet; a blacklist would silently let the new column through.
corpus <- raw |>
  mutate(case_id = sprintf("case_%03d", row_number())) |>
  select(case_id, title = all_of(cols$title), abstract = all_of(cols$abstract))

# The corpus is the LLM's whole view of the task. Empty text would produce a
# decision made on nothing at all, so refuse to write one.
blank <- corpus |> filter(is.na(title) | is.na(abstract) |
                          !nzchar(trimws(title)) | !nzchar(trimws(abstract)))
if (nrow(blank) > 0) {
  stop(nrow(blank), " abstract(s) have an empty title or abstract, e.g. ",
       paste(head(blank$case_id, 3), collapse = ", "),
       ".\n  Fix the source file: the LLM cannot screen an empty record.",
       call. = FALSE)
}

out_path <- here(cfg$inputs$manifest)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(corpus, out_path)

message("Wrote ", nrow(corpus), " abstracts to ", cfg$inputs$manifest)
message("Columns: ", paste(names(corpus), collapse = ", "), "  (no labels -- by design)")
