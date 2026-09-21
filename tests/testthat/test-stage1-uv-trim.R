# ============================================================================
# test-stage1-uv-trim.R  (patch 0057)
#
# Stage 2 drops differenced observations with |d ln p| >= uv_outlier_threshold
# before estimating gamma; Stage 1 estimated sigma on the untrimmed cache.
# prepare_cell_moments(uv_outlier_threshold = ) applies the same rule at the
# same point (after the calendar-lag differencing, before the reference join),
# on the differenced observation only. Locks:
#   1. a planted jump removes exactly its own differenced observation; the
#      following year's difference survives (row-drop would have lost it);
#      the reference exporter's trimmed observation removes that year for
#      everyone (as the join does); NA threshold is bit-identical to v0.7.x.
#   2. data.table and base-R branches agree.
#   3. wrapper argument reaches the estimator and is stamped on rows;
#      --stage1-uv-trim parses (off by default), validates.
# ============================================================================

.uv_source <- function(env) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = env)
  source(file.path(root, "R", "utils_general.R"), local = env)
  source(file.path(root, "R", "liml_estimator.R"), local = env)
}

.uv_panel <- function() {
  # 4 exporters x 10 years, smooth series; exporter 2 gets a x20 unit-value
  # jump in year 6 (d ln p = ln 20 = 3.0 > 2), which reverts in year 7
  set.seed(57L)
  J <- 4L; T <- 10L
  d <- data.frame(exporter = rep(seq_len(J), each = T), t = rep(1995:2004, J))
  d$quantity <- exp(rnorm(nrow(d), 3, 0.2))
  d$value <- d$quantity * exp(rnorm(nrow(d), 1, 0.1))
  d$value[d$exporter == 2L & d$t == 2000L] <- d$value[d$exporter == 2L & d$t == 2000L] * 20
  d
}

test_that("the trim removes the jump's own differenced observation and keeps the next one", {
  .uv_source(environment())
  d <- .uv_panel()
  m0 <- prepare_cell_moments(d)                              # no trim
  m1 <- prepare_cell_moments(d, uv_outlier_threshold = 2.0)
  mNA <- prepare_cell_moments(d, uv_outlier_threshold = NA_real_)
  expect_identical(m0, mNA)                                  # NA = off, bit-identical
  # the reference exporter is chosen by longest panel then largest value:
  # the x20 jump makes exporter 2 the reference. Its trimmed year-2000
  # difference then removes t = 2000 for everyone (the join carries NA).
  expect_identical(m1$ref_exporter, 2L)
  years0 <- sort(unique(m0$moments$t)); years1 <- sort(unique(m1$moments$t))
  # with no min_year the moments keep raw t; year 2000 present untrimmed, absent trimmed
  expect_true(2000L %in% years0); expect_false(2000L %in% years1)
  # 2001's difference (the reversal, d ln p = -3.0 for exporter 2) is ALSO >= 2 in
  # absolute value and is trimmed; 2002 onward survive for every exporter
  expect_false(2001L %in% years1); expect_true(all(c(1996:1999, 2002:2004) %in% years1))
  # row counts: each trimmed year removes one row per non-reference exporter
  expect_equal(nrow(m0$moments) - nrow(m1$moments), 2L * 3L)
})

test_that("data.table and base-R branches agree with and without the trim", {
  .uv_source(environment())
  d <- .uv_panel()
  a <- prepare_cell_moments(d, uv_outlier_threshold = 2.0)
  # force the base-R branch by shadowing requireNamespace inside the function's env
  f <- prepare_cell_moments
  environment(f) <- new.env(parent = environment(prepare_cell_moments))
  assign("requireNamespace", function(...) FALSE, envir = environment(f))
  b <- f(d, uv_outlier_threshold = 2.0)
  expect_identical(a$ref_exporter, b$ref_exporter)
  ma <- as.data.frame(a$moments); ma <- ma[order(ma$exporter, ma$t), c("y", "x1", "x2")]; rownames(ma) <- NULL
  mb <- as.data.frame(b$moments); mb <- mb[order(mb$exporter, mb$t), c("y", "x1", "x2")]; rownames(mb) <- NULL
  expect_equal(ma, mb, tolerance = 1e-12)
})

test_that("wrapper argument reaches the estimator and the CLI flag parses", {
  suppressPackageStartupMessages(library(data.table))
  .uv_source(environment())
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  d <- .uv_panel(); raw <- data.table::as.data.table(d); raw[, `:=`(importer = 1L, good = "0202")]
  tmp <- tempfile(fileext = ".rds")
  o0 <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L, min_periods = 3L, verbose = FALSE)
  o1 <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L, min_periods = 3L, verbose = FALSE,
                        uv_outlier_threshold = 2.0)
  expect_true(is.na(o0$stage1_uv_trim[1])); expect_equal(o1$stage1_uv_trim[1], 2.0)
  expect_equal(o0$n_obs[1] - o1$n_obs[1], 6L)                # the same six observations
  unlink(tmp)
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  source(file.path(root, "R", "validate_config.R"), local = TRUE)
  dd <- tempfile(); dir.create(dd)
  p0 <- parse_cli(c("--data", dd)); expect_true(is.na(p0$stage1_uv_trim))
  expect_true(is.na(build_config(p0)$stage1_uv_trim))
  p1 <- parse_cli(c("--data", dd, "--stage1-uv-trim", "2.0")); expect_equal(p1$stage1_uv_trim, 2.0)
  expect_error(parse_cli(c("--data", dd, "--stage1-uv-trim", "-1")), "stage1-uv-trim")
  cfg <- build_config(p1); cfg$stage1_uv_trim <- 0
  expect_error(validate_config(cfg), "stage1_uv_trim")
  unlink(dd, recursive = TRUE)
})
