# ============================================================================
# test-stage2-gamma-v.R  (patch 0085, 2026-10-03)
#
# Eq. (11)'s reference-destination gamma_V. Locks:
#   1. plumbing: --stage2-gamma-v-source {regional|table} (default regional),
#      a 'table' source needs an existing --stage2-gamma-v-table,
#      --stage2-export-period-count {rows|panel} (default rows); validate_config;
#      the checkpoint stamp moves with the keys and absent keys mean the defaults;
#   2. invariance: an exporter table whose gamma_jV equals, row for row, the
#      value the regional path would have used reproduces the regional run
#      bit for bit, while run_meta reports every export row resolved
#      exporter-specifically -- the lookup is wired, and it alone is the change;
#   3. an exporter table with different values changes Tier-1 cells and only
#      cells with export rows; rows absent from the table fall back to the
#      regional value (counts add up);
#   4. 'panel' changes only the export-side Broda-Weinstein T: same schema,
#      the run meta records the rule;
#   5. the fixed-point census script measures the step sizes and the
#      contraction ratio on synthetic passes.
# ============================================================================

.gv_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.gv_run <- function(cfg, dt) {
  r <- NULL
  suppressMessages(suppressWarnings(capture.output(
    r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output")))
  r
}
.key <- c("importer", "exporter", "good")
# the gamma_V the regional path assigns to (V, good) under cfg
.gv_regional <- function(cfg, V, g) {
  if (!is.null(cfg$gamma_V_lookup)) {
    row <- cfg$gamma_V_lookup[importer == V & good == g]
    if (nrow(row) > 0L && !is.na(row$gamma[1]) && row$gamma[1] > 0) return(row$gamma[1])
  }
  cfg$gamma_V_default
}

test_that("CLI, validate_config and the checkpoint stamp carry the gamma_V family", {
  .gv_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_gv_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  o <- parse_cli(base)
  expect_identical(o$stage2_gamma_v_source, "regional"); expect_identical(o$stage2_export_period_count, "panel")   # patch 0086 default
  expect_equal(o$stage2_gamma_v_passes, 3L); expect_identical(o$stage2_sigma_edge, "fallback")                     # patch 0086/0087
  expect_error(parse_cli(c(base, "--stage2-gamma-v-source", "table")), "stage2-gamma-v-table")
  tab <- file.path(fake, "prev.rds"); saveRDS(data.table(x = 1), tab)
  o2 <- parse_cli(c(base, "--stage2-gamma-v-source", "table", "--stage2-gamma-v-table", tab, "--stage2-export-period-count", "panel"))
  expect_identical(o2$stage2_gamma_v_source, "table"); expect_identical(o2$stage2_gamma_v_table, tab); expect_identical(o2$stage2_export_period_count, "panel")
  cfg2 <- build_config(o2)
  expect_identical(cfg2$stage2_gamma_v_source, "table"); expect_identical(cfg2$stage2_export_period_count, "panel")
  expect_error(parse_cli(c(base, "--stage2-gamma-v-source", "oracle")), "stage2-gamma-v-source")
  expect_error(parse_cli(c(base, "--stage2-export-period-count", "years")), "stage2-export-period-count")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  expect_silent(validate_config(cfg))
  bad <- cfg; bad$stage2_gamma_v_source <- "oracle"; expect_error(validate_config(bad), "stage2_gamma_v_source")
  bad <- cfg; bad$stage2_export_period_count <- "years"; expect_error(validate_config(bad), "stage2_export_period_count")
  c_t <- cfg; c_t$stage2_gamma_v_source <- "table"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(c_t, dt)))
  c_p <- cfg; c_p$stage2_export_period_count <- "rows"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(c_p, dt)))
  c_d <- cfg; c_d$stage2_gamma_v_source <- "regional"; c_d$stage2_export_period_count <- "panel"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(c_d, dt))   # absent keys == the defaults
  c_l <- cfg; c_l$gamma_V_exporter_lookup <- data.table(importer = "4", exporter = "e", good = "0101", gamma = 1)
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(c_l, dt)))   # the table is fingerprinted
})

test_that("an exporter table equal to the regional values reproduces the regional run bit for bit", {
  .gv_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  r0 <- .gv_run(cfg, dt)
  gv0 <- attr(r0, "run_meta")$gamma_v_resolution
  expect_equal(gv0$exporter, 0L)
  expect_gt(gv0$regional + gv0$default, 0L)                     # the fixture has export rows
  # a table covering every (importer, exporter, good) row of the fixture with the regional value for (importer, good)
  rows <- unique(dt[, .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))])
  rows[, gamma := mapply(function(V, g) .gv_regional(cfg, V, g), importer, good)]
  cfg_t <- cfg; cfg_t$stage2_gamma_v_source <- "table"; cfg_t$gamma_V_exporter_lookup <- rows
  r1 <- .gv_run(cfg_t, dt)
  gv1 <- attr(r1, "run_meta")$gamma_v_resolution
  expect_equal(gv1$exporter, gv0$regional + gv0$default)        # every export row now resolves through the table
  expect_equal(gv1$regional + gv1$default, 0L)
  expect_identical(finalize_saved_output(r1), finalize_saved_output(r0))
})

test_that("a different exporter table changes only cells with export rows; absent rows fall back to regional", {
  .gv_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  r0 <- .gv_run(cfg, dt)
  rows <- unique(dt[, .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))])
  rows[, gamma := 2.5 * mapply(function(V, g) .gv_regional(cfg, V, g), importer, good)]
  set.seed(7); rows <- rows[sample.int(nrow(rows), size = floor(0.6 * nrow(rows)))]   # 60% coverage: the rest fall back
  cfg_t <- cfg; cfg_t$stage2_gamma_v_source <- "table"; cfg_t$gamma_V_exporter_lookup <- rows
  r1 <- .gv_run(cfg_t, dt)
  gv1 <- attr(r1, "run_meta")$gamma_v_resolution; gv0 <- attr(r0, "run_meta")$gamma_v_resolution
  expect_gt(gv1$exporter, 0L); expect_gt(gv1$regional + gv1$default, 0L)
  expect_equal(gv1$exporter + gv1$regional + gv1$default, gv0$regional + gv0$default)
  expect_setequal(names(r1), names(r0)); expect_equal(nrow(r1), nrow(r0))
  m <- merge(r0[, c(.key, "gamma", "tier"), with = FALSE], r1[, c(.key, "gamma"), with = FALSE], by = .key, suffixes = c(".0", ".1"))
  changed <- m[gamma.0 != gamma.1]
  expect_gt(nrow(changed), 0L)
  # a cell with no Tier-1 (export-side) row cannot change
  cells_with_export <- unique(m[tier == 1L, .(importer, good)])
  changed_cells <- unique(changed[, .(importer, good)])
  expect_equal(nrow(changed_cells[!cells_with_export, on = .(importer, good)]), 0L)
})

test_that("'rows' is recorded and keeps the schema; 'panel' is the default (patch 0086)", {
  .gv_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  r0 <- .gv_run(cfg, dt)
  expect_identical(attr(r0, "run_meta")$export_period_count, "panel")
  cfg_r <- cfg; cfg_r$stage2_export_period_count <- "rows"
  r1 <- .gv_run(cfg_r, dt)
  expect_identical(attr(r1, "run_meta")$export_period_count, "rows")
  expect_setequal(names(r1), names(r0)); expect_equal(nrow(r1), nrow(r0))
  cfg_p <- cfg; cfg_p$stage2_export_period_count <- "panel"
  expect_identical(finalize_saved_output(.gv_run(cfg_p, dt)), finalize_saved_output(r0))
})

test_that("the fixed-point census measures step sizes and the contraction ratio", {
  .gv_setup()
  skip_if_not_installed("jsonlite")
  script <- file.path(locate_source_dir(), "..", "analysis", "gamma_v_fixed_point.R")
  skip_if_not(file.exists(script))
  td <- tempfile("gvfp_"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  set.seed(1)
  n <- 4000L
  p1 <- data.table(importer = as.character(seq_len(n) %% 50L), exporter = paste0("e", seq_len(n)), good = "0101",
                   gamma = exp(rnorm(n, -0.4, 0.5)), tier = sample(c(0L, 1L, 1L, 1L, 3L), n, TRUE),
                   convergence = 0L, opt_tariff = 0.7)
  eps <- rnorm(n, 0, 0.2)
  p2 <- copy(p1); p2[, gamma := gamma * exp(eps)]
  p3 <- copy(p2); p3[, gamma := gamma * exp(eps / 4)]
  f1 <- file.path(td, "p1.rds"); f2 <- file.path(td, "p2.rds"); f3 <- file.path(td, "p3.rds")
  saveRDS(p1, f1); saveRDS(p2, f2); saveRDS(p3, f3)
  js <- file.path(td, "o.json"); md <- file.path(td, "o.md")
  rs <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rs, c(shQuote(script), "--pass1", shQuote(f1), "--pass2", shQuote(f2), "--pass3", shQuote(f3),
                                        "--out", shQuote(js), "--md", shQuote(md)), stdout = TRUE, stderr = TRUE))
  expect_true(file.exists(js), info = paste(out, collapse = "\n"))
  j <- jsonlite::fromJSON(js)
  expect_equal(nrow(j$steps), 2L)
  expect_equal(j$steps$n_tier1[1], sum(p1$tier == 1L))
  expect_equal(j$contraction_ratio_p50, 0.25, tolerance = 0.03)
  expect_true(any(grepl("Contraction ratio", readLines(md))))
})
