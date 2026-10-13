#!/usr/bin/env Rscript
# ============================================================================
# scripts/build_export_totals.R  (patch 0107)
#
# Builds the all-value export-totals table that --stage2-export-total all
# reads: for every (year, good, exporter), the value of ALL its flows
# (value_all) and of the flows with an observed quantity (value_qobs). The
# raw cache drops flows without a quantity at the HS6 line -- they have no
# unit value -- and the panel's exporter totals inherit the drop; Eq. (11)'s
# share s^J_ij = x_ij / V_j defines V_j over all exports.
#
# Rules: the cache's (prepare_raw_data(): the pipeline's column mapping, the
# value > 0 filter, the year window, HS6 padding, HS4 aggregation) except the
# quantity filter, which here only splits value_all from value_qobs. The
# pipeline checks at use that value_qobs reproduces the panel's exporter
# totals to 1e-9 (apply_export_totals()), so a table built with other rules
# is refused. Reads the BACI year files one at a time (memory = one year).
#
# Also writes the census of value-only flows: by year, the share of value
# without a quantity; by (exporter, good, year), m = 1 - value_qobs/value_all
# and its year-to-year change d ln(1 - m), the term that enters Eq. (11)
# scaled by (gamma_I - gamma_V).
#
# Usage (repo root):
#   Rscript scripts/build_export_totals.R --data BACI_DIR --out PATH
#       [--census-md docs/results/export_totals_census.md] [--census-json results/export_totals_census.json]
#       [--minyear Y] [--maxyear Y] [--agg-level hs4]
# Default --out: <BACI_DIR>/../baci_hs92_v202601_elast_country_hs4_export_totals.rds is NOT assumed;
# pass the path beside the raw cache (the runner looks for <out-dir>/<prefix>_export_totals.rds).
# ============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
data_dir <- get_arg("--data", NA_character_); out_path <- get_arg("--out", NA_character_)
census_md <- get_arg("--census-md", "docs/results/export_totals_census.md")
census_json <- get_arg("--census-json", "results/export_totals_census.json")
if (is.na(data_dir) || is.na(out_path)) stop("usage: Rscript scripts/build_export_totals.R --data BACI_DIR --out PATH [--census-md MD] [--census-json JSON] [--minyear Y] [--maxyear Y]")
if (!dir.exists(data_dir)) stop("BACI directory not found: ", data_dir)
pass <- c(); for (fl in c("--minyear", "--maxyear", "--agg-level")) { v <- get_arg(fl, NA_character_); if (!is.na(v)) pass <- c(pass, fl, v) }
.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) ".")
src <- file.path(normalizePath(file.path(.this_dir, ".."), mustWork = FALSE), "R")
sink(tempfile()); source(file.path(src, "feen94_het_baci.R")); source(file.path(src, "parse_cli.R")); source(file.path(src, "build_config.R")); sink()
cfg <- build_config(parse_cli(c("--data", data_dir, pass)))
files <- sort(list.files(cfg$filepath, pattern = "BACI_HS.*_Y\\d{4}_V.*\\.csv$", full.names = TRUE))
if (!length(files)) stop("no BACI year files (BACI_HS*_Y####_V*.csv) in ", cfg$filepath)
cat(sprintf("build_export_totals: %d year files in %s | minyear %s maxyear %s | %s\n", length(files), cfg$filepath, cfg$minyear,
            if (is.null(cfg$maxyear) || is.na(cfg$maxyear)) "max" else cfg$maxyear, cfg$agg_level))
parts <- list(); by_year <- list()
for (f in files) {
  t0 <- Sys.time()
  d <- fread(f, colClasses = list(character = cfg$good), showProgress = FALSE)
  setnames(d, old = c(cfg$value, cfg$quan, cfg$good, cfg$importer, cfg[["exporter"]], cfg$time),
           new = c("cusval", "quantity", "good", "importer", "exporter", "year"), skip_absent = TRUE)
  d <- d[!is.na(cusval) & cusval > 0 & year >= cfg$minyear]
  if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) d <- d[year <= cfg$maxyear]
  if (!nrow(d)) { cat(sprintf("  %s: no rows in the window\n", basename(f))); next }
  d[, good := pad_hs6(good)]
  d <- d[nchar(good) == 6L]
  d[, qobs := !is.na(quantity) & quantity > 0]
  by_year[[f]] <- d[, .(value_all = sum(cusval), value_qobs = sum(cusval[qobs]), lines = .N, lines_noq = sum(!qobs)), by = year]
  if (identical(cfg$agg_level, "hs4")) d[, good := hs6_to_hs4(good)]
  parts[[f]] <- d[, .(value_all = sum(cusval), value_qobs = sum(cusval[qobs])), by = .(year, good, exporter)]
  cat(sprintf("  %s: %s lines, %.2f%% of value without a quantity (%.0fs)\n", basename(f), format(nrow(d), big.mark = ","),
              100 * (1 - sum(d$cusval[d$qobs]) / sum(d$cusval)), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  rm(d); invisible(gc())
}
tot <- rbindlist(parts)[, .(value_all = sum(value_all), value_qobs = sum(value_qobs)), by = .(year, good, exporter)]
tot[, `:=`(year = as.integer(year), exporter = as.character(exporter))]
setorder(tot, year, good, exporter)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(tot, out_path)

# ---- census
yr <- rbindlist(by_year)[, lapply(.SD, sum), by = year][order(year)]
yr[, share_value_noq := 1 - value_qobs / value_all]
cells <- copy(tot)[value_qobs > 0]
cells[, m := 1 - value_qobs / value_all]
setorder(cells, exporter, good, year)
cells[, `:=`(dl = log(value_qobs / value_all) - shift(log(value_qobs / value_all)), gap = year - shift(year)), by = .(exporter, good)]
dd <- cells[gap == 1L & is.finite(dl)]
wq <- function(x, w, p) { o <- order(x); x <- x[o]; w <- w[o]; cw <- cumsum(w) / sum(w); x[which(cw >= p)[1]] }
q <- function(x, p) unname(quantile(x, p))
cen <- list(
  rows = nrow(tot), years = paste(range(tot$year), collapse = "-"),
  share_value_without_quantity = 1 - sum(tot$value_qobs) / sum(tot$value_all),
  share_cells_with_value_only_flows = mean(cells$m > 0),
  share_value_in_cells_with_value_only_flows = sum(cells$value_all[cells$m > 0]) / sum(cells$value_all),
  cells_all_value_only = sum(tot$value_qobs == 0),
  m_p50 = q(cells$m, .5), m_p90 = q(cells$m, .9), m_p99 = q(cells$m, .99),
  abs_dln1m = list(n = nrow(dd), p50 = q(abs(dd$dl), .5), p90 = q(abs(dd$dl), .9), p99 = q(abs(dd$dl), .99), max = max(abs(dd$dl)),
                   share_gt_0_01 = mean(abs(dd$dl) > 0.01), share_gt_0_10 = mean(abs(dd$dl) > 0.10),
                   value_weighted_p50 = wq(abs(dd$dl), dd$value_all, .5), value_weighted_p90 = wq(abs(dd$dl), dd$value_all, .9),
                   value_weighted_p99 = wq(abs(dd$dl), dd$value_all, .99)),
  by_year = yr[, .(year, share_value_noq, lines, lines_noq)])
L <- c("# Value-only flows and the export-share denominator (patch 0107)", "",
       sprintf("Built by `scripts/build_export_totals.R` from %d BACI year files on %s. Totals table: %s rows (year x good x exporter), years %s.",
               length(files), format(Sys.time(), "%Y-%m-%d"), format(cen$rows, big.mark = ","), cen$years), "",
       sprintf("- Value without a quantity: **%.2f%%** of all value. Exporter-good-year cells with any value-only flow: %.1f%% (holding %.1f%% of value); cells whose every flow lacks a quantity (absent from the panel): %s.",
               100 * cen$share_value_without_quantity, 100 * cen$share_cells_with_value_only_flows, 100 * cen$share_value_in_cells_with_value_only_flows, format(cen$cells_all_value_only, big.mark = ",")),
       sprintf("- m = 1 - value_qobs/value_all over cells in the panel: p50 %.2e, p90 %.4f, p99 %.4f.", cen$m_p50, cen$m_p90, cen$m_p99),
       sprintf("- |d ln(1 - m)| between consecutive years, same exporter and good (%s pairs): p50 %.2e, p90 %.4f, p99 %.4f, max %.3f; above 0.01 in %.2f%%, above 0.10 in %.2f%%; value-weighted p50 %.2e, p90 %.4f, p99 %.4f.",
               format(cen$abs_dln1m$n, big.mark = ","), cen$abs_dln1m$p50, cen$abs_dln1m$p90, cen$abs_dln1m$p99, cen$abs_dln1m$max,
               100 * cen$abs_dln1m$share_gt_0_01, 100 * cen$abs_dln1m$share_gt_0_10, cen$abs_dln1m$value_weighted_p50, cen$abs_dln1m$value_weighted_p90, cen$abs_dln1m$value_weighted_p99), "",
       "| year | share of value without a quantity | HS6 lines | lines without a quantity |", "|---|---|---|---|",
       sprintf("| %d | %.3f%% | %s | %s |", yr$year, 100 * yr$share_value_noq, format(yr$lines, big.mark = ","), format(yr$lines_noq, big.mark = ",")))
dir.create(dirname(census_md), showWarnings = FALSE, recursive = TRUE); writeLines(L, census_md)
dir.create(dirname(census_json), showWarnings = FALSE, recursive = TRUE); writeLines(toJSON(cen, auto_unbox = TRUE, digits = 8, pretty = TRUE), census_json)
cat(sprintf("build_export_totals: wrote %s (%s rows), %s, %s\n", out_path, format(nrow(tot), big.mark = ","), census_md, census_json))
cat(sprintf("  value without a quantity %.2f%% | |d ln(1-m)| p50 %.2e p90 %.4f p99 %.4f (value-weighted p99 %.4f)\n",
            100 * cen$share_value_without_quantity, cen$abs_dln1m$p50, cen$abs_dln1m$p90, cen$abs_dln1m$p99, cen$abs_dln1m$value_weighted_p99))
