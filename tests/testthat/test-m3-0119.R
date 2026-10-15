# ============================================================================
# test-m3-0119.R  (patch 0119: the year window reaches Stage 1; M3 sizing)
#
# Locks:
#   1. year_window() keeps [minyear, maxyear] (maxyear NULL / NA = open), on
#      data.tables and data frames; scripts/run_estimation.R applies it to
#      Stage 1's input before run_stage1_liml() (through patch 0118 --maxyear
#      never reached Stage 1 on a cached run);
#   2. analysis/window_drift_census.R separates drift from noise: halves that
#      differ by noise only give a variance ratio near 1, halves that also
#      carry a true change give a ratio above 2, and the verdicts follow;
#   3. analysis/sigma_window_census.R: clean-set yields, the |z| shares at the
#      published and inflated standard errors, and the full-panel cells lost.
# ============================================================================

.m3_root <- function() dirname(locate_source_dir())
.m3_lib <- function() {
  src <- locate_source_dir()
  for (f in c("utils_general.R", "iteration_helpers.R")) source(file.path(src, f), local = FALSE)
  invisible(TRUE)
}

test_that("year_window() keeps the window; the runner applies it to Stage 1's input", {
  .m3_lib()
  dt <- data.table::data.table(t = 1995:2024, v = 1)
  expect_identical(range(year_window(dt, 2010, NULL, col = "t")$t), c(2010L, 2024L))
  expect_identical(range(year_window(dt, 1995, 2009, col = "t")$t), c(1995L, 2009L))
  expect_identical(nrow(year_window(dt, 1995, NA, col = "t")), 30L)
  df <- data.frame(year = 1995:2000, v = 1:6)
  expect_identical(year_window(df, 1997, 1998)$v, 3:4)
  expect_error(year_window(dt, 1995, col = "year"), "no column")
  run <- readLines(file.path(.m3_root(), "scripts", "run_estimation.R"), warn = FALSE)
  i_win <- grep("baci_for_liml <- year_window(baci_for_liml, config_country$minyear, config_country$maxyear, col = \"t\")", run, fixed = TRUE)
  i_call <- grep("^    run_stage1_liml\\($", run)
  expect_length(i_win, 1L); expect_length(i_call, 1L)
  expect_true(i_win < i_call)
})

test_that("window_drift_census(): noise-only halves read as such; a true change reads as drift", {
  .m3_lib()
  env <- new.env(); sys.source(file.path(.m3_root(), "analysis", "window_drift_census.R"), envir = env)
  set.seed(19)
  cells <- data.table::CJ(importer = as.character(1:60), good = sprintf("%04d", 1:5))
  cells[, truth := rnorm(.N, -0.3, 0.6)]
  mk <- function(shift = 0, sd_noise = 0.15) {
    x <- cells[, .(importer, good, cell_q = truth + shift + rnorm(.N, 0, sd_noise))]
    x <- x[rep(seq_len(.N), each = 4)]
    x[, `:=`(exporter = rep(letters[1:4], .N / 4), tier = 1L, convergence = 0L, trim_reason = NA_character_)]
    x[, gamma := exp(cell_q + rnorm(.N, 0, 0.05))]
    x[, opt_tariff := exp(cell_q)]
    x[, cell_q := NULL]
    x
  }
  drift <- rnorm(nrow(cells), 0, 0.5)
  no <- env$window_drift_census(mk(), mk(), mk(), mk())
  expect_lt(no$quantities$cell_tariff$ratio_robust, 1.5)
  expect_identical(no$quantities$cell_tariff$verdict, "full panel as good")
  yes <- env$window_drift_census(mk(), mk(), mk(), mk(shift = drift))
  expect_gt(yes$quantities$cell_tariff$ratio_robust, 2)
  expect_identical(yes$quantities$cell_tariff$verdict, "recent window better")
  expect_identical(yes$quantities$cell_tariff$period$n, nrow(cells))
  expect_true(all(c("exporter", "rows", "median_change") %in% names(yes$top_exporters)))
  expect_equal(yes$coverage$late$estimated_rows, 4L * nrow(cells))
})

test_that("sigma_window_census(): yields, |z| shares and lost cells", {
  .m3_lib()
  env <- new.env(); sys.source(file.path(.m3_root(), "analysis", "sigma_window_census.R"), envir = env)
  mk <- function(sig, se) data.table::data.table(importer = as.character(1:10), good = "0101", status = "ok", sigma = sig,
                                                 sigma_se = se, sigma_capped = FALSE)
  base <- c(2, 3, 4, 2.5, 6, 3.5, 2.2, 5, 1.05, 3)
  early <- mk(base, rep(0.2, 10))
  late <- mk(base + c(0, 0, 0, 0, 0, 0, 0, 2, 0, 0.9), rep(0.2, 10))   # cell 8 +2 (z ~ 7), cell 10 +0.9 (z ~ 3.2, ~2.1 at 1.5x)
  late$status[2] <- "all_inversions_failed"
  full <- mk(base, rep(0.1, 10))
  res <- env$sigma_window_census(early, late, full)
  expect_identical(res$yield$late$converged, 9L)                      # cell 2 lost; cell 9 (1.05, SE 0.2) is pole-dropped later
  expect_identical(res$yield$early$clean, 9L)                         # cell 9 pole-dropped
  expect_identical(res$early_vs_late$cells, 8L)                       # clean in both
  expect_equal(res$early_vs_late$share_z$se_x1, 2 / 8)
  expect_equal(res$early_vs_late$share_z$se_x1.5, 2 / 8)
  expect_identical(res$full_clean_lost_late, 1L)                      # cell 2
})
