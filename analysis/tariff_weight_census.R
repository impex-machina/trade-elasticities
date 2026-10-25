#!/usr/bin/env Rscript
# ============================================================================
# analysis/tariff_weight_census.R  (patch 0138)
#
# A cell's opt_tariff averages its exporters' optimal tariffs with weights
# avg_trade: the MEAN annual customs value over the years the pair has in the
# Stage-2 panel (estimate_cell_fixed_sigma.R; recompute_opt_tariff() over the
# published, directly estimated rows). The alternative is the TOTAL value over
# those years -- avg_trade times the pair's number of panel years -- which
# weights exporters by their volume across the whole period, so a pair that
# traded heavily for a few years counts for less than one that traded steadily
# for decades. Tier-3 (sporadic) exporters are outside the tariff either way.
#
# No estimation: the pairs' panel years come from the raw cache by the rule
# the reference-exporter census (patch 0125) showed reproduces Stage 2's panel
# (differenced years with |d ln p| < 2), and two replication checks are
# reported: the mean of those years' values against the published avg_trade,
# and the recomputed mean-weighted tariff against the published opt_tariff.
#
# Reading (fixed in patch 0138, before the numbers): "material" if at least
# 10% of cells' opt_tariff move by more than 10% under total weights, or at
# least 10% of products' median opt_tariff move by more than 5%; otherwise
# "immaterial" (the definition is documented and the item closes). A material
# reading leaves the choice -- switch the column or publish both -- to a later
# patch.
#
# Usage (repo root; ~15 min and ~10-15 GB of RAM on the full cache):
#   Rscript analysis/tariff_weight_census.R --raw-cache PATH --stage2b S2B.rds
#       [--json results/tariff_weight_census.json] [--md docs/results/tariff_weight_census.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

#' The census from a pair panel (ref_exporter_panel()) and a Stage-2b table.
tariff_weight_census <- function(panel, s2b) {
  pn <- data.table::as.data.table(panel)[, .(importer = as.integer(importer), good = as.character(good), exporter = as.integer(exporter),
                                              n_years = n_dif_trim, mean_rep = data.table::fifelse(n_dif_trim > 0, total_dif_trim / n_dif_trim, NA_real_))]
  x <- data.table::as.data.table(s2b)
  if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
  x <- x[is_estimated_row(tier, convergence)]
  x <- x[, .(importer = as.integer(importer), exporter = as.integer(exporter), good = as.character(good), gamma, sigma, avg_trade, opt_tariff)]
  m <- merge(x, pn, by = c("importer", "good", "exporter"), all.x = TRUE)
  rep_avg <- m[is.finite(mean_rep) & is.finite(avg_trade) & avg_trade > 0, mean(abs(mean_rep / avg_trade - 1) < 1e-6)]
  matched <- mean(is.finite(m$n_years) & m$n_years > 0)
  cells <- m[, {
    w1 <- avg_trade; w2 <- avg_trade * n_years
    ok <- is.finite(w2) & w2 > 0
    .(ot_pub = opt_tariff[1L], ot_mean = optimal_tariff(gamma, sigma[1L], w1),
      ot_total = if (all(ok)) optimal_tariff(gamma, sigma[1L], w2) else NA_real_, n = .N)
  }, by = .(importer, good)]
  rep_ot <- cells[is.finite(ot_pub) & is.finite(ot_mean), mean(abs(ot_mean - ot_pub) <= 1e-9 * pmax(abs(ot_pub), 1))]
  cc <- cells[is.finite(ot_mean) & is.finite(ot_total) & ot_mean > 0 & ot_total > 0]
  cc[, r := abs(log(ot_total / ot_mean))]
  pr <- cc[, .(med_mean = stats::median(ot_mean), med_total = stats::median(ot_total)), by = good]
  pr[, r := abs(log(med_total / med_mean))]
  q <- function(v) as.list(stats::setNames(stats::quantile(v, c(0.5, 0.9, 0.99), names = FALSE), c("p50", "p90", "p99")))
  share_cells <- mean(exp(cc$r) - 1 > 0.10); share_products <- mean(exp(pr$r) - 1 > 0.05)
  list(rows = nrow(m), share_rows_matched = matched, replication_avg_trade = rep_avg, replication_opt_tariff = rep_ot,
       cells = nrow(cc), cells_single_exporter = sum(cc$n == 1L), cell_change = q(exp(cc$r) - 1),
       share_cells_over_10pct = share_cells, products = nrow(pr), product_change = q(exp(pr$r) - 1),
       share_products_over_5pct = share_products,
       reading = if (share_cells >= 0.10 || share_products >= 0.10) "material" else "immaterial")
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  rc <- get_arg("--raw-cache", NA_character_); s2p <- get_arg("--stage2b", NA_character_)
  if (is.na(rc) || is.na(s2p) || !all(file.exists(c(rc, s2p))))
    stop("usage: Rscript analysis/tariff_weight_census.R --raw-cache PATH --stage2b S2B.rds [--json F] [--md F]")
  json <- get_arg("--json", "results/tariff_weight_census.json"); md <- get_arg("--md", "docs/results/tariff_weight_census.md")
  source("R/utils_general.R")
  e <- new.env(); sys.source("analysis/reference_exporter_census.R", envir = e)
  t0 <- Sys.time()
  res <- tariff_weight_census(e$ref_exporter_panel(readRDS(rc)), readRDS(s2p))
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  res$meta <- list(raw_cache = rc, stage2b = s2p, git_rev = rev, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
                   minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
  jsonlite::write_json(res, json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  p1 <- function(x) sprintf("%.1f%%", 100 * x); n <- function(x) format(x, big.mark = ",")
  writeLines(enc2utf8(c("# opt_tariff under total-trade weights (patch 0138)", "",
    sprintf("Raw cache `%s`, Stage 2b `%s`; rev %s, %s.", rc, s2p, rev, res$meta$timestamp), "",
    "Each cell's optimal tariff recomputed over the published, directly estimated rows with each exporter weighted by its total customs value over its panel years (avg_trade times the number of those years) instead of its mean annual value.", "",
    sprintf("- Replication: the pairs' panel years found for %s of %s rows; the mean of their values equals the published `avg_trade` for %s of them; the mean-weighted tariff recomputed here equals the published `opt_tariff` in %s of cells.",
            p1(res$share_rows_matched), n(res$rows), p1(res$replication_avg_trade), p1(res$replication_opt_tariff)),
    sprintf("- Cells (%s; %s with a single directly estimated exporter, where the weights cannot matter): |change| median %s, p90 %s, p99 %s; more than 10%% in %s of cells.",
            n(res$cells), n(res$cells_single_exporter), p1(res$cell_change$p50), p1(res$cell_change$p90), p1(res$cell_change$p99), p1(res$share_cells_over_10pct)),
    sprintf("- Products (%s): the median cell tariff moves by a median %s (p90 %s, p99 %s); more than 5%% in %s of products.",
            n(res$products), p1(res$product_change$p50), p1(res$product_change$p90), p1(res$product_change$p99), p1(res$share_products_over_5pct)), "",
    sprintf("**Reading (fixed in patch 0138): %s.** Material if at least 10%% of cells move by more than 10%%, or at least 10%% of products' median tariff by more than 5%%.", res$reading))),
    md, useBytes = TRUE)
  cat(sprintf("tariff weight census (%.1f min): %s -- cells over 10%%: %.1f%%, products over 5%%: %.1f%%; replication avg_trade %.1f%%, opt_tariff %.1f%%\n",
              res$meta$minutes, res$reading, 100 * res$share_cells_over_10pct, 100 * res$share_products_over_5pct,
              100 * res$replication_avg_trade, 100 * res$replication_opt_tariff))
}
