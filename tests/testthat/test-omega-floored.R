# ============================================================================
# test-omega-floored.R
#
# B3 -- the omega_floored flag on the Stage 1 output.
#
# invert_structural() clamps the export-supply parameter omega up to its lower
# admissibility floor (omega_floor = 1e-4) whenever the raw inversion lands at
# or below it. That includes the inadmissible region where the omega
# denominator (sigma - 1 - sigma*rho) turns negative and omega would itself be
# negative; invert_structural also returns status = "constraint_violated"
# there. Critically the floor is applied BEFORE the feasibility-adjustment
# block in estimate_cell_liml() assigns `adjust`: a floored omega is still
# > 0, so it passes the HLIML admissibility check and the cell reads downstream
# as a clean adjust-0/1 solution. The omega_floored boolean -- set in the
# estimator's success return and carried through the Stage 1 output row --
# makes the floored cells (~17% of all cells, ~32% of estimated cells) filterable.
#
# Scope: these tests pin (a) the floor mechanism in the real invert_structural
# and (b) the exact predicate the estimator uses to set omega_floored. The
# wrapper copies the value through unchanged
# (omega_floored = isTRUE(fit$omega_floored)).
# ============================================================================

# Identical to the predicate in liml_estimator.R's success return; kept in sync
# here so a change to the floor sentinel (1e-4) is caught by these tests.
.omega_floored_predicate <- function(omega) isTRUE(!is.na(omega) && omega <= 1e-4)

test_that("an inadmissible inversion floors omega and the flag fires", {
  src <- locate_source_dir()
  source(file.path(src, "liml_estimator.R"), local = TRUE)

  # (eta_1, eta_2) = (10, 100): rho is driven to the 0.999 ceiling, the omega
  # denominator (sigma - 1 - sigma*rho) goes negative, so the raw omega is
  # negative and is clamped up to the 1e-4 floor; the Feenstra feasibility
  # check rho < (sigma-1)/sigma fails.
  r <- invert_structural(eta_1 = 10, eta_2 = 100)

  expect_equal(r$status, "constraint_violated")
  expect_equal(r$omega, 1e-4)                  # clamped exactly to the floor
  expect_gt(r$sigma, 1)                         # sigma itself is unremarkable
  expect_true(.omega_floored_predicate(r$omega))
})

test_that("a feasible interior solution is not flagged", {
  src <- locate_source_dir()
  source(file.path(src, "liml_estimator.R"), local = TRUE)

  # (eta_1, eta_2) = (0.1154, -0.2692) recovers sigma ~ 3.0, omega ~ 0.30,
  # an admissible interior point well above the floor.
  r <- invert_structural(eta_1 = 0.1154, eta_2 = -0.2692)

  expect_equal(r$status, "ok")
  expect_gt(r$omega, 1e-4)                      # genuine interior estimate
  expect_false(.omega_floored_predicate(r$omega))
})

test_that("the flag is FALSE, not NA, for a failed inversion", {
  # Failed inversions report omega = NA; the flag must collapse to FALSE so the
  # output column stays a clean logical with no NA contamination.
  expect_false(.omega_floored_predicate(NA_real_))
})
