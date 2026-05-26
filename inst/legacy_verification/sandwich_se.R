# =========================================================================
# sandwich_se.R
#
# R-side helper for sandwich standard errors. Takes the output of
# het_residuals_and_jacobian_fixed_sigma_rcpp() (sparse Jacobian triplets +
# residuals + weights) and returns the K-vector of sandwich SEs.
#
# V = A^{-1} B A^{-1}
#   A = J' W J
#   B = J' diag(w_i^2 r_i^2) J
#
# Edge cases:
#   - A singular -> return NA vector + singular flag
#   - B has zero diagonal -> return NA, treat as identification failure
# =========================================================================

#' Compute sandwich SEs from sparse Jacobian triplets.
#'
#' @param jac_out List with fields residuals, weights, jac_row, jac_col,
#'   jac_val, K, status. Output of het_residuals_and_jacobian_fixed_sigma_rcpp.
#' @return List with: se (K-vector), singular (logical), method ("sandwich").
compute_sandwich_se <- function(jac_out) {

  K <- jac_out$K
  na_se <- list(se = rep(NA_real_, K), singular = TRUE, method = "sandwich")

  if (!identical(jac_out$status, "ok")) return(na_se)

  r <- jac_out$residuals
  w <- jac_out$weights
  rows <- jac_out$jac_row + 1L  # 0-based -> 1-based for R sparse indexing
  cols <- jac_out$jac_col + 1L
  vals <- jac_out$jac_val
  n <- length(r)

  # Sanity: any non-finite Jacobian entry is a deal-breaker (means optimum
  # is at a corner where the prediction isn't differentiable, or the
  # parameter hit the boundary)
  if (any(!is.finite(vals)) || any(!is.finite(r)) || any(!is.finite(w))) {
    return(na_se)
  }

  # Build A = J' W J and B = J' diag(w^2 r^2) J by direct outer-product
  # accumulation over the sparse Jacobian triplets. Since the Jacobian
  # has at most 2 nonzeros per row (import side) or 1 (export side),
  # we accumulate contributions to A and B row by row.
  A <- matrix(0, K, K)
  B <- matrix(0, K, K)

  # Group triplets by residual row
  ord <- order(rows)
  rows <- rows[ord]; cols <- cols[ord]; vals <- vals[ord]

  i <- 1L
  while (i <= length(rows)) {
    cur_row <- rows[i]
    # Collect all triplets with this row
    j <- i
    while (j <= length(rows) && rows[j] == cur_row) j <- j + 1L
    # Indices and values for this row
    row_cols <- cols[i:(j - 1L)]
    row_vals <- vals[i:(j - 1L)]
    w_row    <- w[cur_row]
    r_row    <- r[cur_row]

    # Outer product J_i J_i', scaled by w_row (for A) or w_row^2 r_row^2 (for B)
    nc <- length(row_cols)
    for (a in seq_len(nc)) {
      for (b in seq_len(nc)) {
        A[row_cols[a], row_cols[b]] <- A[row_cols[a], row_cols[b]] +
          w_row * row_vals[a] * row_vals[b]
        B[row_cols[a], row_cols[b]] <- B[row_cols[a], row_cols[b]] +
          (w_row * r_row)^2 * row_vals[a] * row_vals[b]
      }
    }

    i <- j
  }

  # Sandwich: V = A^{-1} B A^{-1}
  V <- tryCatch({
    Ainv <- solve(A)
    Ainv %*% B %*% Ainv
  }, error = function(e) NULL)

  if (is.null(V)) return(na_se)

  diag_V <- diag(V)
  if (any(diag_V < 0) || any(!is.finite(diag_V))) return(na_se)

  list(se = sqrt(diag_V), singular = FALSE, method = "sandwich")
}


#' Convenience wrapper: given the fitted parameters and the cell's
#' data, refits no further but computes the sandwich SE.
#'
#' @param d_hat Numeric vector, optimized parameters (K = J+1)
#' @param sigma_val Fixed sigma for this cell
#' @param imp_Y, imp_X, exp_Y, exp_X, exp_jmap, exp_sig_V, exp_gam_V,
#'   wt_imp, wt_exp: same inputs as het_obj_fixed_sigma_rcpp
sandwich_se_for_cell <- function(d_hat, sigma_val,
                                  imp_Y, imp_X,
                                  exp_Y, exp_X,
                                  exp_jmap, exp_sig_V, exp_gam_V,
                                  wt_imp, wt_exp) {

  jac_out <- het_residuals_and_jacobian_fixed_sigma_rcpp(
    d = d_hat,
    sigma = sigma_val,
    imp_Y = imp_Y, imp_X = imp_X,
    exp_Y = exp_Y, exp_X = exp_X,
    exp_jmap = exp_jmap,
    exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
    wt_imp = wt_imp, wt_exp = wt_exp
  )

  compute_sandwich_se(jac_out)
}
