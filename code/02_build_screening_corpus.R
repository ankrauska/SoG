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
