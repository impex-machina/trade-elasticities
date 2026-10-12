# ============================================================================
# test-0093-schema.R  (patch 0093, 2026-10-11)
#
# Two schema columns, both producible without re-estimation:
#   gamma_v_resid -- |ln gamma - ln gamma_prev| between the last two native
#                    gamma_V passes (attach_gamma_v_resid()), NA where either
#                    pass lacks a published directly estimated converged gamma;
#   trim_reason   -- NA on every kept row; under --stage2-trim-action flag
#                    the trimmed rows stay with their reason (add_trim_flags()
#                    builds the same table from a drop-mode table + its CSV).
# Locks: drop mode is the previous output plus two NA columns and the same
# rows; flag mode's published rows equal drop mode's exactly and its flagged
# rows are the CSV's; the CSV record carries the full row; gamma_v_step and
# build_summary read published rows only; the residual's definition; both
# scripts end to end; CLI / config / validation and the unchanged defaults.
# ============================================================================

.s93_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.s93_run <- function(cfg, dt) {
  unlink(list.files(".", pattern = "_fs_checkpoint\\.rds$", full.names = TRUE))
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}
.s93_cfg <- function(trim_pct = 0.10) { cfg <- make_synthetic_cfg(); cfg$bw_lag <- "calendar"; cfg$tail_trim_pct <- trim_pct; cfg }

test_that("drop vs flag: same published rows, flagged rows are the CSV's, record carries the full row", {
  .s93_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  cfg_d <- .s93_cfg(); cfg_f <- .s93_cfg(); cfg_f$stage2_trim_action <- "flag"
  tr_file <- paste0(build_output_prefix(cfg_d), "_stage2_trimmed.csv"); tr_rds <- paste0(build_output_prefix(cfg_d), "_stage2_trimmed.rds")
  on.exit(unlink(c(tr_file, tr_rds, paste0(build_output_prefix(cfg_d), "_stage2_fallbacks.csv"))), add = TRUE)
  d <- finalize_saved_output(.s93_run(cfg_d, dt))
  expect_true(all(c("gamma_v_resid", "trim_reason") %in% names(d)))
  expect_true(all(is.na(d$gamma_v_resid))); expect_true(all(is.na(d$trim_reason)))
  expect_true(file.exists(tr_file)); expect_true(file.exists(tr_rds))
  rec <- fread(tr_file, colClasses = list(character = c("importer", "exporter", "good", "ref_exporter")))
  rec_rds <- readRDS(tr_rds); setDT(rec_rds)
  expect_equal(nrow(rec_rds), nrow(rec))
  expect_gt(nrow(rec), 0L)
  expect_true(all(c("gamma_se", "opt_tariff", "avg_trade", "reason") %in% names(rec)))   # full row + reason
  f <- finalize_saved_output(.s93_run(cfg_f, dt))
  expect_equal(nrow(f), nrow(d) + nrow(rec))
  pub <- f[is.na(trim_reason)]; flg <- f[!is.na(trim_reason)]
  expect_identical(pub, d)                                                   # published rows identical, column for column
  expect_setequal(paste(flg$importer, flg$exporter, flg$good), paste(rec$importer, rec$exporter, rec$good))
  expect_setequal(unique(flg$trim_reason), unique(rec$reason))
  expect_true(all(is.na(flg$gamma_v_resid)))
  expect_equal(attr(.s93_run(cfg_f, dt), "run_meta")$n_trim_flagged, nrow(rec))
  # add_trim_flags(): drop table + rds record == flag table bit for bit; + CSV record == to 15 digits;
  # NULL record == drop schema; a foreign record is refused
  expect_identical(finalize_saved_output(add_trim_flags(d, rec_rds)), f)
  g <- finalize_saved_output(add_trim_flags(d, rec))
  expect_equal(g, f, tolerance = 1e-12)
  expect_identical(finalize_saved_output(add_trim_flags(d[, !c("gamma_v_resid", "trim_reason")], NULL)), d)
  expect_error(add_trim_flags(f, rec), "already in the table")
  # a pre-0093 (7-column) record: rows come back with NA in the unrecorded columns
  rec7 <- rec[, .(importer, exporter, good, sigma, gamma, tier, convergence, reason)]
  h <- add_trim_flags(d, rec7)
  expect_equal(attr(h, "trim_flag_census")$n_unrecorded_columns,
               length(setdiff(names(d), c(names(rec7), "gamma_v_resid", "trim_reason"))))   # the two the function fills itself
  expect_true(all(is.na(h[!is.na(trim_reason)]$gamma_se)))
  # consumers read published rows: gamma_v_step and build_summary agree across the two actions
  expect_equal(gamma_v_step(f, f)[["n"]], gamma_v_step(d, d)[["n"]])
  sd <- .s93_run(cfg_d, dt); sf <- .s93_run(cfg_f, dt)
  bd <- build_summary(sd, cfg_d); bf <- build_summary(sf, cfg_f)
  expect_equal(bf$global$n_estimates, bd$global$n_estimates)
  expect_equal(bf$global$n_trim_flagged, nrow(rec)); expect_equal(bd$global$n_trim_flagged, 0L)
  # the script, end to end
  in_path <- tempfile(fileext = ".rds"); out_path <- tempfile(fileext = ".rds"); saveRDS(d, in_path)
  script <- file.path(locate_source_dir(), "..", "scripts", "add_trim_flags.R"); skip_if_not(file.exists(script))
  res <- system2(file.path(R.home("bin"), "Rscript"), c(script, "--in", in_path, "--trimmed", tr_rds, "--out", out_path), stdout = TRUE, stderr = TRUE)
  expect_true(file.exists(out_path), info = paste(res, collapse = "\n"))
  got <- readRDS(out_path); setDT(got)
  expect_identical(got, f)
})

test_that("attach_gamma_v_resid(): the definition, and the script", {
  .s93_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  cfg <- .s93_cfg(trim_pct = 0)
  on.exit(unlink(paste0(build_output_prefix(cfg), c("_stage2_trimmed.csv", "_stage2_fallbacks.csv"))), add = TRUE)
  cur <- finalize_saved_output(.s93_run(cfg, dt))
  prev <- copy(cur)
  set.seed(1); prev[, gamma := gamma * exp(rnorm(.N, 0, 0.1))]        # a "previous pass" with moved gammas
  prev <- prev[-1L]                                                    # one row absent from the previous pass
  gone <- cur[1L]
  cen <- attach_gamma_v_resid(cur, prev)
  est <- is_estimated_row(cur$tier, cur$convergence) & cur$convergence %in% 0L & is.finite(cur$gamma) & cur$gamma > 0
  expect_true(all(is.na(cur$gamma_v_resid[!est])))
  expect_true(is.na(cur[importer == gone$importer & exporter == gone$exporter & good == gone$good]$gamma_v_resid))
  m <- merge(cur[est], prev[, .(importer, exporter, good, gp = gamma)], by = c("importer", "exporter", "good"))
  expect_equal(m$gamma_v_resid, abs(log(m$gamma) - log(m$gp)))
  expect_equal(cen$n_filled, sum(is.finite(cur$gamma_v_resid))); expect_gt(cen$n_filled, 0L)
  if (any(cur$tier == 3L)) expect_true(all(is.na(cur[tier == 3L]$gamma_v_resid)))
  # a flagged row in either pass gets NA
  cur2 <- copy(cur); cur2[est][1L]; i <- which(est)[1L]; cur2[i, trim_reason := "gamma_hi"]
  attach_gamma_v_resid(cur2, prev); expect_true(is.na(cur2$gamma_v_resid[i]))
  # idempotent: re-attaching against the same previous pass gives the same column
  before <- copy(cur$gamma_v_resid); attach_gamma_v_resid(cur, prev); expect_identical(cur$gamma_v_resid, before)
  # the script
  in_path <- tempfile(fileext = ".rds"); prev_path <- tempfile(fileext = ".rds"); out_path <- tempfile(fileext = ".rds")
  blank <- copy(cur)[, gamma_v_resid := NA_real_]; saveRDS(blank, in_path); saveRDS(prev, prev_path)
  script <- file.path(locate_source_dir(), "..", "scripts", "add_gamma_v_resid.R"); skip_if_not(file.exists(script))
  res <- system2(file.path(R.home("bin"), "Rscript"), c(script, "--prev", prev_path, "--in", in_path, "--out", out_path), stdout = TRUE, stderr = TRUE)
  expect_true(file.exists(out_path), info = paste(res, collapse = "\n"))
  got <- readRDS(out_path); setDT(got)
  expect_identical(got, finalize_saved_output(cur))
})

test_that("CLI, config and validation accept --stage2-trim-action and keep the default", {
  .s93_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_s93_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  cfg <- build_config(parse_cli(base)); expect_identical(cfg$stage2_trim_action, "flag"); expect_silent(validate_config(cfg))   # patch 0101 default
  r <- build_config(parse_cli(c(base, "--stage2-trim-action", "drop"))); expect_identical(r$stage2_trim_action, "drop")
  e <- build_config(parse_cli(c(base, "--stage2-trim-action", "flag"))); expect_identical(e$stage2_trim_action, "flag"); expect_silent(validate_config(e))
  expect_error(parse_cli(c(base, "--stage2-trim-action", "keep")), "stage2-trim-action")
  bad <- cfg; bad$stage2_trim_action <- "keep"; expect_error(validate_config(bad), "stage2_trim_action")
  expect_true(all(is_published_row(data.table(x = 1:3))))
  expect_identical(is_published_row(data.table(trim_reason = c(NA, "gamma_hi"))), c(TRUE, FALSE))
})
