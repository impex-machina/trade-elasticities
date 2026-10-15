# ============================================================================
# test-known-truth-0122.R  (patch 0122, audit #8: known truth and sigma EB)
#
#   1. R/sigma_eb.R: Paule-Mandel tau^2 on known cases; the posterior lies
#      between the estimate and the prior mean; cells without data (failed,
#      edge) sit at the prior mean; a grouped prior falls back to the global
#      one for thin groups.
#   2. validation/known_truth_stage2.R: the arms' Stage-1 tables, the recovery
#      metrics on hand-built tables with known answers, the reading rules.
#   3. analysis/sigma_eb_period_census.R: scores and the reading on toy tables.
#   4. one tiny world through the harness's run machinery (shipped + sigma_eb
#      arms; skipped with TE_SKIP_E2E=1).
# ============================================================================

.kt_root <- function() dirname(locate_source_dir())
.kt_env <- function() {
  env <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "R/sigma_eb.R", "validation/synthetic_baci.R", "validation/known_truth_stage2.R"))
    sys.source(file.path(.kt_root(), f), envir = env)
  sys.source(file.path(.kt_root(), "analysis", "sigma_eb_period_census.R"), envir = env)
  env
}

test_that("sigma_eb_fit: Paule-Mandel tau^2 on known cases", {
  e <- .kt_env()
  z <- c(-1, -0.5, 0, 0.5, 1); s <- rep(0.1, 5)
  f <- e$sigma_eb_fit(z, s)
  expect_equal(f$mu, 0)
  expect_equal(f$tau2, var(z) - 0.01, tolerance = 1e-8)       # equal SEs: tau^2 = sample variance - s^2
  g <- e$sigma_eb_fit(c(0.01, -0.01, 0.02, -0.02), rep(1, 4))  # dispersion far below the noise
  expect_identical(g$tau2, 0)
  expect_identical(e$sigma_eb_fit(numeric(0), numeric(0))$n, 0L)
})

test_that("sigma_eb_shrink: posterior between estimate and prior, no-data cells at the prior", {
  e <- .kt_env()
  s1 <- data.table::data.table(importer = as.character(1:8), good = rep(c("0101", "0202"), each = 4),
                               sigma = c(2, 3, 4, 6, 1.05, 2.5, 50, 3), sigma_se = c(0.2, 0.3, 2, 0.5, 0.5, 0.25, 1, NA),
                               convergence = c(0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L), sigma_capped = c(rep(FALSE, 6), TRUE, FALSE))
  x <- e$sigma_eb_shrink(s1)
  mu <- attr(x, "eb_mu")
  expect_identical(x$eb_data, c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE))   # edge cell and NA-SE cell carry no data
  expect_true(all(x$eb_weight >= 0 & x$eb_weight <= 1))
  z <- log(s1$sigma - 1); ze <- log(x$sigma_eb - 1)
  d <- x$eb_data
  expect_true(all((ze[d] - mu) * (z[d] - mu) >= 0 & abs(ze[d] - mu) <= abs(z[d] - mu) + 1e-12))
  expect_equal(ze[!d], rep(mu, 2))
  expect_lt(x$eb_weight[5], x$eb_weight[1])          # the near-pole cell (sigma 1.05, SE 0.5) is pulled hardest
  expect_true(all(x$sigma_eb > 1))
  xg <- e$sigma_eb_shrink(s1, group = "good", min_n = 3L)
  grp <- attr(xg, "eb_groups")
  expect_identical(grp[group == "0101"]$own, TRUE)     # 4 data cells >= 3
  expect_identical(grp[group == "0202"]$own, FALSE)    # 2 data cells < 3 -> global prior
  expect_equal(grp[group == "0202"]$mu, mu)
})

test_that("known-truth harness: arm Stage-1 tables, metrics and readings", {
  e <- .kt_env()
  s1 <- data.table::data.table(importer = c(1L, 1L, 2L), good = c("0101", "0202", "0101"), sigma = c(2.5, 50, 1.2),
                               sigma_se = c(0.3, NA, 0.4), status = "ok", convergence = 0L, sigma_capped = c(FALSE, TRUE, FALSE),
                               adjust = c(0L, 4L, 0L), gamma = c(0.5, 0.6, 0.7))
  ts <- data.table::data.table(importer = c(1L, 1L, 2L), good = c("0101", "0202", "0101"), sigma_true = c(3, 4, 2))
  expect_identical(e$kt_arm_stage1(s1, "estimated", ts)$sigma, s1$sigma)
  tt <- e$kt_arm_stage1(s1, "true", ts)
  expect_equal(tt$sigma, c(3, 4, 2)); expect_true(all(tt$sigma_capped == FALSE)); expect_equal(tt$sigma_se, rep(0.01, 3))
  eb <- e$kt_arm_stage1(s1, "eb", ts)
  expect_true(all(eb$sigma > 1)); expect_identical(eb$sigma_capped, s1$sigma_capped)   # edge flag kept (capped-omega rule)
  expect_equal(eb$sigma[2], 1 + exp(attr(eb, "eb_mu")))                                # the edge cell takes the prior median

  # metrics: a run whose gamma equals the truth recovers everything
  td <- tempfile("ktm_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  tg <- data.table::data.table(importer = rep(c(1L, 2L), each = 4), exporter = rep(c(10L, 11L, 12L, 13L), 2), good = "0101",
                               gamma_true = c(0.2, 0.5, 1, 2, 0.3, 0.6, 0.9, 1.5))
  truth <- list(gamma = tg, sigma = data.table::data.table(importer = c(1L, 2L), good = "0101", sigma_true = c(3, 2)))
  s2b <- data.table::data.table(importer = as.character(tg$importer), exporter = as.character(tg$exporter), good = "0101",
                                sigma = rep(c(3, 2), each = 4), gamma = tg$gamma_true, tier = c(0L, 1L, 1L, 1L, 0L, 1L, 1L, 1L),
                                convergence = 0L, avg_trade = c(5, 1, 2, 3, 4, 1, 1, 2), gamma_shrink_wt = 0.5, trim_reason = NA_character_,
                                sigma_source = "estimated")
  s2b[, opt_tariff := e$optimal_tariff(gamma, sigma[1], avg_trade), by = .(importer, good)]
  saveRDS(s2b, file.path(td, paste0(e$KT_PREFIX, "_fixed_sigma.rds")))
  m <- e$kt_metrics(td, truth)
  expect_equal(m$within_r, 1); expect_equal(m$within_rank_r, 1); expect_equal(m$within_sd_ratio, 1)
  expect_equal(m$opt_tariff_err, 0); expect_equal(m$composite_err, 0); expect_equal(m$sigma_err, 0)
  # the good-level prior everywhere: no within-cell spread at all
  s2b[, gamma := 0.7]; s2b[, opt_tariff := e$optimal_tariff(gamma, sigma[1], avg_trade), by = .(importer, good)]
  saveRDS(s2b, file.path(td, paste0(e$KT_PREFIX, "_fixed_sigma.rds")))
  m0 <- e$kt_metrics(td, truth)
  expect_equal(m0$within_sd_ratio, 0)
  expect_true(is.na(m0$within_r))                      # no spread: NA, not a warning

  sm <- function(w_sh, w_t0, ot) data.table::data.table(arm_name = rep(c("shipped", "truesigma0"), each = 2), scale = c(1, 3, 1, 3),
                                                        within_r = c(w_sh, w_t0), opt_tariff_r = c(ot, ot))
  none <- data.table::data.table()
  expect_identical(e$kt_readings(sm(c(0.6, 0.7), c(0.8, 0.9), c(0.6, 0.7)), none, none)$R1_within_cell_gamma$verdict, "recovered")
  expect_identical(e$kt_readings(sm(c(0.05, 0.1), c(0.2, 0.3), c(0.1, 0.2)), none, none)$R1_within_cell_gamma$verdict, "not recovered")
  expect_identical(e$kt_readings(sm(c(0.05, 0.1), c(0.2, 0.6), c(0.4, 0.6)), none, none)$R1_within_cell_gamma$verdict, "partial")
  expect_identical(e$kt_readings(sm(c(0.05, 0.1), c(0.2, 0.3), c(0.1, 0.2)), none, none)$R2_cell_opt_tariff$verdict, "weak")
  runs <- data.table::data.table(arm_name = c("shipped", "sigma_eb", "shipped", "sigma_eb"), opt_tariff_err = c(0.30, 0.31, 0.30, 0.31))
  sl_ok  <- data.table::data.table(err_published = c(0.25, 0.20), err_eb = c(0.20, 0.17))
  sl_bad <- data.table::data.table(err_published = c(0.25, 0.20), err_eb = c(0.24, 0.19))
  expect_identical(e$kt_readings(sm(0.1, 0.2, 0.2)[1:2], sl_ok, runs)$R3_sigma_eb$verdict, "qualifies")
  expect_identical(e$kt_readings(sm(0.1, 0.2, 0.2)[1:2], sl_bad, runs)$R3_sigma_eb$verdict, "closed at known truth")
})

test_that("sigma EB period census: scores and reading on toy tables", {
  e <- .kt_env()
  set.seed(1)
  n <- 200; truth_z <- rnorm(n, 0.8, 0.2); se <- runif(n, 0.2, 1)
  mk <- function() { z <- truth_z + rnorm(n, 0, se); data.table::data.table(importer = as.character(seq_len(n)), good = rep(c("0101", "0202"), n / 2),
                                                                             sigma = 1 + exp(z), sigma_se = se * exp(z), convergence = 0L, sigma_capped = FALSE) }
  res <- e$sigma_eb_period_census(mk(), mk())
  expect_identical(res$reading$verdict, "passes")      # noisy estimates of a tight truth: shrinkage must help
  expect_lt(res$early_to_late$eb$wmse, res$early_to_late$published$wmse)
  expect_equal(res$early_to_late$targets, n)
})

test_that("harness run machinery: one tiny world, shipped and sigma_eb arms", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "jsonlite", "Rcpp", "openssl")) skip_if_not_installed(p)
  e <- .kt_env()
  td <- normalizePath(tempfile("ktg_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  res <- e$kt_grid(normalizePath(.kt_root(), winslash = "/"), td, seeds = 7L, scales = 1, arms = c("shipped", "sigma_eb"),
                   goods = 2L, countries = 8L, years = 1995:2010, ncores = 1L)
  expect_setequal(res$runs$arm_name, c("shipped", "sigma_eb"))
  expect_true(all(is.finite(res$runs$within_r)))
  expect_true(all(is.finite(res$sigma_level$err_eb)))
  expect_identical(res$runs[arm_name == "sigma_eb"]$fallback_sigma_share, 0)   # every cell carries its own (posterior) sigma
  expect_true(res$readings$R3_sigma_eb$verdict %in% c("qualifies", "closed at known truth"))
  expect_true(file.exists(file.path(td, "w7_x1", "sigma_eb", "run.log")))
})
