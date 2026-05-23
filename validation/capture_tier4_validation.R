# =============================================================================
# capture_tier4_validation.R
#
# Runs Tier 4 of validate_liml.R (HLIML vs pre-HLIML Feenstra GMM baseline)
# and captures three artifacts to docs/methodology/:
#   - tier4_console.txt           full console capture
#   - tier4_comp.csv              cell-level comparison
#   - tier4_hliml_vs_gmm.md       (drafted by hand after reviewing numbers)
#
# Run from the repo root:
#   source("R/liml_estimator.R")
#   # source any additional file that defines estimate_elasticities() if needed
#   source("validation/validate_liml.R")
#   source("validation/capture_tier4_validation.R")
#
# Tier 4 needs two inputs that are NOT published in this repo (they are
# EC2-class intermediates): the BACI raw cache and the pre-HLIML Feenstra
# GMM Stage 2 archive. Point the two constants below at your local copies,
# or set the environment variables TRADE_ELAST_BACI_CACHE / TRADE_ELAST_GMM
# before sourcing. This is a re-run path only; the published Tier 4 outputs
# (data/derived/validation/tier4_comp.csv) reproduce the figures without it.
# =============================================================================

# ---- Paths (EDIT THESE, or set the env vars) --------------------------------
BACI_PATH <- Sys.getenv("TRADE_ELAST_BACI_CACHE",
  "<path-to>/baci_hs92_v202601_elast_country_hs4_raw_cache.rds")
GMM_PATH  <- Sys.getenv("TRADE_ELAST_GMM",
  "<path-to>/archive_feenstra_gmm/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")

# ---- Run parameters ---------------------------------------------------------
N_CELLS       <- 200
MIN_EXPORTERS <- 3
MIN_PERIODS   <- 5

# ---- Output paths -----------------------------------------------------------
OUT_DIR     <- "docs/methodology"
CONSOLE_OUT <- file.path(OUT_DIR, "tier4_console.txt")
COMP_OUT    <- file.path(OUT_DIR, "tier4_comp.csv")

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# ---- Sanity checks ----------------------------------------------------------
stopifnot(
  "estimate_cell_liml not found — source R/liml_estimator.R first"   = exists("estimate_cell_liml"),
  "validate_tier4 not found — source validation/validate_liml.R first"    = exists("validate_tier4"),
  "estimate_elasticities not found — see Risk 1 in session plan"     = exists("estimate_elasticities"),
  "BACI raw cache not at BACI_PATH"                                  = file.exists(BACI_PATH),
  "Feenstra GMM archive not at GMM_PATH"                             = file.exists(GMM_PATH)
)

# ---- Run with console capture -----------------------------------------------
con <- file(CONSOLE_OUT, open = "wt")
sink(con, split = TRUE)
sink(con, type = "message")

cat("================================================================\n")
cat("Tier 4: HLIML (refactored) vs Feenstra GMM (legacy) sigma\n")
cat("Run date:        ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n", sep = "")
cat("BACI path:       ", BACI_PATH, "\n", sep = "")
cat("GMM path:        ", GMM_PATH,  "\n", sep = "")
cat("n_cells:         ", N_CELLS, "\n", sep = "")
cat("min_exporters:   ", MIN_EXPORTERS, "\n", sep = "")
cat("min_periods:     ", MIN_PERIODS, "\n", sep = "")
cat("================================================================\n\n")

t0 <- Sys.time()

result <- validate_tier4(
  baci_path             = BACI_PATH,
  current_pipeline_path = GMM_PATH,
  n_cells               = N_CELLS,
  min_exporters         = MIN_EXPORTERS,
  min_periods           = MIN_PERIODS
)

elapsed <- difftime(Sys.time(), t0, units = "mins")
cat(sprintf("\nTier 4 wall time: %.1f min\n", as.numeric(elapsed)))

# ---- Persist cell-level comparison ------------------------------------------
# Harness returns $comp (verified against validate_liml.R line 835).
if (is.null(result$comp)) {
  cat("\nWARNING: result$comp is NULL — check harness return shape.\n")
} else {
  write.csv(result$comp, COMP_OUT, row.names = FALSE)
  cat(sprintf("\nWrote cell-level comparison: %s  (%d rows)\n",
              COMP_OUT, nrow(result$comp)))
}

# ---- Headline numbers -------------------------------------------------------
if (!is.null(result$comp) && nrow(result$comp) > 0) {
  cmp <- result$comp
  
  # Defensive column lookup — surface schema if expectations are wrong
  cat("\nComparison columns: ", paste(names(cmp), collapse = ", "), "\n", sep = "")
  
  if (all(c("sigma_new", "sigma_stage1") %in% names(cmp))) {
    valid <- is.finite(cmp$sigma_new) & is.finite(cmp$sigma_stage1) &
      cmp$sigma_stage1 > 0
    cmp_v <- cmp[valid, , drop = FALSE]
    
    ratio_vec <- cmp_v$sigma_new / cmp_v$sigma_stage1
    median_ratio <- median(ratio_vec, na.rm = TRUE)
    mean_ratio   <- mean(ratio_vec,   na.rm = TRUE)
    
    spearman <- suppressWarnings(
      cor(cmp_v$sigma_new, cmp_v$sigma_stage1,
          method = "spearman", use = "complete.obs")
    )
    pearson <- suppressWarnings(
      cor(cmp_v$sigma_new, cmp_v$sigma_stage1,
          method = "pearson", use = "complete.obs")
    )
    
    qprobs <- c(0.05, 0.25, 0.50, 0.75, 0.95)
    qtab <- rbind(
      HLIML = quantile(cmp_v$sigma_new,    qprobs, na.rm = TRUE),
      GMM   = quantile(cmp_v$sigma_stage1, qprobs, na.rm = TRUE)
    )
    
    # Verdict per harness thresholds (validate_liml.R)
    verdict <- if (median_ratio < 0.85) {
      "PASS (ratio < 0.85, expected ~35% LIML bias correction confirmed)"
    } else if (median_ratio <= 1.0) {
      "MARGINAL (0.85 <= ratio <= 1.0, smaller correction than Soderbery 2015)"
    } else {
      "INVESTIGATE (ratio > 1.0, LIML produces HIGHER sigma — unexpected)"
    }
    
    cat("\n=== TIER 4 HEADLINE ===\n")
    cat(sprintf("Sample n (valid):         %d of %d\n",
                nrow(cmp_v), nrow(cmp)))
    cat(sprintf("Median ratio (HLIML/GMM): %.3f\n", median_ratio))
    cat(sprintf("Mean ratio   (HLIML/GMM): %.3f\n", mean_ratio))
    cat(sprintf("Spearman rho:             %.3f\n", spearman))
    cat(sprintf("Pearson r:                %.3f\n", pearson))
    cat("\nMarginal quantiles:\n")
    print(round(qtab, 3))
    cat("\nVerdict: ", verdict, "\n", sep = "")
    
    # Convergence-stratified ratio (descriptive, for the writeup).
    # GMM archive carries a 'convergence' column with codes {-1, 0, 1}:
    # 0 dominates (~73%), -1 is ~26% with near-identical sigma median to 0,
    # 1 is <1% with visibly lower sigma. Surface the breakdown so we can
    # decide post-hoc whether to filter.
    if ("convergence" %in% names(cmp_v)) {
      cat("\nRatio by GMM convergence code:\n")
      print(cmp_v[, .(n = .N,
                      median_ratio = median(sigma_new / sigma_stage1,
                                            na.rm = TRUE)),
                  by = convergence])
    } else {
      cat("\nNote: 'convergence' column not present in comparison frame ",
          "— harness may have dropped it during dedup.\n", sep = "")
    }
  } else {
    cat("\nWARNING: expected columns sigma_new / sigma_stage1 not present.\n")
    cat("Skipping headline computation — inspect tier4_comp.csv manually.\n")
  }
}

# ---- Echo any verdict the harness emits -------------------------------------
if (!is.null(result$verdict)) {
  cat("\nHarness verdict: ", result$verdict, "\n", sep = "")
}

cat("\n================================================================\n")
cat("Tier 4 capture complete.\n")
cat("Console:   ", CONSOLE_OUT, "\n", sep = "")
cat("Comp CSV:  ", COMP_OUT, "\n", sep = "")
cat("Next:      hand-draft docs/methodology/tier4_hliml_vs_gmm_20260521.md\n")
cat("           then push all three to s3://.../refactored_run_20260519/validation/\n")
cat("================================================================\n")

sink(type = "message")
sink()
close(con)

invisible(result)