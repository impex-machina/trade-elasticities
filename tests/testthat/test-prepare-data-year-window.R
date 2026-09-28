# ============================================================================
# test-prepare-data-year-window.R  (patch 0072)
# prepare_data() applied --minyear/--maxyear only on the fresh-load path; a
# run from the raw cache skipped the window entirely (the branch that opens
# at the fresh load closes after the HS4 aggregation), so year-window
# experiments on cached runs reproduced the full panel. Locks: the window
# applies on the cached path; the full window is bit-preserving.
# ============================================================================
.yw_setup <- function() {
  src_dir <- locate_source_dir(); assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE); invisible(TRUE)
}
.yw_cache <- function() {
  set.seed(4); g <- data.table::CJ(year = 1995:2004, importer = c("1", "2", "3"), exporter = c("101", "102", "103", "104"), good = c("0101", "0202"))
  g[, cusval := exp(rnorm(.N, 10, 0.3))]; g[, quantity := exp(rnorm(.N, 5, 0.3))]; g
}
test_that("a year window on the CLI applies to a cached run, and the full window is bit-preserving", {
  .yw_setup(); cfg <- make_synthetic_cfg(); cfg$minyear <- 1995L; cfg$maxyear <- NULL
  rc <- .yw_cache()
  full <- NULL; capture.output(full <- prepare_data(cfg, raw_cache = data.table::copy(rc))$dt)
  cfg_w <- cfg; cfg_w$maxyear <- 1999L
  win <- NULL; capture.output(win <- prepare_data(cfg_w, raw_cache = data.table::copy(rc))$dt)
  expect_equal(max(full$year), 2004L); expect_equal(max(win$year), 1999L)
  expect_lt(nrow(win), nrow(full))
  cfg_b <- cfg; cfg_b$minyear <- 2000L
  late <- NULL; capture.output(late <- prepare_data(cfg_b, raw_cache = data.table::copy(rc))$dt)
  # the panel is first-differenced: a window's first year has no lag and drops out
  expect_equal(min(late$year), 2001L); expect_equal(min(late$t), 2L); expect_false(any(late$year < 2000L))
  full2 <- NULL; capture.output(full2 <- prepare_data(cfg, raw_cache = data.table::copy(rc))$dt)
  expect_identical(full, full2)
})
