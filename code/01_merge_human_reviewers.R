# ---------------------------------------------------------------------------
# Stage 01: merge the per-reviewer label files into one analysis-ready table.
#
# WHAT THIS DOES
#   Each human reviewer hands you a spreadsheet: one row per abstract, with
#   their decision on it. This script joins those files side by side, so every
#   abstract becomes one row carrying every reviewer's label.
#
# WHY IT MATTERS
#   The solve-or-guess model reads agreement between raters, so it needs all
#   raters' labels for the SAME item lined up on the same row. A complete
#   design -- every rater labels every item -- is what makes the pairwise
#   agreement rates estimable. This script is also where that assumption is
#   checked: if the reviewer files disagree about which abstracts they cover,
#   it stops here rather than silently fitting a model on a partial overlap.
#
# INPUT   the reviewer files named in `inputs.reviewers` of the experiment YAML
# OUTPUT  the CSV named in `inputs.merged_labels`
#
# USAGE
#   Rscript code/01_merge_human_reviewers.R                           # worked example
#   Rscript code/01_merge_human_reviewers.R experiments/my_study.yaml
#
# ---------------------------------------------------------------------------
# SETTING UP YOUR OWN REVIEWER FILES
#
# 1. WHERE TO PUT THEM
#    Save one CSV per reviewer under `data/inputs/`:
#
#      SoG/
#        data/
#          inputs/
#            reviewerA.csv        <- one file per human reviewer
#            reviewerB.csv
#            reviewerC.csv
#
#    `data/inputs/` is a convention, not a requirement. Paths in the YAML are
#    resolved from the project root, so anywhere inside the kit works. Keeping
#    them together is what makes the study easy to hand to someone else.
#
# 2. WHAT TO NAME THEM
#    Anything. Nothing parses the file name. A readable pattern is
#    `reviewer<ID>.csv`, where <ID> is the short id you give that reviewer in
#    the YAML. Use initials or a code rather than full names if the labels are
#    identifiable.
#
#    The `id` in the YAML, NOT the file name, is what appears in your results.
#    Choose ids you want to read in solving_probabilities.csv and in the kappa
#    tables.
#
# 3. WHAT GOES IN THEM
#    One row per abstract. Three columns are required. The column NAMES are
#    yours to choose; you map them in the YAML.
#
#    Two real rows from data/inputs/reviewerA.csv, abridged:
#
#      Title,Abstract,CONSORT flag,Reasoning,Difficulty
#      Resin Infiltration for Masking...,"Background: White spot lesions...",Exclude,Systematic review,0
#      Sustained Effects of Low-to-Moderate Doses of Psilocybin...,"Background: Psilocybin is a classic psychedelic...",Include,Evaluated an individual health outcome,80
#
#      Title        required   the join key. Must be IDENTICAL across every
#                              reviewer's file, character for character.
#      Abstract     required   the text being screened.
#      CONSORT flag required   that reviewer's decision. Use one consistent
#                              vocabulary; "Include" and "include" are two
#                              different labels to the estimator.
#      Reasoning    optional   free text, carried through for provenance.
#      Difficulty   optional   carried through, not used by this fit.
#
#    Every reviewer must label every abstract. This script stops if the files
#    disagree about which abstracts they cover.
#
# 4. HOW TO WIRE THEM UP
#    In your experiment YAML:
#
#      inputs:
#        reviewers:
#          - id: A
#            file: data/inputs/reviewerA.csv
#            canonical_text: true      # exactly one file supplies the abstracts
#          - id: B
#            file: data/inputs/reviewerB.csv
#          - id: C
#            file: data/inputs/reviewerC.csv
#        reviewer_columns:
#          title: Title
#          abstract: Abstract
#          label: CONSORT flag
#          reasoning: Reasoning        # omit if you did not collect it
#          difficulty: Difficulty      # omit if you did not collect it
#        merged_labels: data/derived/human_reviewer_labels_merged.csv
#
# 5. THEN RUN
#      Rscript code/01_merge_human_reviewers.R experiments/my_study.yaml
#
#    Add or remove `reviewers` entries freely. The model needs three or more
#    raters in total, so with one LLM that means two or more humans.
#
# See data/README.md for the full data contract, and experiments/README.md for
# every YAML key.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})
source(here("code", "config.R"))

cfg  <- load_experiment()
cols <- reviewer_columns(cfg)

message("Experiment: ", cfg$id, "  (", cfg$.path, ")")
n_rev <- length(cfg$reviewer_ids)
message("Merging ", n_rev, if (n_rev == 1) " reviewer: " else " reviewers: ",
        paste(cfg$reviewer_ids, collapse = ", "))

# ---------------------------------------------------------------------------
# Read one reviewer's file and give its label columns a rater-specific name.
#
# Reviewer files all share the same column names ("CONSORT flag", "Reasoning",
# ...), so before joining them we suffix each with the rater's id -- otherwise
# the join would produce consort_flag.x / consort_flag.y and you would lose
# track of whose label is whose. `reasoning` and `difficulty` are optional:
# they are carried through for provenance but the model does not read them.
# ---------------------------------------------------------------------------
read_reviewer <- function(rev, keep_abstract) {
  path <- here(rev$file)
  if (!file.exists(path)) {
    stop("Reviewer '", rev$id, "': file not found at ", path,
         "\n  Check 'inputs.reviewers' in ", cfg$.path, call. = FALSE)
  }
  d <- read_csv(path, show_col_types = FALSE)

  required <- c(cols$title, cols$abstract, cols$label)
  missing  <- setdiff(required, names(d))
  if (length(missing) > 0) {
    stop("Reviewer '", rev$id, "' (", rev$file, ") is missing column(s): ",
         paste(sprintf("'%s'", missing), collapse = ", "),
         "\n  Found: ", paste(names(d), collapse = ", "),
         "\n  Fix the file, or rename the columns in 'inputs.reviewer_columns'.",
         call. = FALSE)
  }

  out <- d |> select(title = all_of(cols$title), abstract = all_of(cols$abstract))
  out[[paste0("consort_flag_", rev$id)]] <- d[[cols$label]]

  # Optional columns, included only when configured AND actually present.
  for (opt in c("reasoning", "difficulty")) {
    src <- cols[[opt]]
    if (!is.null(src) && src %in% names(d)) {
      out[[paste0(opt, "_", rev$id)]] <- d[[src]]
    }
  }

  if (!keep_abstract) out <- out |> select(-abstract)
  out
}

# The canonical reviewer supplies the abstract text; the rest contribute only
# their labels, so the merged table has exactly one copy of each abstract.
canon_id <- cfg$canonical_reviewer$id
# A plain loop rather than map(), so a bad reviewer file reports its own error
# instead of burying it under a purrr backtrace.
tables <- list()
for (rev in cfg$inputs$reviewers) {
  tables[[as.character(rev$id)]] <- read_reviewer(rev, keep_abstract = rev$id == canon_id)
}

# ---------------------------------------------------------------------------
# Check the complete-design assumption before joining.
#
# Every reviewer must have labelled exactly the same set of abstracts. If they
# have not, the join would quietly produce NA labels and the model would treat
# them as a "MISSING" category, which is almost never what you want. Better to
# fail loudly and name the offending titles.
# ---------------------------------------------------------------------------
reference_titles <- tables[[canon_id]]$title
for (id in cfg$reviewer_ids) {
  these <- tables[[id]]$title
  if (!setequal(reference_titles, these)) {
    only_ref  <- setdiff(reference_titles, these)
    only_this <- setdiff(these, reference_titles)
    stop("Reviewer '", id, "' does not cover the same abstracts as '", canon_id, "'.\n",
         "  ", length(only_ref),  " title(s) missing from ", id, ", e.g.: ",
         paste(head(only_ref, 2), collapse = " | "), "\n",
         "  ", length(only_this), " title(s) only in ", id, ", e.g.: ",
         paste(head(only_this, 2), collapse = " | "), "\n",
         "  The solve-or-guess model needs a complete design: every rater ",
         "labels every item.\n",
         "  Titles are matched exactly, so check for stray whitespace or ",
         "encoding differences between the files.", call. = FALSE)
  }
  if (anyDuplicated(these)) {
    stop("Reviewer '", id, "' has duplicate titles, so the join would multiply rows. ",
         "Titles must uniquely identify an abstract.", call. = FALSE)
  }
}

# Join on title. Reduce() folds the per-reviewer tables together left to right,
# which keeps the column order predictable: title, abstract, then each
# reviewer's columns in the order they appear in the YAML.
merged <- reduce(tables, left_join, by = "title")

# The abstract text rides along with whichever reviewer is canonical, which may
# not be the first one, so pull it to the front. Layout is then always:
# title, abstract, then each reviewer's columns in YAML order.
merged <- merged |> relocate(abstract, .after = title)

# Restore the original human-facing column names for the two shared columns,
# so the merged file still reads like the reviewers' spreadsheets.
merged <- merged |> rename(!!cols$title := title, !!cols$abstract := abstract)

out_path <- here(cfg$inputs$merged_labels)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(merged, out_path)

message("Wrote ", nrow(merged), " rows x ", ncol(merged), " cols to ",
        cfg$inputs$merged_labels)
