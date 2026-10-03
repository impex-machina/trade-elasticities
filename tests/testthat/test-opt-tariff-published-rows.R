# ============================================================================
# test-opt-tariff-published-rows.R  (patch 0081, 2026-10-03)
#
# opt_tariff / opt_tariff_all are cell-level statistics. Through v0.8.2 the
# cell estimator computed them before the 0.5%-per-tail trim, so a cell's
# published value could include rows the table does not carry (on the
# shipped v0.8.2 Stage-2b table, 12% of cells; 1,571 cells above their own
# largest published gamma). Locks:
#   1. recompute_opt_tariff() applies the published-row definition to every
#      cell, corrects a wrong stored value, leaves cells with no estimated
#      row at NA (opt_tariff) but finite (opt_tariff_all), and is idempotent;
#   2. the e2e fixture output satisfies the definition on every cell, under
#      the no-trim default and under a trim that removes rows;
#   3. scripts/recompute_opt_tariff.R applies the same function to a saved
#      table, prints the census, and returns a pipeline table unchanged.
# ============================================================================

.ot_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.ot_pub <- function(dt) dt[, {
  est <- is_estimated_row(tier, convergence)
  .(pub = if (any(est)) optimal_tariff(gamma[est], sigma[est][1], avg_trade[est]) else NA_real_,
    pub_all = optimal_tariff(gamma, sigma[1], avg_trade),
    stored = opt_tariff[1], stored_all = opt_tariff_all[1])
}, by = .(importer, good)]
.ot_ok <- function(dt) { v <- .ot_pub(dt); isTRUE(all.equal(v$stored, v$pub)) && isTRUE(all.equal(v$stored_all, v$pub_all)) }
.ot_run <- function(cfg, dt) {
  r <- NULL
  suppressMessages(suppressWarnings(capture.output(
    r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output")))
  r
}

test_that("recompute_opt_tariff() applies the published-row definition and is idempotent", {
  .ot_setup()
  # cell A: three estimated rows, stored value is a pre-trim artefact (86.9 > max gamma);
  # cell B: one estimated row and one Tier-3 row; cell C: Tier-3 rows only (no estimated row)
  tab <- data.table(
    importer = c("4", "4", "4", "8", "8", "12", "12"), good = "0101",
    exporter = c("e1", "e2", "e3", "e1", "t1", "t1", "t2"),
    gamma = c(0.5, 1.0, 2.0, 0.8, 0.6, 0.6, 0.6), sigma = c(3, 3, 3, 4, 4, 5, 5),
    avg_trade = c(10, 20, 30, 5, 7, 1, 2),
    tier = c(0L, 1L, 1L, 1L, 3L, 3L, 3L), convergence = c(0L, 0L, 0L, 0L, -1L, -1L, -1L),
    opt_tariff = c(86.9, 86.9, 86.9, 0.8, 0.8, 0.6, 0.6), opt_tariff_all = c(86.9, 86.9, 86.9, 0.7, 0.7, 0.6, 0.6))
  expect_false(.ot_ok(tab))
  res <- recompute_opt_tariff(tab)
  expect_true(.ot_ok(tab))
  expect_equal(res$n_cells, 3L)
  expect_equal(res$n_changed, 3L)
  expect_equal(res$n_above_gmax_before, 1L)
  expect_equal(res$n_above_gmax_after, 0L)
  expect_equal(unique(tab[importer == "4", opt_tariff]), optimal_tariff(c(0.5, 1.0, 2.0), 3, c(10, 20, 30)))
  expect_lt(unique(tab[importer == "4", opt_tariff]), 2.0)                  # a weighted mean cannot exceed max gamma
  expect_equal(unique(tab[importer == "8", opt_tariff]), 0.8)                # the one estimated row
  expect_equal(unique(tab[importer == "8", opt_tariff_all]), optimal_tariff(c(0.8, 0.6), 4, c(5, 7)))
  expect_true(all(is.na(tab[importer == "12", opt_tariff])))                  # no estimated row
  expect_equal(unique(tab[importer == "12", opt_tariff_all]), 0.6)
  snap <- copy(tab)
  res2 <- recompute_opt_tariff(tab)
  expect_equal(res2$n_changed, 0L)
  expect_identical(tab, snap)                                                # idempotent
  expect_error(recompute_opt_tariff(tab[, !"avg_trade"]), "missing columns")
})

test_that("the e2e fixture satisfies the definition on every cell, with and without a trim", {
  .ot_setup()
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  r0 <- .ot_run(cfg, dt)
  expect_true(.ot_ok(r0))
  cfg_t <- cfg; cfg_t$tail_trim_pct <- 0.05                                  # a trim that removes rows on this fixture
  r1 <- .ot_run(cfg_t, dt)
  expect_lt(nrow(r1), nrow(r0))
  expect_true(.ot_ok(r1))
  # the pre-0081 arithmetic: a cell that lost a row to the trim would have kept its pre-trim value
  lost <- r0[!r1, on = c("importer", "exporter", "good")]
  expect_gt(nrow(lost), 0L)
  cells_lost <- unique(lost[, .(importer, good)])
  both <- merge(unique(r0[cells_lost, on = .(importer, good), .(importer, good, ot0 = opt_tariff)]),
                unique(r1[cells_lost, on = .(importer, good), .(importer, good, ot1 = opt_tariff)]), by = c("importer", "good"))
  expect_true(any(!is.na(both$ot0) & !is.na(both$ot1) & both$ot0 != both$ot1))
})

test_that("scripts/recompute_opt_tariff.R corrects a saved table and leaves a pipeline table unchanged", {
  .ot_setup()
  script <- file.path(locate_source_dir(), "..", "scripts", "recompute_opt_tariff.R")
  skip_if_not(file.exists(script))
  td <- tempfile("otr_"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  rs <- file.path(R.home("bin"), "Rscript")
  # a pipeline table comes back identical
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  r0 <- finalize_saved_output(.ot_run(cfg, dt))
  p_in <- file.path(td, "pipe.rds"); p_out <- file.path(td, "pipe_out.rds"); saveRDS(r0, p_in)
  out <- suppressWarnings(system2(rs, c(shQuote(script), "--in", shQuote(p_in), "--out", shQuote(p_out)), stdout = TRUE, stderr = TRUE))
  expect_true(file.exists(p_out), info = paste(out, collapse = "\n"))
  back <- readRDS(p_out); setDT(back)
  expect_identical(names(back), names(r0)); expect_equal(back, r0)   # content; attributes may differ after serialization
  expect_true(any(grepl("changed on 0 cells", out)))
  # a table with a pre-trim artefact is corrected in place (--out defaults to --in)
  bad <- copy(r0); setDT(bad)
  key1 <- bad[1L, .(importer, good)]
  bad[key1, on = .(importer, good), opt_tariff := 999]
  p_bad <- file.path(td, "bad.rds"); saveRDS(bad, p_bad)
  out2 <- suppressWarnings(system2(rs, c(shQuote(script), "--in", shQuote(p_bad)), stdout = TRUE, stderr = TRUE))
  fixed <- readRDS(p_bad); setDT(fixed)
  expect_true(.ot_ok(fixed))
  expect_identical(names(fixed), names(r0)); expect_equal(fixed, r0)
  expect_true(any(grepl("changed on 1 cells", out2)))
})
