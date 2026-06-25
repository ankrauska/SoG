
# ----------------------------
# Spectral Initializer Function
# ----------------------------
spectral_initializer <- function(M, H, R) {
  # Combine machine output (M) and human outputs (H) into one matrix of responses.
  # Machine is treated as the first "reviewer" (index 1),
  # Humans follow: indices 2,...,(R+1).

  Y <- cbind(M, H)
  n <- nrow(Y)
  if (is.null(n)) {
    # If H is a vector (in case R=1), ensure Y is still a matrix
    Y <- matrix(Y, ncol=R+1)
    n <- nrow(Y)
  }

  # Compute the agreement matrix A of dimension (R+1) x (R+1)
  A = cohens_kappa_numerator(Y)

  # # A[i,j] = empirical probability that reviewer i and reviewer j give the same answer
  # A <- matrix(0, R+1, R+1)
  # for (i in 1:(R+1)) {
  #   for (j in 1:(R+1)) {
  #     A[i,j] <- mean(Y[,i] == Y[,j])
  #   }
  # }
  #
  # Compute the eigen-decomposition of A
  e <- eigen(A)

  # Find the eigenvector corresponding to the largest eigenvalue
  idx <- which.max(e$values)
  ev <- e$vectors[, idx]

  # If the largest value in ev is negative, flip the sign
  if (max(ev) < 0) {
    ev <- -ev
  }

  # The returned vector ev will be used as intercept initializations
  return(ev)
}


#################################################################################
# Cohen's Kappa Numerator Calculator
#
# This script provides a function to compute the numerator of Cohen's kappa
# (observed - expected agreement) for all pairs of columns in a matrix.
#
# The input matrix Y contains integer values that are interpreted as categorical
# labels rather than numerical values.
#################################################################################

#' Calculate the numerator of Cohen's kappa for all column pairs in a matrix
#'
#' @param Y An n x m matrix with integer values (interpreted as categorical labels)
#' @return An m x m matrix where element [i,j] contains the difference between
#'         observed and expected agreement for columns i and j
#' @examples
#' # Create a sample matrix
#' Y <- matrix(sample(1:3, 50, replace=TRUE), nrow=10, ncol=5)
#' # Calculate Cohen's kappa numerator
#' result <- cohens_kappa_numerator(Y)
cohens_kappa_numerator <- function(Y) {
  n <- nrow(Y)
  m <- ncol(Y)

  # Initialize result matrix
  result <- matrix(0, m, m)

  # Compute for each pair of columns
  for (i in 1:m) {
    for (j in i:m) {  # Only compute upper triangle (for efficiency)
      col_i <- Y[, i]
      col_j <- Y[, j]

      # Calculate observed agreement
      observed <- sum(col_i == col_j) / n

      # Get unique values across both columns
      all_labels <- unique(c(col_i, col_j))

      # Calculate expected agreement
      expected <- 0
      for (label in all_labels) {
        p_i <- sum(col_i == label) / n
        p_j <- sum(col_j == label) / n
        expected <- expected + (p_i * p_j)
      }

      # Calculate numerator
      result[i, j] <- observed - expected

      # Fill symmetric entry
      if (i != j) {
        result[j, i] <- result[i, j]
      }
    }
  }

  return(result)
}
