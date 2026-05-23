# ============================================================================
# test-cli-parsing.R
#
# Tests for parse_cli() and build_config(). These are pure-R, no Rcpp,
# no data — should run in well under a second.
#
# Together they catch the failure mode where someone runs the pipeline
# overnight only to discover in the morning that an arg was ignored,
# misspelled, or out of range. Validation runs before any data is read.
# ============================================================================


# Find R/ relative to the test file. testthat::test_path() returns the
# testthat/ directory; the repo root is two levels up.
.find_repo_R <- function() {
  start <- tryCatch(testthat::test_path(), error = function(e) getwd())
  dir <- normalizePath(start, mustWork = FALSE)
  for (i in seq_len(6L)) {
    candidate <- file.path(dir, "R", "parse_cli.R")
    if (file.exists(candidate)) return(file.path(dir, "R"))
    parent <- dirname(dir)
    if (parent == dir) break
    dir <- parent
  }
  stop("Could not find R/parse_cli.R relative to test directory.")
}

.repo_R <- .find_repo_R()
source(file.path(.repo_R, "parse_cli.R"))
source(file.path(.repo_R, "build_config.R"))


# Helper: a temp dir that looks like a valid --data target.
# We never actually call load_baci on it; only dir.exists matters
# during CLI validation.
.make_fake_data_dir <- function() {
  d <- file.path(tempdir(), paste0("fake_baci_",
                                    as.integer(Sys.time()), "_",
                                    sample.int(1e6, 1)))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}


# =============================================================================
# Required arguments
# =============================================================================

test_that("parse_cli requires --data", {
  expect_error(
    parse_cli(args = character(0)),
    regexp = "--data is required"
  )
})


test_that("parse_cli requires --data to be an existing directory", {
  expect_error(
    parse_cli(args = c("--data", "/this/does/not/exist")),
    regexp = "not a directory"
  )

  # File-not-dir also fails
  tmpfile <- tempfile()
  file.create(tmpfile)
  on.exit(unlink(tmpfile))
  expect_error(
    parse_cli(args = c("--data", tmpfile)),
    regexp = "not a directory"
  )
})


# =============================================================================
# Defaults
# =============================================================================

test_that("parse_cli applies sensible defaults with just --data", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))

  opts <- parse_cli(args = c("--data", data_dir))

  expect_equal(opts$data, data_dir)
  expect_equal(opts$out_dir, ".")
  expect_equal(opts$agg_level, "hs4")
  expect_equal(opts$minyear, 1995L)
  expect_true(is.na(opts$maxyear))
  expect_gte(opts$ncores, 1L)
  expect_equal(opts$shrinkage_lambda, 0.1)
  expect_equal(opts$stage, "all")
})


# =============================================================================
# Provided values flow through
# =============================================================================

test_that("parse_cli respects explicit values", {
  data_dir <- .make_fake_data_dir()
  out_dir  <- file.path(tempdir(),
                         paste0("out_", as.integer(Sys.time())))
  on.exit({
    unlink(data_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  opts <- parse_cli(args = c(
    "--data", data_dir,
    "--out-dir", out_dir,
    "--agg-level", "hs6",
    "--minyear", "2000",
    "--maxyear", "2020",
    "--ncores", "4",
    "--shrinkage-lambda", "0.05",
    "--stage", "2b"
  ))

  expect_equal(opts$data, data_dir)
  expect_equal(opts$out_dir, out_dir)
  expect_equal(opts$agg_level, "hs6")
  expect_equal(opts$minyear, 2000L)
  expect_equal(opts$maxyear, 2020L)
  expect_equal(opts$ncores, 4L)
  expect_equal(opts$shrinkage_lambda, 0.05)
  expect_equal(opts$stage, "2b")
})


test_that("parse_cli creates --out-dir if it does not exist", {
  data_dir <- .make_fake_data_dir()
  out_dir  <- file.path(tempdir(),
                         paste0("new_out_", as.integer(Sys.time())))
  on.exit({
    unlink(data_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })
  expect_false(dir.exists(out_dir))

  opts <- parse_cli(args = c("--data", data_dir, "--out-dir", out_dir))
  expect_true(dir.exists(out_dir))
  expect_equal(opts$out_dir, out_dir)
})


# =============================================================================
# Validation errors
# =============================================================================

test_that("parse_cli rejects invalid --agg-level", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  expect_error(
    parse_cli(args = c("--data", data_dir, "--agg-level", "hs8")),
    regexp = "--agg-level must be"
  )
})


test_that("parse_cli rejects invalid --stage", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  expect_error(
    parse_cli(args = c("--data", data_dir, "--stage", "3")),
    regexp = "--stage must be one of"
  )
})

test_that("parse_cli accepts --stage '1' and '2a'", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  
  opts1 <- parse_cli(args = c("--data", data_dir, "--stage", "1"))
  expect_equal(opts1$stage, "1")
  
  opts2a <- parse_cli(args = c("--data", data_dir, "--stage", "2a"))
  expect_equal(opts2a$stage, "2a")
})

test_that("parse_cli rejects maxyear < minyear", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  expect_error(
    parse_cli(args = c("--data", data_dir,
                       "--minyear", "2010",
                       "--maxyear", "2005")),
    regexp = "--maxyear .* must be >= --minyear"
  )
})


test_that("parse_cli rejects ncores < 1", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  expect_error(
    parse_cli(args = c("--data", data_dir, "--ncores", "0")),
    regexp = "--ncores must be >= 1"
  )
})


test_that("parse_cli rejects negative shrinkage_lambda", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  expect_error(
    parse_cli(args = c("--data", data_dir,
                       "--shrinkage-lambda", "-0.1")),
    regexp = "--shrinkage-lambda must be >= 0"
  )
})


test_that("parse_cli rejects implausible minyear", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))
  expect_error(
    parse_cli(args = c("--data", data_dir, "--minyear", "1500")),
    regexp = "--minyear must be"
  )
})


# =============================================================================
# build_config — values flow into the cfg list
# =============================================================================

test_that("build_config plumbs CLI values into config", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))

  opts <- parse_cli(args = c(
    "--data", data_dir,
    "--agg-level", "hs6",
    "--minyear", "2000",
    "--maxyear", "2020",
    "--shrinkage-lambda", "0.05"
  ))
  cfg <- build_config(opts)

  # CLI-driven values
  expect_equal(cfg$filepath, data_dir)
  expect_equal(cfg$agg_level, "hs6")
  expect_equal(cfg$minyear, 2000L)
  expect_equal(cfg$maxyear, 2020L)
  expect_equal(cfg$shrinkage_lambda, 0.05)

  # NA maxyear -> NULL in cfg (the library's contract)
  opts2 <- parse_cli(args = c("--data", data_dir))
  cfg2 <- build_config(opts2)
  expect_null(cfg2$maxyear)
})


test_that("build_config sets methodological constants", {
  data_dir <- .make_fake_data_dir()
  on.exit(unlink(data_dir, recursive = TRUE))

  opts <- parse_cli(args = c("--data", data_dir))
  cfg <- build_config(opts)

  # These are baked in — they should match the old runner's static block.
  expect_equal(cfg$value, "v")
  expect_equal(cfg$quan, "q")
  expect_equal(cfg$good, "k")
  expect_equal(cfg$importer, "j")
  expect_equal(cfg$exporter, "i")
  expect_equal(cfg$time, "t")

  expect_equal(cfg$min_exporters, 2L)
  expect_equal(cfg$min_destinations, 2L)
  expect_equal(cfg$min_periods, 3L)
  expect_equal(cfg$uv_outlier_threshold, 2.0)

  expect_equal(cfg$sigma_start, 2.88)
  expect_equal(cfg$gamma_start, 0.69)

  expect_equal(cfg$exporter_weight, "trade_value")
  expect_equal(cfg$weight_period_floor, 10L)

  expect_equal(cfg$tier1_min_periods, 3L)
  expect_equal(cfg$tier1_min_dests, 2L)
  expect_equal(cfg$tier2_min_periods, 3L)

  expect_equal(cfg$tail_trim_pct, 0.005)
})
