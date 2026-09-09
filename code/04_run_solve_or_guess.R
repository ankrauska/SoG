# ---------------------------------------------------------------------------
# Stage 04: fit the solve-or-guess model and compare the LLM to the humans.
#
# WHAT THIS DOES
#   Loads every rater's label for every abstract -- the humans from stage 01,
#   the LLM from the JSON files stage 03 wrote -- and fits the solve-or-guess
#   model to all of them at once. Then it reports how often each rater solves
#   the task, and how the LLM compares to each human.
#
# WHY IT WORKS WITHOUT A GOLD STANDARD
#   The model says each rater is, on any given item, either SOLVING (they
#   report the true label) or GUESSING (they draw from a personal habit
#   distribution that ignores the truth). Rater a solves with probability p_a.
#
#   Two raters can agree for two different reasons: both solved, or someone
#   guessed and got lucky. The model separates those. Under it, Cohen's kappa
#   between two raters factors into the product of their solving probabilities:
#
#       kappa(a, b) = p_a * p_b
#
#   That factorisation is the whole trick. Take a third rater c and divide:
#
#       kappa(a, c) / kappa(b, c) = (p_a * p_c) / (p_b * p_c) = p_a / p_b
#
#   The reference rater cancels. So you can compare rater a to rater b using
#   only how each of them agrees with everyone else -- no answer key, and no
#   assumption that any particular rater is correct. That is why this works
#   when there is no gold standard, and why it needs at least three raters:
#   with two, there is no third rater to cancel.
#
#   What you are NOT getting is accuracy against truth. A kappa-ratio of 1.0
#   says the LLM solves as often as that human, not that either is right.
#
# INPUTS
#   the merged human labels from stage 01 (`inputs.merged_labels`)
#   the LLM decisions from stage 03  (`output.runs_dir`/<condition>/*.json)
#
# OUTPUTS (under results/<experiment>/)
#   rater_labels_long.csv          the item x rater matrix actually fitted
#   solving_probabilities.csv      p_hat per rater + 95% bootstrap CI
#   pairwise_kappa.csv             observed Cohen's kappa, every rater pair
#   kappa_ratios_llm_vs_human.csv  p_LLM / p_human + 95% bootstrap CI
#
# See results/README.md for how to read each of these.
#
# USAGE
#   Rscript code/04_run_solve_or_guess.R                           # worked example
#   Rscript code/04_run_solve_or_guess.R experiments/my_study.yaml
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(jsonlite)
})
source(here("code", "config.R"))

cfg        <- load_experiment()
experiment <- cfg$id
condition  <- cfg$analysis$condition
SYSTEM     <- cfg$analysis$system_rater_id   # the automated rater's id, e.g. "LLM"
HUMANS     <- cfg$reviewer_ids
RATERS     <- cfg$rater_order                # humans first, system rater last
B          <- cfg$analysis$bootstrap_B

# Seed before anything random happens. Everything downstream of this line --
# the fit and then the bootstrap, in that order -- consumes the same random
# stream on every run, which is what makes the committed results/ reproducible.
set.seed(cfg$analysis$seed_fit)

# ---------------------------------------------------------------------------
# The estimator itself is vendored under code/em/, copied verbatim from the
# published method (Rohe et al.). See code/em/SOURCE.md. Do not edit those
# files; this script only calls them.
# ---------------------------------------------------------------------------
source(here("code", "em", "spectral_initializer.R"))
source(here("code", "em", "tidy_solve_or_guess_fast.R"))
source(here("code", "em", "tidy_bootstrap_nonparametric.R"))

# The estimator works on the logit scale, so its "intercept" parameter has to
# be pushed back through the inverse logit to read as a probability.
logit_inv <- function(x) 1 / (1 + exp(-x))

message("Experiment: ", experiment, " / condition: ", condition)
message("Raters: ", paste(RATERS, collapse = ", "),
        "  (system rater: ", SYSTEM, ")")

# ---------------------------------------------------------------------------
# Load the LLM decisions: one JSON record per abstract, written by stage 03.
#
# We read the run files rather than a summary table on purpose. Each record
# carries the prompt hash, model, and timestamp alongside the decision, so the
# labels being fitted here are traceable to the exact call that produced them.
# ---------------------------------------------------------------------------
run_dir   <- here(cfg$runs_dir, condition)
llm_files <- list.files(run_dir, pattern = "\\.json$", full.names = TRUE)
if (length(llm_files) == 0) {
  stop("No LLM decision files found in ", run_dir, "\n",
       "  Run stage 03 first, or check 'output.runs_dir' and ",
       "'analysis.condition' in ", cfg$.path, call. = FALSE)
}

llm <- map_dfr(llm_files, function(f) {
  j <- fromJSON(f, simplifyVector = TRUE)
  tibble(case_id = j$case_id, title = j$title, evaluation = j$output$consort_flag)
})

# With n_runs = 1 there must be exactly one record per abstract. More than one
# means the run directory holds several passes; stage 04 fits a single label
# per rater, so that has to be resolved (or aggregated) before fitting.
if (any(duplicated(llm$case_id))) {
  dupes <- unique(llm$case_id[duplicated(llm$case_id)])
  stop(length(dupes), " case_id(s) appear more than once in ", run_dir,
       " (e.g. ", paste(head(dupes, 3), collapse = ", "), ").\n",
       "  This happens when a run was repeated into the same directory. ",
       "runs/ is append-only, so move the stale files aside rather than ",
       "deleting them.", call. = FALSE)
}

# ---------------------------------------------------------------------------
# Load the human labels and attach the LLM's decision to the same rows.
#
# Title is the join key: it is the only field the reviewer spreadsheets and the
# run records share. That makes it fragile -- a smart quote or a trimmed space
# breaks the match -- so the failure below reports the offending titles.
# ---------------------------------------------------------------------------
cols <- reviewer_columns(cfg)
humans_raw <- read_csv(here(cfg$inputs$merged_labels), show_col_types = FALSE)

humans <- humans_raw |>
  select(title = all_of(cols$title),
         all_of(setNames(paste0("consort_flag_", HUMANS), HUMANS)))

dat <- humans |>
  left_join(llm |> select(case_id, title, !!SYSTEM := evaluation), by = "title")

if (anyNA(dat[[SYSTEM]])) {
  unmatched <- dat$title[is.na(dat[[SYSTEM]])]
  stop(length(unmatched), " abstract(s) have a human label but no matched ",
       SYSTEM, " decision, so the title join failed.\n",
       "  First unmatched: ", paste(head(unmatched, 2), collapse = " | "), "\n",
       "  Titles are matched exactly. Common causes: the reviewer file and the ",
       "corpus were built from different snapshots, or the text differs by ",
       "whitespace, curly quotes, or unicode dashes.\n",
       "  Rerunning stage 02 and stage 03 from the current reviewer files ",
       "usually fixes it.", call. = FALSE)
}
dat <- dat |> relocate(case_id)

# ---------------------------------------------------------------------------
# The abstain label.
#
# The codebook lets the LLM answer "Human Review" when an abstract is too
# ambiguous to call. The humans in this study had no such option -- they
# recorded only Include or Exclude -- so "Human Review" is not a third opinion
# about the world, it is a refusal to give one. Left alone it would enter the
# model as a genuine third label class, and the LLM's guessing distribution
# would absorb it as though abstaining were a kind of answer.
#
# So it has to be resolved, and the choice is a judgement call rather than a
# fact. `analysis.human_review_action` in the experiment YAML records which
# one you made:
#
#   "include"  collapse to Include. Conservative for a screening step that
#              feeds a downstream full-text check: an abstain becomes "pass it
#              on to a human", which is what abstaining meant operationally.
#   "exclude"  collapse to Exclude. Appropriate if an abstain is closer to
#              "probably not eligible" in your workflow.
#   "keep"     treat Human Review as its own label class. Honest, but only
#              defensible if the humans could also abstain.
#   "drop"     remove those items entirely. Cleanest, at the cost of sample
#              size and of conditioning the corpus on the LLM's behaviour.
#
# Report which one you used, and check that it does not drive the result. In
# the worked example only 2 of 100 abstracts are affected and all four policies
# move the estimates negligibly; if the choice does change your conclusion,
# that is a finding about your codebook, not a detail to bury.
# ---------------------------------------------------------------------------
action <- cfg$analysis$human_review_action
ABSTAIN <- "Human Review"

n_hr <- sum(dat[[SYSTEM]] == ABSTAIN)
message(sprintf("%s emitted '%s' on %d / %d abstracts.",
                SYSTEM, ABSTAIN, n_hr, nrow(dat)))

recode_hr <- function(x, action) {
  if (action == "include")      ifelse(x == ABSTAIN, "Include", x)
  else if (action == "exclude") ifelse(x == ABSTAIN, "Exclude", x)
  else x
}

if (action == "drop") {
  n_before <- nrow(dat)
  dat <- dat |> filter(.data[[SYSTEM]] != ABSTAIN)
  message(sprintf("Dropped %d abstracts under human_review_action='drop'.",
                  n_before - nrow(dat)))
} else {
  dat <- dat |> mutate(across(all_of(RATERS), \(x) recode_hr(x, action)))
}
message(sprintf("Human Review policy: '%s'. Fitting on %d abstracts.",
                action, nrow(dat)))

# ---------------------------------------------------------------------------
# Reshape into the tidy (item, rater, label) frame the estimator expects.
#
# This long table is the exact input to the model, after the abstain policy has
# been applied, so it is written out as a result in its own right: it is the
# audit trail for what was actually fitted. Stage 05 reads it back.
# ---------------------------------------------------------------------------
long <- dat |>
  pivot_longer(all_of(RATERS), names_to = "rater_id", values_to = "evaluation") |>
  transmute(item_id = case_id, rater_id, evaluation)

results_dir <- here("results", experiment)
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(long, file.path(results_dir, "rater_labels_long.csv"))

evaluations <- long |> select(item_id, rater_id, evaluation)

# ---------------------------------------------------------------------------
# Fit the homogeneous model: one solving probability per rater, constant across
# items. (The estimator also supports a heterogeneous form where solving
# probability varies with per-item difficulty features; this baseline does not
# use it, so every rater gets a single intercept.)
# ---------------------------------------------------------------------------
message("\nFitting solve-or-guess (", SYSTEM, " as system rater)...")
fit <- solve_or_guess_fast(evaluations, system_rater_id = SYSTEM, verbose = FALSE)

abilities <- fit$rater_ability |>
  filter(parameter_id == "intercept") |>
  transmute(rater_id, p_hat = logit_inv(estimate))

# ---------------------------------------------------------------------------
# Confidence intervals by nonparametric bootstrap.
#
# We resample ABSTRACTS with replacement, not individual labels. That matters:
# an abstract is the unit that carries the agreement structure -- all four
# raters' opinions about the same item -- and resampling labels independently
# would destroy exactly the correlation the model is estimating.
# ---------------------------------------------------------------------------
message(sprintf("Bootstrapping (B = %d)...", B))
invisible(capture.output(
  boot <- nonparametric_bootstrap_solve_or_guess(
    evaluations, system_rater_id = SYSTEM, B = B, verbose = FALSE)
))

boot_p <- boot$bootstrap_rater_ability |>
  filter(parameter_id == "intercept") |>
  mutate(p = logit_inv(estimate)) |>
  select(bootstrap_iter, rater_id, p)

ci <- boot_p |>
  group_by(rater_id) |>
  summarise(ci_lower = quantile(p, 0.025),
            ci_upper = quantile(p, 0.975), .groups = "drop")

solving <- abilities |>
  left_join(ci, by = "rater_id") |>
  arrange(desc(p_hat))
write_csv(solving, file.path(results_dir, "solving_probabilities.csv"))

# ---------------------------------------------------------------------------
# Observed pairwise Cohen's kappa: a descriptive check, not part of the fit.
#
# Reported so you can see the raw agreement the model is working from. If the
# LLM's kappa with the humans sits inside the range of the humans' kappas with
# each other, the model's conclusion should not surprise you.
# ---------------------------------------------------------------------------
cohen_kappa <- function(a, b) {
  lv <- sort(union(unique(a), unique(b)))
  m  <- table(factor(a, lv), factor(b, lv)) / length(a)
  po <- sum(diag(m)); pe <- sum(rowSums(m) * colSums(m))
  if (abs(1 - pe) < 1e-12) NA_real_ else (po - pe) / (1 - pe)
}
pairs <- combn(RATERS, 2, simplify = FALSE)
pairwise_kappa <- map_dfr(pairs, function(p) {
  tibble(rater_a = p[1], rater_b = p[2],
         kappa = cohen_kappa(dat[[p[1]]], dat[[p[2]]]))
})
write_csv(pairwise_kappa, file.path(results_dir, "pairwise_kappa.csv"))

# ---------------------------------------------------------------------------
# The kappa-ratio: p_system / p_human, the headline estimand.
#
# Point estimate from the fit, interval from the bootstrap replicates. Read it
# as: > 1 means the LLM solves the task more often than that human, and an
# interval CONTAINING 1 means the data cannot tell them apart. Note what that
# does not mean -- an interval containing 1 is a failure to detect a
# difference, which with 100 items and wide intervals is a weak statement, not
# proof of equivalence.
# ---------------------------------------------------------------------------
boot_wide <- boot_p |>
  pivot_wider(names_from = rater_id, values_from = p)
p_of <- \(r) abilities$p_hat[abilities$rater_id == r]

kappa_ratios <- map_dfr(HUMANS, function(hr) {
  r <- boot_wide[[SYSTEM]] / boot_wide[[hr]]
  tibble(comparison = paste0(SYSTEM, " / ", hr),
         ratio_hat = p_of(SYSTEM) / p_of(hr),
         ci_lower  = quantile(r, 0.025),
         ci_upper  = quantile(r, 0.975))
})
write_csv(kappa_ratios, file.path(results_dir, "kappa_ratios_llm_vs_human.csv"))

# ---------------------------------------------------------------------------
# Console summary
# ---------------------------------------------------------------------------
cat("\n==================  Solving probability  (p_hat)  ==================\n")
solving |>
  mutate(across(where(is.numeric), \(x) round(x, 3)),
         rater = if_else(rater_id == SYSTEM, paste0(SYSTEM, " (system)"), rater_id)) |>
  select(rater, p_hat, ci_lower, ci_upper) |>
  print(n = Inf)

cat("\n==================  Pairwise Cohen's kappa  =======================\n")
pairwise_kappa |> mutate(kappa = round(kappa, 3)) |> print(n = Inf)

cat("\n==================  Kappa-ratio  (system vs human)  ===============\n")
kappa_ratios |>
  mutate(across(where(is.numeric), \(x) round(x, 3))) |>
  print(n = Inf)

cat(sprintf("\nWrote results to %s\n", results_dir))
cat("See results/README.md for how to read these tables.\n")
