#!/usr/bin/env Rscript
# ============================================================================
# analysis/product_summary.R  (patch 0127; published form patch 0128)
#
# A product-level (HS4) companion to the Stage-2b table. At known truth the
# pipeline recovers differences between products (reading R4a: the products'
# median gamma at r = 0.88 / 0.91, their opt_tariff at 0.89), weakly those
# between importers within a product, and not those between exporters within
# a cell (R1, R4b) -- so the product level is where the published estimates
# carry information. One row per HS4 good:
#   n_cells, n_rows, n_rows_estimated   published (importer, good) cells, rows,
#                                       directly estimated rows
#   trade                               sum of avg_trade over published rows
#   gamma_median                        median gamma over directly estimated rows
#   opt_tariff_median                   median over cells of the cell's opt_tariff
#   opt_tariff_total_median             (since v0.11.3) the same for opt_tariff_total
#   sigma_median                        median over cells of the published sigma
#   share_cells_own_sigma               cells whose sigma is their own estimate
# (patch 0128) No interval columns. Patch 0127 bootstrapped the product median
# over importers; on the shipped table those intervals were about +-0.5% wide
# (median ln(hi / lo) 0.011) because every importer's gamma for a product sits
# near the same product prior, and resampling importers never touches the
# prior -- the main source of a product's uncertainty. The census instead
# reports how far a product's median moves between the halves (the level gap).
# (patch 0130) Those halves are NOT independent for the product prior: the
# odd/even (--t-parity) runs of the 2% subsample re-estimated Stage 2b only, with
# the full-panel Stage 1 and Stage-2a tables, and the period runs re-estimated
# Stage 2a and 2b on the full-panel Stage 1 (hash check, patch 0130), so the
# correlations and the gap measure how little a product's median depends on the
# Stage-2 data given that Stage 1. The independent test is
# analysis/product_window_census.R (each period's own Stage 1, 2a and 2b).
# sigma differs little across products: one global value (the fallback, 2.47)
# predicts a cell's other-period sigma better than the cell's own estimate
# (docs/results/sigma_eb_period_census_v0110.md).
#
# Before the table is published, its reproducibility is measured on the 2%
# product subsample runs of the shipped configuration (patch 0119): the
# odd-year and even-year halves (within a period) and, as information, the
# 1995-2009 and 2010-2024 windows (across periods): the Spearman correlation
# across products, and the level gap |ln(median_a / median_b)| (median, p90).
#
# Reading (fixed in patch 0127, before the numbers): "publish" if, between the
# odd and even halves, the Spearman correlation across products of the
# product median gamma AND of the product median opt_tariff are both >= 0.5;
# "do not publish" if both are < 0.3; otherwise "partial" (decided with the
# numbers in hand). The subsample has ~25 products, so each correlation
# carries a bootstrap interval over products.
#
# Usage (repo root; local; ~1 min on the full table):
#   Rscript analysis/product_summary.R [--stage2b S2B.rds] [--odd O.rds --even E.rds]
#       [--early A.rds --late B.rds]
#       [--table data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv]
#       [--json results/product_summary_census.json] [--md docs/results/product_summary_census.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

#' The product table from a Stage-2b table.
product_summary <- function(s2b) {
  x <- data.table::as.data.table(s2b)
  if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
  x[, `:=`(importer = as.character(importer), good = as.character(good))]
  x[, est := is_estimated_row(tier, convergence)]
  has_src <- "sigma_source" %in% names(x)
  has_tot <- "opt_tariff_total" %in% names(x)                              # patch 0139
  cells <- x[, .(opt_tariff = opt_tariff[1L], opt_tariff_total = if (has_tot) opt_tariff_total[1L] else NA_real_, sigma = sigma[1L],
                 own_sigma = if (has_src) sigma_source[1L] == "estimated" else NA), by = .(good, importer)]
  out <- x[, .(n_cells = data.table::uniqueN(importer), n_rows = .N, n_rows_estimated = sum(est),
               trade = sum(avg_trade, na.rm = TRUE)), by = good]
  gs <- x[est == TRUE & is.finite(gamma) & gamma > 0, .(gamma_median = stats::median(gamma)), by = good]
  os <- cells[is.finite(opt_tariff), .(opt_tariff_median = stats::median(opt_tariff)), by = good]
  ts <- if (has_tot) cells[is.finite(opt_tariff_total), .(opt_tariff_total_median = stats::median(opt_tariff_total)), by = good]
  ss <- cells[, .(sigma_median = stats::median(sigma), share_cells_own_sigma = mean(own_sigma)), by = good]
  out <- Reduce(function(a, b) merge(a, b, by = "good", all.x = TRUE), Filter(Negate(is.null), list(out, gs, os, ts, ss)))
  data.table::setorder(out, good)
  out[]
}

#' Spearman correlation across products of two product tables' columns, with a
#' bootstrap interval over products.
product_reproducibility <- function(a, b, cols = c("gamma_median", "opt_tariff_median"), B = 1000L, seed = 20261017L) {
  set.seed(seed)
  m <- merge(a[, c("good", cols), with = FALSE], b[, c("good", cols), with = FALSE], by = "good", suffixes = c("_a", "_b"))
  res <- lapply(cols, function(k) {
    u <- m[[paste0(k, "_a")]]; v <- m[[paste0(k, "_b")]]; ok <- is.finite(u) & is.finite(v); u <- u[ok]; v <- v[ok]
    if (length(u) < 4L) return(list(products = length(u), spearman = NA_real_, lo = NA_real_, hi = NA_real_,
                                    gap_median = NA_real_, gap_p90 = NA_real_))
    r <- suppressWarnings(stats::cor(u, v, method = "spearman"))
    bs <- vapply(seq_len(B), function(i) { s <- sample.int(length(u), replace = TRUE); suppressWarnings(stats::cor(u[s], v[s], method = "spearman")) }, 0)
    ci <- stats::quantile(bs, c(0.025, 0.975), names = FALSE, na.rm = TRUE)
    pos <- u > 0 & v > 0                                    # (patch 0128) the level gap between the halves
    gap <- abs(log(u[pos] / v[pos]))
    list(products = length(u), spearman = r, lo = ci[1], hi = ci[2],
         gap_median = if (any(pos)) stats::median(gap) else NA_real_,
         gap_p90 = if (any(pos)) as.numeric(stats::quantile(gap, 0.9, names = FALSE)) else NA_real_)
  })
  stats::setNames(res, cols)
}

#' The pre-registered reading, from the odd/even reproducibility.
product_reading <- function(rep_oe) {
  if (is.null(rep_oe)) return("not measured")
  r <- c(rep_oe$gamma_median$spearman, rep_oe$opt_tariff_median$spearman)
  if (any(!is.finite(r))) return("not measured")
  if (all(r >= 0.5)) "publish" else if (all(r < 0.3)) "do not publish" else "partial"
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  source("R/utils_general.R")
  s2p <- get_arg("--stage2b", "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
  if (!file.exists(s2p)) stop("no Stage-2b table at ", s2p, " (scripts/download_outputs.R)")
  tab_p <- get_arg("--table", "data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv")
  json <- get_arg("--json", "results/product_summary_census.json"); md <- get_arg("--md", "docs/results/product_summary_census.md")
  t0 <- Sys.time()
  tab <- product_summary(readRDS(s2p))
  dir.create(dirname(tab_p), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(tab, tab_p)
  pair <- function(fa, fb) {
    pa <- get_arg(fa, NA_character_); pb <- get_arg(fb, NA_character_)
    if (is.na(pa) || is.na(pb)) return(NULL)
    if (!file.exists(pa) || !file.exists(pb)) stop("missing ", if (!file.exists(pa)) pa else pb)
    list(paths = c(pa, pb), rep = product_reproducibility(product_summary(readRDS(pa)), product_summary(readRDS(pb))))
  }
  oe <- pair("--odd", "--even"); pe <- pair("--early", "--late")
  reading <- product_reading(if (is.null(oe)) NULL else oe$rep)
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(stage2b = s2p, table = tab_p, products = nrow(tab), git_rev = rev,
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
  q <- function(v) as.list(stats::setNames(stats::quantile(v, c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE, names = FALSE), c("p10", "p25", "p50", "p75", "p90")))
  dist <- list(gamma_median = q(tab$gamma_median), opt_tariff_median = q(tab$opt_tariff_median), sigma_median = q(tab$sigma_median),
               share_cells_own_sigma = q(tab$share_cells_own_sigma))
  jsonlite::write_json(list(meta = meta, reading = reading, distribution = dist,
                            odd_even = if (is.null(oe)) NULL else c(list(paths = oe$paths), oe$rep),
                            early_late = if (is.null(pe)) NULL else c(list(paths = pe$paths), pe$rep)),
                       json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f2 <- function(x) formatC(x, digits = 2, format = "f"); f3 <- function(x) formatC(x, digits = 3, format = "f")
  pc <- function(x) sprintf("%.1f%%", 100 * (exp(x) - 1))
  rl <- function(lab, r) if (is.null(r)) character(0) else
    sprintf("| %s | %d | %s [%s, %s] | %s / %s | %s [%s, %s] | %s / %s |", lab, r$gamma_median$products,
            f2(r$gamma_median$spearman), f2(r$gamma_median$lo), f2(r$gamma_median$hi), pc(r$gamma_median$gap_median), pc(r$gamma_median$gap_p90),
            f2(r$opt_tariff_median$spearman), f2(r$opt_tariff_median$lo), f2(r$opt_tariff_median$hi),
            pc(r$opt_tariff_median$gap_median), pc(r$opt_tariff_median$gap_p90))
  qd <- function(d) sprintf("%s / %s / %s / %s / %s", f3(d$p10), f3(d$p25), f3(d$p50), f3(d$p75), f3(d$p90))
  writeLines(enc2utf8(c("# Product-level companion table (patches 0127-0128)", "",
    sprintf("Built from `%s` (%d products); written to `%s`; rev %s, %s.",
            s2p, nrow(tab), tab_p, rev, meta$timestamp), "",
    "## Distribution across products (p10 / p25 / p50 / p75 / p90)", "",
    sprintf("- product median gamma: %s", qd(dist$gamma_median)),
    sprintf("- product median opt_tariff: %s", qd(dist$opt_tariff_median)),
    sprintf("- product median sigma: %s", qd(dist$sigma_median)),
    sprintf("- share of a product's cells with their own sigma: %s", qd(dist$share_cells_own_sigma)), "",
    "## Reproducibility across products", "",
    "Spearman correlation across products (95% bootstrap interval over products), and the level gap: how far a product's median moves between the two halves, |median_a / median_b - 1| at the median and the 90th percentile across products.", "",
    "| split | products | median gamma: Spearman | gap p50 / p90 | median opt_tariff: Spearman | gap p50 / p90 |", "|---|---|---|---|---|---|",
    rl("odd vs even years (within a period)", if (is.null(oe)) NULL else oe$rep),
    rl("1995-2009 vs 2010-2024 (across periods)", if (is.null(pe)) NULL else pe$rep), "",
    sprintf("**Reading (fixed in patch 0127): %s.** Publish if both odd/even correlations are at least 0.50; do not publish if both are below 0.30; otherwise partial.", reading))),
    md, useBytes = TRUE)
  cat(sprintf("product summary: %d products in %.1f min -> %s; reading: %s (%s, %s)\n", nrow(tab), meta$minutes, tab_p, reading, json, md))
}
