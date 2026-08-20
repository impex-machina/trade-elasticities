# Patch 0033: value-based cap flags for boundary-search optima.
# Corners: hliml_boundary_search() optimizes 1-D ALONG an edge, so the free
# parameter can land within optimize() tolerance of its own cap. The flags
# must record the value state (route stays in hliml_boundary_edge).

test_that("pure edges flag only their own wall", {
  b <- boundary_flags("sigma_cap", 10, 0.42, 10, 10)
  expect_true(b$sigma_capped)
  expect_false(b$omega_capped)
  b <- boundary_flags("omega_floor", 3.1, 1e-4, 10, 10)
  expect_false(b$sigma_capped)
  expect_false(b$omega_capped)
})

test_that("sigma corners on omega edges set sigma_capped", {
  # optimize() lands within tol of the cap, never exactly on it
  b <- boundary_flags("omega_floor", 10 - 1e-6, 1e-4, 10, 10)
  expect_true(b$sigma_capped)
  b <- boundary_flags("omega_cap", 9.9995, 10, 10, 10)
  expect_true(b$sigma_capped)
  expect_true(b$omega_capped)   # the (sigma_cap, omega_cap) double corner
})

test_that("omega corner on the sigma_cap edge sets omega_capped", {
  b <- boundary_flags("sigma_cap", 10, 10 - 5e-4, 10, 10)
  expect_true(b$omega_capped)
})

test_that("interior values below tolerance never flag", {
  b <- boundary_flags("omega_floor", 10 - 0.01, 5, 10, 10)
  expect_false(b$sigma_capped)
  expect_false(b$omega_capped)
})

test_that("NA values do not flag and do not error", {
  b <- boundary_flags("omega_floor", NA_real_, NA_real_, 10, 10)
  expect_false(b$sigma_capped)
})
