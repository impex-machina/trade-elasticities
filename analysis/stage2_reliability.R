#!/usr/bin/env Rscript
# =============================================================================
# analysis/stage2_reliability.R   (patch 0071, v0.8.0 experiment infrastructure)
# Reads a manifest of Stage-2b tables produced by the local design grid and
# reports, per configuration: the gamma ~ 0 population, non-convergence, the
# shrinkage weight, the within-cell dispersion, the distance from the good-
# level prior and opt_tariff -- and, for configurations run on two disjoint
# halves of the panel, the split-half reliability of the within-cell
# heterogeneity: the correlation, over (importer, exporter, good) keys
# directly estimated in both halves and cells with >= 2 such keys, of the
# within-cell-demeaned log gamma between halves (Pearson) and the rank
# correlation of log gamma. Reproducible heterogeneity is signal; the
# reliability of the shipped log-ridge at lambda = 0.1 is ~1 by construction
# (both halves are the prior), so read it against the within-cell sd.
# Usage:
#   Rscript analysis/stage2_reliability.R --runs runs.csv --stage2a <regional rds> \
#       [--out results/stage2_reliability.json] [--md docs/results/stage2_reliability.md]
# runs.csv columns: config (label shared by a configuration's passes), split
# (full | A | B), path (the 2b rds). Extra columns are carried into the tables.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.est <- function(x) x[!is.na(tier) & tier < 3L & !(convergence %in% -1L) & is.finite(gamma) & gamma > 0]

reliability_summary <- function(x, priors) {
  x <- as.data.table(x); x[, good := as.character(good)]
  e <- .est(x); e <- priors[e, on = "good"]; e[, lg := log(gamma)]; e[, dev := lg - ln_gamma_prior]
  e[, cell := paste(importer, good, sep = "|")]; e[, n_cell := .N, by = cell]
  wc <- e[n_cell >= 2L, .(sd_lg = sd(lg)), by = cell]
  oc <- unique(e[, .(importer, good, opt_tariff)], by = c("importer", "good"))
  list(rows = nrow(x), n_estimated = nrow(e),
       share_non_converged = mean(x$gamma_se_status %in% "non_converged"),
       share_gamma_le_0_01 = mean(e$gamma <= 0.01), share_gamma_le_1e_4 = mean(e$gamma <= 1e-4),
       share_gamma_ge_10 = mean(e$gamma >= 10),
       shrink_wt_median = median(e$gamma_shrink_wt, na.rm = TRUE),
       within_cell_sd_median = median(wc$sd_lg, na.rm = TRUE),
       abs_dev_median = median(abs(e$dev), na.rm = TRUE), abs_dev_p90 = unname(quantile(abs(e$dev), 0.9, na.rm = TRUE)),
       opt_tariff_median = median(oc$opt_tariff, na.rm = TRUE),
       gamma_median = median(e$gamma))
}

split_half_reliability <- function(a, b, priors) {
  k <- c("importer", "exporter", "good")
  ea <- .est(as.data.table(a))[, c(k, "gamma"), with = FALSE]; eb <- .est(as.data.table(b))[, c(k, "gamma"), with = FALSE]
  ea[, good := as.character(good)]; eb[, good := as.character(good)]
  j <- merge(ea, eb, by = k, suffixes = c("_a", "_b"))
  if (nrow(j) < 2L) return(list(n_keys = nrow(j), n_cells = 0L, r_within = NA_real_, rho_rank = NA_real_, r_raw = NA_real_))
  j[, `:=`(la = log(gamma_a), lb = log(gamma_b))]; j[, cell := paste(importer, good, sep = "|")]
  j[, n := .N, by = cell]; j2 <- j[n >= 2L]
  j2[, `:=`(da = la - mean(la), db = lb - mean(lb)), by = cell]
  list(n_keys = nrow(j), n_cells = uniqueN(j2$cell),
       r_within = if (nrow(j2) > 2L) cor(j2$da, j2$db) else NA_real_,
       rho_rank = if (nrow(j2) > 2L) cor(j2$da, j2$db, method = "spearman") else NA_real_,
       r_raw = cor(j$la, j$lb),
       sd_within_a = sd(j2$da), sd_within_b = sd(j2$db))
}

reliability_report <- function(runs, priors) {
  runs <- as.data.table(runs)
  tabs <- list(); cfgs <- unique(runs$config); out_full <- list(); out_split <- list()
  for (cf in cfgs) {
    r <- runs[config == cf]
    for (sp in intersect(c("full", "A", "B"), r$split)) {
      p <- r[split == sp, path][1]; if (!p %in% names(tabs)) tabs[[p]] <- readRDS(p)
    }
    if ("full" %in% r$split) out_full[[cf]] <- c(list(config = cf), reliability_summary(tabs[[r[split == "full", path][1]]], priors))
    if (all(c("A", "B") %in% r$split))
      out_split[[cf]] <- c(list(config = cf), split_half_reliability(tabs[[r[split == "A", path][1]]], tabs[[r[split == "B", path][1]]], priors))
  }
  list(full = rbindlist(lapply(out_full, as.data.table), fill = TRUE),
       split = rbindlist(lapply(out_split, as.data.table), fill = TRUE))
}

.md_table <- function(dt, digits = 3) {
  dt <- as.data.table(dt); if (!nrow(dt)) return("(none)")
  f <- function(v) if (is.numeric(v)) formatC(v, digits = digits, format = "g") else as.character(v)
  hdr <- paste("|", paste(names(dt), collapse = " | "), "|"); sep <- paste("|", paste(rep("---", ncol(dt)), collapse = " | "), "|")
  rows <- vapply(seq_len(nrow(dt)), function(i) paste("|", paste(vapply(names(dt), function(nm) f(dt[[nm]][i]), ""), collapse = " | "), "|"), "")
  c(hdr, sep, rows)
}

if (sys.nframe() == 0L && !exists("RELIABILITY_NO_MAIN")) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  runs_path <- get_arg("--runs"); s2a_path <- get_arg("--stage2a")
  out_json <- get_arg("--out", "results/stage2_reliability.json"); out_md <- get_arg("--md", "docs/results/stage2_reliability.md")
  if (is.null(runs_path) || is.null(s2a_path)) stop("--runs and --stage2a are required")
  runs <- fread(runs_path); s2a <- readRDS(s2a_path); setDT(s2a); s2a[, good := as.character(good)]
  priors <- s2a[!is.na(sigma) & !is.na(gamma) & gamma > 0, .(ln_gamma_prior = median(log(gamma))), by = good]
  res <- reliability_report(runs, priors)
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(list(full = res$full, split = res$split, generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), runs = runs_path),
             out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  md <- c("# Stage-2 design grid: summaries and split-half reliability (patch 0071)", "",
          sprintf("Runs manifest: `%s`; priors from `%s`. Generated %s.", runs_path, basename(s2a_path), format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")), "",
          "## Full-panel summaries", "", .md_table(res$full), "",
          "## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)", "", .md_table(res$split), "")
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n"); cat("wrote", out_json, "and", out_md, "\n")
}
