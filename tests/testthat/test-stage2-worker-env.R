# ============================================================================
# test-stage2-worker-env.R  (patch 0040)
#
# Locks the Stage 2 (fixed-sigma) PSOCK worker environment.
#
# Background (2026-08-20 fresh-eyes audit): the Windows branch of
# estimate_all_fixed_sigma() had two provisioning defects, unexercised in
# production (EC2 uses the Linux fork path; the e2e test runs ncores = 1):
#
#   1. worker_fns lacked compute_penalized_gn_se() and
#      het_grad_fixed_sigma() -- the SE pipeline could not run on workers.
#   2. The worker Rcpp bootstrap compiled the objectives by bare filename,
#      dead since the .cpp files moved to src/ (2026-05 refactor); workers
#      then fell back to master-exported compiled functions whose external
#      pointers do not survive PSOCK serialization, and the Jacobian .cpp
#      was never compiled on workers at all (gamma_se would be all-NA even
#      if the objectives had worked).
#
# Patch 0040 moves the export list to the top-level constant
# stage2_worker_fns and the whole bootstrap into stage2_psock_provision(),
# which reuses load_rcpp_objectives() with an explicit cpp_dir so workers
# compile their own local objectives. PSOCK clusters run on every OS, so
# this test drives the EXACT production helper on a 1-worker cluster:
#
#   1. after provisioning, the worker has the fixed-sigma AND Jacobian
#      Rcpp objectives compiled locally, plus compute_penalized_gn_se and
#      het_grad_fixed_sigma defined;
#   2. estimate_product_fixed_sigma() runs to completion INSIDE the worker
#      on the synthetic fixture and populates a finite gamma_se for at
#      least one converged row (the assertion defect 1+2 would fail);
#   3. worker results match a master-side run of the same products.
#
# Runtime: ~40-70s on first run — the worker session compiles the three
# .cpp files from scratch (sourceCpp caches are per-session). This is the
# price of certifying the worker environment for real; do not stub it.
# ============================================================================

test_that("stage2_psock_provision equips a worker for the full fixed-sigma cell path", {
  skip_if_not_installed("parallel")

  src_dir <- locate_source_dir()
  cpp_dir <- locate_cpp_dir()
  assert_cpp_files_present(cpp_dir)

  # Master-side library, exactly as test-stage2b-e2e.R loads it (global,
  # so the provision helper's lexical lookups resolve the same way they
  # do in production).
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(src_dir)
  sink_file <- tempfile(fileext = ".log")
  sink(sink_file)
  loaded <- tryCatch({ source(file.path(src_dir, "feen94_het_baci.R"),
                              local = FALSE); TRUE },
                     error = function(e) e)
  sink()
  if (!isTRUE(loaded)) fail(paste("library load failed:",
                                  conditionMessage(loaded)))

  synth_dt <- make_synthetic_baci(seed = 42L)
  cfg      <- make_synthetic_cfg()
  products <- unique(synth_dt$good)

  cl <- parallel::makePSOCKcluster(1L)
  on.exit(parallel::stopCluster(cl), add = TRUE)

  # The production provisioning, verbatim (worker_fns defaults to
  # stage2_worker_fns; names resolve through this frame up to the global
  # environment where the wrapper installed them).
  stage2_psock_provision(cl, cpp_dir, env = environment())

  # 1. Environment completeness on the worker.
  have <- parallel::clusterEvalQ(cl, c(
    fs_rcpp  = isTRUE(.het_obj_fs_rcpp_loaded),
    jac_rcpp = isTRUE(.het_jac_rcpp_loaded),
    gn_se    = exists("compute_penalized_gn_se", mode = "function"),
    grad     = exists("het_grad_fixed_sigma",    mode = "function"),
    tiers    = exists("classify_exporter_tiers", mode = "function")
  ))[[1]]
  expect_true(all(have), info = paste("missing on worker:",
                                      paste(names(have)[!have], collapse = ", ")))

  # 2. + 3. Every fixture product estimates inside the worker; SEs are
  # populated through the worker-local Jacobian; results match the master.
  run_one <- function(g) {
    slice <- synth_dt[good == g]
    parallel::clusterExport(cl, c("g", "slice", "cfg"), envir = environment())
    w <- parallel::clusterEvalQ(cl,
           estimate_product_fixed_sigma(g, slice, cfg))[[1]]
    m <- NULL
    capture.output(m <- estimate_product_fixed_sigma(g, slice, cfg),
                   type = "output")
    list(w = w, m = m)
  }

  worker_all <- list(); master_all <- list()
  for (g in products) {
    r <- run_one(g)
    expect_s3_class(r$w, "data.table")
    worker_all[[g]] <- r$w
    master_all[[g]] <- r$m
  }
  w_dt <- data.table::rbindlist(worker_all, fill = TRUE)
  m_dt <- data.table::rbindlist(master_all, fill = TRUE)
  expect_gt(nrow(w_dt), 0L)

  ok_rows <- w_dt[convergence == 0L & gamma_se_status == "ok" &
                  is.finite(gamma_se)]
  expect_gt(nrow(ok_rows), 0L)

  data.table::setorder(w_dt, importer, exporter, good)
  data.table::setorder(m_dt, importer, exporter, good)
  expect_identical(nrow(w_dt), nrow(m_dt))
  expect_equal(w_dt$gamma,    m_dt$gamma,    tolerance = 1e-10)
  expect_equal(w_dt$gamma_se, m_dt$gamma_se, tolerance = 1e-8)
})
