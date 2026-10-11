# ============================================================================
# test-trim-diagnostic.R  (patch 0097, 2026-10-11)
#
# analysis/trim_diagnostic.R on the synthetic fixture: a trimmed run's record
# (full rows, and the seven-column pre-0093 form), the published table and a
# Stage-1 table. Locks: the function runs on both record forms; the counts
# are internally consistent (reasons sum to the record, tails = gamma_lo +
# gamma_hi, union = published estimated + tail rows, within-good overlap
# bounded by both rules' removals); the markdown and JSON are written and the
# script runs end to end.
# ============================================================================

.tdg_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  source(file.path(src_dir, "..", "analysis", "trim_diagnostic.R"), local = FALSE)   # sys.nframe() > 0: no CLI
  invisible(TRUE)
}
.tdg_run <- function(cfg, dt) {
  unlink(list.files(".", pattern = "_fs_checkpoint\\.rds$", full.names = TRUE))
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

test_that("trim_diagnostic() runs on full-row and seven-column records with consistent counts; the script writes both outputs", {
  .tdg_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg(); cfg$bw_lag <- "calendar"; cfg$tail_trim_pct <- 0.10
  prefix <- build_output_prefix(cfg)
  on.exit(unlink(paste0(prefix, c("_stage2_trimmed.csv", "_stage2_trimmed.rds", "_stage2_fallbacks.csv"))), add = TRUE)
  tb <- finalize_saved_output(.tdg_run(cfg, dt))
  rec <- readRDS(paste0(prefix, "_stage2_trimmed.rds")); setDT(rec)
  expect_gt(nrow(rec), 0L)
  s1 <- cfg$sigma_lookup[, .(importer, good, sigma, sigma_se = 0.3, status = "ok", final_source = "hliml", adjust = 0L, sigma_capped = FALSE)]
  d <- trim_diagnostic(rec, tb, s1, label = "fixture", trim_pct = 0.10)
  expect_true(d$full_row_record)
  expect_equal(sum(d$by_reason$N), nrow(rec))
  expect_equal(d$n_tail_rows, sum(rec$reason %in% c("gamma_lo", "gamma_hi")))
  expect_equal(d$within_good$n_union_rows, d$n_published_estimated + d$n_tail_rows)
  expect_equal(d$within_good$n_removed_global, d$n_tail_rows)
  expect_lte(d$within_good$n_both, min(d$within_good$n_removed_global, d$within_good$n_removed_within_good))
  expect_equal(d$within_good$n_both + d$within_good$n_global_only, d$within_good$n_removed_global)
  expect_equal(d$within_good$n_both + d$within_good$n_within_only, d$within_good$n_removed_within_good)
  expect_true(all(c("hliml_interior") %in% names(d$sigma$published$provenance)))
  expect_false(is.null(d$extras)); expect_true(is.finite(d$extras$avg_trade$pub_p50))
  md <- write_trim_diagnostic(d); expect_true(any(grepl("within-good", md)))
  # the seven-column record (pre-0093): no extras, same counts
  rec7 <- rec[, .(importer, exporter, good, sigma, gamma, tier, convergence, reason)]
  d7 <- trim_diagnostic(rec7, tb, s1, label = "fixture7", trim_pct = 0.10)
  expect_false(d7$full_row_record); expect_null(d7$extras)
  expect_equal(d7$n_tail_rows, d$n_tail_rows); expect_equal(d7$within_good$n_removed_within_good, d$within_good$n_removed_within_good)
  # a published table carrying flagged trimmed rows (trim action 'flag') is read on its published rows only
  cfg_f <- cfg; cfg_f$stage2_trim_action <- "flag"
  tbf <- finalize_saved_output(.tdg_run(cfg_f, dt))
  df <- trim_diagnostic(rec, tbf, s1, label = "flag", trim_pct = 0.10)
  expect_equal(df$n_published_estimated, d$n_published_estimated)
  # the script end to end
  rec_path <- tempfile(fileext = ".rds"); tb_path <- tempfile(fileext = ".rds"); s1_path <- tempfile(fileext = ".rds")
  saveRDS(rec, rec_path); saveRDS(tb, tb_path); saveRDS(s1, s1_path)
  out_md <- tempfile(fileext = ".md"); out_json <- tempfile(fileext = ".json")
  script <- file.path(locate_source_dir(), "..", "analysis", "trim_diagnostic.R"); skip_if_not(file.exists(script))
  res <- system2(file.path(R.home("bin"), "Rscript"), c(script, "--trimmed", rec_path, "--table", tb_path, "--stage1", s1_path,
                                                       "--label", "fx", "--out", out_md, "--json", out_json), stdout = TRUE, stderr = TRUE)
  expect_true(file.exists(out_md), info = paste(res, collapse = "\n")); expect_true(file.exists(out_json))
  j <- jsonlite::fromJSON(out_json); expect_equal(j$n_trimmed, nrow(rec))
  rec_csv <- tempfile(fileext = ".csv"); fwrite(rec, rec_csv)
  d_csv <- trim_diagnostic(read_trim_record(rec_csv), tb, s1, label = "csv", trim_pct = 0.10)
  expect_equal(d_csv$n_tail_rows, d$n_tail_rows)
})
