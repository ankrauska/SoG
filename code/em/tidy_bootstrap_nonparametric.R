###############################################################################
# nonparametric_bootstrap_solve_or_guess.R
#
# This R script provides a stand-alone function for performing a nonparametric
# (empirical) bootstrap on a fitted "Solve-or-Guess" model.
#
# In the Solve-or-Guess model, we have:
#   - A latent true label Y_i for each item i
#   - Multiple raters (system + h humans) who each either:
#       (a) Solve the item (with logistic probability) => correct label
#       (b) Fail to solve => guess from a rater-specific guess distribution
#   - The model is fit using an EM algorithm in the function solve_or_guess_fast()
#
# In a nonparametric bootstrap, we re-sample items (clusters) from the original
# dataset with replacement, preserving the rater evaluations for each item.
# We then re-fit the Solve-or-Guess model on each re-sampled dataset to estimate
# variability in the parameters.
#
# The function below:
#  - Takes the original evaluations and difficulty data (same as solve_or_guess)
#  - Re-samples entire items with replacement
#  - Re-fits solve_or_guess_fast() on each bootstrap replicate
#  - Collects the rater_ability (beta) estimates across replicates
#  - Returns a large data frame of these parameter estimates for post-hoc
#    analysis of confidence intervals, standard errors, etc.
#
# Usage:
#   boot_out <- nonparametric_bootstrap_solve_or_guess_fast(
#     evaluations     = my_original_evals,
#     difficulty      = my_original_difficulty,
#     system_rater_id = "system",
#     B               = 200
#   )
#
#   # Summarize results (e.g., computing mean & SD):
#   library(dplyr)
#   summary_df <- boot_out$bootstrap_rater_ability %>%
#     group_by(rater_id, parameter_id) %>%
#     summarize(
#       mean_est = mean(estimate),
#       sd_est   = sd(estimate),
#       .groups  = "drop"
#     )
#
#   # For percentile-based CI:
#   ci_df <- boot_out$bootstrap_rater_ability %>%
#     group_by(rater_id, parameter_id) %>%
#     summarize(
#       lower_95 = quantile(estimate, 0.025),
#       median   = median(estimate),
#       upper_95 = quantile(estimate, 0.975),
#       .groups  = "drop"
#     )
#
###############################################################################

nonparametric_bootstrap_solve_or_guess <- function(
    evaluations,
    difficulty = NULL,
    system_rater_id = "system",
    B = 100,         # number of bootstrap replicates
    max_iter = 100,  # EM fitting iterations for solve_or_guess
    tol = 1e-6,      # EM convergence tolerance
    verbose = TRUE   # whether to print progress messages
) {
  # ---------------------------------------------------------------------------
  # 1) Identify the set of distinct items
  #    We'll resample from these item_ids with replacement.
  # ---------------------------------------------------------------------------
  library(dplyr)
  library(tidyr)
  library(tibble)

  # The evaluations data frame must have columns: (item_id, rater_id, evaluation)
  # The 'solve_or_guess_fast()' function typically requires these, so we assume
  # they've been validated before.
  unique_items <- unique(evaluations$item_id)
  n_items <- length(unique_items)  # total number of distinct items

  # ---------------------------------------------------------------------------
  # 2) Create a helper function that, given a vector of sampled items,
  #    constructs a new (bootstrap) dataset for that replicate.
  # ---------------------------------------------------------------------------
  # Items can appear multiple times if the sampling draws duplicates, so
  # we will rename them to keep them distinct. For example, if "item_5"
  # appears twice, we'll rename them as "item_5.1" and "item_5.2" in
  # the bootstrap dataset so the model sees them as separate items.
  #
  # This is a standard "cluster bootstrap" approach at the item level.
  # ---------------------------------------------------------------------------
  build_bootstrap_dataset <- function(sampled_items) {
    # We'll build "eval_boot" and "diff_boot".
    # 1) Start with an empty list for evaluations
    eval_list <- list()
    # 2) Similarly for difficulty
    diff_list <- list()

    # We'll track a numeric index to build up the lists
    idx_eval <- 1
    idx_diff <- 1

    # Each element of sampled_items might be repeated or unique
    # We'll assign a suffix .1, .2, ... for each repeated occurrence
    for (i in seq_along(sampled_items)) {
      orig_item <- sampled_items[i]
      # Let's define a new item_id to represent this "replicated" version
      # of the original item
      new_item_id <- paste0(orig_item, ".", i)

      # 1) Filter the original evaluations for this item
      sub_eval <- evaluations %>%
        filter(item_id == orig_item)

      # Rename item_id to new_item_id
      if (nrow(sub_eval) > 0) {
        sub_eval$item_id <- new_item_id
      }

      # 2) Filter the original difficulty for this item (if difficulty is provided)
      if (!is.null(difficulty) && nrow(difficulty) > 0) {
        sub_diff <- difficulty %>%
          filter(item_id == orig_item)
        if (nrow(sub_diff) > 0) {
          sub_diff$item_id <- new_item_id
        }
      } else {
        sub_diff <- tibble(
          item_id    = character(0),
          feature_id = character(0),
          value      = numeric(0)
        )
      }

      # Store in the growing lists
      eval_list[[idx_eval]] <- sub_eval
      idx_eval <- idx_eval + 1

      diff_list[[idx_diff]] <- sub_diff
      idx_diff <- idx_diff + 1
    }

    # Combine all sub-dataframes
    eval_boot <- bind_rows(eval_list)
    diff_boot <- bind_rows(diff_list)
    if(nrow(diff_boot)==0) diff_boot = NULL

    # Return a list of the bootstrap evaluations + difficulty
    list(
      evaluations = eval_boot,
      difficulty  = diff_boot
    )
  }

  # ---------------------------------------------------------------------------
  # 3) MAIN BOOTSTRAP LOOP
  #    - For each of B replicates, we:
  #      (a) sample n_items from unique_items (with replacement)
  #      (b) build the new dataset
  #      (c) call solve_or_guess_fast() on that dataset
  #      (d) store rater_ability results
  # ---------------------------------------------------------------------------
  all_boot_estimates <- vector("list", B)

  for (b in seq_len(B)) {
    if (verbose) {
      message(sprintf("Nonparametric bootstrap replicate %d / %d ...", b, B))
    }

    # (a) Sample item_ids (with replacement)
    #     We sample exactly n_items to match the original dataset size
    sampled_items <- sample(unique_items, size=n_items, replace=TRUE)

    # (b) Build the new dataset for these sampled items
    boot_data <- build_bootstrap_dataset(sampled_items)

    # (c) Re-fit solve_or_guess on this new dataset
    boot_fit <- solve_or_guess_fast(
      evaluations     = boot_data$evaluations,
      difficulty      = boot_data$difficulty,
      system_rater_id = system_rater_id,
      max_iter        = max_iter,
      tol             = tol,
      verbose         = FALSE
    )

    # (d) Extract the rater_ability tibble
    #     We'll add a column "bootstrap_iter" = b
    boot_ability <- boot_fit$rater_ability %>%
      mutate(bootstrap_iter = b)

    all_boot_estimates[[b]] <- boot_ability
  }

  # Combine all replicate results into a single data frame
  all_boot_estimates_df <- bind_rows(all_boot_estimates)

  # ---------------------------------------------------------------------------
  # 4) RETURN THE RESULTS
  #    The main output is:
  #      - $bootstrap_rater_ability: data frame with columns
  #          (rater_id, parameter_id, estimate, bootstrap_iter)
  #    which can be used to compute means, SDs, percentile CIs, etc.
  # ---------------------------------------------------------------------------
  list(
    n_boot = B,
    bootstrap_rater_ability = all_boot_estimates_df
  )
}
