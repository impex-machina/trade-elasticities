# ============================================================================
# test-feenstra-homogeneity-limit.R
#
# Regression lock for the optional Feenstra (1994) Stage-1 objective
# (R/estimate_stage1_feenstra.R), F1-aligned in the post-v0.4.1 audit.
#
# The legacy path is NOT production Stage 1 (that is HLIML), but it must
# agree with the production Eq. (10) objective in the homogeneity limit
# gamma_j = gamma_k -- otherwise the repo carries two inconsistent
# statements of the same moment condition. Three locks:
#
#   1. feenstra_sigma_obj equals the production het_obj (src/het_obj.R)
#      evaluated at gamma_j = gamma_k = gamma with an empty export side,
#      for arbitrary Y -- i.e. the two objectives share predictions.
#   2. In that limit the objective collapses to Feenstra (1994)'s
#      two-regressor form: Y = theta1*X1 + theta2*X2 with
#        theta1 = gamma / ((1+gamma)(sigma-1))
#        theta2 = (gamma(sigma-1) - (1+gamma)) / ((1+gamma)(sigma-1))
#      equivalently theta1 = rho/((1-rho)(sigma-1)^2),
#      theta2 = (2rho-1)/((1-rho)(sigma-1)) under
#      rho = gamma(sigma-1)/(1+gamma*sigma). Zero residual at that Y.
#   3. The pre-F1 term-4 coefficient (g_frac^2/(sigma-1), the homogeneity
#      limit of the transcription error corrected in v0.4.0) does NOT
#      satisfy the collapse -- the permanent negative control.
#
# Regressors are constructed from underlying share/price differences the
# same way estimate_feenstra_sigma_cell builds them, so the algebraic
# relation x2 = x3 - x4 (Dk_lp = lp_dif - ref_lp_dif) holds by
# construction, as it does on real data.
# ============================================================================

make_design <- function(J, seed) {
  set.seed(seed)
  Dk_ls   <- rnorm(J)
  lp_dif  <- rnorm(J)
  ref_lp  <- rnorm(J)
  Dk_lp   <- lp_dif - ref_lp
  cbind(x1 = Dk_ls^2,
        x2 = Dk_ls * Dk_lp,
        x3 = Dk_ls * lp_dif,
        x4 = Dk_ls * ref_lp,
        x5 = Dk_lp * ref_lp)
}

param_grid <- expand.grid(sigma = c(1.5, 2, 3, 5, 8),
                          gamma = c(0.1, 0.5, 1, 2, 5))

test_that("feenstra_sigma_obj is the exact homogeneity limit of Eq. (10)", {
  src <- locate_source_dir()
  cpp_dir <- locate_cpp_dir()

  feen_env <- new.env()
  source(file.path(src, "estimate_stage1_feenstra.R"), local = feen_env)
  het_env <- new.env()
  source(file.path(cpp_dir, "het_obj.R"), local = het_env)

  J  <- 8L
  X  <- make_design(J, seed = 20260725L)
  wt <- runif(J, 0.5, 2)

  empty_exp <- list(exp_Y = numeric(0),
                    exp_X = matrix(numeric(0), nrow = 0, ncol = 9),
                    exp_jmap = integer(0),
                    exp_sig_V = numeric(0),
                    exp_gam_V = numeric(0),
                    wt_exp = numeric(0))

  for (i in seq_len(nrow(param_grid))) {
    sig <- param_grid$sigma[i]
    gam <- param_grid$gamma[i]
    for (draw in 1:2) {
      Y <- rnorm(J, sd = 2)
      obj_feen <- feen_env$feenstra_sigma_obj(c(sig, gam), Y, X, wt)
      obj_het  <- het_env$het_obj(
        d = c(sig, gam, rep(gam, J)),
        imp_Y = Y, imp_X = X,
        exp_Y = empty_exp$exp_Y, exp_X = empty_exp$exp_X,
        exp_jmap = empty_exp$exp_jmap,
        exp_sig_V = empty_exp$exp_sig_V,
        exp_gam_V = empty_exp$exp_gam_V,
        wt_imp = wt, wt_exp = empty_exp$wt_exp)
      expect_equal(obj_feen, obj_het, tolerance = 1e-12,
                   info = sprintf("sigma=%.1f gamma=%.1f draw=%d",
                                  sig, gam, draw))
    }
  }
})

test_that("the homogeneity limit collapses to Feenstra (1994)'s two-regressor form", {
  src <- locate_source_dir()
  feen_env <- new.env()
  source(file.path(src, "estimate_stage1_feenstra.R"), local = feen_env)

  J  <- 8L
  X  <- make_design(J, seed = 20260726L)
  wt <- runif(J, 0.5, 2)

  for (i in seq_len(nrow(param_grid))) {
    sig <- param_grid$sigma[i]
    gam <- param_grid$gamma[i]
    sm1 <- sig - 1

    theta1 <- gam / ((1 + gam) * sm1)
    theta2 <- (gam * sm1 - (1 + gam)) / ((1 + gam) * sm1)

    # Same coefficients via Feenstra's rho parameterization.
    rho <- gam * sm1 / (1 + gam * sig)
    expect_equal(theta1, rho / ((1 - rho) * sm1^2), tolerance = 1e-12)
    expect_equal(theta2, (2 * rho - 1) / ((1 - rho) * sm1), tolerance = 1e-12)

    Y_star <- theta1 * X[, "x1"] + theta2 * X[, "x2"]
    obj <- feen_env$feenstra_sigma_obj(c(sig, gam), Y_star, X, wt)
    scale <- max(1, sum(wt * Y_star^2))
    expect_lt(obj, 1e-20 * scale)
  }
})

test_that("the pre-F1 term-4 coefficient fails the collapse (negative control)", {
  J  <- 8L
  X  <- make_design(J, seed = 20260727L)
  wt <- runif(J, 0.5, 2)

  # The pre-F1 objective, frozen inline: term 4 carried g_frac^2/sm1,
  # the homogeneity limit of gam_j*gam_k/((1+gam_j)(1+gam_k)(sigma-1)).
  pre_f1_obj <- function(d, Y, X, wt) {
    sig <- d[1]; gam <- d[2]
    sm1 <- sig - 1; g_frac <- gam / (1 + gam)
    pred <- (g_frac / sm1)   * X[, 1] +
            g_frac           * X[, 2] +
            (-1 / sm1)       * X[, 3] +
            (g_frac^2 / sm1) * X[, 4]
    sum(wt * (Y - pred)^2)
  }

  for (i in seq_len(nrow(param_grid))) {
    sig <- param_grid$sigma[i]
    gam <- param_grid$gamma[i]
    sm1 <- sig - 1
    theta1 <- gam / ((1 + gam) * sm1)
    theta2 <- (gam * sm1 - (1 + gam)) / ((1 + gam) * sm1)
    Y_star <- theta1 * X[, "x1"] + theta2 * X[, "x2"]
    scale  <- max(1, sum(wt * Y_star^2))
    # Coefficient gap on x4 is (1 - g_frac^2)/sm1 > 0 for finite gamma,
    # so the pre-F1 form leaves an O(1) residual at the collapse point.
    expect_gt(pre_f1_obj(c(sig, gam), Y_star, X, wt), 1e-6 * scale)
  }
})
