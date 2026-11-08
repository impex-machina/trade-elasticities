#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_sigma_se.R  (patch 0160)
#
# The sandwich standard error of the profile sigma (R/sigma_update.R,
# sigma_profile_import()$se_ln), read at known truth on a synthetic world:
#   1. coverage -- the share of profiled cells whose interval
#      ln(sigma_update - 1) +/- 1.96 se_ln covers ln(sigma_true - 1) (the
#      unshrunk update is the estimator the SE describes; the shrinkage passes
#      it through as b_full x se_ln);
#   2. agreement with an exporter bootstrap -- on a subset of cells, the
#      exporters of the cell are resampled with replacement B times, the
#      import block re-profiled at the same gammas, and the sd of
#      ln(sigma - 1) over the draws compared with se_ln (ratio sandwich /
#      bootstrap, median over cells).
# Rule (fixed before the numbers): the SE ships if coverage is within
# 90-98% and the median ratio is within 0.8-1.25.
#
# Runs through the runner as the arms harness does: the shipped pipeline on
# the world, then the profile at the gamma_V-final gamma-hats. Env:
#   KT_SEED (20261015)  KT_WITHIN_SD (0.7)  KT_GOODS (12)  KT_BOOT_CELLS (40)  KT_BOOT_B (60)
# Usage (sandbox / Windows alike, a world directory W that holds BACI_HS92_V202601):
#   Rscript validation/known_truth_sigma_se.R --data W/BACI_HS92_V202601 --out-dir W/out --ncores 1 --stage all
# ===========================================================================
suppressPackageStartupMessages(library(data.table))
.root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])), ".."), mustWork = TRUE)
kt_seed <- as.integer(Sys.getenv("KT_SEED", "20261015")); kt_wsd <- as.numeric(Sys.getenv("KT_WITHIN_SD", "0.7")); kt_goods <- as.integer(Sys.getenv("KT_GOODS", "12"))
n_boot_cells <- as.integer(Sys.getenv("KT_BOOT_CELLS", "40")); n_boot <- as.integer(Sys.getenv("KT_BOOT_B", "60"))
source(file.path(.root, "scripts", "run_estimation.R"))   # the shipped pipeline on the world (loaded where its outputs exist)
stopifnot(exists("dt_country"), exists("paths"))
if (!exists("config_2b")) {   # the runner loaded Stage 2b: rebuild its config as the arms harness does (pass-3 lookups)
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

sb <- new.env(); sys.source(file.path(.root, "validation", "synthetic_baci.R"), envir = sb)
truth <- if (file.exists(file.path(dirname(opts$data), "truth.rds"))) readRDS(file.path(dirname(opts$data), "truth.rds")) else
  sb$make_synthetic_baci_dir(file.path(tempdir(), "kt_se", "BACI_HS92_V202601"), n_goods = kt_goods, seed = kt_seed, within_sd = kt_wsd, good_sd = 0, importer_sd = 0)
tr_sig <- copy(truth$sigma)[, `:=`(importer = as.character(importer), good = as.character(good))]

# the gamma_V-final gamma-hats (the table the update profiles at)
s2b <- readRDS(if (file.exists(paste0(out_base_country, "_fixed_sigma_pass3.rds"))) paste0(out_base_country, "_fixed_sigma_pass3.rds") else paths$country_file); setDT(s2b)
gam_tab <- s2b[is.finite(gamma) & gamma > 0, .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good), gamma)]
prof <- sigma_update_import(config_2b, dt_country, gam_tab, floor = 1.02, ceiling = config_2b$stage1_sigma_cap, ncores = 1L)
ok <- merge(prof[status == "ok" & is.finite(se_ln)], tr_sig, by = c("importer", "good"))
z <- (log(ok$sigma - 1) - log(ok$sigma_true - 1)) / ok$se_ln
cov95 <- mean(abs(z) <= 1.96); cov90 <- mean(abs(z) <= 1.645)
cat(sprintf("\n=== sandwich SE of the profile sigma at known truth (world seed %d, within_sd %.2f) ===\n", kt_seed, kt_wsd))
cat(sprintf("profiled %d cells, ok %d, se computable %d | median se_ln %.3f | median |ln ratio| %.3f\n", nrow(prof), sum(prof$status == "ok"), nrow(ok), median(ok$se_ln), median(abs(log(ok$sigma - 1) - log(ok$sigma_true - 1)))))
cat(sprintf("coverage of ln(sigma_true - 1): 95%% interval %.1f%% | 90%% interval %.1f%% | z: median %.2f, sd %.2f, p05 %.2f, p95 %.2f\n",
            100 * cov95, 100 * cov90, median(z), sd(z), quantile(z, 0.05), quantile(z, 0.95)))

# the exporter bootstrap on a subset of cells
set.seed(kt_seed)
sub <- ok[sample.int(nrow(ok), min(n_boot_cells, nrow(ok)))]
boot_sd <- rep(NA_real_, nrow(sub))
for (i in seq_len(nrow(sub))) {
  g <- sub$good[i]; imp <- sub$importer[i]
  dt_g <- dt_country[good == g]
  ed <- compute_exporter_dest_counts(dt_g); el <- compute_exporter_lookup(dt_g)
  cfg_g <- config_2b
  if (!is.null(cfg_g$gamma_V_exporter_lookup)) { gvt <- cfg_g$gamma_V_exporter_lookup[good == as.character(g)]; setkeyv(gvt, c("importer", "exporter")); cfg_g$gamma_V_exporter_lookup <- gvt }
  m <- tryCatch(estimate_importer_product_fixed_sigma(dt_g, imp, dt_g, cfg_g, exporter_dests = ed, exp_lookup = el, return_moments = TRUE), error = function(e) NULL)
  if (!is.list(m) || is.null(m$imp_Y)) next
  gt_g <- gam_tab[good == g & importer == imp]
  keys <- c(m$ref_exporter, m$exporter_order); gv <- gt_g$gamma[match(keys, gt_g$exporter)]
  if (any(!is.finite(gv))) next
  draws <- vapply(seq_len(n_boot), function(b) {
    idx <- sample.int(m$J, m$J, replace = TRUE)
    mb <- m; mb$imp_Y <- m$imp_Y[idx]; mb$imp_X <- m$imp_X[idx, , drop = FALSE]; mb$wt_imp <- m$wt_imp[idx]; mb$J <- length(idx)
    # the gammas travel with their rows: d = (gamma_k, gamma_j in exporter_order); gamma_k stays, the j's are resampled
    gvb <- c(gv[1], gv[-1][idx])
    pb <- sigma_profile_import(mb, gvb, floor = 1.02, ceiling = config_2b$stage1_sigma_cap)
    if (pb$status == "ok") log(pb$sigma - 1) else NA_real_
  }, numeric(1))
  if (sum(is.finite(draws)) >= n_boot * 0.8) boot_sd[i] <- sd(draws, na.rm = TRUE)
}
sub[, boot_sd := boot_sd]; sub <- sub[is.finite(boot_sd) & boot_sd > 0]
ratio <- sub$se_ln / sub$boot_sd
cat(sprintf("exporter bootstrap on %d cells (B = %d, cells with >= 80%% ok draws): sandwich / bootstrap ratio median %.2f, p25 %.2f, p75 %.2f | median boot sd %.3f, median sandwich %.3f\n",
            nrow(sub), n_boot, median(ratio), quantile(ratio, 0.25), quantile(ratio, 0.75), median(sub$boot_sd), median(sub$se_ln)))
verdict <- if (cov95 >= 0.90 && cov95 <= 0.98 && median(ratio) >= 0.8 && median(ratio) <= 1.25) {
  "SHIPS: coverage within 90-98% and the bootstrap ratio within 0.8-1.25"
} else sprintf("does not ship under the rule (coverage %.1f%%, ratio %.2f)", 100 * cov95, median(ratio))
cat("Reading (rule, patch 0160):", verdict, "\n")
saveRDS(list(prof = prof, ok = ok, boot = sub, cov95 = cov95, cov90 = cov90, ratio = ratio, verdict = verdict), file.path(opts$out_dir, "kt_sigma_se.rds"))
