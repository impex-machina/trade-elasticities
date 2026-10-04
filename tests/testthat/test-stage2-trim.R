# ============================================================================
# test-stage2-trim.R  (patch 0083, 2026-10-03)
#
# estimate_all_fixed_sigma()'s 0.5%-per-tail trim. Locks:
#   1. plumbing: --stage2-trim accepts legacy/v2, default legacy, validate_config,
#      checkpoint stamp moves with the key, absent key == legacy;
#   2. the record: under either mode, run_meta$trimmed_rows and
#      <prefix>_stage2_trimmed.csv list exactly the rows the trim removed, each
#      with a reason consistent with the bounds; a run that trims nothing writes
#      no table (and removes a stale one);
#   3. legacy is bit-identical to the <= v0.8.3 arithmetic (sigma bounds as row
#      quantiles) and to the absent-key default;
#   4. v2 takes the sigma bounds over cells, so a cell is removed on sigma
#      grounds whole or not at all; the gamma trim is unchanged; rows shared
#      with legacy carry identical values (membership is the only difference).
# ============================================================================

.tr_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.tr_run <- function(cfg, dt) {
  r <- NULL
  suppressMessages(suppressWarnings(capture.output(
    r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output")))
  r
}
.tr_file <- function(cfg) paste0(build_output_prefix(cfg), "_stage2_trimmed.csv")
.key <- c("importer", "exporter", "good")
.kstr <- function(d) paste(d$importer, d$exporter, d$good)

test_that("CLI, validate_config and the checkpoint stamp carry stage2_trim", {
  .tr_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_tr_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  expect_identical(parse_cli(c(base, "--stage2-trim", "v2"))$stage2_trim, "v2")
  expect_identical(parse_cli(base)$stage2_trim, "v2")                      # patch 0086 default
  expect_identical(build_config(parse_cli(base))$stage2_trim, "v2")
  expect_error(parse_cli(c(base, "--stage2-trim", "v3")), "stage2-trim")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  expect_silent(validate_config(cfg))
  cfg_bad <- cfg; cfg_bad$stage2_trim <- "v3"
  expect_error(validate_config(cfg_bad), "stage2_trim")
  cfg_v2 <- cfg; cfg_v2$stage2_trim <- "v2"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_v2, dt))    # absent key == v2 (patch 0086)
  cfg_leg <- cfg; cfg_leg$stage2_trim <- "legacy"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_leg, dt)))
})

test_that("legacy: the trimmed table is exactly the removed rows; default identical to legacy; no trim -> no table", {
  .tr_setup()
  dt <- make_synthetic_baci(seed = 42L)
  cfg0 <- make_synthetic_cfg()                       # no trim on the fixture
  fwrite(data.table(stale = 1L), .tr_file(cfg0))     # a stale table from an earlier run
  r0 <- .tr_run(cfg0, dt)
  expect_false(file.exists(.tr_file(cfg0)))          # removed by the no-trim run
  expect_null(attr(r0, "run_meta")$trimmed_rows)
  expect_identical(attr(r0, "run_meta")$trim_mode, "v2")                  # absent key == v2 (patch 0086)

  cfg <- make_synthetic_cfg(); cfg$tail_trim_pct <- 0.05
  on.exit(unlink(.tr_file(cfg)), add = TRUE)
  cfg_leg <- cfg; cfg_leg$stage2_trim <- "legacy"
  r1 <- .tr_run(cfg_leg, dt)
  meta <- attr(r1, "run_meta"); tr <- meta$trimmed_rows; b <- meta$trim_bounds
  expect_gt(nrow(tr), 0L)
  expect_lt(nrow(r1), nrow(r0))
  expect_true(file.exists(.tr_file(cfg)))
  csv <- fread(.tr_file(cfg), colClasses = list(character = c("importer", "exporter", "good")))
  expect_equal(nrow(csv), nrow(tr))
  removed <- r0[!r1, on = .key]
  expect_setequal(.kstr(removed), .kstr(tr))
  expect_setequal(.kstr(removed), .kstr(csv))
  # every recorded row violates the bound its reason names; every kept row is inside the bounds
  expect_true(all(tr[reason == "sigma_lo", sigma] < b$sig_lo)); expect_true(all(tr[reason == "sigma_hi", sigma] > b$sig_hi))
  expect_true(all(tr[reason == "gamma_lo", gamma] < b$gam_lo)); expect_true(all(tr[reason == "gamma_hi", gamma] > b$gam_hi))
  expect_true(all(r1$sigma >= b$sig_lo & r1$sigma <= b$sig_hi & r1$gamma >= b$gam_lo & r1$gamma <= b$gam_hi))
  # the <= v0.8.3 arithmetic: row-quantile bounds over the estimated rows of the untrimmed table
  src <- r0[is.na(tier) | is_estimated_row(tier, convergence)]
  expect_equal(unname(b$sig_lo), unname(quantile(src$sigma, 0.05))); expect_equal(unname(b$sig_hi), unname(quantile(src$sigma, 0.95)))
  expect_equal(unname(b$gam_lo), unname(quantile(src$gamma, 0.05))); expect_equal(unname(b$gam_hi), unname(quantile(src$gamma, 0.95)))
})

test_that("v2: sigma bounds over cells, whole-cell removal, gamma trim unchanged, shared rows identical", {
  .tr_setup()
  dt <- make_synthetic_baci(seed = 42L)
  r0 <- .tr_run(make_synthetic_cfg(), dt)
  cfg <- make_synthetic_cfg(); cfg$tail_trim_pct <- 0.05
  on.exit(unlink(.tr_file(cfg)), add = TRUE)
  cfg_leg <- cfg; cfg_leg$stage2_trim <- "legacy"; r1 <- .tr_run(cfg_leg, dt); b1 <- attr(r1, "run_meta")$trim_bounds
  cfg_v2  <- cfg; cfg_v2$stage2_trim  <- "v2";     r2 <- .tr_run(cfg_v2, dt);  m2 <- attr(r2, "run_meta"); b2 <- m2$trim_bounds; tr2 <- m2$trimmed_rows
  expect_identical(m2$trim_mode, "v2")
  expect_setequal(names(r2), names(r1))
  # sigma bounds are quantiles over the cells of the untrimmed estimated rows
  src <- r0[is.na(tier) | is_estimated_row(tier, convergence)]
  cells <- unique(src[, .(importer, good, sigma)])
  expect_equal(unname(b2$sig_lo), unname(quantile(cells$sigma, 0.05))); expect_equal(unname(b2$sig_hi), unname(quantile(cells$sigma, 0.95)))
  # the gamma bounds are the legacy ones
  expect_equal(b2$gam_lo, b1$gam_lo); expect_equal(b2$gam_hi, b1$gam_hi)
  # a cell removed on sigma grounds is removed whole
  sig_cells <- unique(tr2[reason %in% c("sigma_lo", "sigma_hi"), .(importer, good)])
  if (nrow(sig_cells)) expect_equal(nrow(r2[sig_cells, on = .(importer, good), nomatch = 0L]), 0L)
  # the record is exactly the removed rows
  expect_setequal(.kstr(r0[!r2, on = .key]), .kstr(tr2))
  # rows shared with legacy are identical in every column (membership is the only difference)
  m <- merge(r1, r2, by = .key, suffixes = c(".l", ".v"))
  for (col in setdiff(names(r1), .key)) expect_equal(m[[paste0(col, ".l")]], m[[paste0(col, ".v")]], info = col)
  # (patch 0086) an absent key is v2: the default run equals the explicit v2 run
  r_def <- .tr_run(cfg, dt)
  expect_identical(finalize_saved_output(r_def), finalize_saved_output(r2))
})
