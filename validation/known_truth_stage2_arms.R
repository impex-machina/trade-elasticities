#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_stage2_arms.R  (prototype, patch 0150 follow-up)
#
# Stage-2 arms at known truth, run the way the pipeline runs Stage 2b:
# estimate_all_fixed_sigma() on the prepared panel with the pass-3 lookups.
#   A  shipped
#   B  import-only: every exporter Tier 2, no reference export row (Eq. (11) absent)
#   C  V rule: reference destination = most differenced periods, ties by value
#   D  hybrid: Eq. (11) only for the reference exporter's own row (every other
#      exporter Tier 2) -- pins gamma_k, which enters every import row
#   S  sigma update: the pipeline's sigma_update_import() (R/sigma_update.R,
#      patch 0152) at the shipped Stage-2b gamma-hats -- the flag's first pass:
#      every cell with import rows, fallback cells included, floor 1.02,
#      ceiling --stage1-sigma-cap, a floor/cap minimum is no update; then
#      Stage 2b re-run at the updated sigma and sigma_V; no iteration
#   H  hybrid as D with the import constant forced on: the cell estimator
#      concentrates fn. 14's constant out only when M >= 2, so B and D run
#      without it as a side effect; H isolates that
#   T  as S, then shrunk toward the full-panel level by b_full = 2B/(1+B)
#      (patch 0154, B = KT_SHRINK_B, default 0.44 = the synthetic two-window
#      census); cells with no updated sigma take the level, as the flag does
#   E  shipped structure, TRUE sigma, lambda 0   (the repo's upper-bound baseline)
#   G  V rule,            TRUE sigma, lambda 0
# Readings against the true gammas, published estimated rows only:
#   R1 within-cell r of ln gamma (cell-demeaned), R2 cor(ln opt_tariff, ln tau*),
#   row |log error| median and share < 0.2, cell-mean |log error| median.
#
# Usage (sources the runner; Stage 1/2a/2b outputs must exist in --out-dir):
#   KT_SEED=20261015 KT_WITHIN_SD=0.7 KT_GOODS=12 KT_ARMS=A,B,C,D,H,S,E,G \
#   Rscript validation/known_truth_stage2_arms.R --data <world>/BACI_HS92_V202601 \
#           --out-dir <world>/out --ncores 1 --stage all
# Each arm's table is saved as <out-dir>/kt_arm_<X>.rds; rerun with a subset of
# KT_ARMS to add arms, the summary reads every saved arm.
# ===========================================================================
kt_seed  <- as.integer(Sys.getenv("KT_SEED", "20261015")); kt_wsd <- as.numeric(Sys.getenv("KT_WITHIN_SD", "0.7"))
kt_goods <- as.integer(Sys.getenv("KT_GOODS", "12")); kt_arms <- strsplit(Sys.getenv("KT_ARMS", "A,B,C,E,G"), ",")[[1]]
.this_dir <- function() { f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else normalizePath(".") }
.root <- normalizePath(file.path(.this_dir(), ".."))
source(file.path(.root, "scripts", "run_estimation.R"))
stopifnot(exists("dt_country"), exists("paths"))
if (!exists("config_2b")) {   # as in known_truth_sigma_update.R: the runner's else-branch config, pass-3 lookups
  config_2b <- config_country
  .lk <- stage2b_sigma_lookups(sigma_clean)
  config_2b$sigma_lookup <- .lk$sigma_lookup; config_2b$sigma_se_lookup <- .lk$sigma_se_lookup
  config_2b$sigma_adjust_lookup <- .lk$sigma_adjust_lookup; config_2b$sigma_V_lookup <- .lk$sigma_V_lookup
  config_2b$sigma_fallback <- sigma_fallback; config_2b$shrinkage_priors <- country_priors
  config_2b$shrinkage_lambda <- config$shrinkage_lambda
  config_2b$tier1_min_periods <- config$tier1_min_periods; config_2b$tier1_min_dests <- config$tier1_min_dests
  config_2b$tier2_min_periods <- config$tier2_min_periods
  config_2b$sigma_V_default <- sigma_fallback; config_2b$gamma_V_default <- exp(median(country_priors$ln_gamma_prior))
  config_2b$sigma_start <- sigma_fallback; config_2b$gamma_start <- config_2b$gamma_V_default
  .rmap <- build_region_map(); .cc <- unique(as.integer(dt_country$importer))
  .c2r <- data.table::data.table(cty_code = .cc, region = assign_regions(.cc, .rmap))
  .gvc <- merge(.c2r, s2b_priors$gam_V_regional, by = "region", allow.cartesian = TRUE)
  config_2b$gamma_V_lookup <- .gvc[, .(importer = as.character(cty_code), good, gamma)]
  .p2 <- paste0(out_base_country, "_fixed_sigma_pass2.rds")
  if (file.exists(.p2)) { .prev <- readRDS(.p2); data.table::setDT(.prev)
    config_2b$gamma_V_exporter_lookup <- .prev[is_estimated_row(tier, convergence) & convergence == 0L & is.finite(gamma) & gamma > 0 & is_published_row(.prev),
                                               .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good), gamma)] }
  config_2b <- init_from_regional(config_2b, regional_handoff)
}
config_2b$checkpoint_file <- NULL; config_2b$out_prefix <- NULL
cat("\n\n========== STAGE-2 ARMS AT KNOWN TRUTH ==========\n")
.truth_file <- file.path(dirname(opts$data), "truth.rds")
if (file.exists(.truth_file)) {       # written by validation/synthetic_baci.R's CLI or by known_truth_eq11_worlds.R
  truth <- readRDS(.truth_file); cat("  truth read from", .truth_file, "\n")
} else {                              # a flat world from the heterogeneity harness: regenerate from the seed
  sb <- new.env(); sys.source(file.path(.root, "validation", "synthetic_baci.R"), envir = sb)
  .tmp <- file.path(tempdir(), sprintf("kt_truth_w%g_s%d", kt_wsd, kt_seed), "BACI_HS92_V202601")
  truth <- sb$make_synthetic_baci_dir(.tmp, n_goods = kt_goods, seed = kt_seed, within_sd = kt_wsd, good_sd = 0, importer_sd = 0)
  unlink(dirname(.tmp), recursive = TRUE)
}
tr_sig <- data.table::copy(truth$sigma)[, `:=`(importer = as.character(importer), good = as.character(good))]
tr_gam <- data.table::copy(truth$gamma)[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]

.bem_shipped <- build_export_moments
.bem_periods <- local({ src <- deparse(build_export_moments)
  hit <- grep("ref_dest <- dest_stats\\$importer\\[which.max\\(dest_stats\\$dest_val\\)\\]", src)
  if (length(hit) != 1L) stop("could not find the V rule in build_export_moments()")
  src[hit] <- "    dest_stats <- exp_flows[importer != focal_importer, .(dest_val = sum(cusval, na.rm = TRUE), n_per = sum(is.finite(lp_dif))), by = importer]; data.table::setorder(dest_stats, -n_per, -dest_val); ref_dest <- dest_stats$importer[1L]"
  eval(parse(text = src)) })

# ---- arm S: the pipeline's sigma update (R/sigma_update.R, patch 0152) at the shipped Stage-2b gamma-hats ----
# (through the v3 harness this was an introspection profile with a ceiling of 60 and no floor/cap rule; arm S is now
# exactly the flag's first pass: Eq. (10) block, floor 1.02, ceiling --stage1-sigma-cap, a floor/cap minimum is no update)
.harness_sigma_profile <- function(cfg, s2b_file) {
  s2b <- readRDS(s2b_file); data.table::setDT(s2b)
  upd <- sigma_update_import(cfg, dt_country, s2b[is.finite(gamma) & gamma > 0, .(importer, exporter, good, gamma)],
                             floor = 1.02, ceiling = cfg$stage1_sigma_cap)
  cat(sprintf("  sigma profile: %d cells profiled, %d updated, %d at the floor, %d at the cap\n", nrow(upd), sum(upd$status == "ok"),
              sum(upd$status == "floor"), sum(upd$status == "ceiling")))
  upd[, `:=`(importer = as.character(importer), good = as.character(good))]
}
.harness_sigma_update <- function(cfg, s2b_file) .harness_sigma_profile(cfg, s2b_file)[status == "ok", .(importer, good, sigma)]
# arm T (patch 0154): the update shrunk toward the level by Spearman-Brown's b_full = 2B / (1 + B), B from KT_SHRINK_B
# (the synthetic two-window census read B = 0.44 for the updated sigma); cells with no updated sigma take the level
.harness_sigma_shrunk <- function(cfg, s2b_file, B) {
  prof <- .harness_sigma_profile(cfg, s2b_file); ok <- prof[status == "ok"]
  L <- median(log(ok$sigma - 1)); b_full <- 2 * B / (1 + B); level_sigma <- 1 + exp(L)
  prof[, sigma_pub := fifelse(status == "ok", 1 + exp(L + b_full * (log(sigma - 1) - L)), level_sigma)]
  cat(sprintf("  arm T: B = %.3f, b_full = %.3f, level sigma %.3f | median sigma unshrunk %.3f shrunk %.3f\n", B, b_full, level_sigma, median(ok$sigma), median(prof[status == "ok", sigma_pub])))
  list(upd = prof[, .(importer, good, sigma = sigma_pub)], level = level_sigma)
}

.est_shipped <- estimate_importer_product_fixed_sigma
.est_const_always <- local({
  src <- deparse(estimate_importer_product_fixed_sigma)
  hit <- grep("imp_const <- imp_const_cfg && exp_mom\\$M >= 2L", src)
  if (length(hit) != 1L) stop("could not find the import-constant guard in estimate_importer_product_fixed_sigma()")
  src[hit] <- sub("imp_const_cfg && exp_mom\\$M >= 2L", "imp_const_cfg", src[hit])
  eval(parse(text = src))
})

arm_cfg <- function(arm) {
  cfg <- config_2b
  if (arm %in% c("H")) { cfg$tier1_min_dests <- .Machine$integer.max; cfg$stage2_ref_export_moment <- "on" }
  if (arm %in% c("B")) { cfg$tier1_min_dests <- .Machine$integer.max; cfg$stage2_ref_export_moment <- "off" }
  if (arm %in% c("D")) { cfg$tier1_min_dests <- .Machine$integer.max; cfg$stage2_ref_export_moment <- "on" }
  if (arm %in% c("S", "T")) {
    upd <- if (arm == "S") .harness_sigma_update(config_2b, paths$country_file) else {
      sh <- .harness_sigma_shrunk(config_2b, paths$country_file, as.numeric(Sys.getenv("KT_SHRINK_B", "0.44")))
      cfg$sigma_fallback <- sh$level; cfg$sigma_V_default <- sh$level; sh$upd }
    k_upd <- paste(upd$importer, upd$good, sep = "\r")
    replace_sigma <- function(tab) rbind(tab[!paste(as.character(importer), as.character(good), sep = "\r") %in% k_upd,
                                             .(importer = as.character(importer), good = as.character(good), sigma)], upd)
    cfg$sigma_lookup <- replace_sigma(config_2b$sigma_lookup); cfg$sigma_V_lookup <- replace_sigma(config_2b$sigma_V_lookup)
    drop_cells <- function(tab) if (is.null(tab)) NULL else tab[!paste(as.character(importer), as.character(good), sep = "\r") %in% k_upd]
    cfg$sigma_se_lookup <- drop_cells(config_2b$sigma_se_lookup); cfg$sigma_adjust_lookup <- drop_cells(config_2b$sigma_adjust_lookup)
    cat(sprintf("  arm S: sigma median before %.3f (clean set) after %.3f (updated cells)\n", median(config_2b$sigma_lookup$sigma), median(upd$sigma)))
  }
  if (arm %in% c("E", "G")) {
    cfg$sigma_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]; cfg$sigma_fallback <- median(tr_sig$sigma_true)
    cfg$sigma_V_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]; cfg$sigma_V_default <- median(tr_sig$sigma_true)
    cfg$sigma_se_lookup <- NULL; cfg$sigma_adjust_lookup <- NULL; cfg$shrinkage_lambda <- 0
  }
  cfg
}
for (arm in kt_arms) {
  cat(sprintf("\n----- arm %s -----\n", arm))
  build_export_moments <<- if (arm %in% c("C", "G")) .bem_periods else .bem_shipped
  estimate_importer_product_fixed_sigma <<- if (arm %in% c("H")) .est_const_always else .est_shipped
  t0 <- Sys.time()
  res <- estimate_all_fixed_sigma(arm_cfg(arm), ncores = 1L, prepared_dt = dt_country)
  build_export_moments <<- .bem_shipped; estimate_importer_product_fixed_sigma <<- .est_shipped
  saveRDS(res, file.path(opts$out_dir, sprintf("kt_arm_%s.rds", arm)))
  cat(sprintf("arm %s: %d rows, %.0f s\n", arm, nrow(res), as.numeric(Sys.time() - t0, units = "secs")))
}

# ---- readings over every saved arm ----
read_arm <- function(arm) {
  r <- readRDS(file.path(opts$out_dir, sprintf("kt_arm_%s.rds", arm))); data.table::setDT(r)
  r <- r[is_published_row(r) & is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0]
  r[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]
  r <- merge(r, tr_gam, by = c("importer", "exporter", "good"))
  r <- merge(r, tr_sig, by = c("importer", "good"))
  r[, `:=`(le = log(gamma / gamma_true), lg = log(gamma), lt = log(gamma_true))]
  r[, `:=`(dlg = lg - mean(lg), dlt = lt - mean(lt), ncell = .N), by = .(importer, good)]
  # true optimal tariff with the true sigma and the same mean-trade weights the arm used
  cell <- r[, .(tau_hat = opt_tariff[1], tau_true = optimal_tariff(gamma_true, sigma_true[1], avg_trade),
                le_cell = log(mean(gamma) / mean(gamma_true))), by = .(importer, good)]
  sig_cell <- unique(r[, .(importer, good, sigma, sigma_true)])
  data.table::data.table(arm = arm, rows = nrow(r), cells = nrow(cell),
                         sigma_med_abs_lr = round(median(abs(log((sig_cell$sigma - 1) / (sig_cell$sigma_true - 1)))), 3),
                         R1_within_r = round(cor(r[ncell >= 3, dlg], r[ncell >= 3, dlt]), 3),
                         R2_tariff_r = round(cor(log(cell$tau_hat), log(cell$tau_true), use = "complete.obs"), 3),
                         row_med_abs_le = round(median(abs(r$le)), 3), row_share_lt_0.2 = round(mean(abs(r$le) < 0.2), 3),
                         cell_med_abs_le = round(median(abs(cell$le_cell)), 3), tariff_med_abs_le = round(median(abs(log(cell$tau_hat / cell$tau_true)), na.rm = TRUE), 3))
}
arms_done <- sub("^kt_arm_([A-Z])\\.rds$", "\\1", list.files(opts$out_dir, pattern = "^kt_arm_[A-Z]\\.rds$"))   # not kt_arm_readings.rds
cat("\n=== readings (published estimated rows vs the true gammas) ===\n")
readings_all <- data.table::rbindlist(lapply(sort(arms_done), read_arm)); print(readings_all)
readings_t1 <- NULL
# the rows where Eq. (11) acts: Tier 1 in the shipped arm A, read in every arm on that same row set
if ("A" %in% arms_done) {
  loadr <- function(a) { r <- readRDS(file.path(opts$out_dir, sprintf("kt_arm_%s.rds", a))); data.table::setDT(r)
    r <- r[is_published_row(r) & is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0]
    r[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]
    merge(r, tr_gam, by = c("importer", "exporter", "good")) }
  A <- loadr("A"); t1 <- A[tier == 1L, .(importer, exporter, good)]
  cat(sprintf("\n=== the same readings on the rows that are Tier 1 in arm A (%d of %d rows; mean gamma_shrink_wt there %.3f) ===\n",
              nrow(t1), nrow(A), A[tier == 1L, mean(gamma_shrink_wt, na.rm = TRUE)]))
  readings_t1 <- data.table::rbindlist(lapply(sort(arms_done), function(a) {
    r <- merge(loadr(a), t1, by = c("importer", "exporter", "good"))
    r[, `:=`(lg = log(gamma), lt = log(gamma_true))]; r[, `:=`(dlg = lg - mean(lg), dlt = lt - mean(lt), n = .N), by = .(importer, good)]
    data.table::data.table(arm = a, rows = nrow(r), within_r_tier1 = round(cor(r[n >= 3, dlg], r[n >= 3, dlt]), 3),
                           med_abs_le_tier1 = round(median(abs(r$lg - r$lt)), 3)) }))
  print(readings_t1)
}
saveRDS(list(all = readings_all, tier1 = readings_t1, seed = kt_seed, within_sd = kt_wsd, goods = kt_goods),
        file.path(opts$out_dir, "kt_arm_readings.rds"))
