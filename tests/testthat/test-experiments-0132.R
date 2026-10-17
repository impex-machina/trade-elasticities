# ============================================================================
# test-experiments-0132.R  (patch 0132: two experiment flags, measured locally)
#
#   1. .ridge_cell_scale(): the noise variance of a time-averaged squared shock
#      and lambda = 1 / tau2; --stage2-ridge-scale cell needs tau2 > 0;
#   2. prepare_cell_moments(): "levels" keeps every release's choice, "stable"
#      takes a jump-free reference within two years of the longest series, and
#      the two agree when no reference candidate has a jump;
#   3. the CLI validates both flags; the defaults are every release's;
#   4. validation/known_truth_stage2.R reading R5, and
#      analysis/reference_rule_census.R's reading.
# ============================================================================

.x32_root <- function() dirname(locate_source_dir())

test_that("ridge cell scale: noise variance of a time-averaged squared shock, lambda = 1 / tau2", {
  e <- new.env(); sys.source(file.path(.x32_root(), "R", "estimate_cell_fixed_sigma.R"), envir = e)
  rs <- e$.ridge_cell_scale(wt = c(1, 3), imp_y = c(0.2, 0.4), n_periods = c(10, 20), tau2 = 0.25)
  ybar <- (0.2 + 3 * 0.4) / 4; tbar <- (10 + 3 * 20) / 4
  expect_equal(rs$s2, 2 * ybar^2 / tbar); expect_equal(rs$factor, 1 / (2 * ybar^2 / tbar)); expect_equal(rs$lambda, 4)
  expect_error(e$.ridge_cell_scale(1, 0.2, 10, NA_real_), "needs --stage2-ridge-tau2 > 0")
  expect_error(e$.ridge_cell_scale(1, 0.2, 10, 0), "needs --stage2-ridge-tau2 > 0")
  expect_identical(e$.ridge_cell_scale(0, 0.2, 10, 0.1)$factor, 1)     # nothing to scale by: unchanged
})

test_that("Stage-1 reference: levels as every release, stable avoids a jump within two years of the longest", {
  suppressPackageStartupMessages(library(data.table))
  for (f in c("R/utils_general.R", "R/liml_estimator.R")) source(file.path(.x32_root(), f), local = TRUE)
  set.seed(3)
  mk <- function(ex, years, jump_year = NA, v = 10) {
    p <- exp(cumsum(rnorm(length(years), 0, 0.1))); if (!is.na(jump_year)) p[years >= jump_year] <- p[years >= jump_year] * 20
    data.frame(exporter = ex, t = years, value = v * p * (1 + runif(length(years))), quantity = 1 + runif(length(years)))
  }
  # exporter 1: 12 years with a x20 unit-value jump; exporter 2: 11 years, no jump; exporter 3: 6 years
  cell <- rbind(mk(1L, 2001:2012, jump_year = 2006, v = 50), mk(2L, 2002:2012), mk(3L, 2005:2010))
  lv <- prepare_cell_moments(cell, exporter_col = "exporter", time_col = "t", value_col = "value", quantity_col = "quantity")
  st <- prepare_cell_moments(cell, exporter_col = "exporter", time_col = "t", value_col = "value", quantity_col = "quantity",
                             reference_rule = "stable")
  expect_identical(as.integer(lv$ref_exporter), 1L)
  expect_identical(as.integer(st$ref_exporter), 2L)
  cell2 <- rbind(mk(1L, 2001:2012), mk(2L, 2002:2012), mk(3L, 2005:2010))    # no jumps: the two rules agree
  expect_identical(prepare_cell_moments(cell2, reference_rule = "stable")$ref_exporter,
                   prepare_cell_moments(cell2)$ref_exporter)
  expect_error(prepare_cell_moments(cell2, reference_rule = "nope"))
})

test_that("CLI: both flags validated, defaults are every release's", {
  source(file.path(.x32_root(), "R", "parse_cli.R"), local = TRUE)
  cli <- readLines(file.path(.x32_root(), "R", "parse_cli.R"), warn = FALSE)
  expect_true(any(grepl('c("--stage2-ridge-scale"), type = "character", default = "none"', cli, fixed = TRUE)))
  expect_true(any(grepl('c("--stage1-reference-rule"), type = "character", default = "levels"', cli, fixed = TRUE)))
  base <- c("--data", tempdir())
  o <- parse_cli(base)
  expect_identical(c(o$stage1_reference_rule, o$stage2_ridge_scale), c("levels", "none"))
  expect_error(parse_cli(c(base, "--stage1-reference-rule", "x")), "--stage1-reference-rule must be", fixed = TRUE)
  expect_error(parse_cli(c(base, "--stage2-ridge-scale", "x")), "--stage2-ridge-scale must be", fixed = TRUE)
  expect_error(parse_cli(c(base, "--stage2-ridge-scale", "cell")), "needs --stage2-ridge-tau2 > 0", fixed = TRUE)
  ok <- parse_cli(c(base, "--stage2-ridge-scale", "cell", "--stage2-ridge-tau2", "0.1", "--stage1-reference-rule", "stable"))
  expect_identical(ok$stage2_ridge_tau2, 0.1)
  run <- readLines(file.path(.x32_root(), "scripts", "run_estimation.R"), warn = FALSE)
  expect_true(any(grepl('config_2a$ridge_scale <- "none"', run, fixed = TRUE)))
  # prepare_data()'s cell summary printed medians with %d, which stops a run whose median is x.5
  pd <- readLines(file.path(.x32_root(), "R", "prepare_data.R"), warn = FALSE)
  expect_false(any(grepl("median=%d", pd, fixed = TRUE)))
})

test_that("reading R5 and the reference-rule census reading", {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "R/sigma_eb.R", "validation/synthetic_baci.R", "validation/known_truth_stage2.R"))
    sys.source(file.path(.x32_root(), f), envir = e)
  sm <- function(wg, wr, bg) data.table::data.table(structure = "good_importer", arm_name = rep(c("shipped", "ridge_t01"), each = 2), scale = c(1, 3, 1, 3),
                                                    within_good_gamma_r = wg, within_r = wr, between_good_gamma_r = bg)
  expect_identical(e$kt_readings_r5(sm(c(0.16, 0.23, 0.45, 0.50), c(0.03, 0.07, 0.1, 0.1), c(0.82, 0.93, 0.85, 0.9)))$verdict, "calibrate on real data")
  expect_identical(e$kt_readings_r5(sm(c(0.16, 0.23, 0.45, 0.50), c(0.03, 0.07, 0.1, 0.1), c(0.82, 0.93, 0.70, 0.9)))$verdict, "closed")   # product signal lost
  expect_identical(e$kt_readings_r5(sm(c(0.16, 0.23, 0.30, 0.35), c(0.03, 0.07, 0.1, 0.1), c(0.82, 0.93, 0.85, 0.9)))$verdict, "closed")
  r <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "analysis/reference_rule_census.R")) sys.source(file.path(.x32_root(), f), envir = r)
  set.seed(4)
  n <- 60
  mk <- function(z) data.table::data.table(importer = as.character(seq_len(n)), good = rep(sprintf("%04d", 1:6), 10), status = "ok", convergence = 0L,
                                           sigma = 1 + exp(z), sigma_se = 0.1, sigma_capped = FALSE, adjust = 0L, gamma = exp(rnorm(n)),
                                           omega_floored = FALSE, omega_capped = FALSE)
  tz <- rnorm(n, 0.8, 0.5)
  le <- mk(tz + rnorm(n, 0, 0.6)); ll <- mk(tz + rnorm(n, 0, 0.6)); se <- mk(tz + rnorm(n, 0, 0.2)); sl <- mk(tz + rnorm(n, 0, 0.2))
  res <- r$reference_rule_census(le, ll, se, sl)
  expect_equal(res$per_rule$levels$cells, n)
  expect_lt(res$per_rule$stable$sigma_mad, res$per_rule$levels$sigma_mad)
  expect_true(res$reading %in% c("stable helps", "closed"))
})
