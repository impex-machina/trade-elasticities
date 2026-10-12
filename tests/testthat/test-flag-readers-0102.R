# ============================================================================
# test-flag-readers-0102.R  (patch 0102, 2026-10-12)
#
# The v0.10.0 table is the first published with flagged trimmed rows. Locks:
#   1. recompute_opt_tariff() on a flag table recomputes over the published
#      rows only and leaves the flagged rows' cell values untouched; on the
#      published rows it equals the recompute of the drop table;
#   2. analysis/gate_v0100.R judges optimizer non-convergence on directly
#      estimated rows: a table whose Tier-3 share (convergence -1 by
#      construction) moves while the optimizer share does not PASSES; one
#      whose optimizer share rises by more than 0.1 point FAILS.
# ============================================================================

.fr_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.fr_run <- function(cfg, dt) {
  unlink(list.files(".", pattern = "_fs_checkpoint\\.rds$", full.names = TRUE))
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

test_that("recompute_opt_tariff() leaves flagged rows untouched and equals the drop table on published rows", {
  .fr_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  cfg_d <- make_synthetic_cfg(); cfg_d$bw_lag <- "calendar"; cfg_d$tail_trim_pct <- 0.10
  cfg_f <- cfg_d; cfg_f$stage2_trim_action <- "flag"
  on.exit(unlink(paste0(build_output_prefix(cfg_d), c("_stage2_trimmed.csv", "_stage2_trimmed.rds", "_stage2_fallbacks.csv"))), add = TRUE)
  d <- finalize_saved_output(.fr_run(cfg_d, dt)); f <- finalize_saved_output(.fr_run(cfg_f, dt))
  expect_gt(sum(!is.na(f$trim_reason)), 0L)
  flagged_before <- f[!is.na(trim_reason), .(importer, exporter, good, opt_tariff, opt_tariff_all)]
  set.seed(7); f2 <- copy(f); d2 <- copy(d)
  f2[is.na(trim_reason), opt_tariff := opt_tariff * runif(.N, 0.5, 1.5)]          # disturb the published cell values
  d2[, opt_tariff := opt_tariff * runif(.N, 0.5, 1.5)]
  recompute_opt_tariff(f2); recompute_opt_tariff(d2)
  expect_equal(f2[!is.na(trim_reason), .(importer, exporter, good, opt_tariff, opt_tariff_all)], flagged_before)
  pub <- f2[is.na(trim_reason)]; setkey(pub, importer, exporter, good); setkey(d2, importer, exporter, good)
  expect_equal(pub$opt_tariff, d2$opt_tariff, tolerance = 1e-12)
  expect_equal(pub$opt_tariff_all, d2$opt_tariff_all, tolerance = 1e-12)
})

test_that("gate_v0100.R: Tier-3 share movement passes, an optimizer non-convergence rise fails", {
  .fr_setup()
  script <- file.path(locate_source_dir(), "..", "analysis", "gate_v0100.R"); skip_if_not(file.exists(script))
  mk <- function(n_t3, n_nc, fallback = 2.4728, seed = 1L) {
    set.seed(seed); n <- 400L
    x <- data.table(importer = as.character(rep(1:40, each = 10)), exporter = as.character(rep(1:10, 40)), good = "0101",
                    gamma = exp(rnorm(n, -0.3, 0.5)), sigma = rep(c(rep(fallback, 16), runif(24, 1.5, 6)), each = 10),
                    tier = 1L, convergence = 0L, opt_tariff = 0.7, sigma_robust = FALSE, gamma_v_resid = abs(rnorm(n, 0, 0.01)))
    x[seq_len(n_t3), `:=`(tier = 3L, convergence = -1L)]
    if (n_nc > 0L) x[(n_t3 + 1L):(n_t3 + n_nc), convergence := -1L]
    x[, trim_reason := NA_character_]
    rbind(x, data.table(importer = "41", exporter = "1", good = "0101", gamma = 50, sigma = 3, tier = 1L, convergence = 0L,
                        opt_tariff = 0.7, sigma_robust = FALSE, gamma_v_resid = NA_real_, trim_reason = "gamma_hi"))
  }
  s1 <- data.table(importer = as.character(1:40), good = "0101", status = "ok", sigma = c(rep(1.05, 16), runif(24, 1.5, 6)),
                   sigma_se = c(rep(0.2, 16), rep(0.1, 24)), sigma_capped = FALSE)
  old <- mk(n_t3 = 100L, n_nc = 2L, fallback = 2.3059); old[, trim_reason := NULL]; old <- old[1:400]
  run_gate <- function(new) {
    p_o <- tempfile(fileext = ".rds"); p_n <- tempfile(fileext = ".rds"); p_s <- tempfile(fileext = ".rds"); p_md <- tempfile(fileext = ".md")
    saveRDS(old, p_o); saveRDS(new, p_n); saveRDS(s1, p_s)
    out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(script, "--old", p_o, "--new", p_n, "--stage1", p_s, "--out", p_md), stdout = TRUE, stderr = TRUE))
    list(status = attr(out, "status"), md = if (file.exists(p_md)) readLines(p_md) else out)
  }
  ok <- run_gate(mk(n_t3 = 110L, n_nc = 2L))                       # Tier 3 grows (all-row "-1" share up), optimizer share flat
  expect_true(any(grepl("\\*\\*PASS\\*\\*", ok$md)), info = paste(ok$md, collapse = "\n"))
  expect_true(is.null(ok$status) || ok$status == 0L)
  bad <- run_gate(mk(n_t3 = 100L, n_nc = 20L))                     # optimizer non-convergence up ~6 points
  expect_true(any(grepl("\\*\\*FAIL\\*\\*", bad$md)), info = paste(bad$md, collapse = "\n"))
  expect_true(any(grepl("optimizer non-convergence", bad$md)))
})
