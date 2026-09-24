#!/usr/bin/env Rscript
# =============================================================================
# analysis/stage2_shrinkage_census.R   (patch 0067, 2026-09-24 fresh-eyes audit #3, F1)
# Reads only the shipped Stage-2b and Stage-2a tables (no raw cache, no
# re-estimation) and asks how much of the published gamma_ij is data and how
# much is the good-level log-ridge prior. Background (fresh_eyes_review_
# 20260924.md, F1): the Stage-2 objective is an SSR over one time-averaged
# row per exporter, of order Y^2, plus lambda * (ln gamma - ln prior)^2; the
# data curvature per parameter (~w_j (d pred_j / d gamma_j)^2, 1e-3 .. 1e-2)
# does not grow with the panel length, while the prior curvature 2 lambda /
# gamma^2 is ~0.4 at lambda = 0.1, so the prior share of curvature
# (gamma_shrink_wt, median 0.98 shipped) is ~1 at every T. On the structural
# DGP the slope of log gamma_hat on log gamma_true at that shrink_wt is 0.01.
# This census measures the real-data counterparts.
# Usage (from the repo root, shipped tables in data/derived):
#   Rscript analysis/stage2_shrinkage_census.R \
#       --stage2b data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds \
#       --stage2a data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds \
#       [--out results/stage2_shrinkage_census.json] [--md docs/results/stage2_shrinkage_census.md]
# Questions:
#   Q1  gamma_shrink_wt on the directly estimated rows (tier 0/1/2, fitted):
#       distribution overall, by tier, by within-cell trade rank; the implied
#       data share d = 2(1-s)/(2-s) [with s = 2P/(JWJ+2P) as the column is
#       defined, JWJ/(JWJ+P) = 2(1-s)/(2-s) is the share of the estimate's
#       curvature that is data in half-objective units]; trade-weighted means.
#   Q2  Variance decomposition of log gamma on estimated rows: good /
#       importer x good within good / exporter within cell, unweighted and
#       trade-weighted (avg_trade). If F1 holds the exporter-within-cell
#       share is a few percent.
#   Q3  Distance from the Stage-2b prior, rebuilt from the Stage-2a table
#       exactly as scripts/run_estimation.R does (median log gamma by good
#       over sigma/gamma-clean regional rows): |log gamma - ln prior| by tier,
#       shares within 1% / 5% / 20%, the reference rows separately.
#   Q4  Within-cell dispersion of log gamma (cells with >= 2 estimated
#       exporters) against the across-good dispersion of the prior.
#   Q5  opt_tariff against the prior at the cell level.
#   Q6  |dev| and implied data share by shrink_wt bin.
# The function shrinkage_census(s2b, s2a) does the work so the test suite can
# drive it on synthetic tables; the CLI block below only runs when the script
# is the top-level Rscript target.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.vd_nested <- function(x, good, cell, w = NULL) {
  # weighted nested sum-of-squares decomposition: total = good + cell|good + within cell
  if (is.null(w)) w <- rep(1, length(x))
  d <- data.table(x = x, good = good, cell = cell, w = w)
  d <- d[is.finite(x) & is.finite(w) & w > 0]
  if (nrow(d) < 2L) return(list(n = nrow(d), n_goods = NA_integer_, n_cells = NA_integer_, var_total = NA_real_,
                                share_good = NA_real_, share_cell_within_good = NA_real_, share_exporter_within_cell = NA_real_))
  xbar <- sum(d$w * d$x) / sum(d$w)
  d[, xg := sum(w * x) / sum(w), by = good]
  d[, xc := sum(w * x) / sum(w), by = cell]
  ss_tot <- sum(d$w * (d$x - xbar)^2)
  list(n = nrow(d), n_goods = uniqueN(d$good), n_cells = uniqueN(d$cell),
       var_total = ss_tot / sum(d$w),
       share_good = sum(d$w * (d$xg - xbar)^2) / ss_tot,
       share_cell_within_good = sum(d$w * (d$xc - d$xg)^2) / ss_tot,
       share_exporter_within_cell = sum(d$w * (d$x - d$xc)^2) / ss_tot)
}

.q <- function(x, p = c(0.1, 0.25, 0.5, 0.75, 0.9)) {
  x <- x[is.finite(x)]
  if (!length(x)) return(setNames(as.list(rep(NA_real_, length(p))), paste0("p", p * 100)))
  setNames(as.list(unname(quantile(x, p))), paste0("p", p * 100))
}

shrinkage_census <- function(s2b, s2a) {
  s2b <- as.data.table(s2b); s2a <- as.data.table(s2a)
  for (nm in c("importer", "exporter", "good", "gamma", "tier", "convergence"))
    if (!nm %in% names(s2b)) stop("Stage-2b table lacks column ", nm)
  if (!"gamma_shrink_wt" %in% names(s2b)) s2b[, gamma_shrink_wt := NA_real_]
  if (!"avg_trade" %in% names(s2b)) s2b[, avg_trade := NA_real_]
  if (!"opt_tariff" %in% names(s2b)) s2b[, opt_tariff := NA_real_]
  s2b[, good := as.character(good)]; s2a[, good := as.character(good)]

  # --- the Stage-2b prior, rebuilt as run_estimation.R builds country_priors ---
  regional_clean <- s2a[!is.na(sigma) & !is.na(gamma) & gamma > 0]
  priors <- regional_clean[, .(ln_gamma_prior = median(log(gamma), na.rm = TRUE)), by = good]

  # --- directly estimated rows (the is_estimated_row() rule of patch 0066) ---
  est <- s2b[!is.na(tier) & tier < 3L & !(convergence %in% -1L) & is.finite(gamma) & gamma > 0]
  est[, cell := paste(importer, good, sep = "|")]
  est[, lg := log(gamma)]
  est <- priors[est, on = "good"]
  est[, dev := lg - ln_gamma_prior]
  est[, s := gamma_shrink_wt]
  est[, data_share := ifelse(is.finite(s), 2 * (1 - s) / (2 - s), NA_real_)]
  est[, w := ifelse(is.finite(avg_trade) & avg_trade > 0, avg_trade, NA_real_)]
  est[, trade_rank := frank(-fifelse(is.finite(w), w, 0), ties.method = "first"), by = cell]
  est[, rank_bin := cut(trade_rank, c(0, 1, 3, 10, Inf), labels = c("1", "2-3", "4-10", ">10"))]
  est[, n_est_cell := .N, by = cell]

  wmean <- function(x, w) { ok <- is.finite(x) & is.finite(w) & w > 0; if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) / sum(w[ok]) }

  # ---- Q1: shrink_wt ----
  s_ok <- est[is.finite(s)]
  q1 <- list(
    n_estimated_rows = nrow(est), n_with_shrink_wt = nrow(s_ok),
    shrink_wt = .q(s_ok$s), shrink_wt_mean = mean(s_ok$s),
    share_gt_0_9 = mean(s_ok$s > 0.9), share_gt_0_95 = mean(s_ok$s > 0.95), share_gt_0_99 = mean(s_ok$s > 0.99),
    implied_data_share = .q(s_ok$data_share), implied_data_share_mean = mean(s_ok$data_share),
    implied_data_share_trade_weighted = wmean(s_ok$data_share, s_ok$w),
    one_minus_shrink_wt_trade_weighted = wmean(1 - s_ok$s, s_ok$w),
    by_tier = s_ok[, .(n = .N, shrink_wt_median = median(s), data_share_median = median(data_share),
                       data_share_trade_weighted = wmean(data_share, w)), by = tier][order(tier)],
    by_trade_rank = s_ok[, .(n = .N, shrink_wt_median = median(s), data_share_median = median(data_share),
                             data_share_trade_weighted = wmean(data_share, w)), by = rank_bin][order(rank_bin)]
  )

  # ---- Q2: variance decomposition of log gamma ----
  q2 <- list(
    unweighted     = .vd_nested(est$lg, est$good, est$cell),
    trade_weighted = .vd_nested(est$lg, est$good, est$cell, est$w),
    tier1_only     = .vd_nested(est[tier == 1L, lg], est[tier == 1L, good], est[tier == 1L, cell]),
    prior_only     = .vd_nested(est$ln_gamma_prior, est$good, est$cell)  # sanity: 100% good by construction
  )

  # ---- Q3: distance from the prior ----
  has_p <- est[is.finite(dev)]
  q3 <- list(
    n_with_prior = nrow(has_p), n_without_prior = nrow(est) - nrow(has_p),
    abs_dev = .q(abs(has_p$dev)), dev_signed = .q(has_p$dev),
    share_within_1pct = mean(abs(has_p$dev) < 0.01), share_within_5pct = mean(abs(has_p$dev) < 0.05),
    share_within_20pct = mean(abs(has_p$dev) < 0.20),
    abs_dev_trade_weighted_mean = wmean(abs(has_p$dev), has_p$w),
    by_tier = has_p[, .(n = .N, abs_dev_median = median(abs(dev)), abs_dev_p90 = quantile(abs(dev), 0.9),
                        share_within_5pct = mean(abs(dev) < 0.05)), by = tier][order(tier)],
    reference_rows = { r <- has_p[tier == 0L]; list(n = nrow(r), abs_dev = .q(abs(r$dev)), share_within_1pct = mean(abs(r$dev) < 0.01)) }
  )

  # ---- Q4: within-cell dispersion vs across-good prior dispersion ----
  wc <- est[n_est_cell >= 2L, .(sd_lg = sd(lg), n = .N), by = cell]
  q4 <- list(
    n_cells_ge2 = nrow(wc), within_cell_sd_log_gamma = .q(wc$sd_lg),
    across_good_sd_prior = sd(priors$ln_gamma_prior), sd_log_gamma_all_estimated = sd(est$lg),
    ratio_median_within_cell_sd_to_prior_sd = median(wc$sd_lg, na.rm = TRUE) / sd(priors$ln_gamma_prior)
  )

  # ---- Q5: opt_tariff vs prior at the cell level ----
  cells <- unique(est[, .(importer, good, opt_tariff, ln_gamma_prior)], by = c("importer", "good"))
  cells <- cells[is.finite(opt_tariff) & opt_tariff > 0 & is.finite(ln_gamma_prior)]
  cells[, dev_t := log(opt_tariff) - ln_gamma_prior]
  q5 <- list(n_cells = nrow(cells), abs_dev = .q(abs(cells$dev_t)),
             share_within_5pct = mean(abs(cells$dev_t) < 0.05), share_within_20pct = mean(abs(cells$dev_t) < 0.20))

  # ---- Q6: dev by shrink_wt bin ----
  sb <- has_p[is.finite(s)]
  sb[, s_bin := cut(s, c(-Inf, 0.5, 0.9, 0.95, 0.99, Inf), labels = c("<0.5", "0.5-0.9", "0.9-0.95", "0.95-0.99", ">=0.99"))]
  q6 <- sb[, .(n = .N, abs_dev_median = median(abs(dev)), abs_dev_p90 = quantile(abs(dev), 0.9),
               data_share_median = median(data_share)), by = s_bin][order(s_bin)]

  list(meta = list(n_rows_2b = nrow(s2b), n_estimated = nrow(est), n_goods_with_prior = nrow(priors),
                   timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
       q1 = q1, q2 = q2, q3 = q3, q4 = q4, q5 = q5, q6 = q6)
}

.render_md <- function(res, s2b_path, s2a_path) {
  f <- function(x, d = 3) ifelse(is.na(x), "NA", formatC(x, digits = d, format = "f"))
  qrow <- function(lbl, q) sprintf("| %s | %s | %s | %s | %s | %s |", lbl, f(q$p10), f(q$p25), f(q$p50), f(q$p75), f(q$p90))
  dt_md <- function(dt) {
    dt <- as.data.table(dt); hdr <- paste("|", paste(names(dt), collapse = " | "), "|")
    sep <- paste("|", paste(rep("---", ncol(dt)), collapse = " | "), "|")
    rows <- apply(dt, 1, function(r) paste("|", paste(vapply(r, function(v) if (is.na(suppressWarnings(as.numeric(v)))) as.character(v) else f(as.numeric(v)), ""), collapse = " | "), "|"))
    c(hdr, sep, rows)
  }
  vd_md <- function(nm, v) sprintf("| %s | %s | %s | %s | %s | %s |", nm, v$n, f(v$var_total), f(v$share_good), f(v$share_cell_within_good), f(v$share_exporter_within_cell))
  c(sprintf("# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)"), "",
    sprintf("Inputs: `%s` (%s rows), `%s`. Generated %s.", basename(s2b_path), format(res$meta$n_rows_2b, big.mark = ","), basename(s2a_path), res$meta$timestamp), "",
    sprintf("Directly estimated rows (tier 0/1/2, fitted): %s; goods with a Stage-2b prior: %s.", format(res$meta$n_estimated, big.mark = ","), res$meta$n_goods_with_prior), "",
    "## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)", "",
    "| quantity | p10 | p25 | p50 | p75 | p90 |", "|---|---|---|---|---|---|",
    qrow("gamma_shrink_wt", res$q1$shrink_wt), qrow("implied data share", res$q1$implied_data_share), "",
    sprintf("Mean shrink_wt %s; share > 0.9: %s, > 0.95: %s, > 0.99: %s. Implied data share: mean %s, trade-weighted %s (trade-weighted 1 - s: %s).",
            f(res$q1$shrink_wt_mean), f(res$q1$share_gt_0_9), f(res$q1$share_gt_0_95), f(res$q1$share_gt_0_99),
            f(res$q1$implied_data_share_mean), f(res$q1$implied_data_share_trade_weighted), f(res$q1$one_minus_shrink_wt_trade_weighted)), "",
    "By tier:", "", dt_md(res$q1$by_tier), "", "By within-cell trade rank of the exporter:", "", dt_md(res$q1$by_trade_rank), "",
    "## Q2 Variance decomposition of log gamma (estimated rows)", "",
    "| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |", "|---|---|---|---|---|---|",
    vd_md("unweighted", res$q2$unweighted), vd_md("trade-weighted", res$q2$trade_weighted), vd_md("tier 1 only", res$q2$tier1_only), vd_md("prior (sanity)", res$q2$prior_only), "",
    "## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|", "",
    "| quantity | p10 | p25 | p50 | p75 | p90 |", "|---|---|---|---|---|---|",
    qrow("|dev|, all estimated", res$q3$abs_dev), qrow("dev signed", res$q3$dev_signed), qrow("|dev|, reference rows", res$q3$reference_rows$abs_dev), "",
    sprintf("Share within 1%%: %s, within 5%%: %s, within 20%%: %s; trade-weighted mean |dev| %s; reference rows within 1%%: %s (n = %s).",
            f(res$q3$share_within_1pct), f(res$q3$share_within_5pct), f(res$q3$share_within_20pct), f(res$q3$abs_dev_trade_weighted_mean),
            f(res$q3$reference_rows$share_within_1pct), res$q3$reference_rows$n), "", dt_md(res$q3$by_tier), "",
    "## Q4 Within-cell dispersion vs across-good prior dispersion", "",
    "| quantity | p10 | p25 | p50 | p75 | p90 |", "|---|---|---|---|---|---|", qrow("within-cell sd(log gamma), cells with >= 2 estimated exporters", res$q4$within_cell_sd_log_gamma), "",
    sprintf("Across-good sd of ln prior: %s; sd of log gamma over all estimated rows: %s; median within-cell sd / prior sd: %s (n cells = %s).",
            f(res$q4$across_good_sd_prior), f(res$q4$sd_log_gamma_all_estimated), f(res$q4$ratio_median_within_cell_sd_to_prior_sd), format(res$q4$n_cells_ge2, big.mark = ",")), "",
    "## Q5 opt_tariff vs prior (cells)", "",
    "| quantity | p10 | p25 | p50 | p75 | p90 |", "|---|---|---|---|---|---|", qrow("|log opt_tariff - ln prior|", res$q5$abs_dev), "",
    sprintf("Cells: %s; within 5%%: %s; within 20%%: %s.", format(res$q5$n_cells, big.mark = ","), f(res$q5$share_within_5pct), f(res$q5$share_within_20pct)), "",
    "## Q6 |dev| by shrink_wt bin", "", dt_md(res$q6), "")
}

if (sys.nframe() == 0L && !exists("SHRINKAGE_CENSUS_NO_MAIN")) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  s2b_path <- get_arg("--stage2b", "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
  s2a_path <- get_arg("--stage2a", "data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds")
  out_json <- get_arg("--out", "results/stage2_shrinkage_census.json")
  out_md   <- get_arg("--md",  "docs/results/stage2_shrinkage_census.md")
  for (p in c(s2b_path, s2a_path)) if (!file.exists(p)) stop("input not found: ", p)
  cat("reading", s2b_path, "\n"); s2b <- readRDS(s2b_path)
  cat("reading", s2a_path, "\n"); s2a <- readRDS(s2a_path)
  res <- shrinkage_census(s2b, s2a)
  res$meta$stage2b <- s2b_path; res$meta$stage2a <- s2a_path
  res$meta$git_rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_)
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(res, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  md <- .render_md(res, s2b_path, s2a_path)
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n"); cat("wrote", out_json, "and", out_md, "\n")
}
