# Rank-one diagnostic for the solve-or-guess fit (Rohe et al.).
#
# Under the model the off-diagonal agreement matrix is rank one plus a chance
# constant: A_ab = c + (1 - c) p_a p_b. We measure departure from that structure
# with the residual sum of squares T = sum_{a<b} (A_ab - c - (1-c) p_a p_b)^2,
# and obtain the null distribution of T by parametric bootstrap: simulate
# datasets from the fitted solve-or-guess model, refit the rank-one form, and
# recompute T. The p-value is the fraction of replicates with T >= T_observed.
# A large p-value means the agreement structure is consistent with the model.
#
# Input:   results/<experiment>/rater_labels_long.csv  (written by 04; the same
#          item x rater labels actually fitted, Human Review already collapsed)
# Output:  results/<experiment>/rank_one_diagnostic.csv
#
# Usage:   Rscript code/05_rank_one_diagnostic.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})

experiment <- "exp_001_codebook"
B          <- 1000
set.seed(20260625)

SG <- here("code")  # vendored estimator under code/em/ (see code/em/SOURCE.md)
source(file.path(SG, "em/spectral_initializer.R"))
source(file.path(SG, "em/tidy_solve_or_guess_fast.R"))

results_dir <- here("results", experiment)
long <- read_csv(file.path(results_dir, "rater_labels_long.csv"), show_col_types = FALSE)

RATERS <- c("A", "E", "H", "LLM")          # LLM is the system rater
m <- length(RATERS)

# --- observed agreement matrix A_ab = P(R_a = R_b) ---------------------------
wide <- long |>
  pivot_wider(names_from = rater_id, values_from = evaluation) |>
  select(all_of(RATERS))
agreement_matrix <- function(W) {
  M <- matrix(1, m, m, dimnames = list(RATERS, RATERS))
  for (a in 1:m) for (b in 1:m) if (a != b) M[a, b] <- mean(W[[a]] == W[[b]])
  M
}
A_obs <- agreement_matrix(wide)

# --- fit the rank-one + chance form, return T = off-diagonal RSS -------------
fit_rank_one <- function(A, p_init, c_init) {
  ut <- upper.tri(A)
  obj <- function(par) {
    c0 <- plogis(par[1]); p <- plogis(par[-1])
    pred <- c0 + (1 - c0) * outer(p, p)
    sum((A[ut] - pred[ut])^2)
  }
  clamp <- function(x) pmin(pmax(x, 1e-3), 1 - 1e-3)
  init <- c(qlogis(clamp(c_init)), qlogis(clamp(p_init)))
  optim(init, obj, method = "BFGS")$value
}

# --- fitted solve-or-guess parameters, for the parametric bootstrap ----------
evaluations <- long |> select(item_id, rater_id, evaluation)
fit <- solve_or_guess_fast(evaluations, system_rater_id = "LLM", verbose = FALSE)

p_hat <- setNames(
  vapply(RATERS, function(r) plogis(fit$rater_ability$estimate[
    fit$rater_ability$rater_id == r & fit$rater_ability$parameter_id == "intercept"]), numeric(1)),
  RATERS)
ev_levels <- sort(unique(fit$guessing_distribution$evaluation))
d <- length(ev_levels)
tau <- vapply(ev_levels, function(e)
  fit$class_distribution$prior_prob[fit$class_distribution$evaluation == e][1], numeric(1))
tau <- tau / sum(tau)
Pi <- matrix(0, m, d, dimnames = list(RATERS, ev_levels))
for (r in RATERS) for (e in ev_levels)
  Pi[r, e] <- fit$guessing_distribution$probability[
    fit$guessing_distribution$rater_id == r & fit$guessing_distribution$evaluation == e]
Pi <- Pi / rowSums(Pi)

n <- nrow(wide)
c_init <- sum(tau^2)
T_obs <- fit_rank_one(A_obs, p_init = p_hat, c_init = c_init)

# --- parametric bootstrap: simulate from the fitted model, recompute T -------
sim_T <- function() {
  Y <- sample(d, n, replace = TRUE, prob = tau)
  R <- matrix(0L, n, m, dimnames = list(NULL, RATERS))
  for (a in 1:m) {
    solved <- runif(n) < p_hat[a]
    R[, a] <- ifelse(solved, Y, sample(d, n, replace = TRUE, prob = Pi[a, ]))
  }
  A <- matrix(1, m, m); for (a in 1:m) for (b in 1:m) if (a != b) A[a, b] <- mean(R[, a] == R[, b])
  fit_rank_one(A, p_init = p_hat, c_init = c_init)
}
T_boot <- replicate(B, sim_T())
p_value <- mean(T_boot >= T_obs)

out <- tibble(statistic = "rank_one_RSS", T_obs = T_obs, B = B, p_value = p_value)
write_csv(out, file.path(results_dir, "rank_one_diagnostic.csv"))

cat("\n================  Rank-one diagnostic  ================\n")
cat(sprintf("  T_observed = %.5f\n", T_obs))
cat(sprintf("  parametric bootstrap p-value (B = %d) = %.3f\n", B, p_value))
cat(sprintf("  %s the solve-or-guess model at 0.05\n",
            if (p_value < 0.05) "REJECTS" else "fails to reject"))
cat(sprintf("\nWrote %s\n", file.path(results_dir, "rank_one_diagnostic.csv")))
