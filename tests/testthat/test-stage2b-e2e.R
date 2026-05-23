# ============================================================================
# test-stage2b-e2e.R
#
# End-to-end test for Stage 2b (estimate_all_fixed_sigma).
#
# Purpose: guard against silent schema drops like the keep_cols bug
# (where SE columns attached by the inner cell function were dropped by
# a hardcoded whitelist in estimate_all_fixed_sigma right before return).
#
# The test:
#   1. Synthesizes a tiny BACI panel (2 goods x 3 importers x 5 exporters
#      x 9 first-differenced periods) matching the schema prepare_data()
#      produces, so estimate_all_fixed_sigma() can consume it directly
#      via the prepared_dt argument.
#   2. Runs Stage 2b single-threaded (ncores = 1L) with sigma_lookup and
#      shrinkage priors attached to cfg.
#   3. Asserts the output schema is exactly the 15 columns documented
#      in the README, including the three SE-related columns.
#   4. Asserts the SE columns are populated by the Rcpp Jacobian path
#      (at least one row with status == "ok" and a finite gamma_se).
#
# Expected runtime: ~5-30s on a Windows laptop. First run includes Rcpp
# compilation of the two .cpp files (~25s); subsequent runs are cached.
# ============================================================================

# The columns that estimate_all_fixed_sigma() promises to return.
# This is the contract — if it changes, both the consumers downstream
# (run_estimation.R, heterogeneity_full.R) and this test must update.
EXPECTED_COLS <- c(
  "importer", "exporter", "good",
  "sigma", "gamma",
  "gamma_se", "gamma_se_status", "gamma_exposure",
  "ref_exporter",
  "opt_tariff", "opt_tariff_all",
  "convergence", "obj_value", "tier", "avg_trade"
)


test_that("Stage 2b returns the documented schema and populates SE columns", {

  # ---- Setup ---------------------------------------------------------------
  # Step 3 refactor: feen94_het_baci.R is now a thin wrapper in this repo's
  # R/ directory. The .cpp files still live in the original source/ folder,
  # resolved via TRADE_ELAST_CPP (or TRADE_ELAST_SRC as fallback).
  src_dir <- locate_source_dir()       # contains feen94_het_baci.R wrapper
  cpp_dir <- locate_cpp_dir()          # contains the .cpp files
  assert_cpp_files_present(cpp_dir)

  # Save & restore cwd around the source() call as defensive cleanup. The
  # new wrapper doesn't depend on getwd() (it resolves paths via env vars
  # and its own __FILE__-style lookup), but the original library did, so
  # the dance is cheap insurance against re-introducing getwd-coupling.
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(src_dir)

  # Source the wrapper. Heavy on first run (~25s) due to Rcpp compilation.
  # Suppress verbose cat() output by routing to a temp sink.
  sink_file <- tempfile(fileext = ".log")
  sink(sink_file)
  on.exit({
    if (sink.number() > 0L) sink()
    if (file.exists(sink_file)) file.remove(sink_file)
  }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  sink()

  # Decision #2 from the test plan: if the Jacobian Rcpp file is required,
  # then so is its successful load. A missing .cpp file already failed in
  # assert_cpp_files_present(); a compilation failure (e.g. no Rtools)
  # would leave .het_jac_rcpp_loaded as FALSE. Fail loudly here.
  expect_true(
    exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded),
    info = paste0(
      "Jacobian Rcpp file failed to compile. The SE pipeline cannot run. ",
      "On Windows this usually means Rtools is missing or out of date. ",
      "Without Rcpp, gamma_se will be NA for all rows and the schema ",
      "test below would pass meaninglessly — so this test fails fast."
    )
  )
  expect_true(
    exists(".het_obj_fs_rcpp_loaded") && isTRUE(.het_obj_fs_rcpp_loaded),
    info = "Fixed-sigma objective Rcpp file failed to compile."
  )

  # ---- Run Stage 2b on synthetic data -------------------------------------
  synth_dt <- make_synthetic_baci(seed = 42L)
  cfg      <- make_synthetic_cfg()

  # Sanity: the fixture should yield enough rows per panel to support
  # first-differenced estimation. If this fails the DGP is broken,
  # not the pipeline.
  expect_gt(nrow(synth_dt), 100L)
  expect_true(all(synth_dt$period_count >= cfg$min_periods))

  # Run quietly. Pre-initialize result so a thrown error still leaves a
  # well-defined value for the assertions below (which would otherwise
  # error with "object 'result' not found" and mask the real failure).
  result <- NULL
  tryCatch(
    suppressMessages(suppressWarnings(
      capture.output(
        result <- estimate_all_fixed_sigma(
          cfg, ncores = 1L, prepared_dt = synth_dt
        ),
        type = "output"
      )
    )),
    error = function(e) {
      fail(paste0("estimate_all_fixed_sigma() errored: ",
                  conditionMessage(e)))
    }
  )

  # ---- Assertion 1: output is a non-empty data.table ---------------------
  expect_s3_class(result, "data.table")
  expect_gt(nrow(result), 0L)
  if (is.null(result) || nrow(result) == 0L) return(invisible())  # short-circuit

  # ---- Assertion 2: schema equality (catches the keep_cols bug) ----------
  expect_setequal(names(result), EXPECTED_COLS)

  # ---- Assertion 3: convergence sanity ------------------------------------
  # At least one cell should converge cleanly (convergence == 0L). The
  # synthetic DGP is engineered for this, but small samples + the
  # identification structure of Stage 2b make full coverage unrealistic.
  expect_gt(sum(result$convergence == 0L, na.rm = TRUE), 0L)
  expect_true(any(result$gamma > 0, na.rm = TRUE))

  # ---- Assertion 4: SE columns populated by the Rcpp path ----------------
  # This is the assertion the keep_cols bug would have failed. Pre-fix,
  # gamma_se / gamma_se_status / gamma_exposure were not in keep_cols
  # and would have been silently dropped, failing assertion 2. Post-fix,
  # we also check they contain real values for at least one converged row.
  ok_rows <- result[
    convergence == 0L &
    gamma_se_status == "ok" &
    is.finite(gamma_se)
  ]

  # If the assertion below fails, the diagnostic message gives us the
  # status table for free — expect_gt() doesn't take a custom failure
  # message, so we emit the context as a side-channel message that
  # testthat prints alongside the failure.
  if (nrow(ok_rows) == 0L) {
    message(
      "No rows have status='ok' with finite gamma_se. ",
      "Either the Rcpp Jacobian path isn't producing SEs, or the ",
      "synthetic fixture is too degenerate to identify gamma. ",
      "Status table: ",
      paste(capture.output(print(table(result$gamma_se_status,
                                       useNA = "ifany"))),
            collapse = " | ")
    )
  }
  expect_gt(nrow(ok_rows), 0L)

  # gamma_exposure should be a positive integer count for the ok rows
  # (number of residual rows contributing to each parameter's identification).
  expect_true(all(ok_rows$gamma_exposure > 0L))
  expect_true(is.integer(result$gamma_exposure))

  # ---- Diagnostic dump on test pass (helpful while iterating) ------------
  # Comment out once stable.
  message(sprintf(
    "[stage2b-e2e] %d rows, %d converged, %d with ok SE, gamma median = %.3f",
    nrow(result),
    sum(result$convergence == 0L, na.rm = TRUE),
    nrow(ok_rows),
    median(result$gamma, na.rm = TRUE)
  ))
})
