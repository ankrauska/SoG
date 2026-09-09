# ---------------------------------------------------------------------------
# Shared configuration loader for the R stages of the pipeline (01, 02, 04, 05).
#
# WHY THIS FILE EXISTS
#
# Every stage of the pipeline needs to agree about the same handful of facts:
# who the raters are, where their label files live, which column holds the
# label, which run directory holds the LLM decisions, and how the model should
# be fitted. If each script hardcodes those facts, then running a second study
# means editing R code in four places and hoping you caught them all.
#
# Instead, one experiment YAML in experiments/ is the single source of truth,
# and every script reads it through this file. Running a new study means
# writing a new YAML -- you should never need to edit a numbered script.
#
# USAGE inside a pipeline script:
#
#   source(here::here("code", "config.R"))
#   cfg <- load_experiment()
#
# and from the shell:
#
#   Rscript code/01_merge_human_reviewers.R                           # default
#   Rscript code/01_merge_human_reviewers.R experiments/my_study.yaml # explicit
#
# See experiments/README.md for what each key in the YAML means.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(here)
  library(yaml)
})

DEFAULT_EXPERIMENT <- "experiments/exp_001_codebook.yaml"


# Which experiment file did the user ask for?
#
# The pipeline scripts take the experiment YAML as their one positional
# command-line argument. With no argument they fall back to the worked example,
# so a reader who just clones the repo and runs `Rscript code/04_...R` gets the
# demo rather than an error.
experiment_arg <- function(default = DEFAULT_EXPERIMENT) {
  args <- commandArgs(trailingOnly = TRUE)
  args <- args[!startsWith(args, "-")]        # ignore any flags
  if (length(args) == 0) default else args[[1]]
}


# Small helper: fail with a message that says what was wrong AND what to do.
# Every validation error in this file is phrased that way on purpose -- a
# misconfigured YAML is the most likely thing to go wrong for a new user, and
# a bare "subscript out of bounds" teaches them nothing.
cfg_stop <- function(...) stop(paste0(...), call. = FALSE)


# Read and validate one experiment YAML.
#
# Returns a list with the raw YAML contents plus a few derived conveniences:
#   $reviewer_ids       character vector of human rater IDs, in file order
#   $canonical_reviewer the reviewer whose file supplies title/abstract text
#   $rater_order        humans first, then the system rater (LLM) last
#
# `$rater_order` matters more than it looks: it fixes the row order of
# results/<exp>/rater_labels_long.csv and the pair order of pairwise_kappa.csv,
# so keeping it stable keeps results comparable across runs.
load_experiment <- function(path = experiment_arg()) {
  full_path <- if (file.exists(path)) path else here(path)
  if (!file.exists(full_path)) {
    cfg_stop("Experiment file not found: '", path, "'.\n",
             "  Looked in the working directory and at ", here(path), ".\n",
             "  Available experiments: ",
             paste(list.files(here("experiments"), pattern = "\\.ya?ml$"),
                   collapse = ", "))
  }

  cfg <- yaml::read_yaml(full_path)
  cfg$.path <- full_path

  # --- required top-level structure ---------------------------------------
  for (key in c("id", "inputs")) {
    if (is.null(cfg[[key]])) {
      cfg_stop("Experiment '", path, "' is missing the required top-level key '",
               key, "'. See experiments/README.md.")
    }
  }
  for (key in c("reviewers", "reviewer_columns", "manifest", "merged_labels")) {
    if (is.null(cfg$inputs[[key]])) {
      cfg_stop("Experiment '", path, "' is missing required key 'inputs.", key,
               "'. See experiments/README.md.")
    }
  }

  # --- reviewers -----------------------------------------------------------
  # Each entry is one human rater: an id used everywhere downstream, and the
  # path to that rater's label file. The number of reviewers is free; the
  # solve-or-guess model needs at least three raters in total to be
  # identified, which with one LLM means at least two humans.
  revs <- cfg$inputs$reviewers
  if (!is.list(revs) || length(revs) == 0) {
    cfg_stop("'inputs.reviewers' must be a non-empty list of {id, file} entries.")
  }
  for (r in revs) {
    if (is.null(r$id) || is.null(r$file)) {
      cfg_stop("Every entry in 'inputs.reviewers' needs both an 'id' and a 'file'.")
    }
  }

  ids <- vapply(revs, function(r) as.character(r$id), character(1))
  if (anyDuplicated(ids)) {
    cfg_stop("Duplicate reviewer id(s) in 'inputs.reviewers': ",
             paste(unique(ids[duplicated(ids)]), collapse = ", "),
             ". Reviewer ids must be unique -- they name the raters in the results.")
  }

  system_id <- cfg$analysis$system_rater_id %||% "LLM"
  if (system_id %in% ids) {
    cfg_stop("Reviewer id '", system_id, "' collides with 'analysis.system_rater_id'. ",
             "The automated rater and the humans must have distinct ids.")
  }

  # The solve-or-guess model is identified only with three or more raters
  # (Rohe et al.); with one automated rater that means two or more humans.
  # Warn rather than stop, so someone exploring a two-rater dataset can still
  # see what the estimator does -- but they should not trust the numbers.
  n_raters <- length(ids) + 1L
  if (n_raters < 3L) {
    warning("Only ", n_raters, " raters configured. The solve-or-guess model is ",
            "not identified with fewer than 3 raters; estimates will not be ",
            "meaningful. Add more human reviewers.", call. = FALSE)
  }

  # --- which reviewer file supplies the abstract text? ---------------------
  # All reviewers labelled the same items, so any of their files carries the
  # same titles and abstracts. We pick one to be canonical so that the corpus
  # the LLM sees (code/02) comes from a single, named place.
  canon_flags <- vapply(revs, function(r) isTRUE(r$canonical_text), logical(1))
  if (sum(canon_flags) > 1) {
    cfg_stop("More than one reviewer is marked 'canonical_text: true'. ",
             "Exactly one reviewer file supplies the title/abstract text.")
  }
  canon_idx <- if (any(canon_flags)) which(canon_flags) else 1L

  # --- derived conveniences ------------------------------------------------
  cfg$reviewer_ids       <- ids
  cfg$canonical_reviewer <- revs[[canon_idx]]
  cfg$rater_order        <- c(ids, system_id)   # humans first, system last

  # --- analysis defaults ---------------------------------------------------
  # Spelled out rather than left implicit so a reader can see every knob that
  # affects the fit without hunting through the R scripts.
  a <- cfg$analysis %||% list()
  a$system_rater_id     <- system_id
  a$condition           <- a$condition %||% cfg$conditions[[1]]$name
  a$human_review_action <- a$human_review_action %||% "include"
  a$bootstrap_B         <- as.integer(a$bootstrap_B %||% 1000L)
  a$seed_fit            <- as.integer(a$seed_fit %||% 1L)
  a$seed_diagnostic     <- as.integer(a$seed_diagnostic %||% 2L)

  valid_actions <- c("include", "exclude", "keep", "drop")
  if (!a$human_review_action %in% valid_actions) {
    cfg_stop("'analysis.human_review_action' is '", a$human_review_action,
             "' but must be one of: ", paste(valid_actions, collapse = ", "),
             ". See the comment block in code/04_run_solve_or_guess.R.")
  }
  cfg$analysis <- a

  # --- where the LLM decisions live ---------------------------------------
  # code/03 writes here and code/04 reads from here, so both resolve it the
  # same way rather than each rebuilding the path from the experiment id.
  cfg$runs_dir <- sub("/$", "", cfg$output$runs_dir %||% file.path("runs", cfg$id))

  cfg
}


# Column names inside the reviewer CSVs, with the label column required and
# the rest optional. Keeping this in config means a study whose spreadsheet
# says "Decision" instead of "CONSORT flag" changes one line of YAML.
reviewer_columns <- function(cfg) {
  rc <- cfg$inputs$reviewer_columns
  if (is.null(rc$title) || is.null(rc$abstract) || is.null(rc$label)) {
    cfg_stop("'inputs.reviewer_columns' must name at least 'title', 'abstract' ",
             "and 'label'.")
  }
  rc
}


# Base R has no null-coalescing operator and we do not want to depend on
# rlang here, so define the one we use.
`%||%` <- function(x, y) if (is.null(x)) y else x
