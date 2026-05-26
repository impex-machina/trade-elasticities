# =========================================================================
# verify_jacobian.R
#
# Verifies the analytic Jacobian in het_obj_fixed_sigma_jacobian_rcpp.cpp
# against numerical differentiation (numDeriv::jacobian) on synthetic data.
#
# Tolerance: max absolute difference < 1e-6.
#
# Also computes the sandwich SE under both:
#   (a) the new analytic Jacobian
#   (b) numerical differentiation
# and confirms they agree.
#
# Requires: Rcpp, numDeriv
#   install.packages(c("Rcpp", "numDeriv"))
# =========================================================================

suppressPackageStartupMessages({
  library(Rcpp)
  library(numDeriv)
})

PROJECT_ROOT <- "C:/Users/maxxj/OneDrive/Desktop/Projects/trade-elasticities/trade_elast_baci_hs92_v202601_hs4"
JAC_CPP    <- file.path(PROJECT_ROOT, "source/het_obj_fixed_sigma_jacobian_rcpp.cpp")
OBJ_CPP    <- file.path(PROJECT_ROOT, "source/het_obj_fixed_sigma_rcpp.cpp")
SANDWICH_R <- file.path(PROJECT_ROOT, "source/sandwich_se.R")

# Compile
cat("Compiling Rcpp objects...\n")
sourceCpp(JAC_CPP)
sourceCpp(OBJ_CPP)
source(SANDWICH_R)

# =========================================================================
# Synthetic data
# =========================================================================
set.seed(42)
J <- 5L
N_imp <- J
N_exp <- 20L

# Fixed scalars
sigma_true <- 2.5
sigma_val  <- sigma_true  # the optimizer uses sigma_val (fixed)

# Random data
imp_X    <- matrix(rnorm(N_imp * 5, 1, 0.3), N_imp, 5)
imp_Y    <- rnorm(N_imp, 0, 0.5)
exp_X    <- matrix(rnorm(N_exp * 9, 1, 0.3), N_exp, 9)
exp_Y    <- rnorm(N_exp, 0, 0.5)

# exp_jmap: 1-based index into FULL d (sigma, gamma_k, gamma_j...) so
# valid values are 2 to J+2. Generate uniformly.
exp_jmap <- as.integer(sample(2:(J + 2), N_exp, replace = TRUE))

exp_sig_V <- runif(N_exp, 1.5, 4)
exp_gam_V <- runif(N_exp, 0.1, 1)
wt_imp    <- runif(N_imp, 0.5, 2)
wt_exp    <- runif(N_exp, 0.5, 2)

# Pretend we have a fitted theta_hat. Use something reasonable.
theta_hat <- c(0.4, runif(J, 0.1, 0.8))   # length K = J+1
K <- length(theta_hat)

cat(sprintf("Synthetic cell: J=%d, N_imp=%d, N_exp=%d, K=%d\n",
            J, N_imp, N_exp, K))
cat(sprintf("theta_hat = %s\n",
            paste(sprintf("%.3f", theta_hat), collapse = ", ")))

# =========================================================================
# TEST 1: residuals match between the analytic objective and the new
# residual-returning function
# =========================================================================
cat("\n[TEST 1] Residual consistency between objective and Jacobian function\n")

# The new function returns residuals
jac_out <- het_residuals_and_jacobian_fixed_sigma_rcpp(
  d = theta_hat, sigma = sigma_val,
  imp_Y = imp_Y, imp_X = imp_X,
  exp_Y = exp_Y, exp_X = exp_X,
  exp_jmap = exp_jmap, exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
  wt_imp = wt_imp, wt_exp = wt_exp
)
stopifnot(identical(jac_out$status, "ok"))

# The existing objective returns weighted SSR. So:
#   SSR_from_objective == sum(wt_i * r_i^2)
ssr_from_obj <- het_obj_fixed_sigma_rcpp(
  d = theta_hat, sigma = sigma_val,
  imp_Y = imp_Y, imp_X = imp_X,
  exp_Y = exp_Y, exp_X = exp_X,
  exp_jmap = exp_jmap, exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
  wt_imp = wt_imp, wt_exp = wt_exp,
  ln_gamma_prior = NA_real_, shrinkage_lambda = 0
)

ssr_from_resid <- sum(jac_out$weights * jac_out$residuals^2)
cat(sprintf("  SSR (objective):     %.10f\n", ssr_from_obj))
cat(sprintf("  SSR (sum w_i r_i^2): %.10f\n", ssr_from_resid))
cat(sprintf("  abs diff:            %.2e\n", abs(ssr_from_obj - ssr_from_resid)))
stopifnot(abs(ssr_from_obj - ssr_from_resid) < 1e-10)
cat("  PASS\n")

# =========================================================================
# TEST 2: analytic Jacobian matches numerical differentiation
# =========================================================================
cat("\n[TEST 2] Analytic vs numerical Jacobian\n")

# Build a residual function that takes theta and returns the n-vector r(theta)
resid_fn <- function(theta) {
  out <- het_residuals_and_jacobian_fixed_sigma_rcpp(
    d = theta, sigma = sigma_val,
    imp_Y = imp_Y, imp_X = imp_X,
    exp_Y = exp_Y, exp_X = exp_X,
    exp_jmap = exp_jmap, exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
    wt_imp = wt_imp, wt_exp = wt_exp
  )
  out$residuals
}

# Numerical Jacobian via finite differences
J_numeric <- jacobian(resid_fn, theta_hat)
cat(sprintf("  Numerical Jacobian shape: %d x %d\n",
            nrow(J_numeric), ncol(J_numeric)))

# Reconstruct dense analytic Jacobian from the triplet output
n_total <- N_imp + N_exp
J_analytic <- matrix(0, n_total, K)
rows <- jac_out$jac_row + 1L
cols <- jac_out$jac_col + 1L
vals <- jac_out$jac_val
for (i in seq_along(rows)) {
  J_analytic[rows[i], cols[i]] <- vals[i]
}

max_diff <- max(abs(J_analytic - J_numeric))
cat(sprintf("  max |J_analytic - J_numeric| = %.3e\n", max_diff))

# Where is the worst disagreement (if any)?
worst <- which(abs(J_analytic - J_numeric) == max_diff, arr.ind = TRUE)[1, , drop = FALSE]
cat(sprintf("  worst at (row=%d, col=%d): analytic=%.6e, numeric=%.6e\n",
            worst[1], worst[2],
            J_analytic[worst[1], worst[2]],
            J_numeric[worst[1], worst[2]]))

if (max_diff < 1e-6) {
  cat("  PASS (within tolerance)\n")
} else {
  cat("  FAIL — investigate before trusting SEs\n")
  # Don't stop() so we can inspect
}

# =========================================================================
# TEST 3: sandwich SE finite & positive for this cell
# =========================================================================
cat("\n[TEST 3] Sandwich SE produces finite, positive SEs\n")
sw <- compute_sandwich_se(jac_out)
cat(sprintf("  SE for gamma_k:    %.6f\n", sw$se[1]))
cat(sprintf("  SE for gamma_j[1]: %.6f\n", sw$se[2]))
cat(sprintf("  SE for gamma_j[%d]: %.6f\n", J, sw$se[K]))
stopifnot(all(is.finite(sw$se)))
stopifnot(all(sw$se >= 0))
cat("  PASS\n")

# =========================================================================
# TEST 4: cross-check sandwich SE against a numerical-Jacobian computation
# =========================================================================
cat("\n[TEST 4] Sandwich SE: analytic vs numerical Jacobian\n")

# Build A and B from the numerical Jacobian
W_diag  <- jac_out$weights
r_vec   <- jac_out$residuals
A_num   <- t(J_numeric) %*% diag(W_diag) %*% J_numeric
B_num   <- t(J_numeric) %*% diag(W_diag^2 * r_vec^2) %*% J_numeric
V_num   <- solve(A_num) %*% B_num %*% solve(A_num)
se_num  <- sqrt(diag(V_num))

cat("  Component-wise SE comparison:\n")
for (k in seq_len(K)) {
  cat(sprintf("    theta[%d]: analytic=%.6e  numeric=%.6e  diff=%.2e\n",
              k, sw$se[k], se_num[k], abs(sw$se[k] - se_num[k])))
}

max_se_diff <- max(abs(sw$se - se_num))
cat(sprintf("\n  max |SE_analytic - SE_numeric| = %.3e\n", max_se_diff))
if (max_se_diff < 1e-6) {
  cat("  PASS\n")
} else {
  cat("  WARN: SE difference larger than 1e-6. Investigate.\n")
}

cat("\n=== ALL TESTS COMPLETE ===\n")