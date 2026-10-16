#!/usr/bin/env Rscript
# ============================================================================
# analysis/product_summary.R  (patch 0127, after audit #8)
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
#   gamma_median [gamma_lo, gamma_hi]   median gamma over directly estimated
#                                       rows, with a 95% interval from a
#                                       bootstrap over importers (cells)
#   opt_tariff_median [lo, hi]          median over cells of the cell's
#                                       opt_tariff, same bootstrap
#   sigma_median                        median over cells of the published sigma
#   share_cells_own_sigma               cells whose sigma is their own estimate
# sigma differs little across products: one global value (the fallback, 2.47)
# predicts a cell's other-period sigma better than the cell's own estimate
# (docs/results/sigma_eb_period_census_v0110.md).
#
# Before the table is published, its reproducibility is measured on the 2%
# product subsample runs of the shipped configuration (patch 0119): the
# odd-year and even-year halves (within a period) and, as information, the
# 1995-2009 and 2010-2024 windows (across periods).
#
# Reading (fixed in patch 0127, before the numbers): "publish" if, between the
# odd and even halves, the Spearman correlation across products of the
# product median gamma AND of the product median opt_tariff are both >= 0.5;
# "do not publish" if both are < 0.3; otherwise "partial" (decided with the
# numbers in hand). The subsample has ~25 products, so each correlation
# carries a bootstrap interval over products.
#
# Usage (repo root; local; ~2-5 min on the full table):
#   Rscript analysis/product_summary.R [--stage2b S2B.rds] [--odd O.rds --even E.rds]
#       [--early A.rds --late B.rds] [--boot 200]
#       [--table data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv]
#       [--json results/product_summary_census.json] [--md docs/results/product_summary_census.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

#' Weighted median of sorted values x with weights w.
.wmedian_sorted <- function(x, w) { cw <- cumsum(w); x[which(cw >= cw[length(cw)] / 2)[1L]] }

#' Bootstrap over cells of a product's row median: rows of sorted values x with
#' cell index c (1..K); returns the 2.5% and 97.5% quantiles.
.boot_cells_median <- function(x, cell, B) {
  if (B < 1L || length(x) < 2L) return(c(NA_real_, NA_real_))
  o <- order(x); x <- x[o]; cell <- cell[o]
  K <- max(cell)
  if (K < 2L) return(c(NA_real_, NA_real_))
  W <- stats::rmultinom(B, K, rep(1 / K, K))                      # K x B draw counts
  med <- vapply(seq_len(B), function(b) .wmedian_sorted(x, W[cell, b]), 0)
  as.numeric(stats::quantile(med, c(0.025, 0.975), names = FALSE, na.rm = TRUE))
}

#' The product table from a Stage-2b table.
product_summary <- function(s2b, B = 200L, seed = 20261016L) {
  set.seed(seed)
  x <- data.table::as.data.table(s2b)
  if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
  x[, `:=`(importer = as.character(importer), good = as.character(good))]
  x[, est := is_estimated_row(tier, convergence)]
  cells <- x[, .(opt_tariff = opt_tariff[1L], sigma = sigma[1L],
                 own_sigma = if ("sigma_source" %in% names(.SD)) sigma_source[1L] == "estimated" else NA), by = .(good, importer),
             .SDcols = intersect("sigma_source", names(x))]
  out <- x[, .(n_cells = data.table::uniqueN(importer), n_rows = .N, n_rows_estimated = sum(est),
               trade = sum(avg_trade, na.rm = TRUE)), by = good]
  g <- x[est == TRUE & is.finite(gamma) & gamma > 0]
  g[, cell := match(importer, unique(importer)), by = good]
  gs <- g[, { ci <- .boot_cells_median(gamma, cell, B); .(gamma_median = stats::median(gamma), gamma_lo = ci[1], gamma_hi = ci[2]) }, by = good]
  ot <- cells[is.finite(opt_tariff)]
  ot[, cell := seq_len(.N), by = good]
  os <- ot[, { ci <- .boot_cells_median(opt_tariff, cell, B); .(opt_tariff_median = stats::median(opt_tariff), opt_tariff_lo = ci[1], opt_tariff_hi = ci[2]) }, by = good]
  ss <- cells[, .(sigma_median = stats::median(sigma), share_cells_own_sigma = mean(own_sigma)), by = good]
  out <- Reduce(function(a, b) merge(a, b, by = "good", all.x = TRUE), list(out, gs, os, ss))
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
    if (length(u) < 4L) return(list(products = length(u), spearman = NA_real_, lo = NA_real_, hi = NA_real_))
    r <- suppressWarnings(stats::cor(u, v, method = "spearman"))
    bs <- vapply(seq_len(B), function(i) { s <- sample.int(length(u), replace = TRUE); suppressWarnings(stats::cor(u[s], v[s], method = "spearman")) }, 0)
    ci <- stats::quantile(bs, c(0.025, 0.975), names = FALSE, na.rm = TRUE)
    list(products = length(u), spearman = r, lo = ci[1], hi = ci[2])
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
  B <- as.integer(get_arg("--boot", 200L))
  tab_p <- get_arg("--table", "data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv")
  json <- get_arg("--json", "results/product_summary_census.json"); md <- get_arg("--md", "docs/results/product_summary_census.md")
  t0 <- Sys.time()
  tab <- product_summary(readRDS(s2p), B = B)
  dir.create(dirname(tab_p), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(tab, tab_p)
  pair <- function(fa, fb) {
    pa <- get_arg(fa, NA_character_); pb <- get_arg(fb, NA_character_)
    if (is.na(pa) || is.na(pb)) return(NULL)
    if (!file.exists(pa) || !file.exists(pb)) stop("missing ", if (!file.exists(pa)) pa else pb)
    list(paths = c(pa, pb), rep = product_reproducibility(product_summary(readRDS(pa), B = 0L), product_summary(readRDS(pb), B = 0L)))
  }
  oe <- pair("--odd", "--even"); pe <- pair("--early", "--late")
  reading <- product_reading(if (is.null(oe)) NULL else oe$rep)
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(stage2b = s2p, table = tab_p, boot = B, products = nrow(tab), git_rev = rev,
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
  q <- function(v) as.list(stats::setNames(stats::quantile(v, c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE, names = FALSE), c("p10", "p25", "p50", "p75", "p90")))
  dist <- list(gamma_median = q(tab$gamma_median), opt_tariff_median = q(tab$opt_tariff_median), sigma_median = q(tab$sigma_median),
               gamma_interval_width = q(log(tab$gamma_hi / tab$gamma_lo)), share_cells_own_sigma = q(tab$share_cells_own_sigma))
  jsonlite::write_json(list(meta = meta, reading = reading, distribution = dist,
                            odd_even = if (is.null(oe)) NULL else c(list(paths = oe$paths), oe$rep),
                            early_late = if (is.null(pe)) NULL else c(list(paths = pe$paths), pe$rep)),
                       json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f2 <- function(x) formatC(x, digits = 2, format = "f"); f3 <- function(x) formatC(x, digits = 3, format = "f")
  rl <- function(lab, r) if (is.null(r)) character(0) else
    sprintf("| %s | %d | %s [%s, %s] | %s [%s, %s] |", lab, r$gamma_median$products, f2(r$gamma_median$spearman), f2(r$gamma_median$lo), f2(r$gamma_median$hi),
            f2(r$opt_tariff_median$spearman), f2(r$opt_tariff_median$lo), f2(r$opt_tariff_median$hi))
  qd <- function(d) sprintf("%s / %s / %s / %s / %s", f3(d$p10), f3(d$p25), f3(d$p50), f3(d$p75), f3(d$p90))
  writeLines(enc2utf8(c("# Product-level companion table (patch 0127)", "",
    sprintf("Built from `%s` (%d products; bootstrap over importers, %d draws); written to `%s` (not yet published); rev %s, %s.",
            s2p, nrow(tab), B, tab_p, rev, meta$timestamp), "",
    "## Distribution across products (p10 / p25 / p50 / p75 / p90)", "",
    sprintf("- product median gamma: %s", qd(dist$gamma_median)),
    sprintf("- product median opt_tariff: %s", qd(dist$opt_tariff_median)),
    sprintf("- product median sigma: %s", qd(dist$sigma_median)),
    sprintf("- width of the gamma interval, ln(hi / lo): %s", qd(dist$gamma_interval_width)),
    sprintf("- share of a product's cells with their own sigma: %s", qd(dist$share_cells_own_sigma)), "",
    "## Reproducibility across products (Spearman, 95% bootstrap interval over products)", "",
    "| split | products | median gamma | median opt_tariff |", "|---|---|---|---|",
    rl("odd vs even years (within a period)", if (is.null(oe)) NULL else oe$rep),
    rl("1995-2009 vs 2010-2024 (across periods)", if (is.null(pe)) NULL else pe$rep), "",
    sprintf("**Reading (fixed in patch 0127): %s.** Publish if both odd/even correlations are at least 0.50; do not publish if both are below 0.30; otherwise partial.", reading))),
    md, useBytes = TRUE)
  cat(sprintf("product summary: %d products in %.1f min -> %s; reading: %s (%s, %s)\n", nrow(tab), meta$minutes, tab_p, reading, json, md))
}
