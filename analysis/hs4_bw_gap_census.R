#!/usr/bin/env Rscript
# ============================================================================
# analysis/hs4_bw_gap_census.R — per-cell census of BW fn-14 lag gaps on the
# production prepared panel (country scope).
#
# Companion to the bw_lag = "calendar" change (patches 0009–0012): quantifies,
# on the real BACI HS4 panel, how many rows the legacy positional shift
# handed a STALE x_{t-2+} lag versus how many take the calendar-mode
# weight-1 fallback. Folds into the v0.5 EC2 rerun (same box, same raw
# cache, minutes of extra wall clock) per the Step-0 verdict: the shipped
# Stage-1 RDS carries no period-span fields, so this census is the only
# per-cell read.
#
# What it measures, at prepared-panel level (post prepare_data(): first
# rows, gap-spanning diffs, and UV-trimmed rows already dropped):
#   - per bilateral series (importer, exporter, good): retained years n_t,
#     calendar span, internal holes;
#   - per ROW: is the calendar t-1 present in the series?
#       absent + series-first row  -> BOTH modes weight-1 (lag undefined);
#       absent + later row         -> legacy manufactured a STALE lag;
#                                     calendar takes the weight-1 fallback.
#     The second count is the panel-level incidence of weights that CHANGE
#     between modes. (Cell-level filtering — reference joins, moment-NA
#     drops — adds further changed weights that only the estimator sees;
#     those rows keep a true panel t-1 under calendar mode. This census is
#     therefore a LOWER bound on changed weights and an EXACT count of
#     fallback rows.)
#   - per cell (importer, good): series counts, holed-series share, stale
#     and fallback row counts — the join key for locating moved gammas in
#     the v0.4.1 -> v0.5.0-rc comparison.
#
# Usage (mirrors run_estimation.R; run from the repo root on the box):
#   Rscript analysis/hs4_bw_gap_census.R --data <BACI dir> --out-dir <dir>
# Reads the same raw cache run_estimation.R uses (errors if absent — run
# it on the estimation out-dir AFTER the cache exists). Writes
#   <out>/<prefix>_bw_gap_census_cells.csv     (per-cell table)
#   <out>/<prefix>_bw_gap_census_series.csv    (per-series table)
# and prints the overall summary block (captured by the run log).
# Release-independent: no sigma/gamma inputs, never the manifest.
# ============================================================================

suppressMessages(library(data.table))

repo_dir <- {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  normalizePath(file.path(dirname(f), ".."))
}
src_dir <- file.path(repo_dir, "R")

source(file.path(src_dir, "dependencies.R"))
source(file.path(src_dir, "parse_cli.R"))
source(file.path(src_dir, "build_config.R"))
source(file.path(src_dir, "feen94_het_baci.R"))

opts   <- parse_cli()
config <- build_config(opts)

out_base <- build_output_path(config, opts$out_dir, scope = "country")
raw_cache_file <- paste0(out_base, "_raw_cache.rds")
if (!file.exists(raw_cache_file)) {
  stop("raw cache not found: ", raw_cache_file,
       "\nStage it (or run run_estimation.R once) before the census.")
}
cat(sprintf("Loading raw cache: %s\n", raw_cache_file))
raw_cache <- readRDS(raw_cache_file)

# EXACTLY the production country-scope preparation (run_estimation.R):
config_country <- config
config_country$use_regions <- FALSE
prep <- prepare_data(config_country, raw_cache = raw_cache)
cat(sprintf("Prepared panel: %s rows\n\n", format(nrow(prep), big.mark = ",")))

# ---- Row-level: calendar t-1 presence within the bilateral series ---------
prep[, `:=`(
  no_lag       = !((t - 1L) %in% t),
  series_first = t == min(t)
), by = .(importer, exporter, good)]
prep[, stale_legacy := no_lag & !series_first]   # legacy stale; calendar fallback
prep[, fallback_cal := no_lag]                    # calendar weight-1 rows

# ---- Per-series -----------------------------------------------------------
series <- prep[, .(
  n_t          = uniqueN(t),
  span         = max(t) - min(t) + 1L,
  n_stale      = sum(stale_legacy),
  n_fallback   = sum(fallback_cal)
), by = .(importer, exporter, good)]
series[, holed := n_t < span]

# ---- Per-cell -------------------------------------------------------------
cells <- series[, .(
  n_series        = .N,
  n_series_holed  = sum(holed),
  share_holed     = mean(holed),
  n_rows          = sum(n_t),
  n_stale_rows    = sum(n_stale),
  n_fallback_rows = sum(n_fallback)
), by = .(importer, good)]
setorder(cells, good, importer)
setorder(series, good, importer, exporter)

# ---- Overall summary (printed; lands in the run log) ----------------------
tot_rows  <- nrow(prep)
tot_ser   <- nrow(series)
tot_holed <- sum(series$holed)
tot_stale <- sum(series$n_stale)
tot_fall  <- sum(series$n_fallback)
cells_affected <- cells[n_stale_rows > 0L, .N]

cat("== HS4 BW fn-14 gap census (prepared panel, country scope) ==\n")
cat(sprintf("rows                          %s\n", format(tot_rows,  big.mark = ",")))
cat(sprintf("bilateral series              %s\n", format(tot_ser,   big.mark = ",")))
cat(sprintf("series with internal holes    %s  (%.3f%%)\n",
            format(tot_holed, big.mark = ","), 100 * tot_holed / tot_ser))
cat(sprintf("rows, calendar t-1 absent     %s  (%.3f%% of rows)\n",
            format(tot_fall,  big.mark = ","), 100 * tot_fall  / tot_rows))
cat(sprintf("  of which series-first       %s  (both modes weight-1)\n",
            format(tot_fall - tot_stale, big.mark = ",")))
cat(sprintf("  of which LEGACY-STALE       %s  (%.3f%% of rows; weights change)\n",
            format(tot_stale, big.mark = ","), 100 * tot_stale / tot_rows))
cat(sprintf("cells (importer x good)       %s\n", format(nrow(cells), big.mark = ",")))
cat(sprintf("cells with >=1 stale row      %s  (%.3f%%)\n",
            format(cells_affected, big.mark = ","),
            100 * cells_affected / nrow(cells)))
cat(sprintf("stale rows per affected cell  median %s, p95 %s, max %s\n",
            cells[n_stale_rows > 0L, median(n_stale_rows)],
            cells[n_stale_rows > 0L, as.integer(quantile(n_stale_rows, .95))],
            cells[n_stale_rows > 0L, max(n_stale_rows)]))
cat("NOTE: lower bound on changed weights — cell-level filtering (reference\n")
cat("joins, moment-NA drops) adds changed rows not visible at panel level.\n\n")

cells_csv  <- paste0(out_base, "_bw_gap_census_cells.csv")
series_csv <- paste0(out_base, "_bw_gap_census_series.csv")
fwrite(cells,  cells_csv)
fwrite(series, series_csv)
cat(sprintf("Written: %s\n", cells_csv))
cat(sprintf("Written: %s\n", series_csv))
