# ============================================================================
# test-run-records-dir.R  (patch 0111)
#
# A run's records -- checkpoints, the Stage-2 optimizer-fallback table, the
# tail-trim record -- are written under cfg$run_record_dir (the runner sets it
# to --out-dir) and, without it, into the working directory as every release
# did. Through patch 0110 they always went to the working directory, so two
# local runs from one directory overwrote each other's records and box
# sessions moved them by hand. Unit check of run_record_base(), a source-level
# check that no record path still uses the bare prefix, and an end-to-end
# Stage-2b run on the synthetic fixture with a trim heavy enough to write the
# trim record.
# ============================================================================

.rr_source <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

test_that("run_record_base(): out-dir when set, the bare prefix otherwise", {
  .rr_source()
  cfg <- make_synthetic_cfg()
  p <- build_output_prefix(cfg)
  expect_identical(run_record_base(cfg), p)
  cfg$run_record_dir <- ""
  expect_identical(run_record_base(cfg), p)
  cfg$run_record_dir <- file.path("some", "out")
  expect_identical(run_record_base(cfg), file.path("some", "out", p))
})

test_that("no run record is written under the bare prefix any more", {
  root <- dirname(locate_source_dir())
  for (f in c("R/estimate_parallel.R", "R/estimate_stage1_feenstra.R")) {
    src <- readLines(file.path(root, f), warn = FALSE)
    expect_false(any(grepl("build_output_prefix(cfg)", src, fixed = TRUE)), info = f)
  }
  run <- readLines(file.path(root, "scripts", "run_estimation.R"), warn = FALSE)
  i <- grep("^config <- build_config\\(opts\\)", run)
  expect_length(i, 1L)
  j <- grep("^config\\$run_record_dir <- opts\\$out_dir", run)
  expect_length(j, 1L)
  expect_true(j > i && j - i <= 6L)                      # set once, before any stage config is derived
  expect_true(any(grepl("prefix_country <- run_record_base(config_2b)", run, fixed = TRUE)))
})

test_that("Stage 2b writes its trim record under run_record_dir, and the working directory otherwise", {
  .rr_source()
  skip_if_not(exists(".het_obj_fs_rcpp_loaded") && isTRUE(.het_obj_fs_rcpp_loaded), "fixed-sigma objective did not compile")
  synth_dt <- make_synthetic_baci(seed = 42L)
  run_in <- function(cwd, rec_dir) {
    cfg <- make_synthetic_cfg(); cfg$tail_trim_pct <- 0.2; cfg$run_record_dir <- rec_dir
    old <- setwd(cwd); on.exit(setwd(old), add = TRUE)
    invisible(capture.output(suppressMessages(suppressWarnings(
      estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = data.table::copy(synth_dt))))))
    build_output_prefix(cfg)
  }
  cwd <- tempfile("rr_cwd_"); rec <- tempfile("rr_out_"); dir.create(cwd); dir.create(rec)
  on.exit(unlink(c(cwd, rec), recursive = TRUE), add = TRUE)
  p <- run_in(cwd, rec)
  expect_true(file.exists(file.path(rec, paste0(p, "_stage2_trimmed.csv"))))
  expect_true(file.exists(file.path(rec, paste0(p, "_stage2_trimmed.rds"))))
  expect_length(list.files(cwd, pattern = "_stage2_|checkpoint"), 0L)
  cwd2 <- tempfile("rr_cwd2_"); dir.create(cwd2); on.exit(unlink(cwd2, recursive = TRUE), add = TRUE)
  p2 <- run_in(cwd2, NULL)                                 # library use: the working directory, as every release
  expect_true(file.exists(file.path(cwd2, paste0(p2, "_stage2_trimmed.csv"))))
})
