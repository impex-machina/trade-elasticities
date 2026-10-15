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
# (patch 0117) --boot-goods B adds a cluster bootstrap over goods: the keys of
# a split are resampled by good (cells nest in goods, so within-cell demeaning
# is untouched), B draws, percentile intervals for each configuration's
# r_within and -- with --base CONFIG -- for its difference from that base on
# the same draws, with the share of draws in which the difference is <= 0.
# The 2% subsample has 25 goods: the decision grids since v0.8.0 compared
# configurations on point estimates whose sampling variation across goods
# was never shown (the v0.10.0 rule cleared its +0.03 bar by 0.002).
# Usage:
#   Rscript analysis/stage2_reliability.R --runs runs.csv --stage2a <regional rds> \
#       [--out results/stage2_reliability.json] [--md docs/results/stage2_reliability.md]
#       [--boot-goods 2000 --boot-seed 20261015 --base v091_base]
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

# (patch 0117) the keys behind a split-half reliability: (importer, exporter,
# good) rows directly estimated in both halves, la / lb = log gamma, and, in
# cells with >= 2 such keys, da / db = the within-cell-demeaned values.
split_half_keys <- function(a, b) {
  k <- c("importer", "exporter", "good")
  ea <- .est(as.data.table(a))[, c(k, "gamma"), with = FALSE]; eb <- .est(as.data.table(b))[, c(k, "gamma"), with = FALSE]
  ea[, good := as.character(good)]; eb[, good := as.character(good)]
  j <- merge(ea, eb, by = k, suffixes = c("_a", "_b"))
  if (!nrow(j)) return(list(j = j, j2 = j))
  j[, `:=`(la = log(gamma_a), lb = log(gamma_b))]; j[, cell := paste(importer, good, sep = "|")]
  j[, n := .N, by = cell]; j2 <- j[n >= 2L]
  j2[, `:=`(da = la - mean(la), db = lb - mean(lb)), by = cell]
  list(j = j, j2 = j2)
}

split_half_reliability <- function(a, b, priors) {
  kk <- split_half_keys(a, b); j <- kk$j; j2 <- kk$j2
  if (nrow(j) < 2L) return(list(n_keys = nrow(j), n_cells = 0L, r_within = NA_real_, rho_rank = NA_real_, r_raw = NA_real_))
  list(n_keys = nrow(j), n_cells = uniqueN(j2$cell),
       r_within = if (nrow(j2) > 2L) cor(j2$da, j2$db) else NA_real_,
       rho_rank = if (nrow(j2) > 2L) cor(j2$da, j2$db, method = "spearman") else NA_real_,
       r_raw = cor(j$la, j$lb),
       sd_within_a = sd(j2$da), sd_within_b = sd(j2$db))
}

# (patch 0117) Per-good sufficient statistics of a split's demeaned keys, and
# the Pearson r_within of any resample of goods from them: r is a function of
# the sums n, Sa, Sb, Saa, Sbb, Sab, so a draw is a weighted sum by good.
.good_stats <- function(j2) j2[, .(n = .N, sa = sum(da), sb = sum(db), saa = sum(da^2), sbb = sum(db^2), sab = sum(da * db)), by = good]
.r_from_counts <- function(gs, w) {
  n <- sum(w * gs$n); if (n < 3) return(NA_real_)
  sa <- sum(w * gs$sa); sb <- sum(w * gs$sb)
  vaa <- sum(w * gs$saa) - sa^2 / n; vbb <- sum(w * gs$sbb) - sb^2 / n
  if (vaa <= 0 || vbb <= 0) return(NA_real_)
  (sum(w * gs$sab) - sa * sb / n) / sqrt(vaa * vbb)
}

#' Cluster bootstrap over goods of r_within (and differences from a base
#' configuration on the same draws). j2_list: named list of split_half_keys()$j2.
goods_bootstrap <- function(j2_list, B = 2000L, seed = 20261015L, base = NULL, probs = c(0.025, 0.975)) {
  stats <- lapply(j2_list, .good_stats)
  goods <- sort(unique(unlist(lapply(stats, function(g) g$good))))
  set.seed(seed)
  draws <- replicate(B, tabulate(sample.int(length(goods), length(goods), replace = TRUE), nbins = length(goods)))
  r_boot <- vapply(stats, function(gs) {
    idx <- match(gs$good, goods)
    apply(draws, 2L, function(cnt) .r_from_counts(gs, cnt[idx]))
  }, numeric(B))
  if (B == 1L) r_boot <- matrix(r_boot, nrow = 1L, dimnames = list(NULL, names(stats)))
  out <- rbindlist(lapply(names(stats), function(cf) {
    gs <- stats[[cf]]; rb <- r_boot[, cf]
    row <- list(config = cf, n_goods = nrow(gs), r_within = .r_from_counts(gs, rep(1, nrow(gs))),
                r_lo = unname(quantile(rb, probs[1], na.rm = TRUE)), r_hi = unname(quantile(rb, probs[2], na.rm = TRUE)))
    if (!is.null(base) && base %in% names(stats) && cf != base) {
      dlt <- rb - r_boot[, base]
      row <- c(row, list(base = base, delta = row$r_within - .r_from_counts(stats[[base]], rep(1, nrow(stats[[base]]))),
                         delta_lo = unname(quantile(dlt, probs[1], na.rm = TRUE)), delta_hi = unname(quantile(dlt, probs[2], na.rm = TRUE)),
                         share_delta_le_0 = mean(dlt <= 0, na.rm = TRUE)))
    }
    row
  }), fill = TRUE)
  list(table = out, B = B, seed = seed, n_goods_union = length(goods), probs = probs)
}

reliability_report <- function(runs, priors) {
  runs <- as.data.table(runs)
  tabs <- list(); cfgs <- unique(runs$config); out_full <- list(); out_split <- list()
  for (cf in cfgs) {
    r <- runs[config == cf]
    for (sp in intersect(c("full", "A", "B"), r$split)) {
      p <- r[split == sp, path][1]; if (!p %in% names(tabs)) { tt <- as.data.table(readRDS(p)); tabs[[p]] <- if ("trim_reason" %in% names(tt)) tt[is.na(trim_reason)] else tt }   # patch 0102: published rows
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
  runs <- fread(runs_path); s2a <- readRDS(s2a_path); setDT(s2a); if ("trim_reason" %in% names(s2a)) s2a <- s2a[is.na(trim_reason)]; s2a[, good := as.character(good)]
  priors <- s2a[!is.na(sigma) & !is.na(gamma) & gamma > 0, .(ln_gamma_prior = median(log(gamma))), by = good]
  res <- reliability_report(runs, priors)
  # (patch 0117) the goods bootstrap
  boot_B <- as.integer(get_arg("--boot-goods", "0")); boot_seed <- as.integer(get_arg("--boot-seed", "20261015")); boot_base <- get_arg("--base")
  boot <- NULL
  if (boot_B > 0L) {
    j2s <- list()
    for (cf in unique(runs$config)) {
      r <- runs[config == cf]
      if (!all(c("A", "B") %in% r$split)) next
      rd <- function(p) { tt <- as.data.table(readRDS(p)); if ("trim_reason" %in% names(tt)) tt[is.na(trim_reason)] else tt }
      j2s[[cf]] <- split_half_keys(rd(r[split == "A", path][1]), rd(r[split == "B", path][1]))$j2
    }
    if (!is.null(boot_base) && !boot_base %in% names(j2s)) stop("--base ", boot_base, " has no A/B split in the runs manifest")
    boot <- goods_bootstrap(j2s, B = boot_B, seed = boot_seed, base = boot_base)
  }
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(list(full = res$full, split = res$split, boot = if (is.null(boot)) NULL else list(B = boot$B, seed = boot$seed, base = boot_base,
                                                                                               n_goods = boot$n_goods_union, table = boot$table),
                  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), runs = runs_path),
             out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  md <- c("# Stage-2 design grid: summaries and split-half reliability (patch 0071)", "",
          sprintf("Runs manifest: `%s`; priors from `%s`. Generated %s.", runs_path, basename(s2a_path), format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")), "",
          "## Full-panel summaries", "", .md_table(res$full), "",
          "## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)", "", .md_table(res$split), "",
          if (is.null(boot)) character(0) else c(sprintf("## Goods bootstrap (patch 0117): %d draws over %d goods, seed %d%s", boot$B, boot$n_goods_union, boot$seed,
                                                          if (is.null(boot_base)) "" else sprintf(", differences from `%s` on the same draws", boot_base)), "",
                                                  "r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.", "", .md_table(boot$table), ""))
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n"); cat("wrote", out_json, "and", out_md, "\n")
}
