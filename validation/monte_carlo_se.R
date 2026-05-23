# =============================================================================
# tests/monte_carlo_se.R
#
# Monte Carlo validation of three SE formulas for the heterogeneous-gamma
# fixed-sigma estimator. Reconstructed 2026-05-20 from past-chat traces of
# the original monte_carlo_se.R / _2 / _3 (lost; never saved to disk).
#
# Tests:
#   1. Unpenalized Gauss-Newton:  V = sigma_hat^2 * (J'WJ)^{-1}
#   2. Sandwich:                  V = A^{-1} B A^{-1} where
#                                 A = sum w_i J_i J_i', B = sum w_i^2 r_i^2 J_i J_i'
#   3. Penalized Gauss-Newton:    V = sigma_hat^2 * (J'WJ + 2 lambda diag(1/gamma^2))^{-1}
#
# Regimes (2x2 grid):
#   - homoskedastic + shrinkage_lambda = 0       (the original SE testbed)
#   - heteroskedastic + shrinkage_lambda = 0     (does sandwich win here?)
#   - homoskedastic + shrinkage_lambda = 0.1     (production setting, homo noise)
#   - heteroskedastic + shrinkage_lambda = 0.1   (production setting, hetero noise)
#
# Expected outcome per memory of original findings:
#   - Penalized GN:  ~5% calibration error vs empirical SD across replications
#   - Sandwich:      ~30% UNDER-estimate (residual-Jacobian correlation at NLS optimum)
#   - Unpenalized GN under shrinkage: ~30% OVER-estimate (prior Hessian missing)
#
# Run from repo root:
#   Rscript tests/monte_carlo_se.R
# =============================================================================

suppressPackageStartupMessages({
  library(Rcpp)
})

stopifnot(file.exists("src/het_obj_fixed_sigma_rcpp.cpp"),
          file.exists("src/het_obj_fixed_sigma_jacobian_rcpp.cpp"))

sourceCpp("src/het_obj_fixed_sigma_rcpp.cpp")
sourceCpp("src/het_obj_fixed_sigma_jacobian_rcpp.cpp")

# =============================================================================
# HELPERS
# =============================================================================

# Assemble dense J (residual Jacobian) from the sparse triplet representation
# the Rcpp function returns
assemble_jacobian <- function(jac_obj, n_rows, n_cols) {
  J <- matrix(0, n_rows, n_cols)
  for (k in seq_along(jac_obj$jac_row)) {
    i <- jac_obj$jac_row[k] + 1L   # +1: triplets are 0-based
    j <- jac_obj$jac_col[k] + 1L
    J[i, j] <- jac_obj$jac_val[k]
  }
  J
}

# Compute the three SE candidates given residuals, Jacobian, weights, and
# (for penalized) the shrinkage lambda + theta_hat.
#
# All three formulas operate on the same J, w, r, just combine them differently.
compute_ses <- function(residuals, J, weights, theta_hat, lambda) {
  K  <- ncol(J)
  df <- length(residuals) - K
  if (df <= 0L) return(list(unp_gn = NULL, sandwich = NULL, pen_gn = NULL))

  # Weighted residual variance (denominator of the GN form)
  sigma2_hat <- sum(weights * residuals^2) / df

  # A = J'WJ — common matrix for GN and sandwich
  W <- diag(weights, K + length(residuals) - K)  # only need w for J'WJ; use vector
  WJ <- J * weights
  A <- crossprod(J, WJ)  # J' diag(w) J — symmetric K x K

  # Unpenalized Gauss-Newton
  Ai <- tryCatch(solve(A), error = function(e) NULL)
  if (is.null(Ai)) return(list(unp_gn = NULL, sandwich = NULL, pen_gn = NULL))
  V_unp_gn <- sigma2_hat * Ai
  se_unp_gn <- sqrt(pmax(0, diag(V_unp_gn)))

  # Sandwich: V = A^{-1} B A^{-1}, B = sum w_i^2 r_i^2 J_i J_i'
  w2r2 <- weights^2 * residuals^2
  WJ_sandwich <- J * w2r2
  B <- crossprod(J, WJ_sandwich)
  V_sandwich <- Ai %*% B %*% Ai
  se_sandwich <- sqrt(pmax(0, diag(V_sandwich)))

  # Penalized Gauss-Newton: V = sigma_hat^2 * (J'WJ + 2 lambda diag(1/theta^2))^{-1}
  # Penalty applies only to the gamma_j components (indices 2..K, since theta[1]
  # = gamma_k is the reference gamma which also gets shrunk in production).
  # We follow the production convention: penalize ALL gamma parameters.
  if (lambda > 0) {
    prior_H <- diag(2 * lambda / theta_hat^2)
    A_pen <- A + prior_H
    Ai_pen <- tryCatch(solve(A_pen), error = function(e) NULL)
    if (is.null(Ai_pen)) {
      se_pen_gn <- rep(NA_real_, K)
    } else {
      V_pen_gn <- sigma2_hat * Ai_pen
      se_pen_gn <- sqrt(pmax(0, diag(V_pen_gn)))
    }
  } else {
    # No shrinkage: penalized GN reduces to unpenalized GN
    se_pen_gn <- se_unp_gn
  }

  list(unp_gn = se_unp_gn, sandwich = se_sandwich, pen_gn = se_pen_gn,
       sigma2_hat = sigma2_hat, df = df)
}

# =============================================================================
# FIXED SETUP (same across regimes — only noise / shrinkage vary)
# =============================================================================

set.seed(100)

# Cell dimensions
J        <- 10L     # importer (regions) count
N_exp    <- 60L     # exporter rows
N_REPS   <- 200L
sigma_true   <- 2.5
gamma_k_true <- 0.4
gamma_j_true <- runif(J, 0.15, 0.7)
theta_true   <- c(gamma_k_true, gamma_j_true)
K            <- length(theta_true)   # = J + 1

# Design matrices (small, fixed across replications — Monte Carlo only varies noise)
imp_X     <- matrix(rnorm(J * 5, 0, 0.5), J, 5)
exp_X     <- matrix(rnorm(N_exp * 9, 0, 0.5), N_exp, 9)
exp_jmap  <- as.integer(sample(2:(J + 2), N_exp, replace = TRUE))
exp_sig_V <- runif(N_exp, 1.5, 4)
exp_gam_V <- runif(N_exp, 0.1, 1)
wt_imp_const <- rep(1, J)
wt_exp_const <- rep(1, N_exp)

# At theta_true with imp_Y = exp_Y = 0, residuals are -pred (the "true" predicted
# moments). We use these as the "clean" signal and add noise to them.
jac_true <- het_residuals_and_jacobian_fixed_sigma_rcpp(
  d = theta_true, sigma = sigma_true,
  imp_Y = rep(0, J), imp_X = imp_X,
  exp_Y = rep(0, N_exp), exp_X = exp_X,
  exp_jmap = exp_jmap, exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
  wt_imp = wt_imp_const, wt_exp = wt_exp_const
)
pred_imp_true <- -jac_true$residuals[1:J]
pred_exp_true <- -jac_true$residuals[(J + 1):(J + N_exp)]
df_resid      <- (J + N_exp) - K

# Number of free parameters in the shrinkage prior (used only for log msg)
cat("MC setup: J =", J, "  N_exp =", N_exp,
    "  K =", K, "  N_REPS =", N_REPS, "\n")
cat("True theta: gamma_k =", round(gamma_k_true, 3),
    ", gamma_j range = [", round(min(gamma_j_true), 3), ",",
    round(max(gamma_j_true), 3), "]\n")
cat("True sigma =", sigma_true, "\n\n")

# =============================================================================
# REGIME DRIVER
# =============================================================================

run_mc_regime <- function(label, hetero, shrinkage_lambda, noise_sd = 0.1) {
  cat(strrep("=", 70), "\n", sep = "")
  cat("REGIME: ", label, "  (hetero = ", hetero,
      ", lambda = ", shrinkage_lambda,
      ", noise_sd = ", noise_sd, ")\n", sep = "")
  cat(strrep("=", 70), "\n", sep = "")

  # Per-row noise multiplier
  noise_imp_mult <- if (hetero) runif(J, 0.5, 2.0) else rep(1.0, J)
  noise_exp_mult <- if (hetero) runif(N_exp, 0.5, 2.0) else rep(1.0, N_exp)

  # Storage for one replication's results
  theta_reps    <- matrix(NA_real_, nrow = N_REPS, ncol = K)
  se_unp_gn     <- matrix(NA_real_, nrow = N_REPS, ncol = K)
  se_sandwich   <- matrix(NA_real_, nrow = N_REPS, ncol = K)
  se_pen_gn     <- matrix(NA_real_, nrow = N_REPS, ncol = K)
  conv_codes    <- integer(N_REPS)

  # Prior for shrinkage (set to median of true gamma_j -- approximates what
  # the production pipeline uses, a regional median fed as ln_gamma_prior)
  ln_gamma_prior <- log(median(gamma_j_true))

  set.seed(2026)
  pb <- txtProgressBar(min = 0, max = N_REPS, style = 3)

  for (r in seq_len(N_REPS)) {
    # 1. Generate noisy moments at theta_true
    eps_imp <- rnorm(J,     mean = 0, sd = noise_sd * noise_imp_mult)
    eps_exp <- rnorm(N_exp, mean = 0, sd = noise_sd * noise_exp_mult)
    imp_Y_r <- pred_imp_true + eps_imp
    exp_Y_r <- pred_exp_true + eps_exp

    # 2. Re-estimate via the production NLS objective. Use theta_true as
    #    starting values to ensure convergence to the closest local optimum
    #    (this MC is about SE calibration, not optimizer robustness).
    fit <- tryCatch(
      optim(
        par = theta_true,
        fn = het_obj_fixed_sigma_rcpp,
        sigma = sigma_true,
        imp_Y = imp_Y_r, imp_X = imp_X,
        exp_Y = exp_Y_r, exp_X = exp_X,
        exp_jmap = exp_jmap,
        exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
        wt_imp = wt_imp_const, wt_exp = wt_exp_const,
        ln_gamma_prior = ln_gamma_prior,
        shrinkage_lambda = shrinkage_lambda,
        method = "L-BFGS-B",
        lower = rep(1e-4, K),
        upper = rep(50, K),
        control = list(maxit = 500)
      ),
      error = function(e) NULL
    )
    if (is.null(fit) || fit$convergence != 0L) {
      conv_codes[r] <- if (is.null(fit)) -1L else fit$convergence
      setTxtProgressBar(pb, r)
      next
    }
    conv_codes[r] <- 0L
    theta_hat <- fit$par
    theta_reps[r, ] <- theta_hat

    # 3. At theta_hat, compute residuals + Jacobian + SE candidates
    jac <- het_residuals_and_jacobian_fixed_sigma_rcpp(
      d = theta_hat, sigma = sigma_true,
      imp_Y = imp_Y_r, imp_X = imp_X,
      exp_Y = exp_Y_r, exp_X = exp_X,
      exp_jmap = exp_jmap,
      exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
      wt_imp = wt_imp_const, wt_exp = wt_exp_const
    )
    if (!is.null(jac$status) && jac$status == "invalid_input") {
      setTxtProgressBar(pb, r)
      next
    }

    J_dense <- assemble_jacobian(jac, n_rows = J + N_exp, n_cols = K)
    ses <- compute_ses(jac$residuals, J_dense, jac$weights,
                       theta_hat, shrinkage_lambda)
    if (!is.null(ses$unp_gn)) {
      se_unp_gn[r, ]   <- ses$unp_gn
      se_sandwich[r, ] <- ses$sandwich
      se_pen_gn[r, ]   <- ses$pen_gn
    }

    setTxtProgressBar(pb, r)
  }
  close(pb)

  # ---- Summary -------------------------------------------------------------
  n_ok <- sum(conv_codes == 0L)
  cat("\nConvergence: ", n_ok, "/", N_REPS,
      sprintf(" (%.1f%%)\n", 100 * n_ok / N_REPS), sep = "")

  if (n_ok < 10L) {
    cat("WARNING: too few successful replications to compute calibration ratios.\n")
    return(NULL)
  }

  # Empirical SD across replications -- the "true" SE we want each formula to match
  emp_sd <- apply(theta_reps, 2, sd, na.rm = TRUE)

  # Median of each formula's SE estimate
  med_unp_gn   <- apply(se_unp_gn,   2, median, na.rm = TRUE)
  med_sandwich <- apply(se_sandwich, 2, median, na.rm = TRUE)
  med_pen_gn   <- apply(se_pen_gn,   2, median, na.rm = TRUE)

  # Ratio: SE_formula / empirical_SD. 1.0 = perfectly calibrated.
  ratio_unp_gn   <- med_unp_gn   / emp_sd
  ratio_sandwich <- med_sandwich / emp_sd
  ratio_pen_gn   <- med_pen_gn   / emp_sd

  # Median-of-ratios across parameters as the headline calibration metric
  summary_df <- data.frame(
    regime    = label,
    formula   = c("unp_gn", "sandwich", "pen_gn"),
    n_params  = K,
    med_ratio = c(median(ratio_unp_gn, na.rm = TRUE),
                  median(ratio_sandwich, na.rm = TRUE),
                  median(ratio_pen_gn, na.rm = TRUE)),
    mad_ratio = c(mad(ratio_unp_gn, na.rm = TRUE),
                  mad(ratio_sandwich, na.rm = TRUE),
                  mad(ratio_pen_gn, na.rm = TRUE)),
    pct_err   = NA_real_   # filled in next
  )
  summary_df$pct_err <- 100 * (summary_df$med_ratio - 1)
  cat("\n")
  print(summary_df, row.names = FALSE, digits = 3)

  # Per-parameter detail (useful for tail diagnostics)
  per_param_df <- data.frame(
    regime = label,
    param  = c("gamma_k", paste0("gamma_", seq_len(J))),
    emp_sd = emp_sd,
    ratio_unp_gn = ratio_unp_gn,
    ratio_sandwich = ratio_sandwich,
    ratio_pen_gn = ratio_pen_gn
  )

  invisible(list(summary = summary_df, per_param = per_param_df,
                 n_ok = n_ok, n_reps = N_REPS))
}

# =============================================================================
# RUN ALL FOUR REGIMES
# =============================================================================

results <- list(
  homo_no_shrink   = run_mc_regime("homo,   lambda=0",   hetero = FALSE,
                                   shrinkage_lambda = 0),
  hetero_no_shrink = run_mc_regime("hetero, lambda=0",   hetero = TRUE,
                                   shrinkage_lambda = 0),
  homo_shrink      = run_mc_regime("homo,   lambda=0.1", hetero = FALSE,
                                   shrinkage_lambda = 0.1),
  hetero_shrink    = run_mc_regime("hetero, lambda=0.1", hetero = TRUE,
                                   shrinkage_lambda = 0.1)
)

# =============================================================================
# CONSOLIDATED OUTPUT
# =============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("CONSOLIDATED CALIBRATION SUMMARY\n")
cat(strrep("=", 70), "\n\n", sep = "")

all_summary <- do.call(rbind, lapply(results, function(r) r$summary))
print(all_summary, row.names = FALSE, digits = 3)

# Save artifacts to docs/methodology so they're paper-citable
out_dir <- "docs/methodology"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
today <- format(Sys.Date(), "%Y%m%d")

summary_csv <- file.path(out_dir, "se_calibration_mc_summary.csv")
write.csv(all_summary, summary_csv, row.names = FALSE)
cat("\nSummary written:", summary_csv, "\n")

per_param <- do.call(rbind, lapply(results, function(r) r$per_param))
per_param_csv <- file.path(out_dir,
                            paste0("se_calibration_mc_per_param_", today, ".csv"))
write.csv(per_param, per_param_csv, row.names = FALSE)
cat("Per-parameter detail:", per_param_csv, "\n")

cat("\nDone.\n")
