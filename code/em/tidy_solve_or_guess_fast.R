###############################################################################
# Solve-or-Guess EM with Logistic Regression in R
#
# This file contains:
#   1) logistic_fit()   <-- corresponds to Algorithm 1 (Logistic Regression)
#   2) fast_E_step()         <-- corresponds to Algorithm 2 (E-step; lightly extended
#                           to also return per-item posterior of Y_i)
#   3) M-step is split between fast_E_step() outputs and EM_fit() updates
#                        (see Algorithm 3 steps in code)
#   4) EM_fit()         <-- corresponds to Algorithm 4 (Overall EM Routine)
#   5) spectral_initializer()  <-- used for intercept initialization
#   6) solve_or_guess() <-- a high-level wrapper that:
#         - takes tidy input data frames (evaluations, difficulty)
#         - handles factor/character -> numeric conversions
#         - handles missing evaluations as a separate class
#         - (optionally) adds difficulty features as covariates
#         - calls EM_fit() and returns the final model parameters in a tidy format
#
# In this model, we have:
#   Y_i = Y(X_i)  (unobserved true label)
#   R_{0,i}       (machine's observed label on item i)
#   R_{a,i}       (human rater a's observed label on item i, a=1..h)
#   S_{a,i} in {0,1} (success indicator for rater a on item i)
#   G_{a,i} in {1..d} (guess distribution for rater a)
#   Z_i in R^f    (feature vector for item i)
#
# Model Definition:
#
# The Solve-or-Guess (SG) model posits that for each item i, there exists
# an underlying true label Y_i in {1, 2, ..., d}. Each rater a in {0, 1, ..., h}
# provides an observed label R_{a,i} in {1, 2, ..., d} based on their ability
# to correctly identify the true label.
#
# Specifically:
#   - If rater a succeeds in solving the item (S_{a,i} = 1), then R_{a,i} = Y_i.
#   - If rater a fails to solve the item (S_{a,i} = 0), then R_{a,i} is drawn
#     from the guess distribution pi(G_a).
#
# The success probability s_a(Z_i) for rater a on item i is modeled
# as a logistic function of the feature vector Z_i:
#
#     s_a(Z_i) = logit^{-1}( beta_a^T Z_i ) = 1 / (1 + e^{ - beta_a^T Z_i })
#
# All latent variables (Y_i, S_{a,i}, G_{a,i}) are assumed to be independent
# across items and raters, given Z_i.
#
###############################################################################

# If you use dplyr or tidyr in the wrapper, ensure they're loaded:
# library(dplyr)
# library(tidyr)

############################
# Utility: logistic sigmoid
############################

logit_inv <- function(x) {
  1 / (1 + exp(-x))
}

############################
# Algorithm 1: Logistic Regression with Fractional Outcomes
############################

logistic_fit <- function(Z, y, start=NULL, maxit=100, tol=1e-6) {
  # Corresponds to Algorithm 1 in pseudo-code.
  #
  # Inputs:
  #   Z:    n x f matrix of features
  #   y:    length-n vector of fractional outcomes, in [0,1]
  #   start: optional initial parameter vector (length f)
  #   maxit: maximum number of iterations
  #   tol:   convergence tolerance
  #
  # Output:
  #   A fitted parameter vector (beta) of length f
  #
  # Explanation of approach:
  #   We perform a Newton-Raphson iteration. On each iteration:
  #     1. Compute predictions p = logit_inv(Z %*% beta)
  #     2. Compute gradient: grad = t(Z) %*% (y - p)
  #     3. Compute Hessian: H = t(Z) %*% (Z * (p * (1 - p)))
  #     4. Update parameters: beta_new = beta + solve(H, grad)
  #
  n <- nrow(Z)
  f <- ncol(Z)

  # If no initial parameters given, start from zero
  if (is.null(start)) {
    beta <- rep(0, f)
  } else {
    beta <- start
  }

  for (it in 1:maxit) {
    p <- logit_inv(Z %*% beta)

    # Gradient
    grad <- t(Z) %*% (y - p)

    # Hessian
    W <- as.numeric(p * (1 - p))
    # Multiply each column of Z by W
    H <- t(Z) %*% (Z * W)
    epsilon = median(abs(H))/100
    H = H+ epsilon*diag(rep(1, nrow(H)))

    # Newton-Raphson update
    step <- solve(H, grad)
    beta_new <- beta + step

    # Convergence check
    if (sqrt(sum((beta_new - beta)^2)) < tol) {
      beta <- beta_new
      break
    }
    beta <- beta_new
  }

  return(as.numeric(beta))
}

############################
# Algorithm 2: E-step
############################


fast_E_step<- function(R0, R_h, Z,
                        piY, piG0, piGa,
                        beta0, betaList,
                        d, h) {
  # -------------------------------------------------------------------
  # This function returns exactly the same structure as your E_step():
  #   list( S0, Sa, P_Y, countG0, countGa, posteriorYi )
  # but computes them in a O(n*d*h) manner rather than enumerating 2^(h+1).
  #
  # R0: length-n vector of machine (system) labels in {1..d}
  # R_h: n x h matrix of human labels in {1..d}
  # Z: n x f feature matrix (including intercept!)
  # piY, piG0, piGa: the prior/class distributions for each rater
  # beta0, betaList: logistic parameters for machine & humans
  # d, h: number of classes & number of human raters
  #
  # Assumes NO missing data. If you do have missing data, you'd need
  # special handling or skip them.
  #
  # Returns a list:
  #   - S0: length-n vector of E[S_{0,i}]
  #   - Sa: n x h matrix of E[S_{a,i}]
  #   - P_Y: length-d vector of sum_{i} p(Y_i=j)
  #   - countG0: length-d, how many times machine guessed label j
  #   - countGa: h x d matrix, how many times each human guessed j
  #   - posteriorYi: n x d matrix of p(Y_i=j)
  #   - log_lik: scalar observed-data log-likelihood log P(R | theta)
  # -------------------------------------------------------------------

  n <- nrow(Z)

  # 1) Compute success probabilities
  logit_inv <- function(x) 1/(1+exp(-x))

  # System success prob
  s0_vec <- logit_inv(Z %*% beta0)  # length-n
  # Human success prob
  sA_mat <- matrix(0, n, h)
  for (a in seq_len(h)) {
    sA_mat[, a] <- logit_inv(Z %*% betaList[[a]])
  }

  # 2) Compute p(Y_i=y | R0, R_h) for each i, y
  #    gamma[i,y] in old notation.
  #    Also accumulate the observed-data log-likelihood log P(R | theta)
  #    = sum_i log P(R_i | theta), where P(R_i | theta) is the per-item
  #    normalizer that we already compute as `denom` below.
  gammaMat <- matrix(0, nrow=n, ncol=d)
  log_lik <- 0

  for (i in 1:n) {
    # We'll build a length-d vector of unnormalized log-likelihood for Y_i = y
    # Then normalize. This is effectively:
    #   piY[y] * \prod_{a=0}^h [ p_a^solve or guessDist ]
    # Machine is a=0 => R0[i], success prob = s0_vec[i], guessDist = piG0
    # Humans a=1..h => R_h[i,a], success prob = sA_mat[i,a], guessDist= piGa[a,].

    numer <- numeric(d)
    for (y in 1:d) {
      val <- piY[y]

      # Machine's contribution
      r0i <- R0[i]
      if (r0i == y) {
        # Could be solve => s0_vec[i], or guess => (1-s0_vec[i])* piG0[y]
        val <- val * ( s0_vec[i] + (1 - s0_vec[i])* piG0[y] )
      } else {
        # Must be guess => (1-s0_vec[i])* piG0[r0i]
        val <- val * ( (1 - s0_vec[i]) * piG0[r0i] )
      }

      # Humans
      for (a in 1:h) {
        r_ai <- R_h[i,a]
        # If r_ai == y => solve or guess y
        # else => must guess r_ai
        if (r_ai == y) {
          val <- val * ( sA_mat[i,a] + (1 - sA_mat[i,a])* piGa[a, y] )
        } else {
          val <- val * ( (1 - sA_mat[i,a]) * piGa[a, r_ai] )
        }
      }
      numer[y] <- val
    }

    denom <- sum(numer)
    if (denom < 1e-15) { denom <- 1e-15 }

    gammaMat[i, ] <- numer / denom
    log_lik <- log_lik + log(denom)
  } # end for i

  # 3) Next, we want E[S_{0,i}] and E[S_{a,i}].
  #    E[S_{0,i}] = sum_{y=1}^d p(Y_i=y) * p(S_{0,i}=1 | Y_i=y, R0[i])
  # But the conditional p(S_{0,i}=1 | Y_i=y, R0[i]) is alpha_{i,0,y} in the
  # standard solve-or-guess formula:
  #
  #   alpha_{i,0,y} = 0 if R0[i]!= y,
  #   otherwise = s0_vec[i] / [ s0_vec[i] + (1-s0_vec[i])* piG0[y ] ]
  #
  # So define alpha_{i,0,y}, then sum over y.

  S0 <- numeric(n)  # E[S_{0,i}]
  Sa <- matrix(0, nrow=n, ncol=h)  # E[S_{a,i}]

  for (i in 1:n) {
    r0i <- R0[i]
    # alpha_{i,0,y}
    denomSolve0 <- s0_vec[i] + (1 - s0_vec[i])* piG0[r0i]
    if (denomSolve0 < 1e-15) denomSolve0 <- 1e-15
    alpha0i <- s0_vec[i]/denomSolve0  # only valid if y==r0i, else 0

    # So E[S_{0,i}] = gammaMat[i, r0i]* alpha0i
    S0[i] <- gammaMat[i, r0i] * alpha0i

    # For humans
    for (a in 1:h) {
      r_ai <- R_h[i,a]
      denomSolve_a <- sA_mat[i,a] + (1 - sA_mat[i,a])* piGa[a, r_ai]
      if (denomSolve_a < 1e-15) denomSolve_a <- 1e-15
      alpha_ai <- sA_mat[i,a] / denomSolve_a
      Sa[i,a]  <- gammaMat[i, r_ai] * alpha_ai
    }
  }

  # 4) Accumulate guess counts
  #    For the machine: how many times (posterior) we guess label j
  #    guessCount0[j] = sum_{i} sum_{y} gamma[i,y]* 1_{(r0i = j, S0=0? ... )}
  # Actually it's easier to use the same logic used above:
  # If R0[i] = j, the posterior that it was a guess is gamma[i,j]*(1 - alpha0i).
  # If R0[i] != j, to get label j from the machine is impossible for that item i
  #  => but wait, a "minimal" approach is:
  # We'll do it in one pass:
  # guessCount0[j] += sum_{i where R0[i]==j} [ gamma[i, j]*(1-alpha0i ) + sum_{y != j} gamma[i,y] ] ???
  # Actually simpler is the factorization approach used in the "fast" or "monolithic" code:
  #   for each i:
  #     let j = R0[i]
  #     guessCount0[j] += sum_{y!=j} gamma[i,y] + gamma[i,j]*(1 - alpha0i).

  countG0 <- numeric(d)
  countGa <- matrix(0, nrow=h, ncol=d)

  for (i in 1:n) {
    # Machine
    r0i <- R0[i]
    alpha0i <- S0[i]/(gammaMat[i, r0i] + 1e-15)  # effectively E[S0|Y=r0i]/p(Y=r0i)
    # Or we can recompute the denominator quickly:
    # Actually simpler: alpha0i = ???

    # direct approach:
    # guessCount0[r0i] += sum_{y != r0i} gammaMat[i,y] + gammaMat[i,r0i]*(1 - alpha0i)
    # We already have alpha0i.
    # But recall alpha0i=  s0_vec[i]/[ s0_vec[i] + (1-s0_vec[i]) * piG0[r0i] ]
    # Then E[S0[i]] = gammaMat[i,r0i]*alpha0i
    # => so the fraction of "guesses" for label r0i is gammaMat[i,r0i]*(1-alpha0i).
    # For y != r0i, machine must have guessed label r0i if Y=y. => gammaMat[i,y].
    # So total = sum_{y != r0i} gammaMat[i,y] + gammaMat[i,r0i]*(1-alpha0i)
    guessCount0_term <- sum(gammaMat[i, ]) - gammaMat[i, r0i]*alpha0i
    countG0[r0i] <- countG0[r0i] + guessCount0_term

    # Humans
    for (a in 1:h) {
      ra <- R_h[i,a]
      alpha_ai <- Sa[i,a]/(gammaMat[i, ra] + 1e-15)  # same logic
      guessCount_a_term <- sum(gammaMat[i, ]) - gammaMat[i, ra]*alpha_ai
      countGa[a, ra] <- countGa[a, ra] + guessCount_a_term
    }
  }

  # 5) Summaries
  P_Y <- colSums(gammaMat)  # sum_{i} gamma[i,y]

  # Return the same structure as original E_step, plus log_lik
  list(
    S0 = S0,                # length-n
    Sa = Sa,                # n x h
    P_Y = P_Y,              # length-d
    countG0 = countG0,      # length-d
    countGa = countGa,      # h x d
    posteriorYi = gammaMat, # n x d
    log_lik = log_lik       # scalar log P(R | theta)
  )
}



############################
# Algorithm 4: EM Routine
############################

EM_fit <- function(R0, R_h, Z, d, h,
                   max_iter=100, tol=1e-6, quiet = TRUE) {
  # Corresponds to Algorithm 4 in pseudo-code.
  #
  # Inputs:
  #   R0:    length-n vector of machine outputs in {1,...,d}
  #   R_h:   n x h matrix of human rater outputs in {1,...,d}
  #   Z:     n x f feature matrix (including intercept)
  #   d:     number of classes
  #   h:     number of human raters
  #   max_iter: maximum EM iterations
  #   tol:      convergence threshold
  #
  # Output:
  #   A list of fitted parameters:
  #     piY:      class prior (length-d)
  #     piG0:     guess distribution for machine (length-d)
  #     piGa:     guess distributions for each human rater (h x d)
  #     beta0:    machine logistic parameters (f-vector)
  #     betaList: list of length h, each logistic parameter vector for rater a
  #   Also returns the final E-step outputs in "final_E" for convenience
  #
  # Steps remain the same as your original code.  We only add
  # a final call to fast_E_step() at the end to retrieve the final
  # item-level posteriors (posteriorYi).

  n <- nrow(Z)

  # ----------------------------
  # Initialize the parameters
  # ----------------------------

  # Initialize piY, piG0, piGa to uniform distributions
  piY <- rep(1/d, d)         # Uniform class prior
  piG0 <- rep(1/d, d)        # Uniform machine guess distribution
  piGa <- matrix(1/d, h, d)  # Uniform guess distributions for human raters

  # Initialize logistic parameters using Spectral Initialization
  ev <- spectral_initializer(M = R0, H = R_h, R = h)  # Length h + 1
  # Machine:
  beta0 <- c(ev[1], rep(0, ncol(Z) - 1))
  # Humans:
  betaList <- lapply(1:h, function(a) c(ev[a + 1], rep(0, ncol(Z) - 1)))

  # ----------------------------
  # EM Iterations
  # ----------------------------
  # Convergence is on the change in observed-data log-likelihood,
  # log P(R | theta), as computed by fast_E_step. The check happens
  # before the M-step, so on convergence we return the parameters from
  # the previous iteration's M-step (which produced the current log_lik).
  prev_log_lik <- -Inf
  for (iter in 1:max_iter) {

    # ----------- E-step -----------
    estep <- fast_E_step(R0, R_h, Z, piY, piG0, piGa,
                    beta0, betaList, d, h)

    S0 <- estep$S0
    Sa <- estep$Sa
    P_Y <- estep$P_Y
    countG0 <- estep$countG0
    countGa <- estep$countGa
    cur_log_lik <- estep$log_lik

    # ----------- Convergence check (log-likelihood) -----------
    diff_ll <- cur_log_lik - prev_log_lik
    if (!quiet) cat("Iteration:", iter,
                    "log-lik:", cur_log_lik,
                    "change:", diff_ll, "\n")
    if (iter > 1 && abs(diff_ll) < tol) {
      cat("Convergence achieved after", iter, "iterations.\n")
      break
    }
    prev_log_lik <- cur_log_lik

    # ----------- M-step -----------
    # (i) Update pi(Y)
    piY_new <- P_Y / sum(P_Y)

    # (ii) Update pi(G_0) and pi(G_a)
    piG0_new <- countG0 / sum(countG0)
    piGa_new <- piGa
    for (a in 1:h) {
      piGa_new[a, ] <- countGa[a, ] / sum(countGa[a, ])
    }

    # (iii) Update beta0 (machine logistic parameters)
    beta0_new <- logistic_fit(Z, S0, start=beta0)

    # (iv) Update beta_a for each human rater via logistic regression
    betaList_new <- list()
    for (a in 1:h) {
      betaList_new[[a]] <- logistic_fit(Z, Sa[, a], start=betaList[[a]])
    }

    # Accept parameter updates
    piY <- piY_new
    piG0 <- piG0_new
    piGa <- piGa_new
    beta0 <- beta0_new
    betaList <- betaList_new
  }

  # Perform a final E-step to gather final item-level posteriors
  final_estep <- fast_E_step(R0, R_h, Z, piY, piG0, piGa,
                        beta0, betaList, d, h)

  return(list(
    piY = piY,
    piG0 = piG0,
    piGa = piGa,
    beta0 = beta0,
    betaList = betaList,
    final_E = final_estep
  ))
}
#
# # ----------------------------
# # Spectral Initializer Function
# # ----------------------------
# source("tidy_src/spectral_initializer.R")

# ----------------------------
# Wrapper Function
# ----------------------------
solve_or_guess_fast <- function(evaluations,
                           difficulty = NULL,
                           yes_label = "yes",
                           no_label = "no",
                           system_rater_id = "system",
                           max_iter = 100,
                           tol = 1e-6,
                           verbose = TRUE) {
  # ----------------------------------------------------------------
  # Step A: Validate and tidy the "evaluations" data
  # ----------------------------------------------------------------
  required_cols_eval <- c("item_id", "rater_id", "evaluation")
  if (!all(required_cols_eval %in% names(evaluations))) {
    stop("`evaluations` must contain columns: item_id, rater_id, evaluation")
  }

  # Identify unique items and raters
  all_items  <- unique(evaluations$item_id)
  all_raters <- unique(evaluations$rater_id)

  # Build a full grid to catch missing evaluations
  full_grid <- expand.grid(item_id = all_items, rater_id = all_raters,
                           stringsAsFactors = FALSE)
  merged <- dplyr::left_join(full_grid, evaluations,
                             by = c("item_id", "rater_id"))

  # Check for missing evaluations
  num_missing <- sum(is.na(merged$evaluation))
  if (num_missing > 0) {
    warning(sprintf("There are %d missing evaluations. Treated as 'MISSING' class.",
                    num_missing))
  }

  # Convert missing to "MISSING"
  merged$evaluation <- as.character(merged$evaluation)
  merged$evaluation[is.na(merged$evaluation)] <- "MISSING"
  merged$evaluation <- factor(merged$evaluation, exclude = NULL)

  evaluation_levels <- levels(merged$evaluation)
  d <- length(evaluation_levels)  # total classes

  # Identify system vs. human raters
  if (! (system_rater_id %in% all_raters)) {
    stop(sprintf("System rater_id '%s' not found in the data!", system_rater_id))
  }
  human_raters <- setdiff(all_raters, system_rater_id)
  rater_order  <- c(system_rater_id, human_raters)

  # Order item_id and rater_id to form consistent row/column arrangement
  item_order <- sort(all_items)
  merged$item_id  <- factor(merged$item_id, levels = item_order)
  merged$rater_id <- factor(merged$rater_id, levels = rater_order)
  merged <- merged[order(merged$item_id, merged$rater_id), ]

  n <- length(item_order)
  h <- length(human_raters)

  # Create a matrix of dimension (n, 1+h) for all rater evaluations
  big_mat <- matrix(NA_integer_, nrow = n, ncol = (h + 1))
  for (i_item in seq_len(n)) {
    # subset the rows for item i_item
    irows <- merged[merged$item_id == item_order[i_item], ]
    numeric_vec <- as.integer(irows$evaluation)  # factor => integer
    big_mat[i_item, ] <- numeric_vec
  }
  R0 <- big_mat[, 1]                # system
  R_h <- big_mat[, -1, drop=FALSE]  # humans

  # ----------------------------------------------------------------
  # Step B: Build the feature matrix Z
  # ----------------------------------------------------------------
  if (is.null(difficulty)) {
    # no features, just intercept
    Z <- matrix(1, nrow=n, ncol=1)
    colnames(Z) <- "intercept"
  } else {
    required_cols_diff <- c("item_id", "feature_id", "value")
    if (!all(required_cols_diff %in% names(difficulty))) {
      stop("`difficulty` must contain columns: item_id, feature_id, value")
    }
    wide_diff <- tidyr::pivot_wider(difficulty,
                                    id_cols = "item_id",
                                    names_from = "feature_id",
                                    values_from = "value",
                                    values_fill = 0)
    wide_diff$item_id <- factor(wide_diff$item_id, levels = item_order)
    wide_diff <- wide_diff[order(wide_diff$item_id), ]
    feat_mat <- as.matrix(wide_diff[, setdiff(names(wide_diff), "item_id"), drop=FALSE])
    Z <- cbind(1, feat_mat)
    colnames(Z) <- c("intercept", colnames(feat_mat))
  }
  f <- ncol(Z)

  # ----------------------------------------------------------------
  # Step C: Run the EM Fit
  # ----------------------------------------------------------------
  fit <- EM_fit(R0, R_h, Z, d, h, max_iter = max_iter, tol = tol)
  # The final E-step results are in fit$final_E
  estep_f <- fit$final_E

  piY     <- fit$piY
  piG0    <- fit$piG0
  piGa    <- fit$piGa
  beta0   <- fit$beta0
  betaList<- fit$betaList

  # ----------------------------------------------------------------
  # Step D: Build the four requested tidy data outputs
  # ----------------------------------------------------------------

  # 1) rater_ability
  # system rater => beta0, humans => betaList
  rater_id_vec <- rep(system_rater_id, f)
  param_id_vec <- colnames(Z)
  estimate_vec <- beta0
  df_system <- data.frame(rater_id = rater_id_vec,
                          parameter_id = param_id_vec,
                          estimate = estimate_vec,
                          stringsAsFactors = FALSE)

  df_human <- do.call(rbind, lapply(seq_len(h), function(a) {
    data.frame(
      rater_id     = rep(human_raters[a], f),
      parameter_id = colnames(Z),
      estimate     = betaList[[a]],
      stringsAsFactors = FALSE
    )
  }))
  rater_ability <- dplyr::bind_rows(df_system, df_human)

  # 2) item_estimates
  # success_prob = logistic of (beta_a^T Z_i), expected_success = E[S_{a,i}]
  s0_vec <- logit_inv(Z %*% beta0)
  sA_mat <- matrix(0, n, h)
  for (a in 1:h) {
    sA_mat[, a] <- logit_inv(Z %*% betaList[[a]])
  }
  S0_post <- estep_f$S0
  Sa_post <- estep_f$Sa

  all_rows <- list()
  idx <- 1
  for (i_item in seq_len(n)) {
    cur_item_id <- item_order[i_item]
    # system
    all_rows[[idx]] <- data.frame(
      item_id         = cur_item_id,
      rater_id        = system_rater_id,
      success_prob    = s0_vec[i_item],
      expected_success= S0_post[i_item],
      stringsAsFactors=FALSE
    )
    idx <- idx + 1

    for (a in seq_len(h)) {
      all_rows[[idx]] <- data.frame(
        item_id         = cur_item_id,
        rater_id        = human_raters[a],
        success_prob    = sA_mat[i_item, a],
        expected_success= Sa_post[i_item, a],
        stringsAsFactors=FALSE
      )
      idx <- idx + 1
    }
  }
  item_estimates <- dplyr::bind_rows(all_rows)

  # 3) guessing_distribution
  # machine => piG0, humans => piGa
  guess_rows <- list()
  for (k in seq_len(d)) {
    guess_rows[[length(guess_rows)+1]] <- data.frame(
      rater_id   = system_rater_id,
      evaluation = evaluation_levels[k],
      probability= piG0[k],
      stringsAsFactors = FALSE
    )
  }
  for (a in seq_len(h)) {
    for (k in seq_len(d)) {
      guess_rows[[length(guess_rows)+1]] <- data.frame(
        rater_id   = human_raters[a],
        evaluation = evaluation_levels[k],
        probability= piGa[a, k],
        stringsAsFactors = FALSE
      )
    }
  }
  guessing_distribution <- dplyr::bind_rows(guess_rows)

  # 4) class_distribution
  # prior_prob = piY[k], posterior_prob = estep_f$posteriorYi[i,k]
  class_rows <- list()
  idx <- 1
  for (i_item in seq_len(n)) {
    cur_item_id <- item_order[i_item]
    for (k in seq_len(d)) {
      class_rows[[idx]] <- data.frame(
        item_id        = cur_item_id,
        evaluation     = evaluation_levels[k],
        prior_prob     = piY[k],
        posterior_prob = estep_f$posteriorYi[i_item, k],
        stringsAsFactors=FALSE
      )
      idx <- idx + 1
    }
  }
  class_distribution <- dplyr::bind_rows(class_rows)

  # ----------------------------------------------------------------
  # Return the 4 tidy data frames as a list
  # ----------------------------------------------------------------
  return(list(
    rater_ability         = as_tibble(rater_ability),
    item_estimates        = as_tibble(item_estimates),
    guessing_distribution = as_tibble(guessing_distribution),
    class_distribution    = as_tibble(class_distribution)
  ))
}


###############################################################################
# End of stand-alone code
#
# Example usage (pseudo-code):
#   library(dplyr)
#   library(tidyr)
#
#   df_eval <- data.frame(
#     item_id    = c("wve_1","wve_1","wve_1","wve_2","wve_2","wve_2"),
#     rater_id   = c("bob","sue","system","bob","sue","system"),
#     evaluation = c("yes","no","yes","yes","yes","yes"),
#     stringsAsFactors = FALSE
#   )
#
#   df_diff <- data.frame(
#     item_id   = c("wve_1","wve_1","wve_2","wve_2"),
#     feature_id= c("f1","f2","f1","f2"),
#     value     = c(1, 1, 2, 0),
#     stringsAsFactors = FALSE
#   )
#
#   result <- solve_or_guess(evaluations = df_eval, difficulty = df_diff,
#                            system_rater_id="system",
#                            max_iter=20, tol=1e-5)
#
#   # Inspect outputs:
#   result$rater_ability
#   result$item_estimates
#   result$guessing_distribution
#   result$class_distribution
#
###############################################################################



