# ============================================================================
# test-stage2-v081-shiftlog-parity.R  (patch 0074)
# shiftlog prior: penalty lambda (ln(gamma+eps) - ln(g+eps))^2, finite at 0;
# the analytic gradient matches a central difference; curvature lambda/(d+eps)^2.
# --t-parity: CLI/validate/stamp; the runner filter keeps only the requested
# parity of t (checked on the synthetic prepared panel).
# ============================================================================
.sp_setup <- function() {
  src_dir <- locate_source_dir(); assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE); invisible(TRUE)
}
.sp_cell <- function(seed = 5L, J = 5L, T_len = 30L, sigma = 3, gam_k = 0.7) {
  set.seed(seed); a <- function(g) (1 + g) / g
  gj <- exp(rnorm(J, log(gam_k), 0.4)); Y <- numeric(J); X <- matrix(0, J, 5)
  for (j in seq_len(J)) { eps <- rnorm(T_len, 0, 0.6); q <- rnorm(T_len, 0, 0.5); dlpk <- rnorm(T_len, 0, 0.4)
    aj <- a(gj[j]); ak <- a(gam_k); Dk_lp <- (eps - q - (aj - ak) * dlpk) / (aj + sigma - 1); Dk_ls <- -(sigma - 1) * Dk_lp + eps; Dlp_j <- Dk_lp + dlpk
    Y[j] <- mean(Dk_lp^2); X[j, ] <- c(mean(Dk_ls^2), mean(Dk_ls * Dk_lp), mean(Dk_ls * Dlp_j), mean(Dk_ls * dlpk), mean(Dk_lp * dlpk)) }
  list(Y = Y, X = X, sigma = sigma, d = c(gam_k, gj) * exp(rnorm(J + 1L, 0, 0.1)))
}
.sp_obj <- function(d, c, lam, lnp, pf, eps) het_obj_fixed_sigma(d, c$sigma, c$Y, c$X, numeric(0), matrix(0, 0, 9), integer(0), numeric(0), numeric(0), rep(1, length(c$Y)), numeric(0), lnp, lam, FALSE, TRUE, pf, FALSE, eps)
.sp_grd <- function(d, c, lam, lnp, pf, eps) het_grad_fixed_sigma(d, c$sigma, c$Y, c$X, numeric(0), matrix(0, 0, 9), integer(0), numeric(0), numeric(0), rep(1, length(c$Y)), numeric(0), lnp, lam, FALSE, TRUE, pf, FALSE, eps)
.sp_fd <- function(f, d, h = 1e-6) vapply(seq_along(d), function(i) { e <- numeric(length(d)); e[i] <- h; (f(d + e) - f(d - e)) / (2 * h) }, numeric(1))

test_that("shiftlog: closed-form penalty, finite at zero, gradient vs central difference, curvature", {
  .sp_setup(); c <- .sp_cell(); lam <- 0.1; lnp <- log(0.7); g <- 0.7; d <- c$d
  for (eps in c(0.01, 0.05)) {
    base <- .sp_obj(d, c, 0, NA_real_, 3L, eps)
    expect_equal(.sp_obj(d, c, lam, lnp, 3L, eps) - base, lam * sum((log(d + eps) - log(g + eps))^2), tolerance = 1e-10)
    d0 <- d; d0[2] <- 0; expect_true(is.finite(.sp_obj(d0, c, lam, lnp, 3L, eps)))
    expect_equal(.sp_grd(d, c, lam, lnp, 3L, eps), .sp_fd(function(x) .sp_obj(x, c, lam, lnp, 3L, eps), d), tolerance = 1e-5)
    expect_equal(.ridge_curvature(d, lam, lnp, 3L, 1, eps), lam / (d + eps)^2)
    se <- compute_penalized_gn_se(d, c$sigma, c$Y, c$X, numeric(0), matrix(0, 0, 9), integer(0), numeric(0), numeric(0), rep(1, length(c$Y)), numeric(0),
                                  shrinkage_lambda = lam, ln_gamma_prior = lnp, prior_form = 3L, prior_eps = eps)
    expect_true(all(se$status %in% c("ok", "insufficient_df")))
  }
  # eps -> 0 recovers the log form at interior points
  expect_equal(.sp_obj(d, c, lam, lnp, 3L, 1e-12), .sp_obj(d, c, lam, lnp, 0L, 0.01), tolerance = 1e-8)
})

test_that("--t-parity and --stage2-prior-eps: CLI, validate_config, stamp; parity filter keeps one parity of t", {
  .sp_setup(); skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_sp_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE); on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  o <- parse_cli(c("--data", fake, "--stage2-prior", "shiftlog", "--stage2-prior-eps", "0.05", "--t-parity", "odd"))
  expect_identical(o$stage2_prior, "shiftlog"); expect_equal(o$stage2_prior_eps, 0.05); expect_identical(o$t_parity, "odd")
  d <- parse_cli(c("--data", fake)); expect_identical(d$t_parity, "all"); expect_equal(d$stage2_prior_eps, 0.01)
  expect_error(parse_cli(c("--data", fake, "--t-parity", "half")), "t-parity"); expect_error(parse_cli(c("--data", fake, "--stage2-prior-eps", "0")), "prior-eps")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  cfg_bad <- cfg; cfg_bad$t_parity <- "half"; expect_error(validate_config(cfg_bad), "t_parity")
  cfg_o <- cfg; cfg_o$t_parity <- "odd"; expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_o, dt)))
  odd <- dt[t %% 2L == 1L]; even <- dt[t %% 2L == 0L]
  expect_equal(nrow(odd) + nrow(even), nrow(dt)); expect_true(all(odd$t %% 2L == 1L)); expect_true(all(even$t %% 2L == 0L))
})
