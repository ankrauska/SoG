# Fit the solve-or-guess model to the four raters (humans A/E/H + LLM) on the
# CONSORT-eligibility screening task, to estimate each rater's solving
# probability and compare the LLM against the humans without a gold standard.
#
# This mirrors the RoB2 application in
#   ~/solve_or_guess/section_applications.tex
# one automated system + several humans, homogeneous model, solving
# probabilities with nonparametric bootstrap confidence intervals.
#
# Inputs:
#   data/derived/human_reviewer_labels_merged.csv   humans A/E/H, joined on Title
#   runs/<experiment>/<condition>/*.json            one LLM decision per abstract
#
# Outputs (under results/<experiment>/):
#   rater_labels_long.csv          tidy item x rater label matrix actually fitted
#   solving_probabilities.csv      p_hat per rater + 95% bootstrap CI  (main table)
#   pairwise_kappa.csv             observed Cohen's kappa, all six rater pairs
#   kappa_ratios_llm_vs_human.csv  p_LLM / p_human with 95% bootstrap CI
#
# Usage:
#   Rscript code/04_run_solve_or_guess.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(jsonlite)
})

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
experiment <- "exp_001_codebook"
condition  <- "baseline"
B          <- 1000              # bootstrap replicates
set.seed(20260624)

# How to treat the LLM's "Human Review" label in the analysis. The codebook
# allows Include / Exclude / Human Review, but Human Review is a refusal to
# decide, not a third population class, and the three humans never use it.
# This choice is the open question in spec.md (decision_human_review_label.md).
#   "include" - collapse Human Review -> Include (conservative for screening)
#   "exclude" - collapse Human Review -> Exclude
#   "keep"    - treat Human Review as its own label class
#   "drop"    - drop any item the LLM sent to Human Review
HUMAN_REVIEW_ACTION <- "include"

# Solve-or-guess methodology lives in the sibling project.
SG <- here("code")  # vendored estimator under code/em/ (see code/em/SOURCE.md)
source(file.path(SG, "em/spectral_initializer.R"))
source(file.path(SG, "em/tidy_solve_or_guess_fast.R"))
source(file.path(SG, "em/tidy_bootstrap_nonparametric.R"))

logit_inv <- function(x) 1 / (1 + exp(-x))

# ---------------------------------------------------------------------------
# Load the LLM decisions (one JSON record per abstract)
# ---------------------------------------------------------------------------
run_dir   <- here("runs", experiment, condition)
llm_files <- list.files(run_dir, pattern = "\\.json$", full.names = TRUE)
stopifnot(length(llm_files) > 0)

llm <- map_dfr(llm_files, function(f) {
  j <- fromJSON(f, simplifyVector = TRUE)
  tibble(case_id = j$case_id, title = j$title, LLM = j$output$consort_flag)
})
# n_runs = 1, so expect exactly one record per case.
stopifnot(!any(duplicated(llm$case_id)))

# ---------------------------------------------------------------------------
# Load the human labels and join the LLM to them on title
# ---------------------------------------------------------------------------
humans <- read_csv(here("data/derived/human_reviewer_labels_merged.csv"),
                   show_col_types = FALSE) |>
  select(title = Title, A = consort_flag_A, E = consort_flag_E, H = consort_flag_H)

dat <- humans |>
  left_join(llm |> select(case_id, title, LLM), by = "title")

# Every human-labelled abstract must have an LLM decision.
if (anyNA(dat$LLM)) {
  stop(sprintf("%d abstracts have no matched LLM decision (title join failed).",
               sum(is.na(dat$LLM))))
}
dat <- dat |> relocate(case_id)

# ---------------------------------------------------------------------------
# Apply the Human Review policy
# ---------------------------------------------------------------------------
n_hr <- sum(dat$LLM == "Human Review")
message(sprintf("LLM emitted 'Human Review' on %d / %d abstracts.", n_hr, nrow(dat)))

recode_hr <- function(x, action) {
  if (action == "include") ifelse(x == "Human Review", "Include", x)
  else if (action == "exclude") ifelse(x == "Human Review", "Exclude", x)
  else x
}

if (HUMAN_REVIEW_ACTION == "drop") {
  dropped <- dat |> filter(LLM == "Human Review")
  dat <- dat |> filter(LLM != "Human Review")
  message(sprintf("Dropped %d abstracts under HUMAN_REVIEW_ACTION='drop'.",
                  nrow(dropped)))
} else {
  dat <- dat |> mutate(across(c(A, E, H, LLM), \(x) recode_hr(x, HUMAN_REVIEW_ACTION)))
}
message(sprintf("Human Review policy: '%s'. Fitting on %d abstracts.",
                HUMAN_REVIEW_ACTION, nrow(dat)))

# ---------------------------------------------------------------------------
# Build the tidy evaluations frame the estimator expects
# ---------------------------------------------------------------------------
RATERS <- c("A", "E", "H", "LLM")          # LLM is the "system" rater
long <- dat |>
  pivot_longer(all_of(RATERS), names_to = "rater_id", values_to = "evaluation") |>
  transmute(item_id = case_id, rater_id, evaluation)

results_dir <- here("results", experiment)
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(long, file.path(results_dir, "rater_labels_long.csv"))

evaluations <- long |> select(item_id, rater_id, evaluation)

# ---------------------------------------------------------------------------
# Fit the homogeneous solve-or-guess model
# ---------------------------------------------------------------------------
message("\nFitting solve-or-guess (LLM as system rater)...")
fit <- solve_or_guess_fast(evaluations, system_rater_id = "LLM", verbose = FALSE)

abilities <- fit$rater_ability |>
  filter(parameter_id == "intercept") |>
  transmute(rater_id, p_hat = logit_inv(estimate))

# ---------------------------------------------------------------------------
# Nonparametric (item) bootstrap for confidence intervals
# ---------------------------------------------------------------------------
message(sprintf("Bootstrapping (B = %d)...", B))
invisible(capture.output(
  boot <- nonparametric_bootstrap_solve_or_guess(
    evaluations, system_rater_id = "LLM", B = B, verbose = FALSE)
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
# Observed pairwise Cohen's kappa (descriptive, as Minozzi et al. reported)
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
# Kappa-ratio: p_LLM / p_human, the primary estimand (spec.md). Point estimate
# from the fit; interval from the bootstrap replicates. CI containing 1.0 means
# the LLM is statistically indistinguishable from that human.
# ---------------------------------------------------------------------------
boot_wide <- boot_p |>
  pivot_wider(names_from = rater_id, values_from = p)
p_of <- \(r) abilities$p_hat[abilities$rater_id == r]

kappa_ratios <- map_dfr(c("A", "E", "H"), function(hr) {
  r <- boot_wide[["LLM"]] / boot_wide[[hr]]
  tibble(comparison = paste0("LLM / ", hr),
         ratio_hat = p_of("LLM") / p_of(hr),
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
         rater = if_else(rater_id == "LLM", "LLM (system)", rater_id)) |>
  select(rater, p_hat, ci_lower, ci_upper) |>
  print(n = Inf)

cat("\n==================  Pairwise Cohen's kappa  =======================\n")
pairwise_kappa |> mutate(kappa = round(kappa, 3)) |> print(n = Inf)

cat("\n==================  Kappa-ratio  (LLM vs human)  ==================\n")
kappa_ratios |>
  mutate(across(where(is.numeric), \(x) round(x, 3))) |>
  print(n = Inf)

cat(sprintf("\nWrote results to %s\n", results_dir))
