# ============================================================================
# test-empty-side-guards.R
#
# G6 (v0.4.1 hotfix). The validation harness (stage2_structural_dgp.R,
# Test D) evaluates the production objective with an EMPTY import block
# (export-only residuals). Before G6 the Rcpp objectives' import loops were
# bounded by the parameter count (J from d) rather than the row count, so
# that call pattern read imp_Y / imp_X / wt_imp out of bounds -- benign on
# Linux heaps, a silent access-violation death on Windows Rtools. These
# tests lock the guarded behaviour on every objective entry point:
#
#   - empty import side: Rcpp == pure-R == export-only SSR, finite;
#   - both sides empty: exactly 0;
#   - more import rows than gamma parameters: loud error, not UB.
# ============================================================================

test_that("Rcpp objectives handle an empty import block (export-only calls)", {
  skip_if_not_installed("Rcpp")
  cpp_dir <- locate_cpp_dir()
  env <- new.env()
  source(file.path(cpp_dir, "het_obj.R"), local = env)
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_rcpp.cpp"), env = env)
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_rcpp.cpp"), env = env)

  set.seed(9)
  M <- 4L
  exp_Y <- abs(rnorm(M)); exp_X <- matrix(rnorm(M * 9), M, 9)
  exp_jmap <- seq_len(M) + 2L
  sV <- rep(4, M); gV <- rep(0.9, M); wt <- rep(1, M)
  d_fs <- c(0.7, runif(8, 0.3, 2))     # fixed-sigma: (gam_k, gam_j...)
  sig <- 3.2

  v_r <- env$het_obj(c(sig, d_fs), numeric(0), matrix(0, 0, 5),
                     exp_Y, exp_X, exp_jmap, sV, gV, numeric(0), wt)
  v_fs <- env$het_obj_fixed_sigma_rcpp(d_fs, sig, numeric(0), matrix(0, 0, 5),
                                       exp_Y, exp_X, exp_jmap, sV, gV,
                                       numeric(0), wt, NA_real_, 0)
  v_full <- env$het_obj_rcpp(c(sig, d_fs), numeric(0), matrix(0, 0, 5),
                             exp_Y, exp_X, exp_jmap, sV, gV, numeric(0), wt)

  expect_true(is.finite(v_fs))
  expect_equal(v_fs, v_r, tolerance = 1e-12)
  expect_equal(v_full, v_r, tolerance = 1e-12)
})

test_that("both sides empty returns exactly zero", {
  skip_if_not_installed("Rcpp")
  cpp_dir <- locate_cpp_dir()
  env <- new.env()
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_rcpp.cpp"), env = env)
  v0 <- env$het_obj_fixed_sigma_rcpp(c(0.7, 0.5), 3.2,
                                     numeric(0), matrix(0, 0, 5),
                                     numeric(0), matrix(0, 0, 9), integer(0),
                                     numeric(0), numeric(0),
                                     numeric(0), numeric(0), NA_real_, 0)
  expect_identical(v0, 0)
})

test_that("more import rows than gamma parameters errors loudly", {
  skip_if_not_installed("Rcpp")
  cpp_dir <- locate_cpp_dir()
  env <- new.env()
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_rcpp.cpp"), env = env)
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_jacobian_rcpp.cpp"),
                  env = env)
  expect_error(
    env$het_obj_fixed_sigma_rcpp(runif(3), 3.2,
                                 rnorm(5), matrix(rnorm(25), 5, 5),
                                 numeric(0), matrix(0, 0, 9), integer(0),
                                 numeric(0), numeric(0),
                                 rep(1, 5), numeric(0), NA_real_, 0),
    "more rows than gamma parameters")
  expect_error(
    env$het_residuals_and_jacobian_fixed_sigma_rcpp(
      runif(3), 3.2, rnorm(5), matrix(rnorm(25), 5, 5),
      numeric(0), matrix(0, 0, 9), integer(0),
      numeric(0), numeric(0), rep(1, 5), numeric(0)),
    "more rows than gamma parameters")
})
