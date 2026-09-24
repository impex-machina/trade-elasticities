# ============================================================================
# test-tier3-early-return.R  (patch 0066, 2026-09-24 fresh-eyes audit)
#
# estimate_importer_product_fixed_sigma() has an early return for cells in
# which EVERY non-reference exporter is Tier 3: all rows get the good-level
# prior, no optimizer runs. Before this patch the branch returned only the
# eight core columns, so after rbindlist(fill = TRUE) those rows carried
# gamma_se_status = NA and sigma_robust = NA (counted as "unflagged" rather
# than Tier-3 in results/stage2b_summary.json), and the reference row --
# tier 0, prior gamma, convergence -1 -- passed the `tier < 3` filter in the
# opt_tariff block as a directly estimated exporter, so opt_tariff for such
# a cell was the prior itself. Locks:
#   1. every early-return row is labelled tier3_prior with NA SE columns and
#      the full Stage-2b schema (no fill-NA leakage);
#   2. the reference row keeps tier 0 and convergence -1, and
#      is_estimated_row() excludes it;
#   3. opt_tariff is NA for such a cell (no directly estimated exporter)
#      while opt_tariff_all equals the prior;
#   4. is_estimated_row() keeps tier 0/1/2 rows of fitted cells, including
#      non-converged ones, and drops Tier-3 rows.
# ============================================================================

.t3_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

test_that("is_estimated_row() keeps fitted tier 0/1/2 rows and drops imputed ones", {
  .t3_setup()
  expect_identical(is_estimated_row(c(0L, 1L, 2L, 3L, 0L, NA), c(0L, 0L, 52L, -1L, -1L, 0L)),
                   c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE))
})

test_that("an all-Tier-3 cell returns the full schema, tier3_prior labels and an NA opt_tariff", {
  .t3_setup()
  dt  <- make_synthetic_baci(seed = 42L)
  cfg <- make_synthetic_cfg()
  # Make every non-reference exporter Tier 3: period thresholds no panel meets.
  cfg$tier1_min_periods <- 999L
  cfg$tier2_min_periods <- 999L
  result <- NULL
  suppressMessages(suppressWarnings(capture.output(
    result <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt),
    type = "output")))
  expect_s3_class(result, "data.table")
  expect_gt(nrow(result), 0L)
  # 1. schema + labels
  for (nm in c("gamma_se", "gamma_se_total", "sigma_robust", "sigma_se", "dgamma_dsigma",
               "gamma_se_status", "gamma_exposure", "gamma_shrink_wt"))
    expect_true(nm %in% names(result), info = nm)
  expect_true(all(result$gamma_se_status == "tier3_prior"))
  expect_true(all(is.na(result$gamma_se)))
  expect_true(all(is.na(result$sigma_robust)))
  expect_true(all(result$convergence == -1L))
  # gamma is the good-level prior on every row
  prior <- cfg$shrinkage_priors[match(result$good, good), exp(ln_gamma_prior)]
  expect_equal(result$gamma, prior)
  # 2. the reference row keeps tier 0 and is not an estimate
  ref_rows <- result[exporter == ref_exporter]
  expect_gt(nrow(ref_rows), 0L)
  expect_true(all(ref_rows$tier == 0L))
  expect_false(any(is_estimated_row(result$tier, result$convergence)))
  # 3. tariffs: NA where nothing was estimated; _all equals the prior
  expect_true(all(is.na(result$opt_tariff)))
  expect_equal(result$opt_tariff_all, prior)
})

test_that("a fitted cell is unchanged by the predicate (bit-preserving on the e2e fixture)", {
  .t3_setup()
  dt  <- make_synthetic_baci(seed = 42L)
  cfg <- make_synthetic_cfg()
  result <- NULL
  suppressMessages(suppressWarnings(capture.output(
    result <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt),
    type = "output")))
  est <- is_estimated_row(result$tier, result$convergence)
  # identical to the pre-patch rule on a table with no early-return cells
  expect_identical(est, !is.na(result$tier) & result$tier < 3L)
  expect_true(any(est))
})
