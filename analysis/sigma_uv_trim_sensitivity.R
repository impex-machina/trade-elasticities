#!/usr/bin/env Rscript
# =============================================================================
# analysis/sigma_uv_trim_sensitivity.R   (v0.7.2 note; sample-asymmetry item)
#
# Stage 2 drops differenced observations with |d ln p| >= uv_outlier_threshold
# (2.0) before estimating gamma; Stage 1 estimates sigma on the untrimmed
# cache. This script re-estimates Stage 1 on a random subsample of
# (importer, good) cells twice -- as shipped, and with the same trim applied
# upstream of prepare_cell_moments() -- and reports how sigma, routing and
# the SEs move. Mirrors prepare_data()'s filter exactly: the unit-value
# difference is taken against the previous CALENDAR year (Fn-14; a gap yields
# no difference and the row is kept), and a row is dropped when its own
# |d ln p| >= threshold.
#
# Usage (from the repo root; needs the raw cache locally, ~5 GB in memory):
#   Rscript analysis/sigma_uv_trim_sensitivity.R --cache <raw_cache.rds> \
#       [--frac 0.03] [--seed 20260921] [--threshold 2.0] [--ncores 8] \
#       [--out results/sigma_uv_trim_sensitivity.json] \
#       [--md docs/results/sigma_uv_trim_sensitivity.md]
# On the box: the same, from /tmp/w/trade-elasticities with the cache in out_rc/.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
# Load the library the way the runner does: feen94_het_baci.R sets .R_dir,
# which the PSOCK bootstrap needs to provision workers (patch 0056b).
source("R/feen94_het_baci.R")
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
cache  <- get_arg("--cache"); frac <- as.numeric(get_arg("--frac", "0.03"))
seed   <- as.integer(get_arg("--seed", "20260921")); thresh <- as.numeric(get_arg("--threshold", "2.0"))
ncores <- as.integer(get_arg("--ncores", "8"))
out_json <- get_arg("--out", "results/sigma_uv_trim_sensitivity.json")
out_md   <- get_arg("--md",  "docs/results/sigma_uv_trim_sensitivity.md")
if (is.null(cache) || !file.exists(cache)) stop("--cache <raw cache rds> is required")

cat("reading cache...\n"); raw <- as.data.table(readRDS(cache))
# the cache carries prepare_raw_data()'s names (year, cusval); the wrapper
# expects (t, value) -- the same rename run_estimation.R performs (patch 0056)
if ("year"   %in% names(raw)) setnames(raw, "year",   "t")
if ("cusval" %in% names(raw)) setnames(raw, "cusval", "value")
stopifnot(all(c("importer", "good", "exporter", "t", "value", "quantity") %in% names(raw)))
cells <- unique(raw[, .(importer, good)])
set.seed(seed); pick <- cells[sample.int(nrow(cells), max(1L, round(frac * nrow(cells))))]
sub <- raw[pick, on = .(importer, good)]
cat(sprintf("subsample: %d of %d cells, %s rows\n", nrow(pick), nrow(cells), format(nrow(sub), big.mark = ",")))
rm(raw); invisible(gc())

# the Stage-2 trim, applied row-wise upstream of Stage 1
trim_uv <- function(d, thresh) {
  d <- d[is.finite(value) & is.finite(quantity) & value > 0 & quantity > 0]
  setorder(d, importer, good, exporter, t)
  d[, lp := log(value / quantity)]
  d[, `:=`(lp_prev = shift(lp), t_prev = shift(t)), by = .(importer, good, exporter)]
  d[, dlp := fifelse(!is.na(t_prev) & t - t_prev == 1L, lp - lp_prev, NA_real_)]
  keep <- is.na(d$dlp) | abs(d$dlp) < thresh
  d[keep, !c("lp", "lp_prev", "t_prev", "dlp")]
}
sub_trim <- trim_uv(copy(sub), thresh)
cat(sprintf("trim drops %s of %s rows (%.2f%%)\n", format(nrow(sub) - nrow(sub_trim), big.mark = ","),
            format(nrow(sub), big.mark = ","), 100 * (1 - nrow(sub_trim) / nrow(sub))))

run <- function(d, tag) {
  tmp <- tempfile(fileext = ".rds")
  r <- run_stage1_liml(d, output_path = tmp, n_cores = ncores, min_exporters = 2L, min_periods = 3L, verbose = FALSE)
  unlink(tmp); r[, run := tag]; r
}
cat("Stage 1, as shipped...\n");      a <- run(sub, "shipped")
cat("Stage 1, trim upstream...\n");   b <- run(sub_trim, "trimmed")

m <- merge(a[, .(importer, good, s_a = status, src_a = final_source, sig_a = sigma, om_a = omega, se_a = sigma_se)],
           b[, .(importer, good, s_b = status, src_b = final_source, sig_b = sigma, om_b = omega, se_b = sigma_se)],
           by = c("importer", "good"), all = TRUE)
ok_both <- m[s_a == "ok" & s_b == "ok"]
q <- function(x) unname(quantile(x, c(.25, .5, .75), na.rm = TRUE))
res <- list(
  n_cells = nrow(m), frac = frac, seed = seed, threshold = thresh,
  rows = list(shipped = nrow(sub), trimmed = nrow(sub_trim)),
  ok = list(shipped = sum(m$s_a == "ok", na.rm = TRUE), trimmed = sum(m$s_b == "ok", na.rm = TRUE), both = nrow(ok_both)),
  route_changed_share = ok_both[, mean(src_a != src_b)],
  sigma_median = list(shipped = median(m[s_a == "ok", sig_a]), trimmed = median(m[s_b == "ok", sig_b])),
  sigma_quartiles = list(shipped = q(m[s_a == "ok", sig_a]), trimmed = q(m[s_b == "ok", sig_b])),
  rel_dsigma = list(median = ok_both[, median(abs(sig_b - sig_a) / sig_a)],
                    p75 = ok_both[, quantile(abs(sig_b - sig_a) / sig_a, .75)],
                    p90 = ok_both[, quantile(abs(sig_b - sig_a) / sig_a, .90)],
                    share_gt_10pct = ok_both[, mean(abs(sig_b - sig_a) / sig_a > .1)],
                    share_identical = ok_both[, mean(sig_b == sig_a)]),
  signed_median_rel = ok_both[, median(sig_b / sig_a - 1)],
  sigma_se_median = list(shipped = median(m[s_a == "ok", se_a], na.rm = TRUE), trimmed = median(m[s_b == "ok", se_b], na.rm = TRUE)),
  route_transitions = ok_both[, .N, by = .(src_a, src_b)][order(-N)],
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
write_json(res, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
pct <- function(x) sprintf("%.1f%%", 100 * x)
md <- c("# Stage-1 sigma sensitivity to the Stage-2 unit-value trim", "",
  sprintf("Subsample of %s (importer, good) cells (frac %.3f, seed %d); trim |d ln p| >= %.1f applied upstream of Stage 1. Generated %s.",
          format(res$n_cells, big.mark = ","), frac, seed, thresh, res$generated), "",
  sprintf("- rows: %s -> %s (%s dropped by the trim)", format(res$rows$shipped, big.mark = ","), format(res$rows$trimmed, big.mark = ","),
          pct(1 - res$rows$trimmed / res$rows$shipped)),
  sprintf("- ok cells: shipped %s, trimmed %s, both %s", format(res$ok$shipped, big.mark = ","), format(res$ok$trimmed, big.mark = ","), format(res$ok$both, big.mark = ",")),
  sprintf("- sigma median: shipped %.3f -> trimmed %.3f; quartiles %s -> %s", res$sigma_median$shipped, res$sigma_median$trimmed,
          paste(sprintf("%.3f", res$sigma_quartiles$shipped), collapse = " / "), paste(sprintf("%.3f", res$sigma_quartiles$trimmed), collapse = " / ")),
  sprintf("- on cells ok in both: |dsigma|/sigma median %.3f (p75 %.3f, p90 %.3f); > 10%%: %s; identical: %s; signed median %+.3f",
          res$rel_dsigma$median, res$rel_dsigma$p75, res$rel_dsigma$p90, pct(res$rel_dsigma$share_gt_10pct), pct(res$rel_dsigma$share_identical), res$signed_median_rel),
  sprintf("- route changed on %s of cells ok in both; sigma_se median %.3f -> %.3f", pct(res$route_changed_share), res$sigma_se_median$shipped, res$sigma_se_median$trimmed), "",
  "Route transitions (rows shipped, cols trimmed):", "", "| shipped | trimmed | N |", "|---|---|---|",
  apply(res$route_transitions, 1, function(r) sprintf("| %s | %s | %s |", r[1], r[2], r[3])), "")
writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n"); cat("wrote", out_json, "and", out_md, "\n")
