# ============================================================================
# test-eq11-signs.R
#
# Regression lock for the Eq. (11) sign correction (G1, v0.4.1).
#
# Soderbery (2018) Eq. (11) as PRINTED carries flipped signs on the x5
# (Dls_V * Dlp_V) and x6 (Dls_i * Dlp_V) coefficients relative to the
# product of the paper's own Eq. (8) and Eq. (9) residuals; see
# docs/methodology/eq11_sign_correction.md. Three locks here:
#
#   1. The export-side moment identity holds at truth under the CORRECTED
#      signs and fails under the printed signs (paper_exact_eq11 = TRUE),
#      on a DGP written directly from Eqs. (8)-(9).
#   2. paper_exact_eq11 = TRUE reproduces the pre-G1 objective value on a
#      frozen fixture, bit-for-bit (back-compat lock).
#   3. The pure-R reference and the Rcpp implementation agree in BOTH modes.
#
# The DGP never calls pipeline code to generate truth (same design rule as
# test-stage2-structural-dgp.R).
# ============================================================================

test_that("Eq. (11) corrected signs satisfy the moment identity; printed signs fail it", {
  cpp_dir <- locate_cpp_dir()
  env <- new.env()
  source(file.path(cpp_dir, "het_obj.R"), local = env)

  set.seed(41107)
  T_len <- 2e4
  sigma <- 3; sigma_V <- 4.5; gam_V <- 0.9
  gI <- c(0.4, 0.8, 1.5)
  gfun <- function(g) g / (1 + g)
  M <- length(gI)
  Y <- numeric(M); X <- matrix(0, M, 9)
  gV <- gfun(gam_V)
  for (m in seq_len(M)) {
    g_I   <- gfun(gI[m])
    dlp_V <- rnorm(T_len, 0, 0.4)
    dls_V <- 0.8 * dlp_V + rnorm(T_len, 0, 0.5)
    eps   <- rnorm(T_len, 0, 0.5)
    q     <- rnorm(T_len, 0, 0.4)
    dls_i <- ((1 + (sigma - 1) * gV) * dls_V + (sigma_V - sigma) * dlp_V -
                (sigma - 1) * q + eps) / (1 + (sigma - 1) * g_I)
    dlp_i <- dlp_V + g_I * dls_i - gV * dls_V + q
    Y[m]  <- mean((dlp_i - dlp_V)^2)
    X[m, ] <- c(mean(dls_i^2), mean(dls_i * dlp_i), mean(dls_V^2),
                mean(dls_V * dlp_i), mean(dls_V * dlp_V), mean(dls_i * dlp_V),
                mean(dls_i * dls_V), mean(dlp_V^2), mean(dlp_V * dlp_i))
  }

  d <- c(0.7, gI)  # gam_k placeholder + per-exporter gammas
  ratio <- function(paper_exact) {
    ssr <- env$het_obj(c(sigma, d),
                       numeric(0), matrix(0, 0, 5),
                       Y, X, seq_len(M) + 2L,
                       rep(sigma_V, M), rep(gam_V, M),
                       numeric(0), rep(1, M),
                       paper_exact_eq11 = paper_exact)
    sqrt(ssr / M) / mean(Y)
  }
  r_corrected <- ratio(FALSE)
  r_printed   <- ratio(TRUE)

  expect_lt(r_corrected, 0.05)          # MC noise at T = 2e4
  expect_gt(r_printed, 0.15)            # printed equation misses by scale
  expect_gt(r_printed / r_corrected, 5) # clear separation
})

test_that("paper_exact_eq11 = TRUE reproduces the pre-G1 objective bit-for-bit", {
  cpp_dir <- locate_cpp_dir()
  env <- new.env()
  source(file.path(cpp_dir, "het_obj.R"), local = env)

  # Frozen fixture: the seed-7 draw used throughout the v0.4.1 audit. The
  # locked value 5.991504119885 is the v0.4.0 (printed-sign) objective.
  set.seed(7); J <- 6
  imp_Y <- abs(rnorm(J)); imp_X <- matrix(rnorm(J * 5), J, 5)
  exp_Y <- abs(rnorm(3)); exp_X <- matrix(rnorm(3 * 9), 3, 9)
  exp_jmap <- c(2L, 4L, 5L)
  exp_sig_V <- c(4.0, 3.8, 4.2); exp_gam_V <- c(1.1, 0.9, 1.3)
  wt_imp <- runif(J); wt_exp <- runif(3)
  sig <- 3.2; gam <- runif(J + 1, 0.3, 2)

  v_pe  <- env$het_obj(c(sig, gam), imp_Y, imp_X, exp_Y, exp_X, exp_jmap,
                       exp_sig_V, exp_gam_V, wt_imp, wt_exp,
                       paper_exact_eq11 = TRUE)
  v_new <- env$het_obj(c(sig, gam), imp_Y, imp_X, exp_Y, exp_X, exp_jmap,
                       exp_sig_V, exp_gam_V, wt_imp, wt_exp)

  expect_equal(v_pe, 5.991504119885, tolerance = 1e-10)
  expect_gt(abs(v_new - v_pe), 1e-6)   # the default really changed
})

test_that("pure-R and Rcpp objectives agree in both sign modes", {
  skip_if_not_installed("Rcpp")
  cpp_dir <- locate_cpp_dir()
  env <- new.env()
  source(file.path(cpp_dir, "het_obj.R"), local = env)
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_rcpp.cpp"),
                  env = env)

  set.seed(7); J <- 6
  imp_Y <- abs(rnorm(J)); imp_X <- matrix(rnorm(J * 5), J, 5)
  exp_Y <- abs(rnorm(3)); exp_X <- matrix(rnorm(3 * 9), 3, 9)
  exp_jmap <- c(2L, 4L, 5L)
  exp_sig_V <- c(4.0, 3.8, 4.2); exp_gam_V <- c(1.1, 0.9, 1.3)
  wt_imp <- runif(J); wt_exp <- runif(3)
  sig <- 3.2; gam <- runif(J + 1, 0.3, 2)

  for (pe in c(FALSE, TRUE)) {
    v_r <- env$het_obj(c(sig, gam), imp_Y, imp_X, exp_Y, exp_X, exp_jmap,
                       exp_sig_V, exp_gam_V, wt_imp, wt_exp,
                       paper_exact_eq11 = pe)
    v_c <- env$het_obj_fixed_sigma_rcpp(gam, sig, imp_Y, imp_X, exp_Y, exp_X,
                                        exp_jmap, exp_sig_V, exp_gam_V,
                                        wt_imp, wt_exp, NA_real_, 0, pe)
    expect_equal(v_r, v_c, tolerance = 1e-12,
                 label = sprintf("paper_exact_eq11 = %s", pe))
  }
})
