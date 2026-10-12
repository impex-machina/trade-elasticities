# ============================================================================
# test-v0100-defaults.R  (patch 0101, 2026-10-11)
#
# v0.10.0 defaults: --stage2-sigma-pole-rule fallback (c = 1),
# --stage2a-gamma-v-default priors, --stage2-trim-action flag. Locks: the
# three CLI/config defaults; the v0.9.1 reproducer flags; an estimator config
# without stage2_trim_action keeps the trimmed rows (flag) and is, on its
# published rows, identical to an explicit drop run; the pole rule's absent
# key means fallback in the runner's own fallback expression.
# ============================================================================

.vd_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.vd_run <- function(cfg, dt) {
  unlink(list.files(".", pattern = "_fs_checkpoint\\.rds$", full.names = TRUE))
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

test_that("the v0.10.0 defaults and the v0.9.1 reproducer flags", {
  .vd_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_vd_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  cfg <- build_config(parse_cli(c("--data", fake)))
  expect_identical(cfg$stage2_sigma_pole_rule, "fallback"); expect_equal(cfg$stage2_sigma_pole_se, 1)
  expect_identical(cfg$stage2a_gamma_v_default, "priors"); expect_identical(cfg$stage2_trim_action, "flag")
  expect_identical(cfg$stage2_sigma_edge, "fallback"); expect_identical(cfg$bw_lag, "calendar"); expect_identical(cfg$exporter_weight, "trade_value")
  expect_silent(validate_config(cfg))
  v091 <- build_config(parse_cli(c("--data", fake, "--stage2-sigma-pole-rule", "none", "--stage2a-gamma-v-default", "clean", "--stage2-trim-action", "drop")))
  expect_identical(v091$stage2_sigma_pole_rule, "none"); expect_identical(v091$stage2a_gamma_v_default, "clean"); expect_identical(v091$stage2_trim_action, "drop")
  expect_silent(validate_config(v091))
})

test_that("an estimator config without stage2_trim_action flags (v0.10.0) and equals an explicit drop run on its published rows", {
  .vd_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  cfg_d <- make_synthetic_cfg(); cfg_d$bw_lag <- "calendar"; cfg_d$tail_trim_pct <- 0.10            # the fixture is explicit drop
  cfg_a <- cfg_d; cfg_a$stage2_trim_action <- NULL                                                  # absent key: the v0.10.0 default
  on.exit(unlink(paste0(build_output_prefix(cfg_d), c("_stage2_trimmed.csv", "_stage2_trimmed.rds", "_stage2_fallbacks.csv"))), add = TRUE)
  d <- finalize_saved_output(.vd_run(cfg_d, dt)); a <- finalize_saved_output(.vd_run(cfg_a, dt))
  expect_true(all(is.na(d$trim_reason))); expect_gt(sum(!is.na(a$trim_reason)), 0L)
  expect_identical(a[is.na(trim_reason)], d)
  expect_equal(nrow(a) - nrow(d), sum(!is.na(a$trim_reason)))
})
