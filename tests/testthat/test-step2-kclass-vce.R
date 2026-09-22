# ============================================================================
# test-step2-kclass-vce.R  (patch 0061, 2026-09-22 fresh-eyes review)
#
# The Step-2 (weighted Fuller LIML) robust variance. Through v0.7.2
# fuller_liml_core() filled V_eta_robust with K^{-1} (X'diag(u^2)X) K^{-1}:
# the OLS meat. A k-class estimator solves X_k'(Y - X eta) = 0 with
# X_k = ((1-kappa)I + kappa P_Z)X, so the sandwich meat is X_k'diag(u^2)X_k
# (at kappa = 1, the 2SLS HC0 sandwich). Locks:
#   1. vce = "legacy" is bit-identical to the pre-0061 arithmetic;
#      vce = "kclass" equals an inline dense re-derivation; the two differ.
#   2. Calibration: on a seeded heteroskedastic group-instrument DGP the
#      k-class SE tracks the Monte-Carlo dispersion of eta_hat (ratio within
#      +/-15%) while the legacy SE overstates it (ratio > 1.3).
#   3. estimate_cell_liml(step2_vce = "kclass") changes ONLY the Step-2 SE
#      fields (and the stamp) on a step2_weighted cell -- point estimates,
#      routing, diagnostics untouched; on an interior cell the FINAL SEs are
#      untouched. The default is "legacy" (bit-preserving).
#   4. Wrapper column + CLI flag + config validation.
# ============================================================================

.kv_source <- function(env) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = env)
  source(file.path(root, "R", "utils_general.R"), local = env)
  source(file.path(root, "R", "liml_estimator.R"), local = env)
}
.kv_cell <- function(sigma, omega, J, T, seed) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  simulate_one_cell(sigma, omega, J = J, T = T, seed = seed)
}
# Small IV design with exporter-style group dummies as instruments and
# group-level heteroskedasticity; endogeneity through a shared shock.
.kv_design <- function(J = 12L, T = 15L, seed = 1L) {
  set.seed(seed)
  grp <- rep(seq_len(J), each = T)
  list(grp = grp, Z = sapply(seq_len(J), function(j) as.numeric(grp == j)),
       pi1 = rnorm(J), pi2 = rnorm(J), beta = c(0.8, -0.5, 0.3))
}
.kv_draw <- function(d) {
  n <- length(d$grp)
  e  <- rnorm(n) * (0.5 + abs(d$pi1[d$grp]))
  x1 <- d$pi1[d$grp] + 0.7 * e + rnorm(n)
  x2 <- d$pi2[d$grp] - 0.4 * e + rnorm(n)
  X  <- cbind(x1 = x1, x2 = x2, ones = 1)
  list(y = as.numeric(X %*% d$beta + e), X = X)
}

test_that("legacy is bit-identical to the pre-0061 meat; kclass matches a dense re-derivation", {
  .kv_source(environment())
  d <- .kv_design(seed = 7L); set.seed(11L); dr <- .kv_draw(d)
  w <- exp(rnorm(length(dr$y), 0, 0.3))          # exercise the weighted metric too
  for (wts in list(NULL, w)) {
    f0 <- fuller_liml_core(dr$y, dr$X, d$Z, weights = wts, endog_idx = c(1L, 2L))
    fl <- fuller_liml_core(dr$y, dr$X, d$Z, weights = wts, endog_idx = c(1L, 2L), vce = "legacy")
    fk <- fuller_liml_core(dr$y, dr$X, d$Z, weights = wts, endog_idx = c(1L, 2L), vce = "kclass")
    expect_identical(f0$V_eta_robust, fl$V_eta_robust)   # default == legacy
    expect_identical(fl$eta, fk$eta); expect_identical(fl$kappa, fk$kappa)
    expect_identical(fl$u_hat, fk$u_hat)                 # only the sandwich moves
    # inline: pre-0061 arithmetic and the dense k-class sandwich, both in
    # the (weighted) metric fuller_liml_core() works in
    Y <- dr$y; X <- dr$X; Z <- d$Z; n <- length(Y)
    if (!is.null(wts)) { ws <- sqrt(wts * n / sum(wts)); Y <- Y * ws; X <- X * ws; Z <- Z * ws }
    P <- Z %*% solve(crossprod(Z), t(Z))
    K <- (1 - fl$kappa) * crossprod(X) + fl$kappa * crossprod(X, P %*% X)
    Kinv <- solve(K); u2 <- as.numeric(fl$u_hat^2)
    V_legacy <- Kinv %*% crossprod(X, u2 * X) %*% Kinv
    Xk <- (1 - fk$kappa) * X + fk$kappa * (P %*% X)
    V_kclass <- Kinv %*% crossprod(Xk, u2 * Xk) %*% Kinv
    expect_equal(fl$V_eta_robust, V_legacy, tolerance = 1e-10)
    expect_equal(fk$V_eta_robust, V_kclass, tolerance = 1e-10)
    expect_gt(max(abs(fl$V_eta_robust - fk$V_eta_robust)), 1e-6)
    expect_identical(fl$vce, "legacy"); expect_identical(fk$vce, "kclass")
  }
})

test_that("k-class SE tracks Monte-Carlo dispersion; legacy overstates it", {
  .kv_source(environment())
  d <- .kv_design(seed = 3L); set.seed(20260922L)
  R <- 400L
  eta <- matrix(NA_real_, R, 3); se_l <- eta; se_k <- eta
  for (r in seq_len(R)) {
    dr <- .kv_draw(d)
    fl <- fuller_liml_core(dr$y, dr$X, d$Z, endog_idx = c(1L, 2L), vce = "legacy")
    if (!identical(fl$status, "ok")) next
    fk <- fuller_liml_core(dr$y, dr$X, d$Z, endog_idx = c(1L, 2L), vce = "kclass")
    eta[r, ] <- fl$eta
    se_l[r, ] <- sqrt(diag(fl$V_eta_robust)); se_k[r, ] <- sqrt(diag(fk$V_eta_robust))
  }
  ok <- complete.cases(eta); expect_gt(sum(ok), 0.95 * R)
  mc_sd <- apply(eta[ok, ], 2, sd)
  ratio_k <- apply(se_k[ok, ], 2, median) / mc_sd
  ratio_l <- apply(se_l[ok, ], 2, median) / mc_sd
  expect_true(all(ratio_k[1:2] > 0.85 & ratio_k[1:2] < 1.15))   # endogenous coefficients
  expect_true(all(ratio_l[1:2] > 1.3))
  expect_true(all(ratio_l > ratio_k))
})

test_that("estimate_cell_liml(step2_vce) touches only the Step-2 SE fields; default is legacy", {
  .kv_source(environment())
  se_fields <- c("sigma_se", "omega_se", "rho_se",
                 "sigma_step2_se", "omega_step2_se", "rho_step2_se")
  strip <- function(f) f[setdiff(names(f), c(se_fields, "step2_vce_method"))]
  # a cell routed to Step 2 (closed-form point inadmissible, Step 2 admissible)
  m2 <- .kv_cell(8, 3, 25L, 30L, seed = 20260933L)
  a <- estimate_cell_liml(m2, ref_exporter = 1L)
  b <- estimate_cell_liml(m2, ref_exporter = 1L, step2_vce = "kclass")
  l <- estimate_cell_liml(m2, ref_exporter = 1L, step2_vce = "legacy")
  expect_identical(a$final_source, "step2_weighted"); expect_identical(a$adjust, 1L)
  expect_identical(a$step2_vce_method, "legacy"); expect_identical(b$step2_vce_method, "kclass")
  expect_identical(a[names(a) != "step2_vce_method"], l[names(l) != "step2_vce_method"])  # default == legacy
  expect_identical(strip(a), strip(b))                            # points, routing, diagnostics
  expect_true(all(is.finite(c(a$sigma_se, b$sigma_se))))
  expect_gt(a$sigma_se, b$sigma_se)                                # legacy overstates
  expect_identical(b$sigma_se, b$sigma_step2_se)                   # final SE == Step-2 SE on this route
  # an interior HLIML cell: final SEs come from HNCS and must not move
  mi <- .kv_cell(3, 1, 25L, 30L, seed = 20260923L)
  ai <- estimate_cell_liml(mi, ref_exporter = 1L)
  bi <- estimate_cell_liml(mi, ref_exporter = 1L, step2_vce = "kclass")
  expect_identical(ai$final_source, "hliml")
  expect_identical(ai[c("sigma", "omega", "sigma_se", "omega_se", "rho_se")],
                   bi[c("sigma", "omega", "sigma_se", "omega_se", "rho_se")])
  expect_false(identical(ai$sigma_step2_se, bi$sigma_step2_se))    # the diagnostic still moves
})

test_that("wrapper column, CLI flag and config validation", {
  suppressPackageStartupMessages(library(data.table))
  .kv_source(environment())
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  set.seed(1L)
  raw <- data.table::data.table(importer = 1L, good = "0202",
    exporter = rep(1:6, each = 12L), t = rep(1995:2006, 6L),
    value = exp(rnorm(72)), quantity = exp(rnorm(72)))
  tmp <- tempfile(fileext = ".rds")
  out0 <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                          min_periods = 3L, verbose = FALSE)
  outk <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                          min_periods = 3L, verbose = FALSE, step2_vce = "kclass")
  expect_true("step2_vce_method" %in% names(out0))
  expect_true(all(out0$step2_vce_method[!is.na(out0$hliml_method)] == "legacy"))   # default
  expect_true(all(outk$step2_vce_method[!is.na(outk$hliml_method)] == "kclass"))
  expect_identical(out0$sigma, outk$sigma); expect_identical(out0$final_source, outk$final_source)
  unlink(tmp)
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  source(file.path(root, "R", "validate_config.R"), local = TRUE)
  dd <- tempfile(); dir.create(dd)
  o0 <- parse_cli(c("--data", dd)); expect_identical(o0$stage1_step2_vce, "legacy")
  expect_identical(build_config(o0)$stage1_step2_vce, "legacy")
  ok <- parse_cli(c("--data", dd, "--stage1-step2-vce", "kclass")); expect_identical(ok$stage1_step2_vce, "kclass")
  expect_identical(build_config(ok)$stage1_step2_vce, "kclass")
  expect_error(parse_cli(c("--data", dd, "--stage1-step2-vce", "hc1")), "stage1-step2-vce")
  cfg <- build_config(ok); cfg$stage1_step2_vce <- "hc1"
  expect_error(validate_config(cfg), "stage1_step2_vce")
  unlink(dd, recursive = TRUE)
})
