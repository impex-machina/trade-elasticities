# ============================================================================
# test-stage2-se-form.R  (patch 0069, 2026-09-25 fresh-eyes audit #3)
#
# --stage2-se {legacy|posterior|sandwich} selects the Stage-2 gamma variance
# formula (see docs/methodology/stage2_country.md, "Variance formula").
# Locks:
#   1. algebra on a synthetic cell: legacy = s^2 (JWJ + 2P)^-1,
#      posterior = s^2 (JWJ + P)^-1, sandwich = s^2 A^-1 JWJ A^-1 with
#      A = JWJ + P, P = lambda/d^2 -- checked against an independent
#      reconstruction of J'WJ and s^2 from the Rcpp Jacobian; the three
#      coincide at lambda = 0; ordering sandwich <= posterior and
#      legacy <= posterior hold coordinate-wise;
#   2. gamma_shrink_wt uses the form's own P (data share 2(1-s)/(2-s) under
#      legacy, 1 - s otherwise);
#   3. compute_dgamma_dsigma's ridge curvature follows the form: the legacy
#      and posterior derivatives satisfy (JWJ + 2P) g_leg = (JWJ + P) g_post;
#   4. plumbing: CLI, validate_config, checkpoint stamp;
#   5. e2e fixture: default == legacy bit-for-bit; under sandwich every
#      point/route column is identical and only the SE-side columns move.
# ============================================================================

.sf_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.sf_cell <- function(seed = 5L, J = 6L, M = 4L, T_len = 30L, sigma = 3, gam_k = 0.7) {
  set.seed(seed)
  a <- function(g) (1 + g) / g; gfun <- function(g) g / (1 + g)
  gj <- exp(rnorm(J, log(gam_k), 0.4)); Y <- numeric(J); X <- matrix(0, J, 5)
  for (j in seq_len(J)) {
    eps <- rnorm(T_len, 0, 0.6); q <- rnorm(T_len, 0, 0.5); dlpk <- rnorm(T_len, 0, 0.4)
    aj <- a(gj[j]); ak <- a(gam_k)
    Dk_lp <- (eps - q - (aj - ak) * dlpk) / (aj + sigma - 1); Dk_ls <- -(sigma - 1) * Dk_lp + eps; Dlp_j <- Dk_lp + dlpk
    Y[j] <- mean(Dk_lp^2)
    X[j, ] <- c(mean(Dk_ls^2), mean(Dk_ls * Dk_lp), mean(Dk_ls * Dlp_j), mean(Dk_ls * dlpk), mean(Dk_lp * dlpk))
  }
  eY <- numeric(M); eX <- matrix(0, M, 9); gV <- gfun(0.9); sV <- 4
  for (m in seq_len(M)) {
    gI <- gfun(gj[m]); dlp_V <- rnorm(T_len, 0, 0.4); dls_V <- 0.8 * dlp_V + rnorm(T_len, 0, 0.5)
    eps <- rnorm(T_len, 0, 0.5); q <- rnorm(T_len, 0, 0.4)
    dls_i <- ((1 + (sigma - 1) * gV) * dls_V + (sV - sigma) * dlp_V - (sigma - 1) * q + eps) / (1 + (sigma - 1) * gI)
    dlp_i <- dlp_V + gI * dls_i - gV * dls_V + q
    eY[m] <- mean((dlp_i - dlp_V)^2)
    eX[m, ] <- c(mean(dls_i^2), mean(dls_i * dlp_i), mean(dls_V^2), mean(dls_V * dlp_i), mean(dls_V * dlp_V),
                 mean(dls_i * dlp_V), mean(dls_i * dls_V), mean(dlp_V^2), mean(dlp_V * dlp_i))
  }
  list(Y = Y, X = X, eY = eY, eX = eX, jmap = seq_len(M) + 2L, sV = rep(sV, M), gV = rep(0.9, M),
       gj = gj, sigma = sigma, d_hat = c(gam_k, gj) * exp(rnorm(J + 1L, 0, 0.05)))
}
.sf_se <- function(cell, lam, form) {
  compute_penalized_gn_se(cell$d_hat, cell$sigma, cell$Y, cell$X, cell$eY, cell$eX, cell$jmap, cell$sV, cell$gV,
                          rep(1, length(cell$Y)), rep(1, length(cell$eY)), shrinkage_lambda = lam, se_form = form)
}
.sf_pieces <- function(cell) {  # independent J'WJ and s^2 from the Rcpp Jacobian triplets
  jac <- het_residuals_and_jacobian_fixed_sigma_rcpp(cell$d_hat, cell$sigma, cell$Y, cell$X, cell$eY, cell$eX, cell$jmap,
                                                     cell$sV, cell$gV, rep(1, length(cell$Y)), rep(1, length(cell$eY)), FALSE)
  K <- length(cell$d_hat); Jm <- matrix(0, length(jac$residuals), K)
  for (t in seq_along(jac$jac_row)) Jm[jac$jac_row[t] + 1L, jac$jac_col[t] + 1L] <- jac$jac_val[t]
  list(JWJ = crossprod(Jm, jac$weights * Jm), s2 = sum(jac$weights * jac$residuals^2) / (length(jac$residuals) - K))
}

test_that("the three variance forms match their closed forms and coincide at lambda = 0", {
  .sf_setup()
  cell <- .sf_cell(); lam <- 0.1; p <- .sf_pieces(cell); P <- diag(lam / cell$d_hat^2)
  leg <- .sf_se(cell, lam, "legacy"); post <- .sf_se(cell, lam, "posterior"); sand <- .sf_se(cell, lam, "sandwich")
  expect_true(all(leg$status == "ok"))
  expect_equal(leg$se,  sqrt(diag(p$s2 * solve(p$JWJ + 2 * P))), tolerance = 1e-8)
  expect_equal(post$se, sqrt(diag(p$s2 * solve(p$JWJ + P))), tolerance = 1e-8)
  Ai <- solve(p$JWJ + P)
  expect_equal(sand$se, sqrt(diag(p$s2 * Ai %*% p$JWJ %*% Ai)), tolerance = 1e-8)
  expect_true(all(sand$se <= post$se + 1e-12)); expect_true(all(leg$se <= post$se + 1e-12))
  z <- lapply(c("legacy", "posterior", "sandwich"), function(f) .sf_se(cell, 0, f)$se)
  expect_equal(z[[1]], z[[2]], tolerance = 1e-12); expect_equal(z[[1]], z[[3]], tolerance = 1e-12)
  # shrink_wt uses the form's own P
  expect_equal(leg$shrink_wt,  diag(2 * P) / (diag(p$JWJ) + diag(2 * P)), tolerance = 1e-10)
  expect_equal(post$shrink_wt, diag(P) / (diag(p$JWJ) + diag(P)), tolerance = 1e-10)
  expect_equal(sand$shrink_wt, post$shrink_wt)
  # the default argument is sandwich (patch 0070; legacy through v0.7.3)
  expect_equal(compute_penalized_gn_se(cell$d_hat, cell$sigma, cell$Y, cell$X, cell$eY, cell$eX, cell$jmap, cell$sV, cell$gV,
                                       rep(1, length(cell$Y)), rep(1, length(cell$eY)), shrinkage_lambda = lam)$se, sand$se)
})

test_that("compute_dgamma_dsigma's ridge curvature follows the form", {
  .sf_setup()
  cell <- .sf_cell(); lam <- 0.1; p <- .sf_pieces(cell); P <- diag(lam / cell$d_hat^2)
  g_leg  <- compute_dgamma_dsigma(cell$d_hat, cell$sigma, cell$Y, cell$X, cell$eY, cell$eX, cell$jmap, cell$sV, cell$gV,
                                  rep(1, length(cell$Y)), rep(1, length(cell$eY)), shrinkage_lambda = lam, se_form = "legacy")
  g_post <- compute_dgamma_dsigma(cell$d_hat, cell$sigma, cell$Y, cell$X, cell$eY, cell$eX, cell$jmap, cell$sV, cell$gV,
                                  rep(1, length(cell$Y)), rep(1, length(cell$eY)), shrinkage_lambda = lam, se_form = "posterior")
  g_sand <- compute_dgamma_dsigma(cell$d_hat, cell$sigma, cell$Y, cell$X, cell$eY, cell$eX, cell$jmap, cell$sV, cell$gV,
                                  rep(1, length(cell$Y)), rep(1, length(cell$eY)), shrinkage_lambda = lam, se_form = "sandwich")
  expect_true(all(is.finite(g_leg)))
  expect_equal((p$JWJ + 2 * P) %*% g_leg, (p$JWJ + P) %*% g_post, tolerance = 1e-8)   # same right-hand side
  expect_equal(g_post, g_sand)
  expect_gt(median(abs(g_post / g_leg)), 1)                                          # the consistent curvature is smaller
})

test_that("CLI, validate_config and the checkpoint stamp carry stage2_se", {
  .sf_setup(); skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_sf_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  expect_identical(parse_cli(c(base, "--stage2-se", "sandwich"))$stage2_se, "sandwich")
  expect_identical(parse_cli(base)$stage2_se, "sandwich")   # patch 0070 default
  expect_error(parse_cli(c(base, "--stage2-se", "bootstrap")), "stage2-se")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  cfg_bad <- cfg; cfg_bad$stage2_se <- "bootstrap"
  expect_error(validate_config(cfg_bad), "stage2_se")
  cfg_l <- cfg; cfg_l$stage2_se <- "legacy"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_l, dt)))
  cfg_s <- cfg; cfg_s$stage2_se <- "sandwich"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_s, dt))   # absent key == sandwich (patch 0070)
})

test_that("default == sandwich bit-for-bit; legacy moves only the SE-side columns", {
  .sf_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  run <- function(cfg) {
    r <- NULL
    suppressMessages(suppressWarnings(capture.output(
      r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output")))
    r
  }
  r_def <- run(cfg)
  cfg_s <- cfg; cfg_s$stage2_se <- "sandwich"
  expect_identical(finalize_saved_output(r_def), finalize_saved_output(run(cfg_s)))
  cfg_leg <- cfg; cfg_leg$stage2_se <- "legacy"
  r_s <- run(cfg_leg)
  expect_setequal(names(r_s), names(r_def)); expect_equal(nrow(r_s), nrow(r_def))
  key <- c("importer", "exporter", "good")
  a <- finalize_saved_output(r_def); b <- finalize_saved_output(r_s)
  data.table::setkeyv(a, key); data.table::setkeyv(b, key)
  point_cols <- intersect(c("sigma", "gamma", "tier", "ref_exporter", "convergence", "obj_value", "opt_tariff", "opt_tariff_all", "avg_trade"), names(a))
  for (cc in point_cols) expect_identical(a[[cc]], b[[cc]], info = cc)
  se_cols <- intersect(c("gamma_se", "gamma_shrink_wt", "dgamma_dsigma"), names(a))
  moved <- vapply(se_cols, function(cc) !identical(a[[cc]], b[[cc]]), logical(1))
  expect_true(any(moved))
})
