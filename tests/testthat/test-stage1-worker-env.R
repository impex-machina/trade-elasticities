# ============================================================================
# test-stage1-worker-env.R  (patch 0039)
#
# Locks the Stage 1 PSOCK worker environment.
#
# Background (2026-08-20 fresh-eyes audit): run_stage1_liml()'s Windows
# PSOCK branch sourced only liml_estimator.R on workers, but under the
# default hliml_method = "closed" the boundary-routing site inside
# estimate_cell_liml() calls boundary_flags(), which lives in
# utils_general.R. On Windows with n_cores > 1 every boundary-routable cell
# therefore silently became an est_error row (the per-cell tryCatch
# swallowed the "could not find function" error). The Linux fork path
# inherits master memory and never hit it.
#
# PSOCK clusters run on every OS, so this test drives the EXACT production
# bootstrap (stage1_psock_bootstrap(), extracted by patch 0039 precisely so
# it is testable) on a 1-worker PSOCK cluster and pushes a seeded
# boundary-routed cell through estimate_cell_liml() inside the worker:
#
#   1. after bootstrap, the worker has estimate_cell_liml, boundary_flags,
#      and calendar_lag defined;
#   2. a cell known to route final_source == "hliml_boundary" (canonical
#      DGP, seed 300002) estimates identically on the worker and on the
#      master -- the call shape that crashed pre-0039.
#
# Runtime: ~5-10s (one PSOCK spawn + two file sources on the worker).
# ============================================================================

test_that("stage1_psock_bootstrap provisions a worker that can route boundary cells", {
  skip_if_not_installed("parallel")

  root <- dirname(locate_source_dir())
  r_dir <- file.path(root, "R")

  # Master-side environment (mirrors what run_stage1_liml has in scope).
  source(file.path(r_dir, "hs_codes.R"), local = TRUE)
  source(file.path(r_dir, "utils_general.R"), local = TRUE)
  source(file.path(r_dir, "liml_estimator.R"), local = TRUE)
  source(file.path(r_dir, "stage1_liml_wrapper.R"), local = TRUE)
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)

  cl <- parallel::makePSOCKcluster(1L)
  on.exit(parallel::stopCluster(cl), add = TRUE)

  # The production bootstrap, verbatim.
  stage1_psock_bootstrap(cl, r_dir)

  # 1. Environment completeness. boundary_flags is the symbol whose absence
  #    caused the pre-0039 failure; the other two guard the rest of the
  #    utils_general surface the estimator touches.
  have <- parallel::clusterEvalQ(cl, c(
    estimate_cell_liml = exists("estimate_cell_liml", mode = "function"),
    boundary_flags     = exists("boundary_flags",     mode = "function"),
    calendar_lag       = exists("calendar_lag",       mode = "function")
  ))[[1]]
  expect_true(all(have), info = paste("missing on worker:",
                                      paste(names(have)[!have], collapse = ", ")))

  # 2. A boundary-routed cell estimates on the worker. Seed 300002 under the
  #    canonical harness DGP routes omega_floor / adjust 6 (verified against
  #    the post-0038 edge scan).
  mom <- simulate_one_cell(sigma_true = 6, omega_true = 0.01,
                           J = 5, T = 6, seed = 300002L)
  parallel::clusterExport(cl, "mom", envir = environment())
  worker_fit <- parallel::clusterEvalQ(cl,
    estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "closed")
  )[[1]]

  expect_identical(worker_fit$status, "ok")
  expect_identical(worker_fit$final_source, "hliml_boundary")
  expect_identical(worker_fit$hliml_boundary_edge, "omega_floor")
  expect_identical(worker_fit$adjust, 6L)

  master_fit <- estimate_cell_liml(mom, ref_exporter = 1L,
                                   hliml_method = "closed")
  expect_equal(worker_fit$sigma, master_fit$sigma, tolerance = 1e-12)
  expect_equal(worker_fit$omega, master_fit$omega, tolerance = 1e-12)
})
