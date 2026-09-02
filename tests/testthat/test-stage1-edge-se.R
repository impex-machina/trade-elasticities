# ============================================================================
# test-stage1-edge-se.R  (patch 0049)
#
# SEs for constrained boundary (edge) optima: the HNCS sandwich projected
# onto the edge tangent through the reparameterisation theta = theta(theta0, t),
# with the pinned coordinate reported NA. Locks:
#   1. hncs_parts_groups() refactor leaves hncs_sandwich_se_groups() bit-
#      identical (interior SEs unchanged) -- compared against an inline
#      re-implementation of the pre-0049 arithmetic.
#   2. hncs_edge_se_groups(): the Jacobian columns match finite differences
#      of theta12(); on the omega edges sigma_se is finite and omega_se NA,
#      on the sigma_cap edge the reverse; rho_se follows the stated delta
#      rule; an unsupported edge and a non-PD projected curvature return
#      a status, never a number.
#   3. estimate_cell_liml(edge_se = "hncs") changes ONLY the three SE fields
#      and the two provenance fields on a boundary-routed cell; the default
#      "none" is bit-identical to v0.7.0; interior cells are untouched by
#      either setting.
#   4. wrapper column + CLI flag + config validation.
# ============================================================================

.es_cell <- function(sigma, omega, J, T, seed) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  simulate_one_cell(sigma, omega, J = J, T = T, seed = seed)
}
.es_source <- function(env) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = env)
  source(file.path(root, "R", "utils_general.R"), local = env)
  source(file.path(root, "R", "liml_estimator.R"), local = env)
}

test_that("hncs_parts_groups refactor leaves the interior sandwich bit-identical", {
  .es_source(environment())
  m <- .es_cell(3, 1, 20L, 40L, seed = 20260819L)
  d <- m[complete.cases(m), ]
  Y <- d$y; X <- cbind(1, d$x1, d$x2); grp <- d$exporter
  cf <- hliml_closed_form(Y, X, grp)
  e_hat <- as.numeric(Y - X %*% c(cf$theta0, cf$theta1, cf$theta2))
  new <- hncs_sandwich_se_groups(Y, X, grp, e_hat, cf$sigma, cf$omega, cf$rho, alpha = cf$alpha)
  # pre-0049 arithmetic, inline
  g <- as.integer(factor(grp)); n_g <- tabulate(g); l <- length(n_g)
  gm <- hliml_group_moments(Y, X, grp)
  H_bar <- gm$XcPdXc[-1, -1, drop = FALSE] - cf$alpha * gm$XcXc[-1, -1, drop = FALSE]
  ee <- sum(e_hat^2); eX <- as.numeric(crossprod(e_hat, X))
  X_bar <- X - outer(e_hat, eX / ee)
  PXb <- (rowsum(X_bar, g, reorder = TRUE) / n_g)[g, , drop = FALSE]
  e2 <- e_hat^2
  term1 <- crossprod(PXb, e2 * PXb); term2a <- crossprod(X_bar, (e2 / n_g[g]) * PXb)
  m_g <- rowsum(e_hat * X_bar, g, reorder = TRUE)
  sigma_bar <- term1 - term2a - t(term2a) + crossprod(m_g / n_g)
  v_bar <- solve(H_bar) %*% sigma_bar %*% solve(H_bar)
  expect_identical(new$status, "ok")
  expect_identical(new$v_bar, v_bar)
  expect_true(is.finite(new$sigma_se) && new$sigma_se > 0)
})

test_that("hncs_edge_se_groups: Jacobian, edge mapping, and failure statuses", {
  .es_source(environment())
  theta12 <- function(s, w) { d <- (1 + w) * (s - 1); c(w / d, (w * (s - 2) - 1) / d) }
  s <- 3; w <- 10; h <- 1e-6
  expect_equal((theta12(s + h, w) - theta12(s - h, w)) / (2 * h),
               c(-w / ((1 + w) * (s - 1)^2), 1 / (s - 1)^2), tolerance = 1e-6)
  expect_equal((theta12(s, w + h) - theta12(s, w - h)) / (2 * h),
               c(1 / ((1 + w)^2 * (s - 1)), 1 / (1 + w)^2), tolerance = 1e-6)
  # a real cap-edge cell
  m <- .es_cell(2, 0.01, 10L, 15L, seed = 91043L)
  f <- estimate_cell_liml(m, hliml_method = "closed", edge_se = "hncs")
  expect_identical(f$hliml_boundary_edge, "omega_cap"); expect_identical(f$edge_se_status, "ok")
  expect_true(is.finite(f$sigma_se) && f$sigma_se > 0)
  expect_true(is.na(f$omega_se))                                     # pinned coordinate
  expect_equal(f$rho_se, f$omega * (1 + f$omega) / (1 + f$sigma * f$omega)^2 * f$sigma_se)
  # direct call: unsupported edge and a degenerate (NaN-curvature) input
  d <- m[complete.cases(m), ]; Y <- d$y; X <- cbind(1, d$x1, d$x2)
  e_hat <- rep(0, length(Y))
  expect_identical(hncs_edge_se_groups(Y, X, d$exporter, e_hat, 2, 10, "sigma_floor", alpha = -0.01)$status,
                   "edge_se_unsupported_edge")
  expect_identical(hncs_edge_se_groups(Y, X, d$exporter, e_hat, 2, 10, "omega_cap", alpha = -0.01)$status,
                   "hncs_fail_zero_residuals")
  # sigma_cap edge: omega_se finite, sigma_se NA, rho rule
  m2 <- .es_cell(10, 1, 10L, 15L, seed = 87028L)
  f2 <- estimate_cell_liml(m2, hliml_method = "closed", edge_se = "hncs")
  expect_identical(f2$hliml_boundary_edge, "sigma_cap"); expect_identical(f2$edge_se_status, "ok")
  expect_true(is.finite(f2$omega_se) && f2$omega_se > 0); expect_true(is.na(f2$sigma_se))
  expect_equal(f2$rho_se, (f2$sigma - 1) / (1 + f2$sigma * f2$omega)^2 * f2$omega_se)
})

test_that("edge_se changes only SE and provenance fields; default none is bit-identical; interior untouched", {
  .es_source(environment())
  m <- .es_cell(2, 0.01, 10L, 15L, seed = 91051L)
  f0 <- estimate_cell_liml(m, hliml_method = "closed")
  fn <- estimate_cell_liml(m, hliml_method = "closed", edge_se = "none")
  fh <- estimate_cell_liml(m, hliml_method = "closed", edge_se = "hncs")
  expect_identical(f0, fn); expect_identical(f0$edge_se_method, "none"); expect_true(is.na(f0$edge_se_status))
  expect_identical(fh$final_source, "hliml_boundary"); expect_identical(fh$edge_se_method, "hncs")
  expect_true(is.na(f0$sigma_se)); expect_true(is.finite(fh$sigma_se))
  strip <- function(x) { x[c("sigma_se", "omega_se", "rho_se", "edge_se_method", "edge_se_status")] <- NULL; x }
  expect_identical(strip(f0), strip(fh))
  mi <- .es_cell(3, 1, 20L, 40L, seed = 20260819L)
  a <- estimate_cell_liml(mi, ref_exporter = 1L); b <- estimate_cell_liml(mi, ref_exporter = 1L, edge_se = "hncs")
  expect_identical(a$final_source, "hliml")
  a$edge_se_method <- NULL; b$edge_se_method <- NULL
  expect_identical(a, b)                                            # interior SEs unchanged under either rule
})

test_that("wrapper column, CLI flag and config validation", {
  suppressPackageStartupMessages(library(data.table))
  .es_source(environment())
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  set.seed(1L)
  raw <- data.table::data.table(importer = 1L, good = "0202",
    exporter = rep(1:6, each = 12L), t = rep(1995:2006, 6L),
    value = exp(rnorm(72)), quantity = exp(rnorm(72)))
  tmp <- tempfile(fileext = ".rds")
  out <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                         min_periods = 3L, verbose = FALSE, edge_se = "hncs")
  expect_true(all(c("edge_se_method", "edge_se_status") %in% names(out)))
  expect_true(all(out$edge_se_method[!is.na(out$hliml_method)] == "hncs"))
  out0 <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                          min_periods = 3L, verbose = FALSE)
  expect_true(all(out0$edge_se_method[!is.na(out0$hliml_method)] == "none"))
  unlink(tmp)
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  source(file.path(root, "R", "validate_config.R"), local = TRUE)
  dd <- tempfile(); dir.create(dd)
  o0 <- parse_cli(c("--data", dd)); expect_identical(o0$stage1_edge_se, "none")
  expect_identical(build_config(o0)$stage1_edge_se, "none")
  o1 <- parse_cli(c("--data", dd, "--stage1-edge-se", "hncs")); expect_identical(o1$stage1_edge_se, "hncs")
  expect_error(parse_cli(c("--data", dd, "--stage1-edge-se", "bootstrap")), "stage1-edge-se")
  cfg <- build_config(o1); cfg$stage1_edge_se <- "bootstrap"
  expect_error(validate_config(cfg), "stage1_edge_se")
  unlink(dd, recursive = TRUE)
})
