# ============================================================================
# test-stage1-harness-dgp.R
#
# Regression lock for the Pillar-2 harness DGP (validation/validate_liml.R,
# simulate_one_cell). Added in v0.4.0 after finding F10: the harness wrote
# the supply side with slope 1/omega instead of (1+omega)/omega, so its
# simulated system equaled the correct structural model at
# omega = omega_true/(1-omega_true) -- the omega truth-labels were wrong
# (sigma labels were asymptotically unaffected). This test pins the
# harness's implied second moments to the Feenstra (1994) moment identity
# AT THE LABELED TRUTH, so any drift in the DGP's structural conventions
# fails loudly. Negative controls prove the test has power, including one
# at exactly the pre-fix mislabel omega/(1+omega).
# ============================================================================

test_that("harness DGP satisfies the Feenstra moment identity at its labels", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)

  sigma_true <- 3.0
  omega_true <- 0.7
  mom <- simulate_one_cell(sigma_true, omega_true, J = 6L, T = 8000L,
                           sd_meas = 0, seed = 20260718L)

  # Exporter-level sample moments (means of the per-period contributions).
  Vp <- tapply(mom$y,  mom$exporter, mean)
  Vs <- tapply(mom$x1, mom$exporter, mean)
  Cv <- tapply(mom$x2, mom$exporter, mean)

  # Median relative violation of Var(p) = theta1*Var(s) + theta2*Cov at (s, w).
  resid <- function(s, w) {
    th1 <- w / ((1 + w) * (s - 1))
    th2 <- (w * (s - 2) - 1) / ((1 + w) * (s - 1))
    median(abs(Vp - th1 * Vs - th2 * Cv) / Vp)
  }

  # 1. Identity holds at the labeled truth (sampling noise only).
  expect_lt(resid(sigma_true, omega_true), 0.05)

  # 2. Power: the pre-fix mislabel omega/(1+omega) must violate it loudly.
  expect_gt(resid(sigma_true, omega_true / (1 + omega_true)), 0.08)

  # 3. Power on the demand side.
  expect_gt(resid(sigma_true * 1.3, omega_true), 0.10)
})
