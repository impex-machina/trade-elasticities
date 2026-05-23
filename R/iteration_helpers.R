#' R/iteration_helpers.R
#'
#' Iteration and starting-value helpers: seed two-step passes from prior
#' results and initialise country-level fits from regional estimates.
#' Extracted from feen94_het_baci.R (lines 1521-1608) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   update_defaults_from_results(cfg, results, pass)       — update starting values from a prior pass
#'   init_from_regional(cfg, regional_results, custom_map)  — seed country fits from regional results
#'
#' Depends on: none

# ===========================================================================
#  ITERATION AND STARTING VALUE HELPERS
# ===========================================================================

#' Update defaults from completed results for iterative refinement.
#'
#' NOTE: currently unused by run_estimation.R (three-stage pipeline uses
#' explicit Stage 1 -> Stage 2a -> Stage 2b handoff with its own default
#' updates). Retained for interactive use / iterative robustness checks.
update_defaults_from_results <- function(cfg, results, pass = 1L) {
  ms <- median(results$sigma, na.rm = TRUE)
  mg <- median(results$gamma, na.rm = TRUE)
  cfg$sigma_start <- ms; cfg$gamma_start <- mg
  cfg$sigma_V_default <- ms; cfg$gamma_V_default <- mg
  cat(sprintf("  Defaults updated from pass %d: sigma=%.3f, gamma=%.3f\n", pass, ms, mg))
  cfg
}


#' Initialize country-level starting values from regional estimates.
#'
#' Creates a lookup table mapping (region, product) -> (sigma, gamma)
#' from regional estimation results. When set on config, the estimator
#' uses per-cell starting values instead of global defaults, which
#' speeds convergence and reduces failures.
#'
#' @param cfg Config list (for country-level estimation).
#' @param regional_results data.table from a regional estimation run.
#' @param custom_map Optional region map. NULL uses build_region_map().
#' @return Config list with regional_starts and regional_starts_rmap set.
init_from_regional <- function(cfg, regional_results, custom_map = NULL) {

  # Build per-(region, product) medians from regional results
  starts <- regional_results[!is.na(sigma) & sigma > 1 & gamma > 0,
                              .(sigma = median(sigma),
                                gamma = median(gamma)),
                              by = .(region = importer, good)]

  cfg$regional_starts <- starts
  cfg$regional_starts_rmap <- if (!is.null(custom_map)) custom_map else build_region_map()

  cat(sprintf("  Regional starting values loaded: %d (region x product) cells\n",
              nrow(starts)))
  cat(sprintf("  Coverage: sigma range [%.2f, %.2f], gamma range [%.2f, %.2f]\n",
              min(starts$sigma), max(starts$sigma),
              min(starts$gamma), max(starts$gamma)))
  cfg
}


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
