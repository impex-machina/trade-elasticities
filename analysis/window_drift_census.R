#!/usr/bin/env Rscript
# ============================================================================
# analysis/window_drift_census.R  (patch 0119, audit #7, M3 sizing)
#
# Would a recent-window estimate (2010-2024) describe today's elasticities
# better than the full-panel average? The 2% subsample already has four
# Stage-2b runs under the shipped configuration that answer it without new
# estimation (v0.11.0 pre-session artifacts; full-panel sigma and Stage-2a
# priors in every half, i.e. the "hybrid" design: sigma from the full panel,
# gamma from the window):
#   parity halves  -- odd / even differenced years of the same period: the
#                     difference between them is noise only;
#   period halves  -- 1995-2009 / 2010-2024: noise plus the true change.
# For a quantity q estimated in both halves, d = q_b - q_a. With V the
# variance of d (robust: (1.4826 * MAD)^2), V_parity = 2 s2 and V_period =
# D2 + 2 s2, where s2 is the noise variance of a half-panel estimate and D2
# the variance of the true change. For current use the recent half (error
# variance s2) beats the full-panel average (error ~ D2 / 4 + s2 / 2) iff
# D2 > 2 s2, i.e. V_period > 2 V_parity.
#
# Quantities: the cell's log opt_tariff (the policy number, primary), the
# cell's mean log gamma over directly estimated rows, and row log gamma.
# Also: coverage of each half, and the exporters with the most directly
# estimated rows in both period halves with the median change in their log
# gamma (later minus earlier).
#
# Reading rule (fixed in patch 0119, docs/methodology/stage2_country.md):
# on cell log opt_tariff, V_period / V_parity > 2 -> a recent-window estimate
# beats the full-panel average for current use; < 1.5 -> it does not; between
# -> recorded and decided together with the sigma-window result.
#
# Usage (repo root):
#   Rscript analysis/window_drift_census.R --parity-odd A.rds --parity-even B.rds
#       --period-early C.rds --period-late D.rds [--label v0110]
#       [--out results/window_drift_census_v0110.json] [--md docs/results/window_drift_census_v0110.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.rvar <- function(d) { d <- d[is.finite(d)]; if (length(d) < 3L) NA_real_ else (1.4826 * mad(d, constant = 1))^2 }

#' Cell and row quantities of one published Stage-2b table.
window_quantities <- function(x) {
  x <- as.data.table(x)
  for (k in intersect(c("importer", "exporter", "good"), names(x))) set(x, j = k, value = as.character(x[[k]]))
  if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
  est <- x[is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0]
  list(
    cell_tariff = unique(x[is.finite(opt_tariff) & opt_tariff > 0, .(importer, good, q = log(opt_tariff))], by = c("importer", "good")),
    cell_gamma  = est[, .(q = mean(log(gamma))), by = .(importer, good)],
    row_gamma   = est[, .(importer, exporter, good, q = log(gamma))],
    coverage    = list(published_rows = nrow(x), estimated_rows = nrow(est), cells = uniqueN(x, by = c("importer", "good")),
                       tier3_share = mean(x$tier %in% 3L))
  )
}

#' Compare two halves on one quantity.
split_stats <- function(a, b, keys) {
  j <- merge(a, b, by = keys, suffixes = c("_a", "_b"))
  d <- j$q_b - j$q_a
  list(n = nrow(j), r = if (nrow(j) > 2L) cor(j$q_a, j$q_b) else NA_real_,
       rho = if (nrow(j) > 2L) cor(j$q_a, j$q_b, method = "spearman") else NA_real_,
       v_robust = .rvar(d), v_plain = if (length(d) > 2L) var(d) else NA_real_,
       median_abs = median(abs(d)), median_signed = median(d))
}

#' The census. Four published tables; returns the per-quantity drift readings.
window_drift_census <- function(odd, even, early, late, top_n = 10L) {
  qo <- window_quantities(odd); qe <- window_quantities(even); q1 <- window_quantities(early); q2 <- window_quantities(late)
  keys <- list(cell_tariff = c("importer", "good"), cell_gamma = c("importer", "good"), row_gamma = c("importer", "exporter", "good"))
  out <- list()
  for (nm in names(keys)) {
    par <- split_stats(qo[[nm]], qe[[nm]], keys[[nm]]); per <- split_stats(q1[[nm]], q2[[nm]], keys[[nm]])
    ratio <- per$v_robust / par$v_robust
    out[[nm]] <- list(parity = par, period = per, ratio_robust = ratio, ratio_plain = per$v_plain / par$v_plain,
                      drift_var = per$v_robust - par$v_robust, noise_var_half = par$v_robust / 2,
                      verdict = if (!is.finite(ratio)) "undetermined" else if (ratio > 2) "recent window better" else if (ratio < 1.5) "full panel as good" else "between")
  }
  j <- merge(q1$row_gamma, q2$row_gamma, by = c("importer", "exporter", "good"), suffixes = c("_early", "_late"))
  top <- j[, .(rows = .N, median_change = median(q_late - q_early), p25 = quantile(q_late - q_early, 0.25),
               p75 = quantile(q_late - q_early, 0.75)), by = exporter][order(-rows)][seq_len(min(top_n, .N))]
  list(quantities = out, top_exporters = top,
       coverage = list(odd = qo$coverage, even = qe$coverage, early = q1$coverage, late = q2$coverage))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
  paths <- c(odd = get_arg("--parity-odd"), even = get_arg("--parity-even"), early = get_arg("--period-early"), late = get_arg("--period-late"))
  if (length(paths) != 4L || anyNA(paths)) stop("--parity-odd, --parity-even, --period-early and --period-late are required")
  for (p in paths) if (!file.exists(p)) stop("not found: ", p)
  label <- get_arg("--label", "run")
  out_json <- get_arg("--out", sprintf("results/window_drift_census_%s.json", label))
  out_md <- get_arg("--md", sprintf("docs/results/window_drift_census_%s.md", label))
  .this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) "analysis")
  source(file.path(normalizePath(file.path(.this_dir, ".."), mustWork = FALSE), "R", "utils_general.R"))
  res <- window_drift_census(readRDS(paths[["odd"]]), readRDS(paths[["even"]]), readRDS(paths[["early"]]), readRDS(paths[["late"]]))
  meta <- list(paths = as.list(paths), label = label,
               git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(c(list(meta = meta), res), out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  f3 <- function(x) formatC(x, digits = 3, format = "f"); fi <- function(x) format(x, big.mark = ",", scientific = FALSE)
  qn <- c(cell_tariff = "cell log opt_tariff", cell_gamma = "cell mean log gamma", row_gamma = "row log gamma")
  rows <- vapply(names(qn), function(nm) { z <- res$quantities[[nm]]
    sprintf("| %s | %s / %s | %s / %s | %s / %s | %s | **%s** |", qn[[nm]], fi(z$parity$n), fi(z$period$n), f3(z$parity$r), f3(z$period$r),
            f3(sqrt(z$parity$v_robust)), f3(sqrt(z$period$v_robust)), f3(z$ratio_robust), z$verdict) }, "")
  cv <- res$coverage
  md <- c(sprintf("# Does gamma drift by more than half-panel noise? (%s)", label), "",
          sprintf("Parity halves `%s` / `%s`; period halves `%s` (1995-2009) / `%s` (2010-2024). Rev %s, %s.",
                  basename(paths[["odd"]]), basename(paths[["even"]]), basename(paths[["early"]]), basename(paths[["late"]]), meta$git_rev, meta$timestamp), "",
          "Robust SD of the between-half difference (1.4826 x MAD); ratio = V_period / V_parity. A recent-window estimate beats the full-panel average for current use when the ratio exceeds 2 (reading rule, patch 0119).", "",
          "| quantity | units (parity / period) | r (parity / period) | SD of difference (parity / period) | ratio | reading |", "|---|---|---|---|---|---|", rows, "",
          sprintf("Coverage -- directly estimated rows: odd %s, even %s, 1995-2009 %s, 2010-2024 %s; cells: %s / %s / %s / %s; Tier 3: %.1f%% / %.1f%% / %.1f%% / %.1f%%.",
                  fi(cv$odd$estimated_rows), fi(cv$even$estimated_rows), fi(cv$early$estimated_rows), fi(cv$late$estimated_rows),
                  fi(cv$odd$cells), fi(cv$even$cells), fi(cv$early$cells), fi(cv$late$cells),
                  100 * cv$odd$tier3_share, 100 * cv$even$tier3_share, 100 * cv$early$tier3_share, 100 * cv$late$tier3_share), "",
          "Exporters with the most directly estimated rows in both periods: change in log gamma, 2010-2024 minus 1995-2009 (negative = more elastic supply recently).", "",
          "| exporter | rows | median change | p25 | p75 |", "|---|---|---|---|---|",
          sprintf("| %s | %s | %s | %s | %s |", res$top_exporters$exporter, fi(res$top_exporters$rows), f3(res$top_exporters$median_change),
                  f3(res$top_exporters$p25), f3(res$top_exporters$p75)), "")
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n")
  cat(sprintf("window_drift_census: wrote %s and %s\n", out_json, out_md))
}
