#' R/lambda_calibration.R
#'
#' Lambda (shrinkage) calibration diagnostic and sweep for the fixed-sigma
#' Stage 2 passes.
#' Extracted from feen94_het_baci.R (lines 1571-1743) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   lambda_calibration_diagnostic(results, lambda, ...)   — calibration diagnostic for a given lambda
#'   print_lambda_diagnostic(diag)                         — pretty-print the diagnostic
#'   lambda_calibration_sweep(cfg_base, prepared_dt, ...)  — sweep lambda over a grid
#'
#' Depends on: estimate_parallel.R

# ===========================================================================
#  LAMBDA CALIBRATION DIAGNOSTIC
#
#  Computes the four criteria from the README for choosing shrinkage
#  lambda empirically:
#    1. Within-pair gamma MAD — should approach Soderbery's 0.125
#    2. Cross-cell variance decomposition R-squared — should approach 0.72
#    3. Share of gamma estimates on the plateau — should be near 0
#    4. Distinctness of Tier 1 vs Tier 3 distributions (KS-style gap)
#
#  Designed to be called on the output of estimate_all_fixed_sigma()
#  for a single lambda value. Typical use:
#
#    for (lam in c(0.01, 0.05, 0.1, 0.2, 0.5)) {
#      cfg_test$shrinkage_lambda <- lam
#      res <- estimate_all_fixed_sigma(cfg_test, prepared_dt = dt_test)
#      diag <- lambda_calibration_diagnostic(res, lambda = lam)
#      print(diag)
#    }
#
#  Targets listed in the return value are the Soderbery benchmarks.
#  Interpretation:
#    - Very low lambda (0.01): weak regularization, high plateau share
#    - Very high lambda (0.5): within-pair MAD collapses (overshrinkage)
#    - Sweet spot: plateau share ~0, within-pair MAD near 0.125,
#      Tier 1 / Tier 3 distributions clearly distinct
# ===========================================================================

#' Compute lambda calibration diagnostic for a single fixed-sigma run.
#'
#' @param results Output of estimate_all_fixed_sigma().
#' @param lambda Scalar lambda value used for the run (for labeling).
#' @param plateau_gamma_cutoff gamma value above which estimates are
#'   considered on the plateau. Default 20 (gamma/(1+gamma) > 0.95).
#' @return data.table with one row of diagnostics. Columns:
#'   lambda, n_estimates, n_pairs, within_pair_mad,
#'   r_squared, plateau_share, tier1_gamma_median, tier3_gamma_median,
#'   tier_distinctness
lambda_calibration_diagnostic <- function(results, lambda = NA_real_,
                                           plateau_gamma_cutoff = 20) {
  dt <- results[!is.na(gamma) & gamma > 0]
  if (nrow(dt) == 0L) return(NULL)

  # --- 1. Within-pair gamma MAD ---
  pair_mad <- dt[, .(
    n_exp = .N,
    mad_g = if (.N >= 2L) mad(gamma, constant = 1) else NA_real_
  ), by = .(importer, good)]
  pair_mad <- pair_mad[n_exp >= 2L]
  within_pair_mad <- median(pair_mad$mad_g, na.rm = TRUE)
  n_pairs <- nrow(pair_mad)

  # --- 2. Cross-cell variance decomposition R² ---
  vd <- tryCatch(variance_decomposition(dt), error = function(e) NULL)
  r_sq <- if (!is.null(vd)) vd$r_squared else NA_real_

  # --- 3. Plateau share ---
  plateau_share <- mean(dt$gamma > plateau_gamma_cutoff, na.rm = TRUE)

  # --- 4. Tier distinctness ---
  tier1_med <- NA_real_; tier3_med <- NA_real_; distinctness <- NA_real_
  if ("tier" %in% names(dt)) {
    t1 <- dt[tier == 1L, gamma]
    t3 <- dt[tier == 3L, gamma]
    if (length(t1) > 10L && length(t3) > 10L) {
      tier1_med <- median(t1)
      tier3_med <- median(t3)
      # "Distinctness" = absolute log-median gap. Larger = more distinct.
      # When shrinkage is too aggressive, Tier 1 distributions collapse
      # toward the Tier 3 prior value and this approaches 0.
      distinctness <- abs(log(tier1_med) - log(tier3_med))
    }
  }

  data.table(
    lambda              = lambda,
    n_estimates         = nrow(dt),
    n_pairs             = n_pairs,
    within_pair_mad     = within_pair_mad,
    mad_target          = 0.125,
    r_squared           = r_sq,
    r_squared_target    = 0.72,
    plateau_share       = plateau_share,
    tier1_gamma_median  = tier1_med,
    tier3_gamma_median  = tier3_med,
    tier_distinctness   = distinctness
  )
}


#' Print a lambda calibration diagnostic in a human-readable format.
#'
#' @param diag data.table from lambda_calibration_diagnostic().
print_lambda_diagnostic <- function(diag) {
  if (is.null(diag) || nrow(diag) == 0L) {
    cat("  (no diagnostic data)\n")
    return(invisible())
  }
  cat(sprintf("  Lambda = %g\n", diag$lambda[1]))
  cat(sprintf("    Estimates:             %s (%s pairs)\n",
              format(diag$n_estimates[1], big.mark = ","),
              format(diag$n_pairs[1], big.mark = ",")))
  cat(sprintf("    Within-pair gamma MAD: %.3f  (target: %.3f)\n",
              diag$within_pair_mad[1], diag$mad_target[1]))
  cat(sprintf("    R-squared (imp x good FE): %.3f  (target: %.3f)\n",
              diag$r_squared[1], diag$r_squared_target[1]))
  cat(sprintf("    Plateau share (g>20):  %.4f  (target: ~0)\n",
              diag$plateau_share[1]))
  if (!is.na(diag$tier_distinctness[1])) {
    cat(sprintf("    Tier distinctness:     %.3f (log gap |log T1 - log T3|)\n",
                diag$tier_distinctness[1]))
    cat(sprintf("    Tier 1 gamma median:   %.3f\n",
                diag$tier1_gamma_median[1]))
    cat(sprintf("    Tier 3 gamma median:   %.3f\n",
                diag$tier3_gamma_median[1]))
  }
  invisible()
}


#' Run a lambda sweep and return combined diagnostics.
#'
#' Intended as a one-shot driver for calibrating shrinkage lambda on a
#' subset of products. Takes a prepared data.table, runs Stage 2 at each
#' lambda, and returns a single combined diagnostic table.
#'
#' @param cfg_base Base config list (sigma_lookup, shrinkage_priors, etc.
#'   all set). shrinkage_lambda is overridden per run.
#' @param prepared_dt Prepared data.table (as from prepare_data()$dt).
#' @param lambda_grid Numeric vector of lambdas to sweep.
#' @param ncores Number of cores to use.
#' @return data.table of diagnostics, one row per lambda.
lambda_calibration_sweep <- function(cfg_base, prepared_dt,
                                      lambda_grid = c(0.01, 0.05, 0.1, 0.2, 0.5),
                                      ncores = NULL) {
  diags <- list()
  for (lam in lambda_grid) {
    cat(sprintf("\n=== Lambda sweep: lambda = %g ===\n", lam))
    cfg_lam <- cfg_base
    cfg_lam$shrinkage_lambda <- lam
    res <- estimate_all_fixed_sigma(cfg_lam, ncores = ncores,
                                     prepared_dt = prepared_dt)
    diag <- lambda_calibration_diagnostic(res, lambda = lam)
    print_lambda_diagnostic(diag)
    diags[[length(diags) + 1L]] <- diag
  }
  rbindlist(diags)
}


# ===========================================================================
#  ESTIMATION SUMMARY
#
#  Builds a comprehensive summary from estimation results, modeled on
#  the diagnostics reported in Soderbery (2018):
#    - Table 2-style per-importer distributional statistics
#    - Variance decomposition of gamma (importer×product FE R²)
#    - Within importer-product heterogeneity statistics
#    - Trade value coverage
#    - Performance and convergence diagnostics
#    - Config provenance
#
#  Output: both a machine-readable RDS list and a formatted text report.
# ===========================================================================


#' Build a per-importer summary table in the style of Soderbery Table 2.
#'
#' For each importer, reports: observation count, mean/median/MAD of
#' sigma and gamma. The "World" row gives pooled statistics.
#'
#' @param results data.table of estimation results.
#' @return data.table with one row per importer plus a "World" row.
