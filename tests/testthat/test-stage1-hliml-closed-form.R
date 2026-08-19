# ============================================================================
# test-stage1-hliml-closed-form.R  (patch 0025, v0.6.0-rc)
#
# Locks for hliml_group_moments() / hliml_closed_form() and the
# hliml_method plumbing in estimate_cell_liml():
#   1. O(n) group-sum moments equal the dense Xc'(P - diag P)Xc;
#   2. Q(theta_cf) == alpha (the closed form IS the unconstrained minimiser);
#   3. on an interior synthetic cell BFGS and the closed form agree and the
#      closed form attains a (weakly) lower objective;
#   4. the default path is bit-identical to hliml_method = "bfgs" and the
#      *_cf fields are NA there;
#   5. hliml_method = "closed" routes on the closed form and returns HNCS SEs;
#   6. --stage1-hliml parses and validates.
# ============================================================================

.cf_cell <- function(sigma = 3, omega = 1, J = 20L, T = 40L, seed = 20260819L) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  simulate_one_cell(sigma, omega, J = J, T = T, seed = seed)
}

.dense_Q <- function(theta, Y, X, Z) {
  P <- Z %*% solve(crossprod(Z), t(Z))
  Pmd <- P; diag(Pmd) <- 0
  A <- as.numeric(Y - X %*% theta)
  as.numeric(crossprod(A, Pmd %*% A) / crossprod(A))
}

test_that("group-sum HLIML moments equal the dense projection algebra", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell()
  Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)
  ex <- sort(unique(mom$exporter))
  Z <- sapply(ex, function(e) as.numeric(mom$exporter == e))
  P <- Z %*% solve(crossprod(Z), t(Z)); Pmd <- P; diag(Pmd) <- 0
  Xc <- cbind(Y, X)
  gm <- hliml_group_moments(Y, X, mom$exporter)
  expect_equal(gm$XcXc, unname(crossprod(Xc)), tolerance = 1e-10)
  expect_equal(gm$XcPdXc, unname(crossprod(Xc, Pmd %*% Xc)), tolerance = 1e-10)
  expect_equal(sum(gm$n_g), length(Y))
})

test_that("closed form attains Q == alpha and inverts to an admissible interior point", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell()
  Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)
  ex <- sort(unique(mom$exporter))
  Z <- sapply(ex, function(e) as.numeric(mom$exporter == e))
  cf <- hliml_closed_form(Y, X, mom$exporter)
  expect_identical(cf$status, "ok")
  theta <- c(cf$theta0, cf$theta1, cf$theta2)
  expect_equal(.dense_Q(theta, Y, X, Z), cf$alpha, tolerance = 1e-9)
  expect_true(cf$admissible)
  expect_lt(abs(cf$sigma - 3) / 3, 0.15)
  expect_gt(cf$omega, 0.4); expect_lt(cf$omega, 2.5)
  # perturbing theta in any direction cannot lower Q below alpha
  for (d in list(c(1e-3, 0, 0), c(0, 1e-3, 0), c(0, 0, 1e-3), c(-1e-3, 1e-3, -1e-3)))
    expect_gte(.dense_Q(theta + d, Y, X, Z), cf$alpha - 1e-12)
})

test_that("'both' mode: BFGS and closed form agree on an interior cell; closed form is the global min", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell()
  fit <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "both")
  expect_identical(fit$status, "ok")
  expect_identical(fit$hliml_method, "both")
  expect_identical(fit$hliml_status, "ok")              # BFGS path routed
  expect_identical(fit$hliml_cf_status, "ok")
  expect_true(fit$hliml_cf_admissible)
  expect_lt(abs(fit$sigma_hliml - fit$sigma_hliml_cf) / fit$sigma_hliml_cf, 0.02)
  expect_lt(abs(fit$omega_hliml - fit$omega_hliml_cf) / fit$omega_hliml_cf, 0.05)
  expect_lte(fit$hliml_Q_cf, fit$hliml_Q + 1e-10)
})

test_that("default path is bit-identical to hliml_method = 'bfgs' and carries NA cf fields", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell(seed = 7L)
  f0 <- estimate_cell_liml(mom, ref_exporter = 1L)
  f1 <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "bfgs")
  expect_identical(f0, f1)
  expect_identical(f0$hliml_method, "bfgs")
  expect_true(is.na(f0$sigma_hliml_cf))
  expect_true(is.na(f0$hliml_Q_cf))
  expect_true(is.na(f0$hliml_cf_status))
  # and the routed numbers are untouched by the new fields
  for (nm in c("sigma", "omega", "rho", "adjust", "final_source", "hliml_status"))
    expect_identical(f0[[nm]], f1[[nm]])
})

test_that("'closed' mode routes on the closed form and returns HNCS SEs", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell()
  fb <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "both")
  fc <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "closed")
  expect_identical(fc$status, "ok")
  expect_identical(fc$hliml_status, "ok")
  expect_identical(fc$final_source, "hliml")
  expect_equal(fc$sigma_hliml, fb$sigma_hliml_cf, tolerance = 1e-12)
  expect_equal(fc$sigma, fb$sigma_hliml_cf, tolerance = 1e-12)
  expect_true(is.finite(fc$sigma_se)); expect_gt(fc$sigma_se, 0)
  expect_true(is.finite(fc$omega_se)); expect_gt(fc$omega_se, 0)
  # Step-2 fields are the same in both modes (Steps 1-2 untouched)
  expect_identical(fc$sigma_step2, fb$sigma_step2)
  expect_identical(fc$eta_step2, fb$eta_step2)
})

test_that("--stage1-hliml parses, defaults to bfgs, and rejects unknown values", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  data_dir <- file.path(tempdir(), paste0("fake_baci_cf_", sample.int(1e6, 1)))
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(data_dir, recursive = TRUE))
  opts <- parse_cli(args = c("--data", data_dir))
  expect_equal(opts$stage1_hliml, "bfgs")
  opts <- parse_cli(args = c("--data", data_dir, "--stage1-hliml", "both"))
  expect_equal(opts$stage1_hliml, "both")
  expect_error(parse_cli(args = c("--data", data_dir, "--stage1-hliml", "newton")),
               "stage1-hliml")
})

# ---- patch 0026: O(n) HNCS sandwich equals the dense sandwich ---------------

test_that("hncs_sandwich_se_groups reproduces the dense HNCS sandwich at the closed-form point", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  for (seed in c(20260819L, 11L)) {
    mom <- .cf_cell(seed = seed)
    Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)
    ex <- sort(unique(mom$exporter))
    Z <- sapply(ex, function(e) as.numeric(mom$exporter == e))
    P <- Z %*% solve(crossprod(Z), t(Z)); Pmd <- P; diag(Pmd) <- 0
    cf <- hliml_closed_form(Y, X, mom$exporter)
    e_hat <- as.numeric(Y - X %*% c(cf$theta0, cf$theta1, cf$theta2))
    dense <- hncs_sandwich_se(Y, X, Z, e_hat = e_hat, P = P, diag_P = diag(P),
                              P_minus_diag = Pmd, sigma = cf$sigma, omega = cf$omega, rho = cf$rho)
    grp   <- hncs_sandwich_se_groups(Y, X, mom$exporter, e_hat = e_hat,
                                     sigma = cf$sigma, omega = cf$omega, rho = cf$rho)
    expect_identical(dense$status, "ok"); expect_identical(grp$status, "ok")
    expect_equal(grp$alpha, dense$alpha, tolerance = 1e-9)
    expect_equal(grp$sigma_se, dense$sigma_se, tolerance = 1e-8)
    expect_equal(grp$omega_se, dense$omega_se, tolerance = 1e-8)
    expect_equal(grp$rho_se, dense$rho_se, tolerance = 1e-8)
    expect_equal(grp$F_het, dense$F_het, tolerance = 1e-9)
    expect_equal(grp$J_h, dense$J_h, tolerance = 1e-9)
    expect_equal(unname(grp$v_bar), unname(dense$v_bar), tolerance = 1e-8)
  }
})

test_that("'closed' mode never builds P and matches 'both' cf point with finite O(n) SEs", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell()
  # trace hliml_core: it must NOT be called in closed mode
  calls <- 0L
  trace_env <- environment(estimate_cell_liml)
  orig <- get("hliml_core", envir = trace_env)
  assign("hliml_core", function(...) { calls <<- calls + 1L; orig(...) }, envir = trace_env)
  on.exit(assign("hliml_core", orig, envir = trace_env), add = TRUE)
  fc <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "closed")
  expect_equal(calls, 0L)
  fb <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "both")
  expect_gte(calls, 1L)
  expect_identical(fc$final_source, "hliml")
  expect_equal(fc$sigma, fb$sigma_hliml_cf, tolerance = 1e-12)
  expect_true(is.finite(fc$sigma_se)); expect_true(is.finite(fc$fstat_het)); expect_true(is.finite(fc$jstat_h))
})

# ---- patch 0027: boundary (hybrid) search -----------------------------------

test_that("boundary search never beats the closed form on an admissible cell and is reported only when needed", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  mom <- .cf_cell()
  Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)
  cf <- hliml_closed_form(Y, X, mom$exporter)
  bd <- hliml_boundary_search(Y, X, mom$exporter)
  expect_identical(bd$status, "ok")
  expect_gte(bd$Q, cf$alpha - 1e-12)
  for (e in bd$edges) expect_gte(e$Q, cf$alpha - 1e-12)
  fb <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "both")
  expect_true(fb$hliml_cf_admissible)
  expect_true(is.na(fb$sigma_hliml_bd)); expect_true(is.na(fb$hliml_bd_edge))
})

test_that("boundary search rescues sigma on an all_inversions_failed cell (reported, not routed)", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  # seed 5005: both shipped inversions fail (status all_inversions_failed), the
  # closed form on the rescaled data inverts to eta1 <= 0, and the constrained
  # optimum sits on the omega floor with sigma near the truth of 3.
  mom <- simulate_one_cell(3, 0.003, J = 15L, T = 25L, seed = 5005L)
  f0 <- estimate_cell_liml(mom, ref_exporter = 1L)                        # shipped path
  fb <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "both")
  expect_identical(f0$status, "all_inversions_failed")
  expect_identical(fb$status, "all_inversions_failed")                    # routing untouched
  expect_identical(fb$hliml_cf_status, "ok")
  expect_false(isTRUE(fb$hliml_cf_admissible))
  expect_identical(fb$hliml_cf_inversion, "eta1_nonpositive")
  expect_identical(fb$hliml_bd_edge, "omega_floor")
  expect_true(fb$hliml_bd_usable)
  expect_equal(fb$omega_hliml_bd, 1e-4)
  expect_lt(abs(fb$sigma_hliml_bd - 3) / 3, 0.15)
  expect_gte(fb$hliml_Q_bd, fb$hliml_Q_cf - 1e-12)                      # boundary can't beat the unconstrained min
  # the default path carries none of it
  expect_true(is.null(f0$sigma_hliml_bd) || is.na(f0$sigma_hliml_bd))
})
