#!/usr/bin/env Rscript
# ============================================================================
# analysis/stage2a_prior_rows_census.R  (patch 0079, 2026-09-29 fresh-eyes audit #4)
#
# The Stage-2b good-level prior ln_gamma_prior and the reference-destination
# gamma_V lookup are medians over Stage-2a rows. Through v0.8.2 those medians
# ran over EVERY Stage-2a row with gamma > 0, including the Tier-3 rows Stage
# 2a itself imputed at the Stage-1 good-level prior and the all-Tier-3
# early-return reference rows (convergence -1). This script measures, on a
# shipped Stage-2a table and without re-estimating anything, how far the two
# objects move when only directly estimated rows (is_estimated_row()) are
# used -- the census behind the --stage2b-prior-source {all|estimated} decision.
#
# Reads:  data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds
#         (or --stage2a PATH)
# Writes: results/stage2a_prior_rows_census.json (--out) and
#         docs/results/stage2a_prior_rows_census.md (--md)
#
# Usage (repo root):
#   Rscript analysis/stage2a_prior_rows_census.R
#   Rscript analysis/stage2a_prior_rows_census.R --stage2a PATH --out X.json --md Y.md
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
stage2a_path <- get_arg("--stage2a", "data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds")
out_json     <- get_arg("--out", "results/stage2a_prior_rows_census.json")
out_md       <- get_arg("--md",  "docs/results/stage2a_prior_rows_census.md")
if (!file.exists(stage2a_path)) stop("Stage-2a table not found: ", stage2a_path)

# The runner's objects, from the library, so the census uses the production
# definitions rather than a copy of them.
.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                      error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()

reg <- readRDS(stage2a_path); setDT(reg)
regional_clean <- reg[!is.na(sigma) & !is.na(gamma) & gamma > 0]

# --- row composition of what the medians run over ---------------------------
est <- is_estimated_row(regional_clean$tier, regional_clean$convergence)
composition <- list(
  n_rows_clean      = nrow(regional_clean),
  n_estimated       = sum(est),
  n_imputed         = sum(!est),
  share_imputed     = mean(!est),
  by_tier           = regional_clean[, .(n = .N, share = .N / nrow(regional_clean),
                                         imputed = sum(convergence %in% -1L)), by = tier][order(tier)],
  n_goods           = uniqueN(regional_clean$good),
  n_goods_with_imputed = uniqueN(regional_clean[!est, good]),
  n_goods_all_imputed  = sum(regional_clean[, .(all_imp = !any(is_estimated_row(tier, convergence))), by = good]$all_imp)
)

# --- priors both ways ----------------------------------------------------------
p_all <- stage2b_priors_from_regional(regional_clean, rows = "all")
p_est <- stage2b_priors_from_regional(regional_clean, rows = "estimated")

pri <- merge(p_all$country_priors[, .(good, ln_all = ln_gamma_prior)],
             p_est$country_priors[, .(good, ln_est = ln_gamma_prior)], by = "good", all.x = TRUE)
pri[, d_ln := ln_est - ln_all]
q <- function(x, p = c(.05, .1, .25, .5, .75, .9, .95)) { x <- x[is.finite(x)]; as.list(setNames(quantile(x, p), paste0("p", 100 * p))) }
prior_shift <- list(
  n_goods             = nrow(pri),
  n_goods_no_estimated_rows = sum(is.na(pri$ln_est)),
  median_gamma_all    = exp(median(pri$ln_all)),
  median_gamma_est    = exp(median(pri$ln_est, na.rm = TRUE)),
  d_ln_quantiles      = q(pri$d_ln),
  abs_d_ln_quantiles  = q(abs(pri$d_ln)),
  share_abs_gt_1pct   = mean(abs(pri$d_ln) > 0.01, na.rm = TRUE),
  share_abs_gt_5pct   = mean(abs(pri$d_ln) > 0.05, na.rm = TRUE),
  share_abs_gt_20pct  = mean(abs(pri$d_ln) > 0.20, na.rm = TRUE),
  share_identical     = mean(abs(pri$d_ln) < 1e-12, na.rm = TRUE)
)

gv <- merge(p_all$gam_V_regional[, .(region, good, g_all = gamma)],
            p_est$gam_V_regional[, .(region, good, g_est = gamma)], by = c("region", "good"), all.x = TRUE)
gv[, d_ln := log(g_est) - log(g_all)]
gamma_V_shift <- list(
  n_region_goods      = nrow(gv),
  n_without_estimated = sum(is.na(gv$g_est)),
  median_all          = median(gv$g_all),
  median_est          = median(gv$g_est, na.rm = TRUE),
  d_ln_quantiles      = q(gv$d_ln),
  abs_d_ln_quantiles  = q(abs(gv$d_ln)),
  share_abs_gt_5pct   = mean(abs(gv$d_ln) > 0.05, na.rm = TRUE),
  share_abs_gt_20pct  = mean(abs(gv$d_ln) > 0.20, na.rm = TRUE),
  share_identical     = mean(abs(gv$d_ln) < 1e-12, na.rm = TRUE)
)

git_rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1],
                    error = function(e) NA_character_)
out <- list(meta = list(stage2a = stage2a_path, git_rev = git_rev, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
            composition = composition, prior_shift = prior_shift, gamma_V_shift = gamma_V_shift)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8)

# --- markdown ------------------------------------------------------------------
f3 <- function(x) formatC(x, format = "f", digits = 3)
pc <- function(x) sprintf("%.1f%%", 100 * x)
tier_tab <- composition$by_tier
md <- c(
  "# Stage-2b priors: Stage-2a rows behind the medians (patch 0079 census)", "",
  sprintf("Table: `%s` (rev %s, %s).", stage2a_path, git_rev, out$meta$timestamp), "",
  "## What the v0.8.2 medians ran over", "",
  sprintf("- %s Stage-2a rows with gamma > 0; %s (%s) directly estimated, %s imputed (Tier 3 at the Stage-1 prior, or an all-Tier-3 early return).",
          format(composition$n_rows_clean, big.mark = ","), format(composition$n_estimated, big.mark = ","),
          pc(1 - composition$share_imputed), format(composition$n_imputed, big.mark = ",")),
  sprintf("- %d of %d goods carry at least one imputed row; %d goods have no estimated row at all (their prior is the Stage-1 prior under either rule).",
          composition$n_goods_with_imputed, composition$n_goods, composition$n_goods_all_imputed), "",
  "| tier | rows | share | imputed (convergence -1) |", "|---|---|---|---|",
  sprintf("| %d | %s | %s | %s |", tier_tab$tier, format(tier_tab$n, big.mark = ","), pc(tier_tab$share), format(tier_tab$imputed, big.mark = ",")), "",
  "## Good-level prior ln_gamma_prior: estimated-only minus all-rows", "",
  sprintf("- Median prior gamma: %s (all rows) vs %s (estimated rows).", f3(prior_shift$median_gamma_all), f3(prior_shift$median_gamma_est)),
  sprintf("- |d ln prior| quantiles p50 / p90 / p95: %s / %s / %s; identical on %s of goods; > 5%% on %s; > 20%% on %s.",
          f3(prior_shift$abs_d_ln_quantiles$p50), f3(prior_shift$abs_d_ln_quantiles$p90), f3(prior_shift$abs_d_ln_quantiles$p95),
          pc(prior_shift$share_identical), pc(prior_shift$share_abs_gt_5pct), pc(prior_shift$share_abs_gt_20pct)),
  sprintf("- Signed d ln prior p10 / p50 / p90: %s / %s / %s.", f3(prior_shift$d_ln_quantiles$p10), f3(prior_shift$d_ln_quantiles$p50), f3(prior_shift$d_ln_quantiles$p90)), "",
  "## Reference-destination gamma_V (region x good medians)", "",
  sprintf("- %s (region, good) cells; median %s (all) vs %s (estimated); |d ln| p50 / p90: %s / %s; identical on %s; > 5%% on %s; > 20%% on %s; %s cells have no estimated row.",
          format(gamma_V_shift$n_region_goods, big.mark = ","), f3(gamma_V_shift$median_all), f3(gamma_V_shift$median_est),
          f3(gamma_V_shift$abs_d_ln_quantiles$p50), f3(gamma_V_shift$abs_d_ln_quantiles$p90), pc(gamma_V_shift$share_identical),
          pc(gamma_V_shift$share_abs_gt_5pct), pc(gamma_V_shift$share_abs_gt_20pct), format(gamma_V_shift$n_without_estimated, big.mark = ",")), "",
  "## Reading", "",
  "The prior is a median, so it moves only where imputed rows are numerous enough to cross it; the quantiles above say how often that happens. A shift of a few percent in ln prior is small beside the within-cell dispersion Stage 2b estimates around it, but it is a systematic pull toward the Stage-1 prior, and `--stage2b-prior-source estimated` removes it at no cost. The decision rule for the flip: if |d ln prior| > 5% on more than a handful of goods, ship `estimated` at the next data release (a Stage 2b-only rerun; Stage 2a and Stage 1 are unchanged)."
)
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(sprintf("Wrote %s and %s\n", out_json, out_md))
cat(sprintf("Rows: %s clean, %s estimated, %s imputed (%s); prior |d ln| p50 %.4f / p90 %.4f, > 5%% on %s of goods\n",
            format(composition$n_rows_clean, big.mark = ","), format(composition$n_estimated, big.mark = ","),
            format(composition$n_imputed, big.mark = ","), pc(composition$share_imputed),
            prior_shift$abs_d_ln_quantiles$p50, prior_shift$abs_d_ln_quantiles$p90, pc(prior_shift$share_abs_gt_5pct)))
