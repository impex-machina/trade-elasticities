# ============================================================================
# test-reference-rule.R  (patch 0105)
#
# --stage2-reference-rule {periods_value|periods_stable|value}. Locks: the
# three rules on a constructed cell; NULL/absent == periods_value; the
# estimator under an absent key is bit-identical to periods_value (every
# release reproduces); periods_stable runs end to end; CLI / config /
# validation plumbing and the checkpoint stamp sees the key.
# ============================================================================

.rr_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.rr_run <- function(cfg, dt) {
  unlink(list.files(".", pattern = "_fs_checkpoint\\.rds$", full.names = TRUE))
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

test_that("choose_reference(): the three rules on a constructed cell", {
  .rr_setup()
  set.seed(3)
  dt <- rbindlist(list(
    data.table(exporter = "A", t = 1:10, cusval = 10,  lp_dif = rnorm(10, 0, 0.50)),   # longest, mid value, noisy
    data.table(exporter = "B", t = 1:10, cusval = 5,   lp_dif = rnorm(10, 0, 0.05)),   # longest, small, stable
    data.table(exporter = "C", t = 3:10, cusval = 100, lp_dif = rnorm(8,  0, 0.20))))  # shorter, largest
  expect_identical(choose_reference(dt), "A")
  expect_identical(choose_reference(dt, NULL), "A")
  expect_identical(choose_reference(dt, "periods_value"), "A")
  expect_identical(choose_reference(dt, "periods_stable"), "B")
  expect_identical(choose_reference(dt, "value"), "C")
  expect_error(choose_reference(dt, "longest"), "unknown rule")
  expect_identical(choose_reference(dt[, !"lp_dif"], "periods_stable"), "A")      # no price column: ties broken by value
})

test_that("absent key reproduces periods_value bit for bit; periods_stable runs; plumbing", {
  .rr_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  c0 <- make_synthetic_cfg(); c0$bw_lag <- "calendar"
  c1 <- c0; c1$stage2_reference_rule <- "periods_value"
  c2 <- c0; c2$stage2_reference_rule <- "periods_stable"
  on.exit(unlink(paste0(build_output_prefix(c0), c("_stage2_trimmed.csv", "_stage2_trimmed.rds", "_stage2_fallbacks.csv"))), add = TRUE)
  a <- finalize_saved_output(.rr_run(c0, dt)); b <- finalize_saved_output(.rr_run(c1, dt))
  expect_identical(a, b)
  s <- finalize_saved_output(.rr_run(c2, dt))
  expect_gt(nrow(s), 0L); expect_true(all(c("ref_exporter", "gamma") %in% names(s)))
  expect_identical(.fs_cfg_stamp(c0, dt), .fs_cfg_stamp(c1, dt))                 # absent == periods_value in the stamp
  expect_false(identical(.fs_cfg_stamp(c0, dt), .fs_cfg_stamp(c2, dt)))
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_rr_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  cfg <- build_config(parse_cli(c("--data", fake))); expect_identical(cfg$stage2_reference_rule, "periods_value"); expect_silent(validate_config(cfg))
  e <- build_config(parse_cli(c("--data", fake, "--stage2-reference-rule", "periods_stable"))); expect_identical(e$stage2_reference_rule, "periods_stable")
  expect_error(parse_cli(c("--data", fake, "--stage2-reference-rule", "longest")), "reference-rule")
  bad <- cfg; bad$stage2_reference_rule <- "longest"; expect_error(validate_config(bad), "stage2_reference_rule")
})
