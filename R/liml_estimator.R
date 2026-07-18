#' R/liml_estimator.R
#'
#' Standalone Fuller LIML / HLIML estimator for Feenstra-Soderbery import
#' demand and export supply elasticities. Ported from the Grant & Soderbery
#' (2024) JIE replication package (Mendeley DOI 10.17632/3ffp863bs8.1).
#' Implements Steps 1-3 of GS_Estimation.do: unweighted Fuller(1) starting
#' values, heteroskedasticity-weighted Fuller(1) LIML with delta-method SEs,
#' and the HLIML core with the full diagnostic battery (Kleibergen-Paap F,
#' Hansen J, Stock-Yogo screening) and HNCS sandwich SEs.
#'
#' Exported functions:
#'   estimate_elasticities(trade_df, ...)  — top-level per-cell elasticity estimation
#'   estimate_cell_liml(cell_df, ...)      — per-cell LIML/HLIML fit
#'   prepare_cell_moments(trade_df, ...)   — construct cell moments for estimation
#'   hliml_core(...)                       — heteroskedastic LIML core
#'   fuller_liml_core(Y, X, Z, ...)        — Fuller(1) LIML core
#'   hncs_sandwich_se(...)                 — HNCS sandwich standard errors
#'   kleibergen_paap_F(endog, Z, ...)      — Kleibergen-Paap rk F statistic
#'   hansen_J(u_hat, Z, ...)               — Hansen/Sargan J overid statistic
#'   stockyogo_pass(F_stat, ...)           — Stock-Yogo weak-instrument screen
#'   delta_method_ses(...)                 — delta-method SEs on structural params
#'   invert_structural(eta_1, eta_2, ...)  — reduced-form to structural inversion
#'
#' Depends on: hs_codes.R

# -------------------------------------------------------------------------
# 0. Stock-Yogo (2005) critical values for 2 endogenous regressors,
#    LIML estimator, MAXIMAL SIZE of a nominal 5% Wald test (these are
#    Stock-Yogo's size tables; SY tabulate bias only for TSLS/Fuller-k).
#    Source: StockYogo2005_2EndogRegCritVals.csv in G&S 2024 replication.
#    Rows: number of excluded instruments (suppliers in this context).
#    Columns: maximal-size thresholds 0.10, 0.15, 0.20, 0.25.
#    G&S (2024) screen at 0.25 as their rule of thumb; the headline
#    stockyogo_pass in this pipeline uses the stricter 0.10 (see F8 note).
# -------------------------------------------------------------------------

.stockyogo_2endog_liml <- structure(list(
  suppliers      = 2:30,
  cv_0.10        = c(7.03, 5.44, 4.72, 4.32, 4.06, 3.90, 3.78, 3.70, 3.64,
                     3.60, 3.58, 3.56, 3.55, 3.54, 3.55, 3.55, 3.56, 3.57,
                     3.58, 3.59, 3.60, 3.62, 3.64, 3.65, 3.67, 3.74, 3.87,
                     4.02, 4.12),
  cv_0.15        = c(4.58, 3.81, 3.39, 3.13, 2.95, 2.83, 2.73, 2.66, 2.60,
                     2.55, 2.52, 2.48, 2.46, 2.44, 2.42, 2.41, 2.40, 2.39,
                     2.38, 2.38, 2.37, 2.37, 2.37, 2.37, 2.38, 2.38, 2.38,
                     2.39, 2.39),
  cv_0.20        = c(3.95, 3.32, 2.99, 2.78, 2.63, 2.52, 2.43, 2.36, 2.30,
                     2.25, 2.21, 2.17, 2.14, 2.11, 2.09, 2.07, 2.05, 2.03,
                     2.02, 2.01, 1.99, 1.98, 1.98, 1.97, 1.96, 1.96, 1.95,
                     1.95, 1.95),
  cv_0.25        = c(3.63, 3.09, 2.79, 2.60, 2.46, 2.35, 2.27, 2.20, 2.14,
                     2.09, 2.05, 2.02, 1.99, 1.96, 1.93, 1.91, 1.89, 1.87,
                     1.86, 1.84, 1.83, 1.81, 1.80, 1.79, 1.78, 1.77, 1.77,
                     1.76, 1.75)
), class = "data.frame", row.names = c(NA, -29L))


# -------------------------------------------------------------------------
# 1. CORE FULLER(alpha) LIML SOLVER
#
# Solves: min_eta  (1 - kappa) * (y - X eta)' M (y - X eta) + kappa * (y - X eta)' P (y - X eta)
# where M = I - P, P = Z (Z'Z)^{-1} Z'
#
# Equivalent closed form (per Galstyan 2016 Eq. 9):
#   eta_hat = (X' P X - kappa X' X)^{-1} (X' P Y - kappa X' Y)
#
# Fuller(alpha) sets kappa = lambda_min - alpha / (n - l)
# where lambda_min is the smallest eigenvalue of (X_bar' X_bar)^{-1} (X_bar' P X_bar)
# and X_bar = [Y | X] is the augmented n x (k+1) matrix.
#
# Standard LIML is alpha = 0; Fuller(1) is alpha = 1 (default in Soderbery).
# -------------------------------------------------------------------------

fuller_liml_core <- function(Y, X, Z, weights = NULL, fuller_alpha = 1,
                             endog_idx = NULL) {
  # Y: n x 1 outcome vector (lp_dif squared, in our setting)
  # X: n x k regressors  - typically [x1, x2, ones]
  #    Convention: endogenous regressors FIRST, then included exogenous, then constant
  # Z: n x l instruments - typically [exporter_dummies_minus_one, ones]
  #    Convention: excluded IVs FIRST, then included exogenous, then constant
  # endog_idx: column indices of X that are endogenous regressors.
  #            Default = first (k - (l - L1)) cols, where L1 = #excluded IVs.
  #            For Soderbery setting: endog_idx = c(1, 2), meaning x1 and x2 are endogenous.
  # weights: optional n-vector of analytic weights (Stata aweight semantics)
  # fuller_alpha: 0 for plain LIML, 1 for Fuller(1)
  #
  # Returns: list with eta (k-vector of coefs on X), kappa, lambda, residuals, SEs.
  
  Y <- as.numeric(Y)
  X <- as.matrix(X)
  Z <- as.matrix(Z)
  n <- length(Y)
  k <- ncol(X)
  l <- ncol(Z)
  
  if (nrow(X) != n || nrow(Z) != n)
    stop("Dimension mismatch among Y, X, Z")
  if (l < k)
    stop(sprintf("Not enough instruments: l=%d < k=%d (need l >= k)", l, k))
  
  # If endog_idx not provided, infer it: endogenous regressors are columns of X
  # that are NOT also columns of Z. For our setup [x1, x2, ones] vs [dummies, ones],
  # the endog are columns 1 and 2 (x1, x2).
  if (is.null(endog_idx)) {
    # Simple heuristic: columns of X whose vector is not approximately a column
    # vector of Z. For our standard case, endog_idx = c(1, 2).
    # Production code should pass endog_idx explicitly.
    endog_idx <- seq_len(k)
    # Find which X columns appear in Z
    for (j in seq_len(k)) {
      for (m in seq_len(l)) {
        if (max(abs(X[, j] - Z[, m])) < 1e-10) {
          endog_idx <- setdiff(endog_idx, j)
          break
        }
      }
    }
  }
  if (length(endog_idx) == 0)
    stop("No endogenous regressors identified")
  
  # Z2 = included exogenous part of X = X minus endogenous columns
  # In our case Z2 = ones (just the constant column of X).
  Z2_cols <- setdiff(seq_len(k), endog_idx)
  if (length(Z2_cols) > 0) {
    Z2 <- X[, Z2_cols, drop = FALSE]
  } else {
    Z2 <- NULL
  }
  
  # Apply Stata aweight semantics: rescale weights so sum = n, then multiply
  # Y, X, Z, Z2 by sqrt(w_rescaled). This makes (weighted X)' (weighted X) =
  # sum_i w_i_rescaled * x_i x_i' which matches Stata.
  if (!is.null(weights)) {
    weights <- as.numeric(weights)
    if (any(!is.finite(weights)) || any(weights <= 0))
      stop("weights must be positive and finite")
    w_scaled <- weights * n / sum(weights)
    w_sqrt <- sqrt(w_scaled)
    Y <- Y * w_sqrt
    X <- X * w_sqrt
    Z <- Z * w_sqrt
    if (!is.null(Z2)) Z2 <- Z2 * w_sqrt
  }
  
  # Build Y_aug = [y, X_endog]  (n x (1 + n_endog))
  # This is Stata's "Y" matrix inside s_liml.
  Y_aug <- cbind(Y, X[, endog_idx, drop = FALSE])
  
  # ---- LIML eigenvalue lambda ----
  # Stata's algorithm (from s_liml):
  #   QWW  = Y_aug' M_Z  Y_aug = Y_aug' Y_aug - Y_aug' Z (Z'Z)^-1 Z' Y_aug
  #   QWW1 = Y_aug' M_Z2 Y_aug = Y_aug' Y_aug - Y_aug' Z2 (Z2'Z2)^-1 Z2' Y_aug
  #          (if Z2 is empty, QWW1 = Y_aug' Y_aug; if just a constant, demean)
  #   lambda = min eigenvalue of QWW^{-1/2} QWW1 QWW^{-1/2}
  #
  # Important: lambda >= 1 (with equality iff exactly identified or perfect fit)
  
  YaugYaug <- crossprod(Y_aug)  # Y_aug' Y_aug
  
  # Compute Y_aug' Z (Z'Z)^-1 Z' Y_aug
  ZtZ <- crossprod(Z)
  ZtY <- crossprod(Z, Y_aug)
  ZtZ_chol <- tryCatch(chol(ZtZ), error = function(e) NULL)
  if (is.null(ZtZ_chol))
    return(list(status = "fail_singular_ZtZ"))
  YaugPYaug <- crossprod(ZtY, chol2inv(ZtZ_chol) %*% ZtY)
  QWW <- YaugYaug - YaugPYaug
  QWW <- (QWW + t(QWW)) / 2  # symmetrize
  
  # Compute Y_aug' Z2 (Z2'Z2)^-1 Z2' Y_aug
  if (!is.null(Z2)) {
    Z2tZ2 <- crossprod(Z2)
    Z2tY <- crossprod(Z2, Y_aug)
    Z2tZ2_chol <- tryCatch(chol(Z2tZ2), error = function(e) NULL)
    if (is.null(Z2tZ2_chol))
      return(list(status = "fail_singular_Z2tZ2"))
    YaugPZ2Yaug <- crossprod(Z2tY, chol2inv(Z2tZ2_chol) %*% Z2tY)
    QWW1 <- YaugYaug - YaugPZ2Yaug
  } else {
    QWW1 <- YaugYaug
  }
  QWW1 <- (QWW1 + t(QWW1)) / 2
  
  # lambda = min eigenvalue of QWW^{-1} QWW1
  # Equivalent: min eigenvalue of (QWW^{-1/2}) QWW1 (QWW^{-1/2})
  QWW_chol <- tryCatch(chol(QWW), error = function(e) NULL)
  if (is.null(QWW_chol))
    return(list(status = "fail_singular_QWW"))
  QWW_inv_chol <- backsolve(QWW_chol, diag(ncol(QWW)))
  A <- t(QWW_inv_chol) %*% QWW1 %*% QWW_inv_chol
  A <- (A + t(A)) / 2
  eigvals <- eigen(A, symmetric = TRUE, only.values = TRUE)$values
  lambda <- min(eigvals)
  
  # Sanity check: lambda should be >= 1 - epsilon
  if (lambda < 0.99) {
    # Numerical issue; lambda < 1 should not happen with correct algorithm
    # Could indicate near-singular matrices
  }
  
  # Fuller(alpha) correction: k = lambda - alpha / (n - l)
  # With Stata's formulation, k is slightly LESS than lambda but typically > 1.
  kappa <- lambda - fuller_alpha / (n - l)
  
  # ---- k-class estimator ----
  # beta = ( (1-k) X'X + k X'P_Z X )^-1 ( (1-k) X'y + k X'P_Z y )
  # equivalently: ( X'P_Z X - (k-1)/k * something ... )
  # Stata writes it as:
  #   QXhXh = (1-k)*QXX + k*QXZ*QZZinv*QXZ'
  #   beta = QXhXh^-1 * [ (1-k)*QXy + k*QXZ*QZZinv*QZy ]
  # We replicate that here.
  
  ZtX <- crossprod(Z, X)
  ZtY1 <- crossprod(Z, Y)  # Y (not Y_aug) for the equation y ~ X
  XtX <- crossprod(X)
  XtY <- crossprod(X, Y)
  
  # X'P_Z X = X'Z (Z'Z)^-1 Z'X
  ZtZ_inv <- chol2inv(ZtZ_chol)
  XPZX <- crossprod(ZtX, ZtZ_inv %*% ZtX)
  XPZX <- (XPZX + t(XPZX)) / 2
  # X'P_Z y = X'Z (Z'Z)^-1 Z'y
  XPZY <- crossprod(ZtX, ZtZ_inv %*% ZtY1)
  
  K_mat <- (1 - kappa) * XtX + kappa * XPZX
  K_rhs <- (1 - kappa) * XtY + kappa * XPZY
  
  eta_hat <- tryCatch(solve(K_mat, K_rhs), error = function(e) NULL)
  if (is.null(eta_hat))
    return(list(status = "fail_singular_K"))
  eta_hat <- as.numeric(eta_hat)
  
  # Residuals
  u_hat <- Y - X %*% eta_hat
  rss <- sum(u_hat^2)
  sigma2_u <- rss / (n - k)
  
  # ---- Variance ----
  # Homoskedastic-assumed variance (Stata default with no `robust`):
  #   V = sigma^2 * K_mat^{-1}   where K_mat = X'X(1-k) + k X'P_Z X
  # That's wrong - actually Stata uses:
  #   V = sigma^2 * (X' P_Z X)^{-1}   for IV/2SLS  (kappa=1)
  # For LIML, Stata's V is sigma^2 * (X' (1-k)I + k P_Z X)^{-1} = sigma^2 * K_mat^{-1}
  # but actually the LIML default is `coviv=""` which uses K_mat^{-1}.
  # If coviv is set, use the 2SLS-style covariance, which means X'P_Z X.
  #
  # We follow the default (coviv unset): V = sigma^2 * K_mat^{-1}
  K_inv <- solve(K_mat)
  V_eta_homo <- sigma2_u * K_inv
  
  # Robust (HC0-style) variance for LIML
  # Stata's robust LIML variance is more involved. Use the standard sandwich:
  #   V_robust = K_mat^{-1} * X' diag(u^2) X * K_mat^{-1}
  # This is the heteroskedasticity-consistent version.
  # NOTE: Stata's actual formula uses m_omega which depends on options;
  # this is the simplest robust variant.
  meat <- crossprod(X, as.numeric(u_hat^2) * X)
  V_eta_robust <- K_inv %*% meat %*% K_inv
  
  list(
    status = "ok",
    eta = eta_hat,
    V_eta_homo = V_eta_homo,
    V_eta_robust = V_eta_robust,
    u_hat = as.numeric(u_hat),
    kappa = kappa,
    lambda_min = lambda,
    n = n, k = k, l = l,
    sigma2_u = sigma2_u,
    endog_idx = endog_idx
  )
}


# -------------------------------------------------------------------------
# 2. STRUCTURAL INVERSION
#    Map (eta_1, eta_2) -> (sigma, rho, omega) per Soderbery (2015) Eqs 7-8.
#    eta = (const, eta_1, eta_2) where eta_1 is coefficient on x1 and
#    eta_2 is coefficient on x2.
#
#    rho_hat = 0.5 +/- sqrt(0.25 - 1/(4 + eta_2^2 / eta_1)),
#      sign chosen so that rho stays in (0, 1):
#      "+" if eta_2 > 0, "-" if eta_2 < 0
#    sigma_hat = 1 + (2 rho - 1) / ((1 - rho) * eta_2)
#    omega_hat = rho / (sigma - 1 - sigma * rho)
#
#    Returns NA components if the unconstrained inversion fails
#    (e.g. negative argument under sqrt, or constraint violation).
# -------------------------------------------------------------------------

invert_structural <- function(eta_1, eta_2,
                              rho_floor = 1e-4, rho_ceil = 0.999,
                              sigma_ceil = 1000, omega_floor = 1e-4,
                              omega_ceil = 1000) {
  
  if (!is.finite(eta_1) || !is.finite(eta_2))
    return(list(sigma = NA, rho = NA, omega = NA, status = "non_finite_eta"))
  
  # Argument under the square root: 1/4 - 1/(4 + eta_2^2 / eta_1)
  # For real-valued rho we need 4 + eta_2^2/eta_1 > 4, i.e., eta_2^2/eta_1 > 0,
  # which requires eta_1 > 0. (Galstyan footnote 3 discusses this case.)
  if (eta_1 <= 0)
    return(list(sigma = NA, rho = NA, omega = NA, status = "eta1_nonpositive"))
  
  disc <- 0.25 - 1 / (4 + eta_2^2 / eta_1)
  if (disc < 0)
    return(list(sigma = NA, rho = NA, omega = NA, status = "neg_discriminant"))
  
  rho_root <- sqrt(disc)
  rho <- if (eta_2 > 0) 0.5 + rho_root else 0.5 - rho_root
  
  # Apply admissible-region clamps (mirrors GS_Estimation.do lines 31-33)
  if (rho > rho_ceil) rho <- rho_ceil
  if (rho < rho_floor) rho <- rho_floor
  
  sigma <- 1 + (2 * rho - 1) / ((1 - rho) * eta_2)
  
  if (!is.finite(sigma) || sigma <= 1)
    return(list(sigma = NA, rho = rho, omega = NA,
                status = "sigma_below_1"))
  if (sigma > sigma_ceil) sigma <- sigma_ceil
  
  denom <- sigma - 1 - sigma * rho
  if (abs(denom) < 1e-12)
    return(list(sigma = sigma, rho = rho, omega = NA,
                status = "omega_div_zero"))
  
  omega <- rho / denom
  if (!is.finite(omega))
    return(list(sigma = sigma, rho = rho, omega = NA,
                status = "non_finite_omega"))
  if (omega < omega_floor) omega <- omega_floor
  if (omega > omega_ceil) omega <- omega_ceil
  
  # Check Feenstra constraint: 0 <= rho < (sigma - 1) / sigma
  # which is equivalent to omega > 0 (the natural admissibility condition)
  feasible <- (rho >= 0) && (rho < (sigma - 1) / sigma)
  
  list(sigma = sigma, rho = rho, omega = omega,
       status = if (feasible) "ok" else "constraint_violated")
}


# -------------------------------------------------------------------------
# 3. DELTA-METHOD STANDARD ERRORS
#    Lines 71-87 of GS_Estimation.do.
#
#    Given V_eta (variance of (eta_0, eta_1, eta_2)) and point estimates
#    (sigma, rho), compute variance of (sigma, rho) and then of omega.
#
#    The Jacobian d(eta_1, eta_2) / d(sigma, rho) is:
#      eta_1 = rho / ((1+omega)*(sigma-1))    (NOTE Soderbery writes in omega/sigma)
#      eta_2 = (rho*(sigma-2) - 1) / ((1-rho)*(sigma-1)) ... wait
#
#    Looking at GS_Estimation.do line 78 carefully:
#      d_w_sub = [ (sigma-1)^3 * (1-rho)              ,  -(sigma-1)^2 * (1-rho)^2 * (1-2*rho)
#                  (sigma-1)^2 * (1-rho)              ,   2 * (sigma-1) * rho * (1-rho)^2 ]
#
#    This is the d(eta) / d(sigma, rho) Jacobian after rearrangement.
#    Then delta = d_sub * V_sub * d_sub / (n - l)  with d_sub used directly
#    (not transposed) because the inversion is symbolic.
#
#    For omega SE (line 85):
#      Var(omega) = (1/((sigma*(rho-1)+1)^4)) *
#                     ( rho^2 * (1-rho)^2 * Var(sigma)
#                     + (sigma-1)^2 * Var(rho)
#                     - 2 * (sigma-1) * rho * (1-rho) * Cov(sigma, rho) )
# -------------------------------------------------------------------------

delta_method_ses <- function(sigma, rho, V_eta, n, l, endog_idx = c(1L, 2L)) {
  # V_eta: covariance matrix of full eta vector.
  # endog_idx: which rows/cols of V_eta correspond to (eta_x1, eta_x2).
  #            Default = c(1, 2) for the Stata-convention ordering [x1, x2, _cons].
  V_sub <- V_eta[endog_idx, endog_idx, drop = FALSE]
  
  # Jacobian J = d(sigma, rho) / d(eta_1, eta_2), in closed form.
  # Forward map (with omega = rho / (sigma - 1 - sigma*rho)):
  #   eta_1 = rho / ((sigma - 1)^2 (1 - rho))
  #   eta_2 = (2*rho - 1) / ((sigma - 1)(1 - rho))
  # Differentiating and inverting the 2x2 forward Jacobian
  # (det = -1 / ((sigma-1)^4 (1-rho)^3)) gives:
  #   row 1 (sigma): [ -(sigma-1)^3 (1-rho),            (sigma-1)^2 (1-rho)      ]
  #   row 2 (rho):   [ (1-2*rho)(sigma-1)^2 (1-rho)^2,  2*rho (sigma-1)(1-rho)^2 ]
  # B4 FIX (v0.3.0): the previous d_sub — ported from GS_Estimation.do
  # line 78 — was the elementwise-absolute TRANSPOSE of this matrix, so the
  # sigma row of the quadratic form used d(rho)/d(eta_1) where d(sigma)/d(eta_2)
  # belongs (and vice versa), with dropped cross-term signs. Verified against
  # numerical differentiation of invert_structural() and of the forward map.
  # Typical effect at production points: sigma_se understated ~0-30%,
  # rho_se overstated 2-6x; omega_se contaminated through both.
  d_sub <- matrix(c(
    -(sigma - 1)^3 * (1 - rho),                          # d sigma / d eta_1
    (sigma - 1)^2 * (1 - rho),                           # d sigma / d eta_2
    (1 - 2 * rho) * (sigma - 1)^2 * (1 - rho)^2,         # d rho   / d eta_1
    2 * rho * (sigma - 1) * (1 - rho)^2                  # d rho   / d eta_2
  ), nrow = 2, byrow = TRUE)
  
  # Sandwich: J V J'. Standard delta method form.
  # NOTE: Stata's GS_Estimation.do divides this by (n-l), which is consistent
  # with the spurious division we found in the Step 3 HNCS sandwich. Both
  # divisions appear to be scaling bugs in Soderbery's Stata code — empirical
  # bootstrap on synthetic data shows the corrected (undivided) Step 3 SE
  # matches the bootstrap SD, while the Stata-exact divided version is off
  # by ~500x. By symmetry we drop the division here too.
  delta_mat <- d_sub %*% V_sub %*% t(d_sub)
  
  # Defensive: if floating-point error produced tiny negative diagonals,
  # clamp to zero before sqrt.
  diag(delta_mat) <- pmax(diag(delta_mat), 0)
  
  sigma_se <- sqrt(delta_mat[1, 1])
  rho_se   <- sqrt(delta_mat[2, 2])
  cov_sr   <- delta_mat[1, 2]
  
  # Omega SE via further delta method
  denom4 <- (sigma * (rho - 1) + 1)^4
  if (denom4 < 1e-20) {
    omega_se <- NA_real_
  } else {
    omega_var <- (1 / denom4) * (
      rho^2 * (1 - rho)^2 * delta_mat[1, 1] +
        (sigma - 1)^2 * delta_mat[2, 2] -
        2 * (sigma - 1) * rho * (1 - rho) * cov_sr
    )
    omega_se <- if (omega_var >= 0) sqrt(omega_var) else NA_real_
  }
  
  list(sigma_se = sigma_se, rho_se = rho_se, omega_se = omega_se,
       delta_mat = delta_mat)
}


# -------------------------------------------------------------------------
# 4. WEAK-INSTRUMENT AND OVERID DIAGNOSTICS
#
# Kleibergen-Paap rk Wald F-statistic for the cross-equation Wald test of
# instrument relevance. For 2 endogenous regressors (x1, x2) with l excluded
# instruments and a constant.
#
# Formula (Kleibergen-Paap 2006, also implemented in Stata ivreg2):
#   First-stage regression of (x1, x2) on Z gives pi_hat (l x 2 matrix of
#   coefficients on excluded instruments, after partialling out included
#   exogenous regressors).
#   rk = (n - l_inc) * vec(pi_hat)' * V_pi^{-1} * vec(pi_hat) / (2 * l)
#   where V_pi accounts for cross-equation error correlation.
#
# We implement the simpler version applicable to our setting:
#   F_kp = trace((Pi' Z' Z Pi) (Sigma_uu)^{-1}) / (k_endog * l)
# This matches ivreg2's reported widstat for the homoskedastic case;
# for the heteroskedastic case the formula differs slightly.
# -------------------------------------------------------------------------

kleibergen_paap_F <- function(endog, Z, weights = NULL) {
  # endog: n x k_endog matrix of endogenous regressors (here x1, x2)
  # Z: n x l matrix of instruments (excluded instruments + any included exog)
  # Returns rk Wald F-stat
  
  endog <- as.matrix(endog)
  Z <- as.matrix(Z)
  n <- nrow(endog)
  k_endog <- ncol(endog)
  l <- ncol(Z)
  
  if (!is.null(weights)) {
    w_sqrt <- sqrt(weights * n / sum(weights))
    endog <- endog * w_sqrt
    Z <- Z * w_sqrt
  }
  
  # First-stage OLS: endog = Z Pi + V
  ZtZ <- crossprod(Z)
  ZtZ_inv <- tryCatch(solve(ZtZ), error = function(e) NULL)
  if (is.null(ZtZ_inv)) return(NA_real_)
  
  Pi_hat <- ZtZ_inv %*% crossprod(Z, endog)        # l x k_endog
  V_hat <- endog - Z %*% Pi_hat                     # n x k_endog (first-stage resid)
  Sigma_VV <- crossprod(V_hat) / (n - l)            # k_endog x k_endog
  
  # B7 FIX (v0.3.0): the Stock-Yogo critical values tabulated above are for
  # the MINIMUM-EIGENVALUE Cragg-Donald statistic. The previous trace-form
  # statistic averages over the endogenous directions, so one weakly
  # identified direction was masked by a strong one and the screen was
  # anti-conservative. Compute the CD minimum eigenvalue:
  #   G = Sigma_VV^{-1/2} (Pi' Z'Z Pi) Sigma_VV^{-1/2};  F_CD = min eig(G) / l
  # (homoskedastic CD, not the robust Kleibergen-Paap rk; the function name
  # is kept for schema stability — the output column is fstat_kp.)
  A <- crossprod(Pi_hat, ZtZ) %*% Pi_hat            # Pi' Z'Z Pi, k_endog x k_endog
  A <- (A + t(A)) / 2
  S_chol <- tryCatch(chol(Sigma_VV), error = function(e) NULL)
  if (is.null(S_chol)) return(NA_real_)
  S_inv <- backsolve(S_chol, diag(k_endog))         # R^{-1}, Sigma = R'R
  G <- crossprod(S_inv, A) %*% S_inv                # R^{-T} A R^{-1}, symmetric
  G <- (G + t(G)) / 2
  eigvals <- tryCatch(eigen(G, symmetric = TRUE, only.values = TRUE)$values,
                      error = function(e) NULL)
  if (is.null(eigvals)) return(NA_real_)
  F_kp <- min(eigvals) / l
  
  F_kp
}


# Sargan overidentification statistic (homoskedastic form).
# NOTE: despite the function name (kept for call-site stability), this is
# the Sargan statistic u'P_Z u / (u'u/n), not the heteroskedasticity-robust
# Hansen J. The HLIML path's J_h (computed in hncs_sandwich_se) is the
# heteroskedasticity-adjusted overid statistic.
hansen_J <- function(u_hat, Z, weights = NULL) {
  # u_hat: residuals from LIML estimation
  # Z: instrument matrix
  # J ~ chi^2(l - k_endog) under correct specification
  
  u_hat <- as.numeric(u_hat)
  Z <- as.matrix(Z)
  n <- length(u_hat)
  
  if (!is.null(weights)) {
    w_sqrt <- sqrt(weights * n / sum(weights))
    u_hat <- u_hat * w_sqrt
    Z <- Z * w_sqrt
  }
  
  # J = u' P_Z u / sigma2_u
  ZtZ <- crossprod(Z)
  Ztu <- crossprod(Z, u_hat)
  uPu <- as.numeric(crossprod(Ztu, solve(ZtZ, Ztu)))
  sigma2_u <- as.numeric(crossprod(u_hat)) / n
  J <- uPu / sigma2_u
  J
}


# Stock-Yogo critical-value lookup
stockyogo_pass <- function(F_stat, n_excluded_instruments, size_threshold = 0.10) {
  col_name <- sprintf("cv_%.2f", size_threshold)
  if (!col_name %in% names(.stockyogo_2endog_liml))
    stop("size_threshold must be one of 0.10, 0.15, 0.20, 0.25")
  tbl <- .stockyogo_2endog_liml
  if (n_excluded_instruments < min(tbl$suppliers)) return(NA)
  idx <- if (n_excluded_instruments > max(tbl$suppliers)) {
    nrow(tbl)
  } else {
    which(tbl$suppliers == n_excluded_instruments)
  }
  cv <- tbl[[col_name]][idx]
  list(F_stat = F_stat, cv = cv, pass = F_stat > cv, threshold = size_threshold)
}


# -------------------------------------------------------------------------
# 4.5 HLIML CORE: heteroskedastic LIML (jackknife LIML)
#
# Implements the LIML2 objective from mata_LIMLhybrid_hetero.do:
#
#   Q(d) = A' (P - diag(P)) A / (A' A)
#
# where d = (theta0, sigma, omega), A = Y - X * theta_eq', and
#   theta_eq = (theta0,
#               omega / ((1 + omega) * (sigma - 1)),
#               (omega * (sigma - 2) - 1) / ((1 + omega) * (sigma - 1)))
#
# Constraints: sigma > 1 and omega > 0 are enforced by returning Inf when
# violated (Mata's exp(log(d[2]-1)) trick produces missing values that
# propagate; we replicate with explicit Inf return).
#
# Note: in the Stata implementation, X here is ordered [ones, x1, x2], so
# theta_eq = (theta0=cons, theta1=coef on x1, theta2=coef on x2). We match
# that convention inside this function regardless of the caller's X ordering.
# -------------------------------------------------------------------------

hliml_core <- function(Y, X_ohx, Z, sigma_start, omega_start, theta0_start = 0,
                       control = list(maxit = 200, reltol = 1e-8)) {
  # Y: n x 1 outcome
  # X_ohx: n x 3 in (ones, x1, x2) order. Caller is responsible for ordering.
  # Z: n x l instruments (exporter dummies + ones)
  # sigma_start, omega_start: starting values from Step 2
  # theta0_start: starting value for constant (from Step 2 cons_w)
  
  Y <- as.numeric(Y)
  X_ohx <- as.matrix(X_ohx)
  Z <- as.matrix(Z)
  n <- length(Y)
  
  if (ncol(X_ohx) != 3)
    stop("hliml_core expects X_ohx with 3 columns in order [ones, x1, x2]")
  
  # Project matrix: P = Z (Z'Z)^-1 Z'
  ZtZ <- crossprod(Z)
  ZtZ_chol <- tryCatch(chol(ZtZ), error = function(e) NULL)
  if (is.null(ZtZ_chol))
    return(list(status = "hliml_fail_singular_ZtZ"))
  ZtZ_inv <- chol2inv(ZtZ_chol)
  P <- Z %*% ZtZ_inv %*% t(Z)   # n x n
  
  # Pre-compute P - diag(P) used in objective
  diag_P <- diag(P)
  P_minus_diag <- P
  diag(P_minus_diag) <- 0       # zero out diagonal in-place
  
  # Objective: Q(d) = A'(P - diag(P))A / A'A
  obj_fun <- function(d) {
    theta0 <- d[1]
    sigma  <- d[2]
    omega  <- d[3]
    # Enforce constraints: sigma > 1, omega > 0
    if (sigma <= 1 + 1e-8 || omega <= 1e-8) return(.Machine$double.xmax)
    if (!is.finite(sigma) || !is.finite(omega)) return(.Machine$double.xmax)
    denom <- (1 + omega) * (sigma - 1)
    if (abs(denom) < 1e-12) return(.Machine$double.xmax)
    theta1 <- omega / denom
    theta2 <- (omega * (sigma - 2) - 1) / denom
    theta_eq <- c(theta0, theta1, theta2)
    A <- Y - X_ohx %*% theta_eq
    AA <- as.numeric(crossprod(A))
    if (AA < 1e-16) return(.Machine$double.xmax)
    num <- as.numeric(crossprod(A, P_minus_diag %*% A))
    Q <- num / AA
    if (!is.finite(Q)) return(.Machine$double.xmax)
    Q
  }
  
  # Starting values from Step 2
  d_start <- c(theta0_start, sigma_start, omega_start)
  # Clamp starting values into the feasible interior
  if (d_start[2] <= 1) d_start[2] <- 1.5
  if (d_start[3] <= 0) d_start[3] <- 0.1
  
  # Optimize with BFGS. Mata uses Newton-Raphson; BFGS is the practical
  # R equivalent and avoids analytic Hessian.
  opt <- tryCatch(
    optim(par = d_start, fn = obj_fun, method = "BFGS",
          control = list(maxit = control$maxit, reltol = control$reltol)),
    error = function(e) NULL
  )
  
  if (is.null(opt) || opt$convergence != 0)
    return(list(status = "hliml_fail_no_convergence",
                d_start = d_start,
                last_value = if (!is.null(opt)) opt$value else NA))
  
  d_hat <- opt$par
  theta0_hat <- d_hat[1]
  sigma_hat  <- d_hat[2]
  omega_hat  <- d_hat[3]
  
  # Recompute residuals at the optimum
  denom <- (1 + omega_hat) * (sigma_hat - 1)
  theta1 <- omega_hat / denom
  theta2 <- (omega_hat * (sigma_hat - 2) - 1) / denom
  theta_eq <- c(theta0_hat, theta1, theta2)
  e_hat <- as.numeric(Y - X_ohx %*% theta_eq)
  
  # rho = omega * (sigma - 1) / (1 + sigma * omega)   per GS line 142
  rho_hat <- omega_hat * (sigma_hat - 1) / (1 + sigma_hat * omega_hat)
  
  list(
    status = "ok",
    sigma = sigma_hat,
    omega = omega_hat,
    rho = rho_hat,
    theta0 = theta0_hat,
    theta1 = theta1,
    theta2 = theta2,
    e_hat = e_hat,
    obj_value = opt$value,
    convergence = opt$convergence,
    iterations = if (!is.null(opt$counts)) opt$counts["function"] else NA,
    # Return P and related quantities for use in SE computation
    P = P,
    diag_P = diag_P,
    P_minus_diag = P_minus_diag,
    n = n,
    l = ncol(Z),
    k = ncol(X_ohx)
  )
}


# -------------------------------------------------------------------------
# 4.6 HNCS SANDWICH STANDARD ERRORS
#
# Implements Hausman-Newey-Chao-Swanson sandwich variance estimator
# from GS_Estimation.do lines 147-194. Used for HLIML SEs.
#
# Returns 3x3 v_bar covariance of the eta vector (theta0, theta1, theta2),
# then applies delta method to get (sigma, omega, rho) SEs.
#
# Algorithm:
#   1. Compute alpha = min eigenvalue of (X_circle'X_circle)^-1 X_circle' P_diff X_circle
#      where X_circle = [Y, X] and P_diff = P - diag(P)
#   2. P_circle = P - diag(P) - alpha * I
#   3. H_bar = X' P_circle X
#   4. X_bar = X - e_hat * (e_hat'X / e_hat'e_hat)   (residualize X against e_hat)
#   5. sigma_bar = sigma_first + sigma_second (two pieces)
#   6. v_bar = (1/n) H_bar^-1 sigma_bar H_bar^-1
# -------------------------------------------------------------------------

hncs_sandwich_se <- function(Y, X_ohx, Z, e_hat, P, diag_P, P_minus_diag,
                             sigma, omega, rho) {
  # Y: n x 1
  # X_ohx: n x 3 in (ones, x1, x2) order
  # Z: n x l instruments
  # e_hat: residuals from HLIML
  # P, diag_P, P_minus_diag: precomputed projection and its diagonal pieces
  # sigma, omega, rho: HLIML point estimates
  
  Y <- as.numeric(Y)
  X_ohx <- as.matrix(X_ohx)
  Z <- as.matrix(Z)
  e_hat <- as.numeric(e_hat)
  n <- length(Y)
  l <- ncol(Z)
  k <- ncol(X_ohx)
  
  # Step 1: alpha = min eig of (X_circle'X_circle)^-1 (X_circle' P_diff X_circle)
  X_circle <- cbind(Y, X_ohx)                # n x (1 + k) = n x 4
  XcXc <- crossprod(X_circle)
  XcPdXc <- crossprod(X_circle, P_minus_diag %*% X_circle)
  XcXc_inv <- tryCatch(solve(XcXc), error = function(e) NULL)
  if (is.null(XcXc_inv))
    return(list(status = "hncs_fail_singular_XcXc"))
  M <- XcXc_inv %*% XcPdXc
  eig <- tryCatch(eigen(M, only.values = TRUE)$values, error = function(e) NULL)
  if (is.null(eig))
    return(list(status = "hncs_fail_eig"))
  alpha <- min(Re(eig))
  
  # Step 2: P_circle = P - diag(P) - alpha * I
  P_circle <- P_minus_diag - alpha * diag(n)
  
  # Step 3: H_bar = X' P_circle X
  H_bar <- crossprod(X_ohx, P_circle %*% X_ohx)
  
  # Step 4: X_bar = X - e_hat * (e_hat'X / e_hat'e_hat)
  # i.e., residualize X against e_hat
  ee <- as.numeric(crossprod(e_hat))
  if (ee < 1e-16)
    return(list(status = "hncs_fail_zero_residuals"))
  eX <- as.numeric(crossprod(e_hat, X_ohx))  # length k (was 1 x k matrix)
  # Outer product: e_hat (n) outer with eX/ee (k) gives n x k matrix
  X_bar <- X_ohx - outer(as.numeric(e_hat), eX / ee)  # n x k
  
  # Step 5a: sigma_first vectorized
  # sigma_first[a,b] = sum_i [(PXb)_i (PXb)_i' - P_ii Xb_i (PXb)_i' - P_ii (PXb)_i Xb_i'] * e_i^2
  #                  = sum_i e_i^2 (PXb_i)(PXb_i)'
  #                    - sum_i P_ii e_i^2 [Xb_i (PXb_i)' + (PXb_i) Xb_i']
  PXb <- P %*% X_bar                          # n x k
  e2 <- e_hat^2                               # n
  # Term 1: sum_i e_i^2 (PXb_i)(PXb_i)' = (PXb)' diag(e^2) (PXb)
  term1 <- crossprod(PXb, e2 * PXb)           # k x k
  # Term 2: sum_i P_ii e_i^2 [Xb_i (PXb_i)' + (PXb_i) Xb_i']
  # = X_bar' diag(P_ii e_i^2) (PXb) + (PXb)' diag(P_ii e_i^2) X_bar
  PiiE2 <- diag_P * e2                        # n
  term2a <- crossprod(X_bar, PiiE2 * PXb)     # k x k
  term2  <- term2a + t(term2a)
  sigma_first <- term1 - term2
  
  # Step 5b: sigma_second vectorized
  # sigma_second[a,b] = sum_ij P_ij^2 Xb_i,a Xb_j,b e_i e_j
  # Let M = diag(e) %*% Xb so M[i,a] = e_i Xb_{i,a}
  # Then sigma_second = M' (P :* P) M
  M_mat <- e_hat * X_bar                       # n x k (e_hat is recycled by row)
  P_sq <- P * P                                # element-wise square, n x n
  sigma_second <- crossprod(M_mat, P_sq %*% M_mat)  # k x k
  
  # Total sigma_bar
  sigma_bar <- sigma_first + sigma_second
  
  # Step 6: v_bar = H_bar^-1 * sigma_bar * H_bar^-1
  # NOTE: This deliberately deviates from Stata's GS_Estimation.do which has
  # v_bar = (1/n) * H_bar^-1 * sigma_bar * H_bar^-1, AND then divides delta
  # by (n-l) at the delta-method step. Both of those divisions appear to be
  # spurious given that H_bar = X' P_circle X is already O(n) un-normalized.
  # Empirical bootstrap on synthetic data confirms: removing both divisions
  # gives SEs that match the bootstrap to ~10%, while keeping them gives SEs
  # too small by a factor of ~500. We document this deviation but apply the
  # correction because the Stata version is empirically wrong.
  H_bar_inv <- tryCatch(solve(H_bar), error = function(e) NULL)
  if (is.null(H_bar_inv))
    return(list(status = "hncs_fail_singular_Hbar"))
  v_bar <- H_bar_inv %*% sigma_bar %*% H_bar_inv
  
  # Heteroskedasticity-adjusted F and J statistics (lines 178, 180)
  ePde <- as.numeric(crossprod(e_hat, P_minus_diag %*% e_hat))
  ee2 <- as.numeric(crossprod(e_hat^2))
  F_het <- l * ePde / ee2
  
  # J_h: e_hat' P_diff e_hat / sqrt((1/l) (e_hat')^2 P_diff^2 e_hat^2) + l
  # Translating Mata's element-wise notation:
  # (e_hat')^2 elementwise = e_hat^2 (as row vector)
  # P_diff^2 elementwise = P_minus_diag * P_minus_diag
  # e_hat^2 (column) = e^2 stacked
  # So denominator inside sqrt = (1/l) * (e_hat^2 row) %*% (P_minus_diag * P_minus_diag) %*% (e_hat^2 col)
  e_hat2 <- e_hat^2
  Pd_sq <- P_minus_diag * P_minus_diag
  inner <- as.numeric(t(e_hat2) %*% Pd_sq %*% e_hat2) / l
  J_h <- ePde / sqrt(max(inner, 1e-30)) + l
  
  # Now delta method: V_eta is in (theta0, theta1, theta2) order = (cons, x1, x2)
  # Stata code uses indices 2,3 of e(V), which corresponds to the (x1, x2)
  # submatrix when e(V) is ordered [_cons, x1, x2]. We follow Stata convention
  # here since X_ohx is [ones, x1, x2].
  V_sub <- v_bar[2:3, 2:3, drop = FALSE]
  
  # Jacobian J = d(sigma, rho) / d(theta1, theta2) — same closed form as in
  # delta_method_ses (the theta1/theta2 map is identical to eta_1/eta_2).
  # B4 FIX (v0.3.0): previous matrix was the elementwise-absolute transpose;
  # see the derivation note in delta_method_ses.
  d_sub <- matrix(c(
    -(sigma - 1)^3 * (1 - rho),                          # d sigma / d theta1
    (sigma - 1)^2 * (1 - rho),                           # d sigma / d theta2
    (1 - 2 * rho) * (sigma - 1)^2 * (1 - rho)^2,         # d rho   / d theta1
    2 * rho * (sigma - 1) * (1 - rho)^2                  # d rho   / d theta2
  ), nrow = 2, byrow = TRUE)
  
  # Delta method: standard form J V J' (no /(n-l) division; see note above
  # at v_bar construction).
  delta_mat <- d_sub %*% V_sub %*% t(d_sub)
  diag(delta_mat) <- pmax(diag(delta_mat), 0)
  
  sigma_se <- sqrt(delta_mat[1, 1])
  rho_se   <- sqrt(delta_mat[2, 2])
  
  # Omega SE via further delta method, same formula as Step 2
  denom4 <- (sigma * (rho - 1) + 1)^4
  if (denom4 < 1e-20) {
    omega_se <- NA_real_
  } else {
    omega_var <- (1 / denom4) * (
      rho^2 * (1 - rho)^2 * delta_mat[1, 1] +
        (sigma - 1)^2 * delta_mat[2, 2] -
        2 * (sigma - 1) * rho * (1 - rho) * delta_mat[1, 2]
    )
    omega_se <- if (omega_var >= 0) sqrt(omega_var) else NA_real_
  }
  
  list(
    status = "ok",
    sigma_se = sigma_se,
    omega_se = omega_se,
    rho_se = rho_se,
    F_het = F_het,
    J_h = J_h,
    v_bar = v_bar,
    alpha = alpha
  )
}


# -------------------------------------------------------------------------
# 5. TOP-LEVEL ESTIMATOR FOR ONE CELL
#
# Mirrors GS_Estimation.do Steps 1-3 for a single (importer, product) cell.
# Returns point estimates and SEs for Step 2 (weighted Fuller LIML) and
# Step 3 (HLIML), with feasibility-adjustment logic determining the final
# reported (sigma, omega, rho).
#
# Input data frame `cell_df` must have columns:
#   y       - squared reference-differenced log price changes
#   x1      - squared reference-differenced log share changes
#   x2      - cross product of (lp_dif - h_lp_dif) and (ls_dif - h_ls_dif)
#   exporter - exporter ID (will be dummied out, reference exporter excluded)
#
# This is exactly the moment-equation data produced by GS_Data.do.
# -------------------------------------------------------------------------

estimate_cell_liml <- function(cell_df,
                               ref_exporter = NULL,
                               fuller_alpha = 1,
                               sigma_start_cap = 10,
                               omega_start_cap = 10,
                               omega_start_floor = 0.001,
                               rho_clamp = c(0.0001, 0.999)) {
  
  # Drop missing
  cell_df <- cell_df[complete.cases(cell_df[, c("y", "x1", "x2", "exporter")]), ]
  cell_df <- cell_df[!(cell_df$y == 0 & cell_df$x1 == 0 & cell_df$x2 == 0), ]
  
  n <- nrow(cell_df)
  if (n < 5) return(list(status = "fail_insufficient_obs", n = n))
  
  exporters_unique <- unique(cell_df$exporter)
  if (length(exporters_unique) < 3) return(list(status = "fail_too_few_exporters",
                                                n_exporters = length(exporters_unique)))
  
  # Build exporter dummies, excluding the reference exporter as the omitted category
  # NOTE: in the Stata code (GS_Estimation.do line 18), the instruments are
  # `c_I_*` which are dummies for all products *except* the reference.
  # The reference exporter becomes the omitted category and the constant captures it.
  if (is.null(ref_exporter)) {
    # Default: use the first exporter as reference if not specified
    ref_exporter <- exporters_unique[1]
  }
  non_ref_exporters <- setdiff(exporters_unique, ref_exporter)
  if (length(non_ref_exporters) < 2)
    return(list(status = "fail_too_few_nonref_exporters"))
  
  # Construct dummies
  exporter_dummies <- sapply(non_ref_exporters, function(e) as.numeric(cell_df$exporter == e))
  if (is.null(dim(exporter_dummies))) exporter_dummies <- matrix(exporter_dummies, ncol = 1)
  colnames(exporter_dummies) <- paste0("c_I_", non_ref_exporters)
  
  Y <- cell_df$y
  # Stata convention for ivreg2: regressors are ordered [endogenous, included_exog, constant]
  # Our endogenous regressors are x1 and x2; constant is the only included exogenous.
  X <- cbind(x1 = cell_df$x1, x2 = cell_df$x2, ones = 1)
  # endog_idx points to the x1, x2 columns
  endog_idx <- c(1L, 2L)
  # IMPORTANT: when every observation belongs to one of the non-reference
  # exporters (which is the case after dropping the reference's own data),
  # the exporter dummies sum to a column of ones and are collinear with
  # a constant. So Z = exporter_dummies only (no separate constant column);
  # the dummies span the constant subspace.
  # If reference-exporter observations are also in cell_df (they shouldn't
  # be, since y/x1/x2 are differences from reference and thus identically
  # zero for reference rows), the dummies do NOT span the constant and we
  # add one back. We detect this dynamically.
  any_ref <- any(cell_df$exporter == ref_exporter)
  Z <- if (any_ref) cbind(exporter_dummies, ones = 1) else exporter_dummies
  
  l_excluded <- ncol(exporter_dummies)  # number of excluded instruments
  
  # ---- STEP 1: Unweighted Fuller(1) LIML for starting values + residuals ----
  fit1 <- fuller_liml_core(Y, X, Z, weights = NULL, fuller_alpha = fuller_alpha,
                           endog_idx = endog_idx)
  if (fit1$status != "ok")
    return(list(status = paste0("step1_", fit1$status), n = n))
  
  eta1 <- fit1$eta  # (eta_x1, eta_x2, const)
  # In the new ordering, eta1[1] = coef on x1, eta1[2] = coef on x2, eta1[3] = const
  inv1 <- invert_structural(eta1[1], eta1[2])
  
  # Step 1 is primarily a residual generator + source of starting values for
  # Step 2. If its structural inversion fails (e.g., eta1 < 0), we still
  # have valid Step 1 residuals and can proceed to Step 2. The cap logic
  # below handles NA starting values (replaces them with caps/floors), so
  # Step 1 inversion failure does NOT abort cell estimation.
  
  # Apply starting-value caps from GS_Estimation.do lines 36-41
  # NB: invert_structural can return NA for any component when constraints
  # are violated. Treat NA as "use cap" rather than letting the comparison
  # propagate to the if().
  sigma_start <- inv1$sigma
  omega_start <- inv1$omega
  rho_start   <- inv1$rho
  if (is.na(sigma_start) || sigma_start > sigma_start_cap) sigma_start <- sigma_start_cap
  if (is.na(omega_start) || omega_start > omega_start_cap) omega_start <- omega_start_cap
  if (is.na(omega_start) || omega_start < omega_start_floor || omega_start < 0)
    omega_start <- omega_start_floor
  if (is.na(rho_start)) rho_start <- mean(rho_clamp)
  rho_start <- pmin(pmax(rho_start, rho_clamp[1]), rho_clamp[2])
  
  # ---- STEP 2: Heteroskedasticity correction ----
  # Regress squared residuals on exporter dummies (no constant) to get per-obs variance
  u2 <- fit1$u_hat^2
  # In Stata: regress uhat2 c_I_*, noc
  # This gives predicted u^2 by exporter (since dummies span the exporter dim)
  # Equivalent: mean of u^2 within exporter (for non-ref) and 0 for ref-only obs
  # We'll use mean-by-exporter for clarity
  u2_pred <- ave(u2, cell_df$exporter, FUN = function(x) mean(x))
  # Guard against zero/negative predictions. Perfect-fit edge case (all
  # u2 == 0) previously produced Inf via min() of an empty vector; fall
  # back to the absolute floor instead. (v0.4.0)
  pos_u2 <- u2[u2 > 0]
  u2_floor <- if (length(pos_u2) > 0L) max(1e-10, min(pos_u2) * 0.01) else 1e-10
  u2_pred <- pmax(u2_pred, u2_floor)
  
  weights_step2 <- 1 / u2_pred
  
  fit2 <- fuller_liml_core(Y, X, Z, weights = weights_step2,
                           fuller_alpha = fuller_alpha, endog_idx = endog_idx)
  if (fit2$status != "ok") {
    # Fall back to step 1 estimate
    return(list(status = paste0("step2_", fit2$status, "_fellback_to_step1"),
                n = n,
                sigma = inv1$sigma, omega = inv1$omega, rho = inv1$rho,
                sigma_se = NA, omega_se = NA, rho_se = NA,
                step1_eta = eta1, fallback_used = TRUE))
  }
  
  eta2 <- fit2$eta
  # eta2[1] = coef on x1, eta2[2] = coef on x2, eta2[3] = const
  inv2 <- invert_structural(eta2[1], eta2[2])
  
  # Step 2 inversion failure is non-fatal: HLIML doesn't depend on Step 2's
  # structural inversion (it parameterizes directly in sigma/omega space and
  # uses the eta vector as a starting point for BFGS). If inv2 fails, we
  # produce NA Step 2 SEs but still run HLIML.
  inv2_ok <- !is.na(inv2$sigma)
  
  # Standard errors via delta method using ROBUST V_eta from step 2.
  # Skip if Step 2 inversion failed; we'll rely on HLIML SEs in that case.
  if (inv2_ok) {
    ses <- delta_method_ses(inv2$sigma, inv2$rho, fit2$V_eta_robust,
                            n = fit2$n, l = fit2$l, endog_idx = endog_idx)
  } else {
    ses <- list(sigma_se = NA_real_, omega_se = NA_real_, rho_se = NA_real_)
  }
  
  # Weak-instrument F (Kleibergen-Paap) on the weighted regression
  F_kp <- kleibergen_paap_F(cbind(cell_df$x1, cell_df$x2),
                            Z, weights = weights_step2)
  # Sargan overidentification statistic on the Step-2 fit.
  # B8 FIX (v0.3.0): fit2$u_hat are residuals in the WEIGHTED metric
  # (Y, X, Z were rescaled by sqrt(w) inside fuller_liml_core), so the
  # projection must use the equally rescaled Z. Previously the unweighted
  # Z was projected against weighted residuals — a metric mismatch that
  # made jstat/jstat_pval unreliable. (This is the homoskedastic Sargan
  # form, not a robust Hansen J; see hansen_J's header.)
  w_sqrt_s2 <- sqrt(weights_step2 * n / sum(weights_step2))
  J_stat <- hansen_J(fit2$u_hat, Z * w_sqrt_s2, weights = NULL)
  J_dof <- l_excluded - 2  # 2 endogenous regressors
  J_pval <- if (J_dof > 0) 1 - pchisq(J_stat, df = J_dof) else NA_real_
  
  # Stock-Yogo test (uses number of *suppliers* = number of exporter dummies)
  # F8 (v0.4.0): screen at both the strict 0.10 maximal-size threshold
  # (headline, back-compatible) and G&S (2024)'s 0.25 rule of thumb.
  sy   <- stockyogo_pass(F_kp, n_excluded_instruments = l_excluded,
                         size_threshold = 0.10)
  sy25 <- stockyogo_pass(F_kp, n_excluded_instruments = l_excluded,
                         size_threshold = 0.25)
  
  # ---- STEP 3: HLIML (jackknife LIML) ----
  # GS_Estimation.do lines 94-198. Rescales y, x1, x2, ones by 1/shat
  # before HLIML estimation (lines 94-96). This is the heteroskedasticity
  # adjustment that makes the constrained HLIML objective comparable to
  # Step 2's weighted Fuller LIML.
  shat <- sqrt(u2_pred)   # sqrt of per-obs predicted variance
  Y_h <- Y / shat
  X_h_ohx <- cbind(ones = 1 / shat,
                   x1   = cell_df$x1 / shat,
                   x2   = cell_df$x2 / shat)   # ORDER MATTERS: [ones, x1, x2]
  # Z stays unscaled — exporter dummies aren't divided by shat in Stata code
  # (only y, x1, x2, ones are rescaled in the foreach loop).
  
  # Starting values from Step 2's weighted LIML estimates
  # cons_w = eta2[3] (constant) in our X = [x1, x2, ones] ordering
  cons_w <- eta2[3]
  sigma_w <- inv2$sigma
  omega_w <- inv2$omega
  # Clamp omega_w to be strictly positive for HLIML start
  if (is.na(omega_w) || omega_w <= 0) omega_w <- 0.1
  if (is.na(sigma_w) || sigma_w <= 1) sigma_w <- 1.5
  
  hliml_fit <- hliml_core(Y_h, X_h_ohx, Z,
                          sigma_start = sigma_w,
                          omega_start = omega_w,
                          theta0_start = cons_w)
  
  # Decide which estimate to report based on feasibility-adjustment logic
  # (GS_Estimation.do lines 200-214)
  hliml_status <- hliml_fit$status
  sigma_hliml <- if (hliml_status == "ok") hliml_fit$sigma else NA_real_
  omega_hliml <- if (hliml_status == "ok") hliml_fit$omega else NA_real_
  rho_hliml   <- if (hliml_status == "ok") hliml_fit$rho   else NA_real_
  
  # Compute HLIML SEs if HLIML converged
  if (hliml_status == "ok") {
    se_h <- tryCatch(
      hncs_sandwich_se(Y_h, X_h_ohx, Z,
                       e_hat = hliml_fit$e_hat,
                       P = hliml_fit$P,
                       diag_P = hliml_fit$diag_P,
                       P_minus_diag = hliml_fit$P_minus_diag,
                       sigma = sigma_hliml,
                       omega = omega_hliml,
                       rho   = rho_hliml),
      error = function(e) list(status = paste0("hncs_error_", conditionMessage(e)))
    )
  } else {
    se_h <- list(status = "hliml_failed_no_se")
  }
  sigma_hliml_se <- if (isTRUE(se_h$status == "ok")) se_h$sigma_se else NA_real_
  omega_hliml_se <- if (isTRUE(se_h$status == "ok")) se_h$omega_se else NA_real_
  rho_hliml_se   <- if (isTRUE(se_h$status == "ok")) se_h$rho_se   else NA_real_
  F_het <- if (isTRUE(se_h$status == "ok")) se_h$F_het else NA_real_
  J_h   <- if (isTRUE(se_h$status == "ok")) se_h$J_h   else NA_real_
  
  # ---- Feasibility-adjustment (lines 200-214) ----
  # The final reported (sigma, omega, rho) follows this priority:
  #  1. HLIML if admissible (sigma > 1, omega > 0, sigma <= 10 implied by start cap)
  #  2. Step 2 weighted Fuller LIML (sigma_w, omega_w) if HLIML failed/infeasible
  #     and Step 2 is admissible
  #  3. NA + adjust flag indicating failure
  #
  # The adjust flag mirrors Stata's:
  #   0 = HLIML admissible
  #   1 = HLIML failed, sigma from Step 2 (sigma_w > 1)
  #   2 = HLIML failed, omega from Step 2 (omega_w != .)
  #   3 = omega < 0, clamped to 0.0001
  #   4 = sigma clamped at the upper cap (omega state in omega_capped)
  #   5 = omega clamped at the upper cap, sigma NOT capped
  adjust <- 0L
  final_sigma <- sigma_hliml
  final_omega <- omega_hliml
  final_rho   <- rho_hliml
  final_sigma_se <- sigma_hliml_se
  final_omega_se <- omega_hliml_se
  final_rho_se   <- rho_hliml_se
  final_source <- "hliml"
  
  # Check HLIML admissibility - must have admissible sigma AND omega
  hliml_admissible <- !is.na(sigma_hliml) && sigma_hliml > 1 &&
    sigma_hliml < sigma_start_cap &&
    !is.na(omega_hliml) && omega_hliml > 0 &&
    omega_hliml < omega_start_cap
  
  if (!hliml_admissible) {
    # Try Step 2 fallback, applying the same admissibility caps as HLIML.
    # B9 FIX (v0.3.0): track sigma/omega capping in two explicit booleans
    # rather than letting the omega branch overwrite the ordinal adjust
    # code. Previously a cell with sigma capped AND omega capped reported
    # adjust = 5 only (undercounting the sigma-cap share), and a cell with
    # a valid interior Step-2 sigma whose omega blew up reported adjust = 5
    # and had its perfectly usable sigma_se NA'd by the A1 rule. New
    # semantics: adjust = 4 whenever sigma is capped (omega state in
    # omega_capped), adjust = 5 only when omega alone is capped, and the
    # A1 invalidation applies per-parameter.
    sigma_capped <- FALSE
    omega_capped <- FALSE
    if (!is.na(inv2$sigma) && inv2$sigma > 1 && inv2$sigma < sigma_start_cap) {
      final_sigma <- inv2$sigma
      adjust <- 1L
    } else if (!is.na(inv2$sigma) && inv2$sigma >= sigma_start_cap) {
      # Sigma blew up; clamp to cap
      final_sigma <- sigma_start_cap
      sigma_capped <- TRUE
    } else {
      final_sigma <- NA_real_
    }
    if (!is.na(inv2$omega) && inv2$omega >= 0 && inv2$omega <= omega_start_cap) {
      final_omega <- inv2$omega
      if (adjust == 0L) adjust <- 2L
    } else if (!is.na(inv2$omega) && inv2$omega > omega_start_cap) {
      # Omega blew up; clamp to cap
      final_omega <- omega_start_cap
      omega_capped <- TRUE
    } else {
      final_omega <- NA_real_
    }
    if (sigma_capped) {
      adjust <- 4L         # sigma at cap (omega may or may not be; see omega_capped)
    } else if (omega_capped) {
      adjust <- 5L         # omega at cap, sigma NOT capped
    }
    # If omega < 0 (shouldn't reach here from invert_structural but defensive)
    if (!is.na(final_omega) && final_omega < 0) {
      final_omega <- 0.0001
      adjust <- 3L
    }
    if (!is.na(final_sigma) && !is.na(final_omega)) {
      final_rho <- (final_omega * (final_sigma - 1)) /
        (1 + final_sigma * final_omega)
    }
    final_sigma_se <- ses$sigma_se
    final_omega_se <- ses$omega_se
    final_rho_se   <- ses$rho_se
    final_source <- "step2_weighted"
    # A1 (per-parameter): a clamped point otherwise carries the Step-2 SE
    # of the un-clamped blow-up, meaningless for the clamped value. NA the
    # capped parameter's SE only — an interior sigma estimate keeps its SE
    # even when omega capped (and vice versa).
    if (sigma_capped) final_sigma_se <- NA_real_
    if (omega_capped) final_omega_se <- NA_real_
    if (sigma_capped || omega_capped) final_rho_se <- NA_real_
  } else {
    sigma_capped <- FALSE
    omega_capped <- FALSE
  }
  
  # Final sanity: if both HLIML and Step 2 fallback failed, mark as failed.
  if (is.na(final_sigma) && is.na(final_omega)) {
    return(list(
      status = "all_inversions_failed",
      n = n,
      n_exporters = length(exporters_unique),
      n_periods = length(unique(cell_df$t)),
      eta_step1 = eta1,
      eta_step2 = eta2,
      hliml_status = hliml_status,
      kappa = fit2$kappa,
      lambda_min = fit2$lambda_min
    ))
  }
  
  list(
    status = "ok",
    n = n,
    n_exporters = length(exporters_unique),
    n_periods = length(unique(cell_df$t)),
    # Final reported estimates (with feasibility adjustment applied)
    sigma = final_sigma,
    omega = final_omega,
    rho   = final_rho,
    sigma_se = final_sigma_se,
    omega_se = final_omega_se,
    rho_se   = final_rho_se,
    adjust   = adjust,
    # B9: explicit per-parameter cap flags (see the fallback block above).
    sigma_capped = sigma_capped,
    omega_capped = omega_capped,
    # A1: weakly-identified sigma flag — sigma itself sits at the cap.
    # (Previously TRUE for adjust 5 too, i.e. when only omega was capped.)
    sigma_weak = sigma_capped,
    # B3: ω was clamped to its lower admissibility floor (1e-4, matching
    # invert_structural's omega_floor) rather than estimated at an interior
    # point. invert_structural floors ω before the adjust block sees it, so a
    # floored cell otherwise reads as adjust 0/1; this boolean makes the floored
    # cells filterable (15.7% of all cells, ~31% of estimated cells in the
    # v0.3.0 run; see results/stage1_summary.json). A genuine
    # interior estimate never lands exactly on the floor.
    omega_floored = isTRUE(!is.na(final_omega) && final_omega <= 1e-4),
    final_source = final_source,
    # Test statistics
    fstat_kp = F_kp,
    fstat_het = F_het,        # heteroskedasticity-adjusted F from HLIML
    jstat    = J_stat,
    jstat_pval = J_pval,
    jstat_h  = J_h,           # HLIML-residual-based J
    stockyogo_pass = if (!is.null(sy)) sy$pass else NA,
    stockyogo_cv = if (!is.null(sy)) sy$cv else NA,
    # F8/F9 (v0.4.0): G&S (2024) protocol columns -- SY pass at their 0.25
    # maximal-size rule of thumb, Sargan pass at conventional p > 0.2
    # (their tabulated "J P-value" is the complement, pchisq(J, df)),
    # and the joint pass-both flag.
    stockyogo_pass_gs25 = if (!is.null(sy25)) sy25$pass else NA,
    stockyogo_cv_gs25 = if (!is.null(sy25)) sy25$cv else NA,
    sargan_pass = if (!is.na(J_pval)) J_pval > 0.2 else NA,
    gs_pass_both = {
      .p25 <- if (!is.null(sy25)) sy25$pass else NA
      .sp  <- if (!is.na(J_pval)) J_pval > 0.2 else NA
      if (is.na(.p25) || is.na(.sp)) NA else (.p25 && .sp)
    },
    # Step-specific estimates for diagnostic / comparison purposes
    sigma_step1 = inv1$sigma,
    omega_step1 = inv1$omega,
    rho_step1 = inv1$rho,
    sigma_step2 = inv2$sigma,
    omega_step2 = inv2$omega,
    rho_step2 = inv2$rho,
    sigma_step2_se = ses$sigma_se,
    omega_step2_se = ses$omega_se,
    rho_step2_se = ses$rho_se,
    sigma_hliml = sigma_hliml,
    omega_hliml = omega_hliml,
    rho_hliml = rho_hliml,
    sigma_hliml_se = sigma_hliml_se,
    omega_hliml_se = omega_hliml_se,
    rho_hliml_se = rho_hliml_se,
    hliml_status = hliml_status,
    hliml_convergence = if (hliml_status == "ok") hliml_fit$convergence else NA,
    hliml_iterations = if (hliml_status == "ok") hliml_fit$iterations else NA,
    eta_step1 = eta1,
    eta_step2 = eta2,
    sigma_start = sigma_start,
    omega_start = omega_start,
    fallback_used = (final_source != "hliml"),
    inversion_status = inv2$status,
    kappa = fit2$kappa,
    lambda_min = fit2$lambda_min
  )
}


# -------------------------------------------------------------------------
# 6. DATA PREP: REPLICATE GS_Data.do
#
# Input: long-format trade panel with columns exporter, t, value, quantity
#        for a single (importer, product) cell.
# Output: data frame with columns y, x1, x2, exporter, t suitable for
#         estimate_cell_liml().
#
# Steps (mirroring GS_Data.do):
#  1. Aggregate to (exporter, t) if not already
#  2. Compute share within each t: s = value / sum(value over exporters within t)
#  3. Compute log share ls and log unit value lp = log(value/quantity)
#  4. First-difference by exporter: ls_dif, lp_dif
#  5. Choose reference exporter: largest cusval among exporters with longest panel
#  6. Construct y, x1, x2 relative to reference
# -------------------------------------------------------------------------

prepare_cell_moments <- function(trade_df,
                                 exporter_col = "exporter",
                                 time_col = "t",
                                 value_col = "value",
                                 quantity_col = "quantity",
                                 min_year = NULL) {
  
  use_dt <- requireNamespace("data.table", quietly = TRUE)
  
  if (use_dt) {
    d <- data.table::data.table(
      exporter = trade_df[[exporter_col]],
      t        = trade_df[[time_col]],
      value    = trade_df[[value_col]],
      quantity = trade_df[[quantity_col]]
    )
    d <- d[is.finite(value) & is.finite(quantity) & value > 0 & quantity > 0]
    
    if (!is.null(min_year)) {
      d <- d[t >= min_year]
      d[, t := t - min_year + 1L]
    }
    
    # Sum duplicates per (exporter, t)
    d <- d[, .(value = sum(value), quantity = sum(quantity)),
           by = .(exporter, t)]
    
    if (nrow(d) < 5)
      return(list(moments = NULL, ref_exporter = NA,
                  n_obs = 0, n_exporters = 0))
    
    # Compute share within t, log share, log unit value
    d[, uv := value / quantity]
    d[, lp := log(uv)]
    d[, totsum := sum(value), by = t]
    d[, s  := value / totsum]
    d[, ls := log(s)]
    
    # First-difference by exporter
    data.table::setorder(d, exporter, t)
    d[, ls_dif := ls - data.table::shift(ls, 1L), by = exporter]
    d[, lp_dif := lp - data.table::shift(lp, 1L), by = exporter]

    # B1 guard (Stage-1 counterpart of the prepare_data.R fix): shift()
    # pairs adjacent rows in time order but does not check the year step.
    # An exporter trading in 2002 then 2007 would otherwise contribute a
    # 5-year change treated as a one-period diff to the y/x1/x2 second
    # moments that identify sigma. Null the diffs where the step is not
    # exactly 1; the is.finite() filter below drops them alongside each
    # panel's leading NA.
    d[, t_gap := t - data.table::shift(t, 1L), by = exporter]
    d[is.na(t_gap) | t_gap != 1L,
      `:=`(ls_dif = NA_real_, lp_dif = NA_real_)]
    d[, t_gap := NULL]
    
    # Choose reference exporter: longest panel, ties by largest cusval
    exp_summary <- d[, .(n_periods = data.table::uniqueN(t), cusval = sum(value)),
                     by = exporter]
    max_periods <- max(exp_summary$n_periods)
    ref_exporter <- exp_summary[n_periods == max_periods][which.max(cusval), exporter]
    
    # Pull reference exporter's (ls_dif, lp_dif) by t
    ref_data <- d[exporter == ref_exporter, .(t, h_ls_dif = ls_dif, h_lp_dif = lp_dif)]
    d <- ref_data[d, on = "t"]
    
    # Construct moments
    d[, `:=`(
      y  = (lp_dif - h_lp_dif)^2,
      x1 = (ls_dif - h_ls_dif)^2,
      x2 = (lp_dif - h_lp_dif) * (ls_dif - h_ls_dif)
    )]
    d <- d[is.finite(y) & is.finite(x1) & is.finite(x2)]
    d <- d[!(y == 0 & x1 == 0 & x2 == 0)]
    
    list(moments = as.data.frame(d), ref_exporter = ref_exporter,
         n_obs = nrow(d), n_exporters = data.table::uniqueN(d$exporter))
    
  } else {
    # Base-R fallback (slow on large cells)
    d <- data.frame(
      exporter = trade_df[[exporter_col]],
      t        = trade_df[[time_col]],
      value    = trade_df[[value_col]],
      quantity = trade_df[[quantity_col]]
    )
    d <- d[is.finite(d$value) & is.finite(d$quantity) &
             d$value > 0 & d$quantity > 0, ]
    if (!is.null(min_year)) {
      d <- d[d$t >= min_year, ]
      d$t <- d$t - min_year + 1
    }
    d <- aggregate(cbind(value, quantity) ~ exporter + t, data = d, FUN = sum)
    if (nrow(d) < 5)
      return(list(moments = NULL, ref_exporter = NA, n_obs = 0, n_exporters = 0))
    d$uv <- d$value / d$quantity
    d$lp <- log(d$uv)
    totsum_by_t <- ave(d$value, d$t, FUN = sum)
    d$s <- d$value / totsum_by_t
    d$ls <- log(d$s)
    d <- d[order(d$exporter, d$t), ]
    d$ls_dif <- ave(d$ls, d$exporter, FUN = function(x) c(NA, diff(x)))
    d$lp_dif <- ave(d$lp, d$exporter, FUN = function(x) c(NA, diff(x)))
    # B1 guard: null diffs that span a non-consecutive year step (see the
    # data.table branch above for rationale).
    d$t_gap <- ave(d$t, d$exporter, FUN = function(x) c(NA, diff(x)))
    gap_rows <- is.na(d$t_gap) | d$t_gap != 1
    d$ls_dif[gap_rows] <- NA_real_
    d$lp_dif[gap_rows] <- NA_real_
    d$t_gap <- NULL
    exp_summary <- do.call(rbind, lapply(split(d, d$exporter), function(g) {
      data.frame(exporter = g$exporter[1],
                 n_periods = length(unique(g$t)),
                 cusval = sum(g$value))
    }))
    max_periods <- max(exp_summary$n_periods)
    candidates <- exp_summary[exp_summary$n_periods == max_periods, ]
    ref_exporter <- candidates$exporter[which.max(candidates$cusval)]
    ref_data <- d[d$exporter == ref_exporter, c("t", "ls_dif", "lp_dif")]
    names(ref_data)[2:3] <- c("h_ls_dif", "h_lp_dif")
    d <- merge(d, ref_data, by = "t", all.x = TRUE)
    d$y  <- (d$lp_dif - d$h_lp_dif)^2
    d$x1 <- (d$ls_dif - d$h_ls_dif)^2
    d$x2 <- (d$lp_dif - d$h_lp_dif) * (d$ls_dif - d$h_ls_dif)
    d <- d[complete.cases(d[, c("y", "x1", "x2")]), ]
    d <- d[!(d$y == 0 & d$x1 == 0 & d$x2 == 0), ]
    list(moments = d, ref_exporter = ref_exporter,
         n_obs = nrow(d), n_exporters = length(unique(d$exporter)))
  }
}


# -------------------------------------------------------------------------
# 7. CONVENIENCE WRAPPER
#
# Estimate elasticities for one (importer, product) cell, going from a
# raw long-format trade panel to point estimates and standard errors.
# -------------------------------------------------------------------------

estimate_elasticities <- function(trade_df,
                                  exporter_col = "exporter",
                                  time_col = "t",
                                  value_col = "value",
                                  quantity_col = "quantity",
                                  min_year = NULL,
                                  fuller_alpha = 1) {
  
  prep <- prepare_cell_moments(trade_df, exporter_col, time_col,
                               value_col, quantity_col, min_year)
  if (prep$n_obs < 5)
    return(list(status = "fail_prepare_insufficient_obs", prep = prep))
  
  fit <- estimate_cell_liml(prep$moments,
                            ref_exporter = prep$ref_exporter,
                            fuller_alpha = fuller_alpha)
  fit$ref_exporter <- prep$ref_exporter
  fit$n_obs_raw   <- prep$n_obs
  fit$n_exporters_raw <- prep$n_exporters
  fit
}


# =========================================================================
# END OF MODULE
# =========================================================================
