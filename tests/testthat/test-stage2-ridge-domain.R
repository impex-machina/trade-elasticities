# ============================================================================
# test-stage2-ridge-domain.R  (patch 0068, 2026-09-25 fresh-eyes audit #3)
#
# The Stage-2 log-ridge penalty applied only to coordinates with gamma > 1e-5
# while the optimizer's lower bound is 1e-6, leaving the band (1e-6, 1e-5]
# penalty-free: a hole ~lambda (ln 1e-5 - ln g)^2 deep that traps coordinates
# under strong data pull (>= 10% of directly estimated rows on v0.7.3). Locks:
#   1. objective: under 'all' a coordinate at 5e-6 pays exactly
#      lambda (ln 5e-6 - ln g)^2; under legacy it pays nothing; every
#      coordinate above 1e-5 is identical in both modes;
#   2. analytic gradient: differs between modes only on the sub-1e-5
#      coordinate, by 2 lambda (ln d - ln g) / d, and matches numDeriv under
#      'all' at an interior point;
#   3. dynamics: started inside the hole, legacy stays at the floor and 'all'
#      climbs out toward the prior (a deterministic version of the trap);
#   4. plumbing: the CLI accepts legacy/all and rejects others,
#      validate_config likewise, the checkpoint stamp moves with the field,
#      and the e2e fixture output under the default is byte-identical to an
#      explicit 'legacy' run (bit-preservation) while 'all' runs with the
#      same schema.
# ============================================================================

.rd_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

# Small structural import-side cell (Eqs. 5-6), no export rows.
.rd_cell <- function(seed = 11L, J = 6L, T_len = 40L, sigma = 3, gam_k = 0.7) {
  set.seed(seed)
  a <- function(g) (1 + g) / g
  gj <- exp(rnorm(J, log(gam_k), 0.4)); Y <- numeric(J); X <- matrix(0, J, 5)
  for (j in seq_len(J)) {
    eps <- rnorm(T_len, 0, 0.6); q <- rnorm(T_len, 0, 0.5); dlpk <- rnorm(T_len, 0, 0.4)
    aj <- a(gj[j]); ak <- a(gam_k)
    Dk_lp <- (eps - q - (aj - ak) * dlpk) / (aj + sigma - 1); Dk_ls <- -(sigma - 1) * Dk_lp + eps
    Dlp_j <- Dk_lp + dlpk
    Y[j] <- mean(Dk_lp^2)
    X[j, ] <- c(mean(Dk_ls^2), mean(Dk_ls * Dk_lp), mean(Dk_ls * Dlp_j), mean(Dk_ls * dlpk), mean(Dk_lp * dlpk))
  }
  list(Y = Y, X = X, gj = gj, sigma = sigma, gam_k = gam_k)
}
.rd_obj <- function(d, cell, lambda, lnp, all) {
  het_obj_fixed_sigma(d, cell$sigma, cell$Y, cell$X, numeric(0), matrix(0, 0, 9), integer(0),
                      numeric(0), numeric(0), rep(1, length(cell$Y)), numeric(0),
                      lnp, lambda, paper_exact_eq11 = FALSE, ridge_all_coords = all)
}
.rd_grad <- function(d, cell, lambda, lnp, all) {
  het_grad_fixed_sigma(d, cell$sigma, cell$Y, cell$X, numeric(0), matrix(0, 0, 9), integer(0),
                       numeric(0), numeric(0), rep(1, length(cell$Y)), numeric(0),
                       lnp, lambda, paper_exact_eq11 = FALSE, ridge_all_coords = all)
}

test_that("the objective penalizes a sub-1e-5 coordinate under 'all' and not under legacy", {
  .rd_setup()
  cell <- .rd_cell(); lam <- 0.1; lnp <- log(0.7)
  d_in <- c(0.7, cell$gj); d_in[3] <- 5e-6
  o_leg <- .rd_obj(d_in, cell, lam, lnp, FALSE)
  o_all <- .rd_obj(d_in, cell, lam, lnp, TRUE)
  expect_equal(o_all - o_leg, lam * (log(5e-6) - lnp)^2, tolerance = 1e-10)
  # above the threshold the two modes coincide exactly
  d_up <- c(0.7, cell$gj)
  expect_identical(.rd_obj(d_up, cell, lam, lnp, FALSE), .rd_obj(d_up, cell, lam, lnp, TRUE))
  # the default argument is 'all' (patch 0070; legacy through v0.7.3)
  o_def <- het_obj_fixed_sigma(d_in, cell$sigma, cell$Y, cell$X, numeric(0), matrix(0, 0, 9), integer(0),
                               numeric(0), numeric(0), rep(1, length(cell$Y)), numeric(0), lnp, lam)
  expect_identical(o_def, o_all)
})

test_that("the analytic gradient follows the same domain rule and matches a central difference under 'all'", {
  .rd_setup()
  cell <- .rd_cell(); lam <- 0.1; lnp <- log(0.7)
  d_in <- c(0.7, cell$gj); d_in[3] <- 5e-6
  g_leg <- .rd_grad(d_in, cell, lam, lnp, FALSE); g_all <- .rd_grad(d_in, cell, lam, lnp, TRUE)
  diff <- g_all - g_leg
  expect_equal(diff[-3], rep(0, length(d_in) - 1L))
  expect_equal(diff[3], 2 * lam * (log(5e-6) - lnp) / 5e-6, tolerance = 1e-8)
  d_int <- c(0.8, cell$gj * 1.1)
  f <- function(d) .rd_obj(d, cell, lam, lnp, TRUE); h <- 1e-6
  g_num <- vapply(seq_along(d_int), function(i) { e <- numeric(length(d_int)); e[i] <- h; (f(d_int + e) - f(d_int - e)) / (2 * h) }, numeric(1))
  expect_equal(.rd_grad(d_int, cell, lam, lnp, TRUE), g_num, tolerance = 1e-5)
})

test_that("started inside the hole, legacy stays at the floor and 'all' climbs out", {
  .rd_setup()
  cell <- .rd_cell(); lam <- 0.1; lnp <- log(0.7); K <- length(cell$gj) + 1L
  start <- rep(0.7, K); start[3] <- 5e-6
  fit <- function(all) optim(start, function(d) .rd_obj(d, cell, lam, lnp, all), method = "L-BFGS-B",
                             lower = rep(1e-6, K), upper = rep(Inf, K), control = list(maxit = 500))$par
  p_leg <- fit(FALSE); p_all <- fit(TRUE)
  expect_lte(p_leg[3], 1e-5)                 # trapped: zero ridge gradient inside the band
  expect_gt(p_all[3], 0.05)                  # lifted out toward the prior
  expect_true(all(p_all > 1e-5))
})

test_that("CLI, validate_config and the checkpoint stamp carry stage2_ridge_domain", {
  .rd_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_rd_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  o1 <- parse_cli(c(base, "--stage2-ridge-domain", "all"))
  expect_identical(o1$stage2_ridge_domain, "all")
  o2 <- parse_cli(base)
  expect_identical(o2$stage2_ridge_domain, "all")   # patch 0070 default
  expect_error(parse_cli(c(base, "--stage2-ridge-domain", "hole")), "stage2-ridge-domain")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  expect_silent(validate_config(cfg))
  cfg_bad <- cfg; cfg_bad$stage2_ridge_domain <- "hole"
  expect_error(validate_config(cfg_bad), "stage2_ridge_domain")
  cfg_leg <- cfg; cfg_leg$stage2_ridge_domain <- "legacy"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_leg, dt)))
  cfg_all <- cfg; cfg_all$stage2_ridge_domain <- "all"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_all, dt))   # absent key == all (patch 0070)
})

test_that("default == 'all' bit-for-bit on the e2e fixture; legacy runs with the same schema", {
  .rd_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  run <- function(cfg) {
    r <- NULL
    suppressMessages(suppressWarnings(capture.output(
      r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output")))
    r
  }
  r_def <- run(cfg)
  cfg_all <- cfg; cfg_all$stage2_ridge_domain <- "all"
  r_all <- run(cfg_all)
  expect_identical(finalize_saved_output(r_def), finalize_saved_output(r_all))
  cfg_leg <- cfg; cfg_leg$stage2_ridge_domain <- "legacy"
  r_leg <- run(cfg_leg)
  expect_setequal(names(r_leg), names(r_def))
  expect_equal(nrow(r_leg), nrow(r_def))
})
