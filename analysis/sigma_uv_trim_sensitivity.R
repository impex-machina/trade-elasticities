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
#       [--frac 0.03] [--seed 20260921] [--threshold 2.0] [--ncores 8] [--variant obs|row] \
#       [--sigma-cap 50] \
#       [--out results/sigma_uv_trim_sensitivity.json] \
#       [--md docs/results/sigma_uv_trim_sensitivity.md]
# On the box: the same, from /tmp/w/trade-elasticities with the cache in out_rc/.
# --sigma-cap (patch 0142): the Stage-1 cap of both runs, default 50 (the
# shipped cap since v0.9.0). The committed results (2026-09-21/22, v0.7.2's
# Stage 1) were run at the wrapper's then library default of 10; pass
# --sigma-cap 10 to reproduce them. The at-cap share below uses this value.
# (patch 0145) Three options for a re-run of the threshold curve:
#   --thresholds 3,2,1.5   one untrimmed baseline, one trimmed run per value;
#                          outputs <--out-prefix>_t<tag>.json and
#                          <--md-prefix>_t<tag>.md (tag: 3 -> t3, 1.5 -> t15)
#   --check-shipped PATH   the published Stage-1 table: the untrimmed run must
#                          reproduce its sigma cell by cell (>= 99% of cells
#                          within 1e-6 relative, status agreeing on >= 99%)
#                          before any trimmed run starts, or the script exits 3
#                          -- the proof that the cache is the shipped panel
#   (always) timing: seconds per run, recorded so a small pre-flight can
#                          project the full run's duration
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
sigma_cap <- as.numeric(get_arg("--sigma-cap", "50"))   # patch 0142: explicit; the wrapper no longer defaults it
# variant (patch 0057): "obs" (default) applies the trim to the DIFFERENCED
# observation inside prepare_cell_moments() -- Stage 2's rule exactly; "row"
# drops the raw (exporter, t) row, which also destroys the following year's
# difference and therefore over-trims (the 2026-09-21 first result).
variant <- get_arg("--variant", "obs"); stopifnot(variant %in% c("obs", "row"))
out_json <- get_arg("--out", if (variant == "obs") "results/sigma_uv_trim_sensitivity_obs.json" else "results/sigma_uv_trim_sensitivity.json")
out_md   <- get_arg("--md",  if (variant == "obs") "docs/results/sigma_uv_trim_sensitivity_obs.md" else "docs/results/sigma_uv_trim_sensitivity.md")
if (is.null(cache) || !file.exists(cache)) stop("--cache <raw cache rds> is required")
# (patch 0145) several thresholds against one baseline, and the shipped check
th_arg     <- get_arg("--thresholds")
thresholds <- if (is.null(th_arg)) thresh else as.numeric(strsplit(th_arg, ",", fixed = TRUE)[[1]])
if (!length(thresholds) || any(!is.finite(thresholds)) || any(thresholds <= 0)) stop("--thresholds: positive numbers, comma-separated")
out_prefix <- get_arg("--out-prefix"); md_prefix <- get_arg("--md-prefix")
if (!is.null(th_arg) && (is.null(out_prefix) || is.null(md_prefix))) stop("--thresholds needs --out-prefix and --md-prefix")
th_tag <- function(th) gsub(".", "", format(th), fixed = TRUE)            # 3 -> "3", 1.5 -> "15"
paths_for <- function(th) if (is.null(th_arg)) c(out_json, out_md) else
  c(sprintf("%s_t%s.json", out_prefix, th_tag(th)), sprintf("%s_t%s.md", md_prefix, th_tag(th)))
shipped_path <- get_arg("--check-shipped")
if (!is.null(shipped_path) && !file.exists(shipped_path)) stop("--check-shipped: not found: ", shipped_path)
git_rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_)

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
n_cells_universe <- nrow(cells)
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
run <- function(d, tag, uv = NA_real_) {
  tmp <- tempfile(fileext = ".rds")
  r <- run_stage1_liml(d, output_path = tmp, n_cores = ncores, min_exporters = 2L, min_periods = 3L,
                       verbose = FALSE, uv_outlier_threshold = uv, sigma_cap = sigma_cap)   # patch 0142
  unlink(tmp); r[, run := tag]; r
}
summarise_threshold <- function(a, b, thresh, sub_trim_rows, t_a, t_b, out_json, out_md) {
  sub_trim <- list(n = sub_trim_rows)
  m <- merge(a[, .(importer, good, s_a = status, src_a = final_source, sig_a = sigma, om_a = omega, se_a = sigma_se)],
             b[, .(importer, good, s_b = status, src_b = final_source, sig_b = sigma, om_b = omega, se_b = sigma_se)],
             by = c("importer", "good"), all = TRUE)
  ok_both <- m[s_a == "ok" & s_b == "ok"]
  q <- function(x) unname(quantile(x, c(.25, .5, .75), na.rm = TRUE))
  res <- list(
    variant = variant,
    n_cells = nrow(m), frac = frac, seed = seed, threshold = thresh,
    meta = list(git_rev = git_rev, cache = basename(cache), ncores = ncores),   # patch 0145
    timing = list(shipped_s = t_a, trimmed_s = t_b, n_cells = nrow(m)),        # patch 0145
    n_cells_universe = n_cells_universe,                                         # patch 0145
    shipped_check = shipped_chk,                                                 # patch 0145 (NULL without --check-shipped)
    rows = list(shipped = nrow(sub), trimmed = sub_trim$n),
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
    # (patch 0059) the rc turned on these: share of clean cells at the sigma cap, and the route mix
    sigma_cap = sigma_cap,   # patch 0142: the cap both runs used
    sigma_cap_share = list(shipped = m[s_a == "ok", mean(sig_a >= sigma_cap - 1e-3)], trimmed = m[s_b == "ok", mean(sig_b >= sigma_cap - 1e-3)]),
    sigma_se_finite_share = list(shipped = m[s_a == "ok", mean(is.finite(se_a))], trimmed = m[s_b == "ok", mean(is.finite(se_b))]),
    route_mix = list(shipped = m[s_a == "ok", .N, by = src_a][order(src_a)], trimmed = m[s_b == "ok", .N, by = src_b][order(src_b)]),
    omega_cap_share = list(shipped = m[s_a == "ok", mean(om_a >= 10 - 1e-3, na.rm = TRUE)], trimmed = m[s_b == "ok", mean(om_b >= 10 - 1e-3, na.rm = TRUE)]),
    route_transitions = ok_both[, .N, by = .(src_a, src_b)][order(-N)],
    generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(res, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  pct <- function(x) sprintf("%.1f%%", 100 * x)
  md <- c(sprintf("# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (%s variant)", variant), "",
    sprintf("Subsample of %s (importer, good) cells (frac %.3f, seed %d); trim |d ln p| >= %.1f applied %s. Generated %s.",
            format(res$n_cells, big.mark = ","), frac, seed, thresh,
            if (variant == "obs") "to the differenced observation inside prepare_cell_moments() (Stage 2's rule)"
            else "by dropping the raw row (over-trims: the following year's difference is lost too)", res$generated), "",
    sprintf("- rows: %s -> %s (%s dropped by the trim)", format(res$rows$shipped, big.mark = ","), format(res$rows$trimmed, big.mark = ","),
            pct(1 - res$rows$trimmed / res$rows$shipped)),
    sprintf("- ok cells: shipped %s, trimmed %s, both %s", format(res$ok$shipped, big.mark = ","), format(res$ok$trimmed, big.mark = ","), format(res$ok$both, big.mark = ",")),
    sprintf("- sigma median: shipped %.3f -> trimmed %.3f; quartiles %s -> %s", res$sigma_median$shipped, res$sigma_median$trimmed,
            paste(sprintf("%.3f", res$sigma_quartiles$shipped), collapse = " / "), paste(sprintf("%.3f", res$sigma_quartiles$trimmed), collapse = " / ")),
    sprintf("- on cells ok in both: |dsigma|/sigma median %.3f (p75 %.3f, p90 %.3f); > 10%%: %s; identical: %s; signed median %+.3f",
            res$rel_dsigma$median, res$rel_dsigma$p75, res$rel_dsigma$p90, pct(res$rel_dsigma$share_gt_10pct), pct(res$rel_dsigma$share_identical), res$signed_median_rel),
    sprintf("- route changed on %s of cells ok in both; sigma_se median %.3f -> %.3f", pct(res$route_changed_share), res$sigma_se_median$shipped, res$sigma_se_median$trimmed),
    sprintf("- sigma at the cap (ok cells): %s -> %s; sigma_se finite: %s -> %s; omega at the cap: %s -> %s",
            pct(res$sigma_cap_share$shipped), pct(res$sigma_cap_share$trimmed), pct(res$sigma_se_finite_share$shipped), pct(res$sigma_se_finite_share$trimmed),
            pct(res$omega_cap_share$shipped), pct(res$omega_cap_share$trimmed)),
    sprintf("- route mix (ok cells), shipped: %s | trimmed: %s",
            paste(sprintf("%s %d", res$route_mix$shipped$src_a, res$route_mix$shipped$N), collapse = ", "),
            paste(sprintf("%s %d", res$route_mix$trimmed$src_b, res$route_mix$trimmed$N), collapse = ", ")), "",
    if (!is.null(shipped_chk)) sprintf("- the untrimmed run reproduces the published Stage-1 table (%s) on %s of %s cells ok in both (within 1e-6 relative; identical: %s), status agreeing on %s",
                                       shipped_chk$table, pct(shipped_chk$sigma_match_share), format(shipped_chk$n_ok_both, big.mark = ","),
                                       pct(shipped_chk$sigma_identical_share), pct(shipped_chk$status_agree_share)) else NULL,
    sprintf("- time: untrimmed %.0f s, trimmed %.0f s (%d cores, sigma cap %s)", t_a, t_b, ncores, format(sigma_cap)), "",
    "Route transitions (rows shipped, cols trimmed):", "", "| shipped | trimmed | N |", "|---|---|---|",
    apply(res$route_transitions, 1, function(r) sprintf("| %s | %s | %s |", r[1], r[2], r[3])), "")
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n"); cat("wrote", out_json, "and", out_md, "\n")
}

# (patch 0145) does the untrimmed run reproduce the published Stage-1 table?
check_shipped <- function(a, path) {
  s <- as.data.table(readRDS(path))
  miss <- setdiff(c("importer", "good", "status", "sigma"), names(s))
  if (length(miss)) stop("--check-shipped: the table lacks ", paste(miss, collapse = ", "))
  x <- a[, .(importer = as.character(importer), good = as.character(good), st_run = status, sig_run = sigma)]
  y <- s[, .(importer = as.character(importer), good = as.character(good), st_pub = status, sig_pub = sigma)]
  m <- merge(x, y, by = c("importer", "good"), all.x = TRUE)
  inp <- m[!is.na(st_pub)]
  ok <- inp[st_run == "ok" & st_pub == "ok" & is.finite(sig_run) & is.finite(sig_pub)]
  rel <- ok[, abs(sig_run - sig_pub) / pmax(abs(sig_pub), 1e-12)]
  list(table = basename(path), n_cells = nrow(m), n_in_table = nrow(inp),
       status_agree_share = if (nrow(inp)) mean(inp$st_run == inp$st_pub) else NA_real_,
       n_ok_both = nrow(ok),
       sigma_match_share = if (length(rel)) mean(rel <= 1e-6) else NA_real_,
       sigma_identical_share = if (length(rel)) mean(rel == 0) else NA_real_,
       sigma_rel_diff_max = if (length(rel)) max(rel) else NA_real_)
}
shipped_check_passes <- function(k) isTRUE(k$n_in_table >= 0.99 * k$n_cells) && isTRUE(k$status_agree_share >= 0.99) &&
  isTRUE(k$sigma_match_share >= 0.99)

cat("Stage 1, as shipped...\n")
t_a <- system.time(a <- run(sub, "shipped"))[["elapsed"]]
cat(sprintf("  %.0f s for %d cells\n", t_a, nrow(pick)))
shipped_chk <- NULL
if (!is.null(shipped_path)) {
  shipped_chk <- check_shipped(a, shipped_path)
  cat(sprintf("shipped check (%s): %d of %d cells in the table; status agrees on %.2f%%; sigma within 1e-6 on %.2f%% of %d cells ok in both (identical %.2f%%, max rel diff %.3g)\n",
              shipped_chk$table, shipped_chk$n_in_table, shipped_chk$n_cells, 100 * shipped_chk$status_agree_share,
              100 * shipped_chk$sigma_match_share, shipped_chk$n_ok_both, 100 * shipped_chk$sigma_identical_share, shipped_chk$sigma_rel_diff_max))
  if (!shipped_check_passes(shipped_chk)) {
    cat("SHIPPED CHECK FAILED: the untrimmed run does not reproduce the published Stage-1 table, so this cache (or these options) is not the shipped panel. No trimmed run was started.\n")
    quit(status = 3L)
  }
  cat("shipped check passed: the cache is the shipped panel\n")
}
for (thresh in thresholds) {
  op <- paths_for(thresh)
  if (variant == "row") {
    sub_trim <- trim_uv(copy(sub), thresh)
    cat(sprintf("row variant: trim drops %s of %s rows (%.2f%%)\n", format(nrow(sub) - nrow(sub_trim), big.mark = ","),
                format(nrow(sub), big.mark = ","), 100 * (1 - nrow(sub_trim) / nrow(sub))))
    cat(sprintf("Stage 1, trim %.1f upstream...\n", thresh)); t_b <- system.time(b <- run(sub_trim, "trimmed"))[["elapsed"]]
    n_trim <- nrow(sub_trim); rm(sub_trim)
  } else {
    cat(sprintf("obs variant: |d ln p| >= %.1f dropped on the differenced observation inside prepare_cell_moments()\n", thresh))
    cat(sprintf("Stage 1, trim %.1f...\n", thresh)); t_b <- system.time(b <- run(sub, "trimmed", uv = thresh))[["elapsed"]]
    n_trim <- nrow(sub)
  }
  cat(sprintf("  %.0f s\n", t_b))
  summarise_threshold(a, b, thresh, n_trim, t_a, t_b, op[1], op[2])
}
