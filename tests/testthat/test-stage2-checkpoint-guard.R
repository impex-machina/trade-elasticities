# ============================================================================
# test-stage2-checkpoint-guard.R  (patch 0044, 2026-09-01 fresh-eyes audit)
#
# estimate_all_fixed_sigma() resumes from <prefix>_fs_checkpoint.rds in the
# CWD. Before this patch a stale checkpoint from a run with a DIFFERENT
# estimation config (lambda, bw_lag, gradient, priors, lookups, panel) was
# resumed silently. Locks:
#   1. the stamp is deterministic and sensitive to each estimation-relevant
#      field and to the panel, and insensitive to timing/paths;
#   2. a stamped checkpoint from a different lambda makes the driver STOP with
#      the "[checkpoint]" message instead of splicing batches;
#   3. an unstamped (pre-patch) checkpoint resumes with a warning;
#   4. a same-config checkpoint resumes and the driver's final output equals
#      an uninterrupted run (the checkpoint mechanism itself is unchanged).
# The driver is exercised through the real serial path (ncores = 1) on the
# synthetic Stage-2b fixture, in a temp CWD so no real checkpoint is touched.
# ============================================================================

.ckpt_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

.run_quiet <- function(expr) {
  suppressMessages(capture.output(r <- expr, type = "output")); r
}

test_that("the checkpoint stamp tracks estimation-relevant config and the panel only", {
  .ckpt_setup()
  dt  <- make_synthetic_baci(seed = 42L)
  cfg <- make_synthetic_cfg()
  s0 <- .fs_cfg_stamp(cfg, dt)
  expect_identical(s0, .fs_cfg_stamp(cfg, dt))                 # deterministic
  cfg2 <- cfg; cfg2$shrinkage_lambda <- cfg$shrinkage_lambda + 0.05
  expect_false(identical(s0, .fs_cfg_stamp(cfg2, dt)))
  cfg3 <- cfg; cfg3$bw_lag <- if (identical(cfg$bw_lag, "calendar")) "legacy" else "calendar"
  expect_false(identical(s0, .fs_cfg_stamp(cfg3, dt)))
  cfg4 <- cfg; cfg4$stage2_gradient <- "analytic"
  expect_false(identical(s0, .fs_cfg_stamp(cfg4, dt)))
  cfg5 <- cfg
  if (!is.null(cfg5$shrinkage_priors)) {
    cfg5$shrinkage_priors <- data.table::copy(cfg5$shrinkage_priors)
    cfg5$shrinkage_priors[1L, ln_gamma_prior := ln_gamma_prior + 0.1]
    expect_false(identical(s0, .fs_cfg_stamp(cfg5, dt)))
  }
  expect_false(identical(s0, .fs_cfg_stamp(cfg, dt[-1L])))     # panel shape
  cfg6 <- cfg; cfg6$filepath <- "/some/other/path"; cfg6$ncores_note <- "irrelevant"
  expect_identical(s0, .fs_cfg_stamp(cfg6, dt))                 # paths/timing-free
})

test_that("a stale checkpoint from a different config stops the driver; same config resumes", {
  .ckpt_setup()
  dt  <- make_synthetic_baci(seed = 42L)
  cfg <- make_synthetic_cfg()
  wd <- tempfile("ckpt_"); dir.create(wd)
  old_wd <- setwd(wd); on.exit({ setwd(old_wd); unlink(wd, recursive = TRUE) }, add = TRUE)
  ckpt_file <- paste0(build_output_prefix(cfg), "_fs_checkpoint.rds")

  # reference: uninterrupted run (cleans its own checkpoint)
  ref <- .run_quiet(estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt))
  expect_false(file.exists(ckpt_file))

  # plant a "crashed at product 1" checkpoint written under a DIFFERENT lambda
  cfg_other <- cfg; cfg_other$shrinkage_lambda <- cfg$shrinkage_lambda + 0.05
  saveRDS(list(results = list(NULL), next_idx = 2L,
               cfg_stamp = .fs_cfg_stamp(cfg_other, dt)), ckpt_file)
  expect_error(.run_quiet(estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)),
               "\\[checkpoint\\].*different estimation config")
  expect_true(file.exists(ckpt_file))                          # left for the user to delete

  # an unstamped (pre-patch) checkpoint resumes with a warning, not a stop
  saveRDS(list(results = list(NULL), next_idx = 2L), ckpt_file)
  expect_warning(
    res_w <- .run_quiet(estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)),
    "predates the config stamp")
  expect_s3_class(res_w, "data.table")
  expect_false(file.exists(ckpt_file))

  # a same-config checkpoint resumes silently and reproduces the reference:
  # plant the true product-1 result (next_idx = 2 skips product 1).
  products <- unique(dt$good)
  dt_by_product <- split(dt, by = "good", keep.by = TRUE)
  r1 <- .run_quiet(estimate_product_fixed_sigma(products[1L], dt_by_product[[products[1L]]], cfg))
  saveRDS(list(results = list(r1), next_idx = 2L,
               cfg_stamp = .fs_cfg_stamp(cfg, dt)), ckpt_file)
  res_r <- expect_silent(.run_quiet(estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)))
  expect_false(file.exists(ckpt_file))
  # finalize_saved_output() strips the wall-clock run_meta attribute and
  # canonically sorts -- the same content criterion the release manifest uses.
  expect_identical(finalize_saved_output(res_r), finalize_saved_output(ref))
})
