#!/usr/bin/env Rscript
# ===========================================================================
# analysis/sigma_update_sensitivity_census.R  (patch 0165, fresh-eyes audit #11)
#
# Reads one run made with the patch-0165 diagnostics on --
#   --stage2-sigma-profile both --stage2-gamma-v-refresh 1
#   --stage2-sigma-update-trim-grid 1.5,2,3,off
# -- (the 2% subsample before any default changes; the full data if wanted)
# and answers three questions under rules fixed here, before the numbers:
#
#   1. The closed-form profile (R/sigma_update.R). ADOPTABLE if the closed form
#      and the grid give the same status on at least 99.9% of profiled cells,
#      the largest |d ln(sigma - 1)| between them on cells 'ok' under both is at
#      most 1e-5, and at most 0.1% of cells fell back to the grid. Expected
#      disagreements: cells whose minimum lies within one grid step (1.6% in
#      sigma) of the floor or the cap, which the grid calls failed updates and
#      the closed form interior.
#   2. One gamma_V refresh after the update. The update pass reused the
#      exporter gamma_V lookup of the last gamma_V pass, built at the Stage-1
#      sigma. ADOPT the refresh if it moves at least 10% of directly estimated
#      published rows by more than 1% in gamma, or the opt_tariff of at least
#      10% of cells by more than 1%; otherwise CLOSE it -- the stale lookup then
#      moves the table less than its other uncertainties.
#   3. The update's sensitivity to the unit-value threshold, gammas held at the
#      run's final values. ROBUST if the median ln(sigma - 1) over the cells
#      'ok' at each threshold moves by less than 0.05 between |d ln p| < 1.5 and
#      < 3, and the Spearman correlation of ln(sigma - 1) across the cells 'ok'
#      at both is at least 0.8; THRESHOLD-DEPENDENT otherwise (the README then
#      says the published level is conditional on the threshold). Not measured
#      without both thresholds in the grid.
# Also reported: the final table's rows by trim reason (the sigma tails since
# v0.12.0 hold no pole or explosive cell: the shrunk sigma lies in
# [1.54, 4.96] by construction).
#
# Usage (repo root; seconds):
#   Rscript analysis/sigma_update_sensitivity_census.R --run <out-dir>
#       [--md docs/results/sigma_update_sensitivity_census.md] [--json results/sigma_update_sensitivity_census.json]
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.lr <- function(s) log(s - 1)

#' 1. closed form against the grid, from a _sigma_update_pass<u>.csv written with --stage2-sigma-profile both
profile_method_reading <- function(prof) {
  prof <- as.data.table(prof)
  if (!all(c("sigma_grid", "status_grid") %in% names(prof))) return(NULL)
  n <- nrow(prof); agree <- prof$status == prof$status_grid
  okb <- prof$status == "ok" & prof$status_grid == "ok" & is.finite(prof$sigma) & is.finite(prof$sigma_grid)
  d <- abs(.lr(prof$sigma[okb]) - .lr(prof$sigma_grid[okb]))
  fb <- if ("profile_method" %in% names(prof)) sum(prof$profile_method == "grid_fallback", na.rm = TRUE) else NA_integer_
  dis <- prof[!agree, .N, by = .(grid = status_grid, closed = status)][order(-N)]
  share_agree <- if (n) mean(agree) else NA_real_
  max_d <- if (length(d)) max(d) else NA_real_
  ok <- isTRUE(share_agree >= 0.999) && isTRUE(max_d <= 1e-5) && (is.na(fb) || fb <= 0.001 * n)
  list(cells = n, share_status_agree = share_agree, cells_ok_both = sum(okb), max_abs_dln = max_d,
       p99_abs_dln = if (length(d)) unname(stats::quantile(d, 0.99)) else NA_real_, grid_fallbacks = fb,
       disagreements = dis, reading = if (ok) "ADOPTABLE" else "NOT ADOPTABLE")
}

#' 2. the gamma_V refresh, from _gamma_v_refresh.csv (its last row)
refresh_reading <- function(rf) {
  rf <- as.data.table(rf)
  if (!nrow(rf)) return(NULL)
  z <- rf[nrow(rf)]
  adopt <- isTRUE(z$share_rows_gt_1pct >= 0.10) || isTRUE(z$share_cells_tariff_gt_1pct >= 0.10)
  list(refresh = z$refresh, rows = z$rows, abs_dlng_p50 = z$abs_dlng_p50, abs_dlng_p90 = z$abs_dlng_p90, abs_dlng_p99 = z$abs_dlng_p99,
       share_rows_gt_1pct = z$share_rows_gt_1pct, cells = z$cells, share_cells_tariff_gt_1pct = z$share_cells_tariff_gt_1pct,
       reading = if (adopt) "ADOPT" else "CLOSE")
}

#' 3. the threshold curve, from _sigma_update_trimgrid.csv; `ref` the run's own threshold ("2")
trim_grid_reading <- function(tg, ref = "2") {
  tg <- as.data.table(tg)
  if (!nrow(tg)) return(NULL)
  tg[, threshold := as.character(threshold)]
  ok <- tg[status == "ok" & is.finite(sigma) & sigma > 1]
  curve <- tg[, .(cells = .N, ok = sum(status == "ok"), at_floor = sum(status == "floor"), at_cap = sum(status == "ceiling")), by = threshold]
  lev <- ok[, .(median_sigma = stats::median(sigma), level_ln = stats::median(.lr(sigma))), by = threshold]
  curve <- merge(curve, lev, by = "threshold", all.x = TRUE)
  pair <- function(a, b) {
    m <- merge(ok[threshold == a, .(importer, good, s_a = sigma)], ok[threshold == b, .(importer, good, s_b = sigma)], by = c("importer", "good"))
    if (nrow(m) < 3L) return(list(cells = nrow(m), med_abs = NA_real_, spearman = NA_real_, share_gt_10pct = NA_real_))
    d <- .lr(m$s_a) - .lr(m$s_b)
    list(cells = nrow(m), med_abs = stats::median(abs(d)), spearman = suppressWarnings(stats::cor(.lr(m$s_a), .lr(m$s_b), method = "spearman")),
         share_gt_10pct = mean(abs(d) > log(1.10)))
  }
  if (ref %in% curve$threshold) {
    vs <- rbindlist(lapply(setdiff(curve$threshold, ref), function(t) c(list(threshold = t), pair(t, ref))))
    data.table::setnames(vs, "cells", "cells_vs")
    curve <- merge(curve, vs, by = "threshold", all.x = TRUE)
  }
  ord <- suppressWarnings(as.numeric(curve$threshold)); ord[curve$threshold == "off"] <- Inf
  curve <- curve[order(ord)]
  reading <- "not measured (the grid needs both 1.5 and 3)"
  p13 <- NULL
  if (all(c("1.5", "3") %in% curve$threshold)) {
    p13 <- pair("1.5", "3")
    dl <- abs(curve[threshold == "1.5", level_ln] - curve[threshold == "3", level_ln])
    reading <- if (isTRUE(dl < 0.05) && isTRUE(p13$spearman >= 0.8)) "ROBUST" else "THRESHOLD-DEPENDENT"
    p13$level_gap <- dl
  }
  list(reference = ref, curve = curve, between_1.5_and_3 = p13, reading = reading)
}

#' rows of the final table by trim reason
trim_reason_counts <- function(tab) {
  tab <- as.data.table(tab)
  if (!"trim_reason" %in% names(tab)) return(data.table(trim_reason = "published", rows = nrow(tab)))
  tab[, .(rows = .N), by = .(trim_reason = fifelse(is.na(trim_reason), "published", trim_reason))][order(-rows)]
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  run <- get_arg("--run"); if (is.null(run) || !dir.exists(run)) stop("--run <out-dir of the diagnostic run> is required")
  md <- get_arg("--md", "docs/results/sigma_update_sensitivity_census.md"); js <- get_arg("--json", "results/sigma_update_sensitivity_census.json")
  one <- function(pat) { f <- list.files(run, pattern = pat, full.names = TRUE); if (length(f) == 1L) f else NULL }
  f_prof <- one("_country_hs4_sigma_update_pass1\\.csv$"); f_ref <- one("_country_hs4_gamma_v_refresh\\.csv$")
  f_tg <- one("_country_hs4_sigma_update_trimgrid\\.csv$"); f_tab <- one("_country_hs4_fixed_sigma\\.rds$")
  r1 <- if (!is.null(f_prof)) profile_method_reading(fread(f_prof, colClasses = list(character = c("importer", "good")))) else NULL
  r2 <- if (!is.null(f_ref)) refresh_reading(fread(f_ref)) else NULL
  r3 <- if (!is.null(f_tg)) trim_grid_reading(fread(f_tg, colClasses = list(character = c("importer", "good", "threshold")))) else NULL
  r4 <- if (!is.null(f_tab)) trim_reason_counts(readRDS(f_tab)) else NULL
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(run = run, git_rev = rev, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  dir.create(dirname(js), recursive = TRUE, showWarnings = FALSE); dir.create(dirname(md), recursive = TRUE, showWarnings = FALSE)
  write_json(list(meta = meta, profile_methods = r1, gamma_v_refresh = r2, trim_grid = r3, trim_reasons = r4), js, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  f3 <- function(x) if (is.null(x) || !length(x)) "--" else ifelse(is.na(x), "--", sprintf("%.3f", x))
  pc <- function(x) if (is.null(x) || !length(x)) "--" else ifelse(is.na(x), "--", sprintf("%.1f%%", 100 * x))
  L <- c("# The sigma update: profile method, gamma_V refresh, unit-value threshold (patch 0165)", "",
         sprintf("Run `%s`; rev %s, %s. Rules: the header of `analysis/sigma_update_sensitivity_census.R`, fixed before the numbers.", run, rev, meta$timestamp), "",
         "## 1. Closed-form profile against the grid", "")
  L <- c(L, if (is.null(r1)) "Not measured (the run was not made with `--stage2-sigma-profile both`)." else c(
    sprintf("%s cells profiled; the two give the same status on %s; on the %s cells 'ok' under both, |d ln(sigma - 1)| p99 %.2e, max %.2e; grid fallbacks %s.",
            format(r1$cells, big.mark = ","), pc(r1$share_status_agree), format(r1$cells_ok_both, big.mark = ","), r1$p99_abs_dln, r1$max_abs_dln,
            if (is.na(r1$grid_fallbacks)) "--" else format(r1$grid_fallbacks, big.mark = ",")),
    if (nrow(r1$disagreements)) c("", "| grid | closed form | cells |", "|---|---|---|", sprintf("| %s | %s | %d |", r1$disagreements$grid, r1$disagreements$closed, r1$disagreements$N)) else character(0),
    "", sprintf("**Reading: %s.**", r1$reading)), "", "## 2. One gamma_V refresh after the update", "")
  L <- c(L, if (is.null(r2)) "Not measured (the run was not made with `--stage2-gamma-v-refresh`)." else c(
    sprintf("%s directly estimated rows: |d ln gamma| p50 %.2e, p90 %.2e, p99 %.2e; moved by more than 1%%: %s of rows; opt_tariff moved by more than 1%% in %s of %s cells.",
            format(r2$rows, big.mark = ","), r2$abs_dlng_p50, r2$abs_dlng_p90, r2$abs_dlng_p99, pc(r2$share_rows_gt_1pct), pc(r2$share_cells_tariff_gt_1pct),
            format(r2$cells, big.mark = ",")), "", sprintf("**Reading: %s.**", r2$reading)), "", "## 3. The unit-value threshold, gammas held", "")
  if (is.null(r3)) L <- c(L, "Not measured (the run was not made with `--stage2-sigma-update-trim-grid`).") else {
    cv <- r3$curve; has_vs <- "med_abs" %in% names(cv)
    L <- c(L, sprintf("Reference: the run's own threshold (|d ln p| < %s). Cells 'ok' at both thresholds are compared on ln(sigma - 1).", r3$reference), "",
           if (has_vs) "| threshold | cells | ok | median sigma (ok) | level ln(sigma - 1) | vs reference: cells | median abs diff | Spearman | moved > 10% |" else "| threshold | cells | ok | median sigma (ok) | level ln(sigma - 1) |",
           if (has_vs) "|---|---|---|---|---|---|---|---|---|" else "|---|---|---|---|---|",
           if (has_vs) sprintf("| %s | %d | %d | %s | %s | %s | %s | %s | %s |", cv$threshold, cv$cells, cv$ok, f3(cv$median_sigma), f3(cv$level_ln),
                               ifelse(is.na(cv$cells_vs), "--", format(cv$cells_vs)), f3(cv$med_abs), f3(cv$spearman), pc(cv$share_gt_10pct))
           else sprintf("| %s | %d | %d | %s | %s |", cv$threshold, cv$cells, cv$ok, f3(cv$median_sigma), f3(cv$level_ln)),
           "", sprintf("**Reading: %s.**%s", r3$reading, if (!is.null(r3$between_1.5_and_3)) sprintf(" Between 1.5 and 3: level gap %.3f, Spearman %.3f on %d cells.",
                                                                                                    r3$between_1.5_and_3$level_gap, r3$between_1.5_and_3$spearman, r3$between_1.5_and_3$cells) else ""))
  }
  L <- c(L, "", "## 4. The final table by trim reason", "")
  L <- c(L, if (is.null(r4)) "No final table in the run directory." else c("| trim_reason | rows |", "|---|---|", sprintf("| %s | %s |", r4$trim_reason, format(r4$rows, big.mark = ","))))
  writeLines(enc2utf8(L), md, useBytes = TRUE)
  cat(paste(L, collapse = "\n"), "\n")
  cat(sprintf("sigma_update_sensitivity_census: wrote %s and %s\n", md, js))
}
