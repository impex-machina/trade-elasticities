# ============================================================================
# test-bw-lag-raw.R  (patch 0091, 2026-10-10)
#
# Two default-off experiment flags from the 2026-10-10 fresh-eyes review of
# the Broda-Weinstein fn-14 weights:
#   --bw-lag raw        : the lag x_{t-1} is the cusval_lag column prepare_data()
#                         attaches from the PRE-differencing panel. Under
#                         "calendar" the lag is looked up on the differenced
#                         table, which has no row for a panel's first year, so
#                         the first differenced observation of every run took
#                         bw_weight()'s NA -> 1 fallback (~1 beside 10-3,000)
#                         although x_{t-1} is in the data.
#   --exporter-weight bw_sum : the cross-variety weight fn. 14 implies (the sum
#                         of an exporter's row weights); under "trade_value"
#                         the T^{3/2} factor cancels inside the within-exporter
#                         weighted mean and never reaches the objective.
# Locks: the prepared column's semantics (previous calendar year or NA); zero
# fallback rows under raw vs one per run under calendar on the fixture; the
# legacy and calendar outputs are bit-identical with and without the column
# (so every shipped release is unchanged by its presence); raw moves the
# estimates; bw_sum = normalized sum of bw_w, T^{3/2} cancels under
# trade_value; CLI / config / validation plumbing and the unchanged defaults.
# ============================================================================

.bl_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.bl_run <- function(cfg, dt) {
  # a run that ends with "No estimates." returns before the checkpoint cleanup;
  # clear any stale checkpoint so the resume guard cannot trip the next run
  unlink(list.files(".", pattern = "_fs_checkpoint\\.rds$", full.names = TRUE))
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

test_that("prepare_data() attaches cusval_lag = the previous calendar year's value, NA across a gap", {
  .bl_setup()
  cfg <- make_synthetic_cfg()
  raw <- data.table(year = c(2015L, 2016L, 2017L, 2015L, 2016L, 2019L, 2020L), good = "8501", importer = "840",
                    exporter = c("156", "156", "156", "410", "410", "410", "410"),
                    cusval = c(100, 110, 120, 200, 190, 170, 180), quantity = c(10, 11, 12, 20, 19, 18, 17))
  sink_file <- tempfile(); sink(sink_file); on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  dt <- prepare_data(cfg, raw_cache = raw)$dt
  sink()
  expect_true("cusval_lag" %in% names(dt))
  cont <- dt[exporter == "156"][order(t)]
  expect_equal(cont$t, c(2L, 3L)); expect_equal(cont$cusval_lag, c(100, 110))   # the first differenced row carries x_1
  gap <- dt[exporter == "410"][order(t)]
  expect_equal(gap$t, c(2L, 6L)); expect_equal(gap$cusval_lag, c(200, 170))      # t = 6 (2020) lags 2019, not 2016
  expect_true(all(is.finite(dt$cusval_lag)))                                      # every retained differenced row has one
})

test_that("under raw no row takes the NA -> 1 fallback; under calendar one per run does; T^{3/2} cancels", {
  .bl_setup()
  dt <- make_synthetic_baci(seed = 42L)
  d <- dt[importer == "840" & good == "8501"]
  cal <- copy(d)[, cusval_lag := calendar_lag(d, value = "cusval", t = "t", by = "exporter")]
  expect_equal(cal[, sum(is.na(cusval_lag)), by = exporter]$V1, rep(1L, uniqueN(d$exporter)))
  expect_equal(d[, sum(is.na(cusval_lag)), by = exporter]$V1, rep(0L, uniqueN(d$exporter)))
  cal[, bw_w := bw_weight(cusval, cusval_lag, period_count)]
  first <- cal[, .(w_first = bw_w[which.min(t)], w_med = median(bw_w[t != min(t)])), by = exporter]
  expect_true(all(first$w_first == 1)); expect_true(all(first$w_med > 5))
  # T^{3/2} is inert inside the within-exporter weighted mean once every row has a lag
  d1 <- copy(d)[, bw_w := bw_weight(cusval, cusval_lag, period_count)]
  d2 <- copy(d)[, bw_w := bw_weight(cusval, cusval_lag, period_count * 10L)]
  m1 <- d1[, weighted.mean(lp_dif, bw_w), by = exporter]; m2 <- d2[, weighted.mean(lp_dif, bw_w), by = exporter]
  expect_equal(m1$V1, m2$V1, tolerance = 1e-12)
})

test_that("legacy and calendar are bit-identical with and without the prepared column; raw moves the estimates", {
  .bl_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  dt_nocol <- copy(dt)[, cusval_lag := NULL]
  cfg <- make_synthetic_cfg()
  for (mode in c("legacy", "calendar")) {
    c_m <- cfg; c_m$bw_lag <- mode
    a <- finalize_saved_output(.bl_run(c_m, dt)); b <- finalize_saved_output(.bl_run(c_m, dt_nocol))
    expect_identical(a, b, info = mode)                     # volatile run_meta (timing) stripped, as saveRDS does
  }
  c_raw <- cfg; c_raw$bw_lag <- "raw"
  r <- .bl_run(c_raw, dt)
  c_cal <- cfg; c_cal$bw_lag <- "calendar"
  k <- .bl_run(c_cal, dt)
  expect_equal(nrow(r), nrow(k))
  expect_false(isTRUE(all.equal(r$gamma, k$gamma)))
  expect_error(.bl_run(c_raw, dt_nocol), "cusval_lag")
})

test_that("compute_exporter_weights(): bw_sum is the normalized sum of the row weights; the other modes are unchanged", {
  .bl_setup()
  dt <- make_synthetic_baci(seed = 42L)
  d <- dt[importer == "840" & good == "8501"][, bw_w := bw_weight(cusval, cusval_lag, period_count)]
  ord <- sort(unique(d$exporter))
  cfg <- make_synthetic_cfg(); cfg$exporter_weight <- "bw_sum"
  w <- compute_exporter_weights(d, ord, cfg)
  s <- d[, .(wt = sum(bw_w)), by = exporter][match(ord, exporter)]$wt
  expect_equal(w, s * length(ord) / sum(s))
  expect_equal(sum(w), length(ord))
  expect_error(compute_exporter_weights(copy(d)[, bw_w := NULL], ord, cfg), "bw_w")
  cfg$exporter_weight <- "uniform"; expect_equal(compute_exporter_weights(d, ord, cfg), rep(1, length(ord)))
  cfg$exporter_weight <- "trade_value"; expect_equal(sum(compute_exporter_weights(d, ord, cfg)), length(ord))
})

test_that("CLI, config and validation accept the two flags and keep the defaults", {
  .bl_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_bl_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  cfg <- build_config(parse_cli(base))
  expect_identical(cfg$bw_lag, "calendar"); expect_identical(cfg$exporter_weight, "trade_value")
  expect_silent(validate_config(cfg))
  e <- build_config(parse_cli(c(base, "--bw-lag", "raw", "--exporter-weight", "bw_sum")))
  expect_identical(e$bw_lag, "raw"); expect_identical(e$exporter_weight, "bw_sum")
  expect_silent(validate_config(e))
  expect_error(parse_cli(c(base, "--bw-lag", "panel")), "bw-lag")
  expect_error(parse_cli(c(base, "--exporter-weight", "trade")), "exporter-weight")
  bad <- cfg; bad$exporter_weight <- "trade"; expect_error(validate_config(bad), "exporter_weight")
  dt <- make_synthetic_baci(seed = 42L); c0 <- make_synthetic_cfg()
  c_r <- c0; c_r$bw_lag <- "raw"; c_b <- c0; c_b$exporter_weight <- "bw_sum"
  expect_false(identical(.fs_cfg_stamp(c0, dt), .fs_cfg_stamp(c_r, dt)))   # the checkpoint stamp sees both flags
  expect_false(identical(.fs_cfg_stamp(c0, dt), .fs_cfg_stamp(c_b, dt)))
})
