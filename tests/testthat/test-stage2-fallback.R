# ============================================================================
# test-stage2-fallback.R  (patch 0077, 2026-09-29 fresh-eyes audit #4)
#
# estimate_importer_product_fixed_sigma() re-runs a cell with Nelder-Mead
# when L-BFGS-B does not converge. Through v0.8.2 the NM result replaced the
# L-BFGS-B result unconditionally: NM restarts from d_start with 2 x maxit
# function evaluations in J + 1 dimensions, so it returns a point with a
# HIGHER objective than the one it discards (and its own convergence code
# labels the row). Locks:
#   1. plumbing: the CLI accepts legacy/best and rejects others, the default
#      is legacy, validate_config likewise, the checkpoint stamp moves with
#      the field and an absent key means legacy;
#   2. record: a cell that fell back carries both objective values and both
#      convergence codes in run_meta$fallback_info and in
#      <prefix>_stage2_fallbacks.csv; a run with no fallback writes no table
#      (and removes a stale one);
#   3. legacy: the published obj_value / convergence are the NM ones on every
#      fallback cell (the <= v0.8.2 rule), and the default run is identical
#      to an explicit legacy run;
#   4. best: the published obj_value is min(L-BFGS-B, NM) on every fallback
#      cell, never above legacy's, and on this fixture NM IS worse on at
#      least one cell (the defect is real, not hypothetical). Same schema.
# ============================================================================

.fb_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.fb_run <- function(cfg, dt) {
  r <- NULL
  suppressMessages(suppressWarnings(capture.output(
    r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output")))
  r
}
.fb_file <- function(cfg) paste0(build_output_prefix(cfg), "_stage2_fallbacks.csv")

test_that("CLI, validate_config and the checkpoint stamp carry stage2_fallback", {
  .fb_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_fb_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  expect_identical(parse_cli(c(base, "--stage2-fallback", "best"))$stage2_fallback, "best")
  expect_identical(parse_cli(base)$stage2_fallback, "legacy")            # patch 0077 default
  expect_error(parse_cli(c(base, "--stage2-fallback", "worst")), "stage2-fallback")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  expect_silent(validate_config(cfg))
  cfg_bad <- cfg; cfg_bad$stage2_fallback <- "worst"
  expect_error(validate_config(cfg_bad), "stage2_fallback")
  cfg_best <- cfg; cfg_best$stage2_fallback <- "best"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_best, dt)))
  cfg_leg <- cfg; cfg_leg$stage2_fallback <- "legacy"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_leg, dt))   # absent key == legacy
})

test_that("no fallback on the converging fixture: no table, default identical to explicit legacy", {
  .fb_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  fwrite(data.table(stale = 1L), .fb_file(cfg))               # a stale table from an earlier run
  r_def <- .fb_run(cfg, dt)
  expect_false(file.exists(.fb_file(cfg)))                     # removed by the clean run
  expect_equal(nrow(attr(r_def, "run_meta")$fallback_info), 0L)
  cfg_leg <- cfg; cfg_leg$stage2_fallback <- "legacy"
  r_leg <- .fb_run(cfg_leg, dt)
  expect_identical(finalize_saved_output(r_def), finalize_saved_output(r_leg))
})

test_that("forced fallback: legacy publishes the NM point, best publishes the better point", {
  .fb_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  cfg$stage2_maxit <- 1L     # L-BFGS-B cannot converge -> every fitted cell runs the NM fallback
  on.exit(unlink(.fb_file(cfg)), add = TRUE)

  cfg_leg <- cfg; cfg_leg$stage2_fallback <- "legacy"
  r_leg <- .fb_run(cfg_leg, dt)
  fb_leg <- attr(r_leg, "run_meta")$fallback_info
  expect_gt(nrow(fb_leg), 0L)
  expect_true(file.exists(.fb_file(cfg)))
  expect_setequal(names(fb_leg), c("importer", "good", "J", "M", "lbfgsb_convergence", "lbfgsb_value",
                                   "nm_convergence", "nm_value", "chosen", "rule"))
  expect_true(all(fb_leg$rule == "legacy"))
  expect_true(all(fb_leg$chosen == "nelder_mead"))
  expect_true(all(fb_leg$lbfgsb_convergence != 0L))
  # the published row IS the NM outcome on every fallback cell (<= v0.8.2 rule)
  cells_leg <- unique(r_leg[!is.na(obj_value), .(importer, good, obj_value, convergence)])
  j_leg <- fb_leg[cells_leg, on = .(importer, good), nomatch = 0L]
  expect_equal(nrow(j_leg), nrow(cells_leg))
  expect_equal(j_leg$obj_value, j_leg$nm_value)
  expect_equal(j_leg$convergence, j_leg$nm_convergence)
  # the defect: NM's objective is above the L-BFGS-B point it replaced
  expect_true(any(fb_leg$nm_value > fb_leg$lbfgsb_value))

  cfg_best <- cfg; cfg_best$stage2_fallback <- "best"
  r_best <- .fb_run(cfg_best, dt)
  fb_best <- attr(r_best, "run_meta")$fallback_info
  expect_equal(nrow(fb_best), nrow(fb_leg))
  expect_setequal(names(r_best), names(r_leg))                 # same schema
  expect_true(all(fb_best$rule == "best"))
  expect_true(all((fb_best$chosen == "lbfgsb") == (fb_best$lbfgsb_value <= fb_best$nm_value)))
  cells_best <- unique(r_best[!is.na(obj_value), .(importer, good, obj_value, convergence)])
  j_best <- fb_best[cells_best, on = .(importer, good), nomatch = 0L]
  expect_equal(nrow(j_best), nrow(cells_best))
  expect_equal(j_best$obj_value, pmin(j_best$lbfgsb_value, j_best$nm_value))
  expect_equal(j_best$convergence,
               ifelse(j_best$chosen == "lbfgsb", j_best$lbfgsb_convergence, j_best$nm_convergence))
  # never worse than legacy on any cell, strictly better where NM lost
  cmp <- cells_best[cells_leg, on = .(importer, good), nomatch = 0L]
  expect_true(all(cmp$obj_value <= cmp$i.obj_value + 1e-12))
  expect_true(any(cmp$obj_value < cmp$i.obj_value))
  # both optimizer outcomes are recorded identically under either rule
  k <- c("importer", "good"); setkeyv(fb_leg, k); setkeyv(fb_best, k)
  expect_equal(fb_leg$lbfgsb_value, fb_best$lbfgsb_value)
  expect_equal(fb_leg$nm_value, fb_best$nm_value)
})
