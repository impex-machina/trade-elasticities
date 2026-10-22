# ============================================================================
# test-eb-0133.R  (patch 0133: the empirical-Bayes tau^2 for the scaled ridge)
#
#   analysis/ridge_tau2_eb.R: the method-of-moments tau^2 with its 2.5% trim,
#   the cell reliability and the adoption conditions; the exporter-product
#   effects carry no reading; validation/known_truth_stage2.R: R6's rule and
#   the default arm set.
# ============================================================================

.e33_root <- function() dirname(locate_source_dir())
.e33_env <- function() {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "analysis/ridge_tau2_eb.R")) sys.source(file.path(.e33_root(), f), envir = e)
  e
}
.e33_half <- function(theta, s = 0) data.table::data.table(importer = rep(1:10, each = length(theta) / 10), exporter = seq_along(theta), good = "0101",
                                                         gamma = exp(theta), gamma_shrink_wt = s, tier = 0L, convergence = 0L, trim_reason = NA_character_)

test_that("tau2_eb: the method of moments, the 2.5% trim, the data-share correction", {
  e <- .e33_env()
  pri <- data.table::data.table(good = "0101", ln_prior = 0)
  set.seed(1); th <- c(rnorm(39, 0, 0.6), 10)                       # one runaway row
  r <- e$eb_tau2(.e33_half(th), .e33_half(th), pri)
  expect_identical(r$rows, 40L); expect_identical(r$rows_after_trim, 39L)
  expect_equal(r$tau2_eb_untrimmed, mean(th^2))
  expect_equal(r$tau2_eb, mean(th[-40]^2))
  r2 <- e$eb_tau2(.e33_half(th * 0.5, s = 0.5), .e33_half(th * 0.5, s = 0.5), pri)   # deviations halved, data share 0.5
  expect_equal(r2$tau2_eb, mean(th[-40]^2))
})

test_that("cell reliability, the adoption conditions, and no reading on exporter effects", {
  e <- .e33_env()
  pri <- data.table::data.table(good = "0101", ln_prior = 0)
  set.seed(2); a <- rnorm(40, 0, 0.5)
  co <- .e33_half(a); ce <- .e33_half(a + rnorm(40, 0, 0.05)); so <- .e33_half(a * 0.1 + rnorm(40, 0, 0.05)); se <- .e33_half(a * 0.1 + rnorm(40, 0, 0.05))
  rc <- e$eb_cell_reliability(co, ce, pri); expect_identical(rc$cells, 10L)
  ok <- e$eb_check(co, ce, co, ce, pri, tau2 = 0.3, kt_verdict = "EB validated")
  expect_identical(ok$reading, "adopt-candidate")
  expect_identical(e$eb_check(co, ce, co, ce, pri, tau2 = 5, kt_verdict = "EB validated")$reading, "keep the shipped ridge")
  expect_identical(e$eb_check(co, ce, co, ce, pri, tau2 = 0.3, kt_verdict = "EB not validated")$reading, "keep the shipped ridge")
  big <- .e33_half(a + 1)                                             # product medians move by 1 in logs
  expect_false(e$eb_check(big, big, co, ce, pri, tau2 = 0.3, kt_verdict = "EB validated")$conditions$level_shift)
  ex <- e$eb_exporter_effects(co, ce, min_imp = 1L)
  expect_null(ex$reading)
})

test_that("R6's rule and the harness's default arms", {
  suppressPackageStartupMessages(library(data.table))
  h <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "R/sigma_eb.R", "validation/synthetic_baci.R", "validation/known_truth_stage2.R"))
    sys.source(file.path(.e33_root(), f), envir = h)
  expect_identical(h$kt_r6_verdict(c(0.3, 0.4, 0.6, 0.2, 0.9, 1.5))$verdict, "EB validated")     # 5 of 6 in range
  expect_identical(h$kt_r6_verdict(c(0.3, 0.4, 1.6, 0.2, 0.9, 1.5))$verdict, "EB not validated")
  expect_true(all(c("half_a_t1", "half_b_t1") %in% names(h$KT_ARMS)))
  expect_identical(h$KT_ARMS$half_a_t1$args[6], "block-a")
  src <- paste(readLines(file.path(.e33_root(), "validation", "known_truth_stage2.R"), warn = FALSE), collapse = "\n")
  expect_match(src, 'grep("^(ridge|half)_", names(KT_ARMS), value = TRUE)', fixed = TRUE)
})

test_that("block halves share no level year; odd / even share every interior one", {
  e <- new.env(); sys.source(file.path(.e33_root(), "R", "utils_general.R"), envir = e)
  t <- 1996:2024                                             # differences of the 1995-2024 levels
  lv <- function(k) sort(unique(c(t[k] - 1L, t[k])))        # the level years a half uses
  a <- e$t_parity_keep(t, "block-a", y0 = 1995L); b <- e$t_parity_keep(t, "block-b", y0 = 1995L)
  expect_length(intersect(lv(a), lv(b)), 0L)
  expect_identical(sum(a) + sum(b), length(t) - sum(!a & !b))
  expect_true(all(t[a][1:3] == 1996:1998)); expect_true(all(t[b][1:3] == 2000:2002))   # 1999 and 2003 straddle blocks
  o <- e$t_parity_keep(t, "odd"); v <- e$t_parity_keep(t, "even")
  expect_gt(length(intersect(lv(o), lv(v))), 25L)
  expect_identical(e$t_parity_keep(t, "all"), rep(TRUE, length(t)))
  expect_error(e$t_parity_keep(t, "x"), "unknown mode")
})
