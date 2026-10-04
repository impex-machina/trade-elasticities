# ============================================================================
# test-bootstrap-sigma-cap.R  (patch 0088, 2026-10-04)
#
# validation/bootstrap_se.R re-fits sampled cells under exporter resampling
# through bs_fit_cell() -> estimate_cell_liml(). Through v0.9.0's rc the
# replicate fits used the estimator's default cap (10) whatever cap the
# bootstrapped Stage-1 run had. --sigma-cap threads the cap through
# bs_boot_cell() and bs_fit_cell(); NULL keeps the estimator default, so the
# existing bootstrap tests are unchanged. On a true-sigma-20 panel the default
# fit is published at 10 and the cap-50 fit is an interior estimate near 20.
# ============================================================================

.bc_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  source(file.path(src_dir, "..", "validation", "bootstrap_se_core.R"), local = FALSE)
  invisible(TRUE)
}
.bc_panel <- function(sigma_true, omega_true, J = 30L, T = 24L, seed = 20261003L, sd_meas = 0.01) {
  set.seed(seed)
  denom <- 1 + omega_true * sigma_true
  a_eps_s <- (1 + omega_true) / denom; a_u_s <- -(sigma_true - 1) / denom
  a_eps_p <- omega_true / denom;       a_u_p <- 1 / denom
  sd_eps_j <- runif(J, 0.5, 2.0); sd_u_j <- runif(J, 0.5, 2.0)
  rows <- vector("list", J)
  for (j in seq_len(J)) {
    d_eps <- rnorm(T, sd = sd_eps_j[j]); d_u <- rnorm(T, sd = sd_u_j[j])
    d_ln_s <- a_eps_s * d_eps + a_u_s * d_u
    d_ln_p <- a_eps_p * d_eps + a_u_p * d_u + rnorm(T, sd = sd_meas)
    ln_p <- cumsum(c(0, d_ln_p))[-1]; ln_v <- 10 + cumsum(c(0, d_ln_s))[-1]
    rows[[j]] <- data.frame(exporter = j, t = 1995L + seq_len(T) - 1L, value = exp(ln_v), quantity = exp(ln_v - ln_p))
  }
  do.call(rbind, rows)
}

test_that("bs_fit_cell() and bs_boot_cell() carry the Stage-1 sigma cap", {
  .bc_setup()
  expect_true("sigma_cap" %in% names(formals(bs_fit_cell)))
  expect_true("sigma_cap" %in% names(formals(bs_boot_cell)))
  expect_null(formals(bs_fit_cell)$sigma_cap)                               # default: the estimator's cap
  pan <- .bc_panel(20, 0.5)
  f10 <- bs_fit_cell(pan, min_year = 1995L)
  f50 <- bs_fit_cell(pan, min_year = 1995L, sigma_cap = 50)
  expect_false(is.null(f10)); expect_false(is.null(f50))
  expect_equal(f10$sigma, 10)
  expect_true(f50$sigma > 10 && f50$sigma < 50)
  expect_equal(f50$sigma, 20, tolerance = 0.35)
  pan3 <- .bc_panel(3, 1, seed = 20261004L)
  g10 <- bs_fit_cell(pan3, min_year = 1995L); g50 <- bs_fit_cell(pan3, min_year = 1995L, sigma_cap = 50)
  expect_equal(g10$sigma, g50$sigma)                                         # the cap only touches cells it binds on
  r <- bs_boot_cell(pan, published_route = "step2_weighted", B = 8L, seed = 1L, min_boot_ok = 4L, min_year = 1995L, sigma_cap = 50)
  expect_true(is.list(r))
})
