# ============================================================================
# test-bootstrap-branch-tag.R  (patch 0063, 2026-09-22)
#
# Branch-tagged validation harnesses. Locks:
#   1. validation/bootstrap_se_core.R: bs_fit_cell() reaches an ok fit on a
#      synthetic Feenstra panel and reports its route; bs_boot_cell() keeps
#      the 2026-07-10 schema, adds the branch-tag fields with consistent
#      shares/counts, is deterministic in its seed, and forwards step2_vce
#      (patch 0061) without changing points or routing.
#   2. validation/bootstrap_se.R sources utils_general.R BEFORE the estimator
#      and sources the core: estimate_cell_liml() calls boundary_flags() at
#      its boundary-routing site, and the pre-0063 script (liml_estimator.R
#      alone) would have turned every boundary-routed replicate on a v0.6.0+
#      table into a silent failure.
#   3. validation/validate_liml.R: .tier1_inner() records the route per
#      replicate; validate_tier1a() appends six per-route columns after the
#      ten original ones, with counts that reconcile to the success rate.
# ============================================================================

.bt_source <- function(env) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = env)
  source(file.path(root, "R", "utils_general.R"), local = env)
  source(file.path(root, "R", "liml_estimator.R"), local = env)
  source(file.path(root, "validation", "validate_liml.R"), local = env)
  source(file.path(root, "validation", "bootstrap_se_core.R"), local = env)
}

# A raw (exporter, t, value, quantity) panel whose reference-differenced
# Feenstra moments follow the Pillar-2 DGP of validate_liml.R: log prices and
# log values integrate the same reduced-form shocks; the within-t share
# normalisation cancels in the reference differencing, so prepare_cell_moments()
# recovers exactly the simulated d ln s / d ln p differences.
.bt_panel <- function(sigma_true, omega_true, J = 12L, T = 20L, seed = 1L,
                      sd_eps = 1.0, sd_u = 1.0, sd_meas = 0.3) {
  set.seed(seed)
  denom <- 1 + omega_true * sigma_true
  a_eps_s <- (1 + omega_true) / denom; a_u_s <- -(sigma_true - 1) / denom
  a_eps_p <- omega_true / denom;       a_u_p <- 1 / denom
  sd_eps_j <- runif(J, 0.5, 2.0) * sd_eps; sd_u_j <- runif(J, 0.5, 2.0) * sd_u
  rows <- vector("list", J)
  for (j in seq_len(J)) {
    d_eps <- rnorm(T, sd = sd_eps_j[j]); d_u <- rnorm(T, sd = sd_u_j[j])
    d_ln_s <- a_eps_s * d_eps + a_u_s * d_u
    d_ln_p <- a_eps_p * d_eps + a_u_p * d_u + rnorm(T, sd = sd_meas)
    ln_p <- cumsum(c(0, d_ln_p))[-1]; ln_v <- 10 + cumsum(c(0, d_ln_s))[-1]
    rows[[j]] <- data.frame(exporter = j, t = 1995L + seq_len(T) - 1L,
                            value = exp(ln_v), quantity = exp(ln_v - ln_p))
  }
  do.call(rbind, rows)
}

test_that("bs_fit_cell fits a synthetic panel through the production path and reports its route", {
  .bt_source(environment())
  pan <- .bt_panel(3, 1, seed = 20260924L)
  f <- bs_fit_cell(pan, min_year = 1995L)
  expect_false(is.null(f))
  expect_true(is.finite(f$sigma) && f$sigma > 1)
  expect_true(f$route %in% .bs_routes)
  # step2_vce forwards to the estimator without touching the point or the route
  fl <- bs_fit_cell(pan, min_year = 1995L, step2_vce = "legacy")
  expect_identical(fl$sigma, f$sigma); expect_identical(fl$route, f$route)
  # a Step-2-routed panel: the VCE rule changes only its SE, never the point;
  # the default is kclass (patch 0064) and legacy overstates
  p2 <- .bt_panel(3, 1, seed = 20260925L)
  f2 <- bs_fit_cell(p2, min_year = 1995L); f2l <- bs_fit_cell(p2, min_year = 1995L, step2_vce = "legacy")
  f2k <- bs_fit_cell(p2, min_year = 1995L, step2_vce = "kclass")
  expect_identical(f2$route, "step2_weighted"); expect_identical(f2l$sigma, f2$sigma)
  expect_identical(f2$sigma_se, f2k$sigma_se)
  expect_true(is.finite(f2$sigma_se) && is.finite(f2l$sigma_se) && f2l$sigma_se > f2$sigma_se)
  # a panel too thin to prepare returns NULL, never an error
  expect_null(bs_fit_cell(pan[pan$exporter <= 2, ], min_year = 1995L))
})

test_that("bs_boot_cell keeps the 2026-07-10 fields, adds consistent branch tags, and is seed-deterministic", {
  .bt_source(environment())
  pan <- .bt_panel(3, 1, seed = 20260924L)
  f <- bs_fit_cell(pan, min_year = 1995L)
  r <- bs_boot_cell(pan, published_route = f$route, B = 16L, seed = 7L,
                    min_boot_ok = 5L, min_year = 1995L)
  legacy <- c("sigma_base", "boot_n_ok", "boot_yield", "boot_med", "boot_sd", "boot_mad_sd")
  tags <- c("base_source", "boot_share_same", "boot_share_hliml", "boot_share_step2",
            "boot_share_boundary", "boot_n_same", "boot_med_same", "boot_sd_same",
            "boot_mad_sd_same", "boot_med_se_same")
  expect_identical(names(r), c(legacy, tags))
  expect_identical(r$sigma_base, f$sigma); expect_identical(r$base_source, f$route)
  expect_true(r$boot_n_ok >= 0L && r$boot_n_ok <= 16L)
  expect_equal(r$boot_yield, r$boot_n_ok / 16)
  expect_true(r$boot_n_same <= r$boot_n_ok)
  if (r$boot_n_ok > 0) {
    expect_equal(r$boot_share_hliml + r$boot_share_step2 + r$boot_share_boundary, 1)
    same_named <- switch(f$route, hliml = r$boot_share_hliml,
                         step2_weighted = r$boot_share_step2,
                         hliml_boundary = r$boot_share_boundary)
    expect_equal(r$boot_share_same, same_named)
    expect_equal(r$boot_share_same, r$boot_n_same / r$boot_n_ok)
  }
  # dispersion only when enough replicates; within-branch never exceeds the all-replicate count
  if (r$boot_n_ok >= 5L) expect_true(is.finite(r$boot_sd)) else expect_true(is.na(r$boot_sd))
  if (r$boot_n_same >= 5L) expect_true(is.finite(r$boot_sd_same)) else expect_true(is.na(r$boot_sd_same))
  r2 <- bs_boot_cell(pan, published_route = f$route, B = 16L, seed = 7L,
                     min_boot_ok = 5L, min_year = 1995L)
  expect_identical(r, r2)
  r3 <- bs_boot_cell(pan, published_route = f$route, B = 16L, seed = 8L,
                     min_boot_ok = 5L, min_year = 1995L)
  expect_false(identical(r$boot_med, r3$boot_med))
})

test_that("bootstrap_se.R loads utils_general.R before the estimator and uses the core", {
  root <- dirname(locate_source_dir())
  src <- readLines(file.path(root, "validation", "bootstrap_se.R"), warn = FALSE)
  i_util <- grep('source\\("R/utils_general.R"\\)', src)
  i_est  <- grep('source\\("R/liml_estimator.R"\\)', src)
  i_core <- grep('source\\("validation/bootstrap_se_core.R"\\)', src)
  expect_length(i_util, 1L); expect_length(i_est, 1L); expect_length(i_core, 1L)
  expect_lt(i_util, i_est)
  expect_true(any(grepl("boundary_flags", src)))          # the load gate
  expect_true(any(grepl("--step2-vce", src, fixed = TRUE)))
  expect_false(any(grepl("^fit_sigma <- function", src)))  # the worker moved to the core
})

test_that("Pillar 2 records the route per replicate and reports coverage by route", {
  .bt_source(environment())
  r <- .tier1_inner(3, 1, n_reps = 6L, J = 12L, T = 15L, seed_base = 20260922L)
  expect_length(r$routes, 6L)
  expect_identical(is.na(r$routes), is.na(r$sigmas))
  expect_true(all(r$routes[!is.na(r$routes)] %in% .bs_routes))
  out <- capture.output(
    summ <- validate_tier1a(n_reps = 4L, sigma_grid = 3, omega_grid = c(0.3, 3),
                            J = 12L, T = 15L, seed_base = 20260922L))
  expect_equal(nrow(summ), 2L)
  expect_identical(names(summ)[1:10],
                   c("sigma_true", "omega_true", "success_rate", "sigma_med", "sigma_bias",
                     "omega_med", "omega_bias", "sigma_cov", "omega_cov", "med_fstat"))
  expect_identical(names(summ)[11:16],
                   c("n_hliml", "n_step2", "n_boundary",
                     "sigma_cov_hliml", "sigma_cov_step2", "sigma_cov_boundary"))
  expect_equal(summ$n_hliml + summ$n_step2 + summ$n_boundary, round(summ$success_rate * 4))
  for (v in c("sigma_cov_hliml", "sigma_cov_step2", "sigma_cov_boundary"))
    expect_true(all(is.na(summ[[v]]) | (summ[[v]] >= 0 & summ[[v]] <= 1)))
  expect_true(any(grepl("Tier 1a by route", out)))
})
