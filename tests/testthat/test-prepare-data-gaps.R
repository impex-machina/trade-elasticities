# ============================================================================
# test-prepare-data-gaps.R
#
# Regression test for the consecutive-year guard in prepare_data()'s
# first-differencing. shift() pairs adjacent rows in time order; without a
# guard, a panel with a year gap (e.g. 2016 -> 2019) would be first-differenced
# across the gap as if it were a one-period change, contaminating the d-log
# price/share moments. The guard nulls diffs whose year step != 1 so they are
# dropped alongside each panel's leading NA.
#
# Drives the real prepare_data(cfg, raw_cache=) via a tiny synthetic panel,
# reusing make_synthetic_cfg() (minyear=2015, use_regions=FALSE, uv filter off)
# and locate_source_dir() from the test helpers.
# ============================================================================

test_that("first-differencing drops non-consecutive-year steps", {
  skip_if_not_installed("data.table")
  library(data.table)
  src <- locate_source_dir()
  source(file.path(src, "validate_config.R"), local = TRUE)
  source(file.path(src, "quality_log.R"),     local = TRUE)
  source(file.path(src, "prepare_data.R"),    local = TRUE)

  cfg <- make_synthetic_cfg()  # minyear=2015, use_regions=FALSE, uv filter off

  # Two panels under (importer 840, good 8501); t = year - minyear + 1:
  #   exporter 156: 2015,2016,2017  (continuous)            -> t 1,2,3
  #   exporter 410: 2015,2016,2019,2020 (gap 2016->2019)    -> t 1,2,5,6
  raw <- data.table(
    year     = c(2015L, 2016L, 2017L,  2015L, 2016L, 2019L, 2020L),
    good     = "8501",
    importer = "840",
    exporter = c("156", "156", "156",  "410", "410", "410", "410"),
    cusval   = c(100, 110, 120,  200, 190, 170, 180),
    quantity = c(10, 11, 12,  20, 19, 18, 17)
  )

  out <- prepare_data(cfg, raw_cache = raw)
  dt  <- out$dt

  gap_panel  <- dt[importer == "840" & exporter == "410" & good == "8501"]
  cont_panel <- dt[importer == "840" & exporter == "156" & good == "8501"]

  # The 2019 (t==5) observation, whose only predecessor is 2016 (a 3-year
  # gap), must NOT survive — pre-guard it would have been differenced across
  # the gap and kept.
  expect_false(5L %in% gap_panel$t)
  # The valid consecutive-year diffs survive: 2016 (t2 vs 2015) and 2020
  # (t6 vs 2019).
  expect_setequal(gap_panel$t, c(2L, 6L))
  # The continuous panel is untouched: 2016, 2017 (t2, t3).
  expect_setequal(cont_panel$t, c(2L, 3L))
})

test_that("a fully continuous panel keeps every non-leading period", {
  skip_if_not_installed("data.table")
  library(data.table)
  src <- locate_source_dir()
  source(file.path(src, "validate_config.R"), local = TRUE)
  source(file.path(src, "quality_log.R"),     local = TRUE)
  source(file.path(src, "prepare_data.R"),    local = TRUE)

  cfg <- make_synthetic_cfg()

  # 5 continuous years, 2 exporters each -> 4 first-differences per panel,
  # nothing dropped by the guard.
  raw <- data.table(
    year     = rep(2015:2019, each = 2L),
    good     = "8501",
    importer = "840",
    exporter = rep(c("156", "410"), times = 5L),
    cusval   = 100 + seq_len(10L),
    quantity = 10 + seq_len(10L)
  )

  out <- prepare_data(cfg, raw_cache = raw)
  dt  <- out$dt

  expect_setequal(dt[exporter == "156"]$t, c(2L, 3L, 4L, 5L))
  expect_setequal(dt[exporter == "410"]$t, c(2L, 3L, 4L, 5L))
})
