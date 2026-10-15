#!/usr/bin/env Rscript
# ============================================================================
# analysis/sigma_window_census.R  (patch 0119, audit #7, M3 sizing)
#
# Is sigma stable enough across periods to borrow the full-panel sigma for a
# recent-window gamma (the "hybrid" M3 design), or must a recent-window
# release re-estimate sigma -- and how many cells would then lose a usable
# sigma? Inputs: Stage-1 tables of the 2% product subsample estimated on
# 1995-2009 and on 2010-2024 (scripts/run_estimation.R --stage 1
# --product-sample 0.02 with --minyear / --maxyear; the window reaches Stage 1
# from patch 0119), and the shipped full-panel Stage-1 table, restricted to
# the same goods. Clean sets as Stage 2 builds them (stage2_sigma_clean(),
# edge and pole rules as shipped).
#   - yield: cells with a converged sigma and cells in the clean set, per table;
#   - early vs late, on cells clean in both (independent data): z = (sigma_late
#     - sigma_early) / sqrt(se_early^2 + se_late^2), the share with |z| > 1.96
#     with the standard errors as published and inflated 1.5x (the exporter
#     bootstrap put the robust same-branch dispersion at 0.9-1.7x the analytic
#     SE), the rank correlation and the median |change| of ln(sigma - 1), and
#     its signed median (positive = higher sigma recently);
#   - full panel vs late, the same (dependent data: context only).
# Reading rule (fixed in patch 0119): early vs late, the |z| > 1.96 share at
# 1.5x SE <= 10% -> sigma is stable, the hybrid is the M3 design; > 25% ->
# sigma drifts, a full window re-estimation is the coherent design and its
# clean-set yield is what it costs; between -> recorded and decided with the
# gamma-drift result.
#
# Usage (repo root):
#   Rscript analysis/sigma_window_census.R --early E.rds --late L.rds
#       [--full data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds]
#       [--label v0110] [--out results/sigma_window_census_v0110.json] [--md docs/results/sigma_window_census_v0110.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.s1 <- function(x) {
  x <- as.data.table(x)
  for (k in c("importer", "good")) set(x, j = k, value = as.character(x[[k]]))
  if (!"convergence" %in% names(x)) x[, convergence := fifelse(status == "ok", 0L, -99L)]
  x
}

#' Compare the clean sets of two Stage-1 tables on their common cells.
sigma_pair <- function(a, b, inflate = c(1, 1.5)) {
  j <- merge(a[, .(importer, good, s_a = sigma, se_a = sigma_se)], b[, .(importer, good, s_b = sigma, se_b = sigma_se)],
             by = c("importer", "good"))
  za <- log(j$s_a - 1); zb <- log(j$s_b - 1)
  ok <- is.finite(j$se_a) & is.finite(j$se_b) & j$se_a > 0 & j$se_b > 0
  zs <- (j$s_b - j$s_a)[ok] / sqrt(j$se_a[ok]^2 + j$se_b[ok]^2)
  list(cells = nrow(j), cells_with_se = sum(ok),
       share_z = setNames(as.list(vapply(inflate, function(f) mean(abs(zs / f) > 1.96), 0)), paste0("se_x", inflate)),
       rho = if (nrow(j) > 2L) cor(za, zb, method = "spearman") else NA_real_,
       median_abs_change = median(abs(zb - za)), median_signed_change = median(zb - za),
       share_change_gt_x2 = mean(abs(zb - za) > log(2)))
}

#' The census.
sigma_window_census <- function(early, late, full, pole_c = 1) {
  early <- .s1(early); late <- .s1(late); full <- .s1(full)
  goods <- intersect(unique(late$good), unique(early$good))
  full <- full[good %in% goods]
  clean <- function(x) stage2_sigma_clean(x, "fallback", "fallback", pole_c)$clean
  ce <- clean(early); cl <- clean(late); cf <- clean(full)
  yield <- function(x, cx) list(cells = nrow(x), converged = sum(x$convergence %in% 0L & is.finite(x$sigma) & x$sigma > 1),
                                clean = nrow(cx), clean_share = nrow(cx) / nrow(x))
  list(goods = length(goods),
       yield = list(early = yield(early, ce), late = yield(late, cl), full = yield(full, cf)),
       early_vs_late = sigma_pair(ce, cl), full_vs_late = sigma_pair(cf, cl),
       full_clean_lost_late = sum(!paste(cf$importer, cf$good) %in% paste(cl$importer, cl$good)),
       global_fallback_full = median(cf$sigma), global_fallback_late = median(cl$sigma))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
  e_path <- get_arg("--early"); l_path <- get_arg("--late")
  f_path <- get_arg("--full", "data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds")
  if (is.null(e_path) || is.null(l_path)) stop("--early and --late are required")
  for (p in c(e_path, l_path, f_path)) if (!file.exists(p)) stop("not found: ", p)
  label <- get_arg("--label", "run")
  out_json <- get_arg("--out", sprintf("results/sigma_window_census_%s.json", label))
  out_md <- get_arg("--md", sprintf("docs/results/sigma_window_census_%s.md", label))
  .this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) "analysis")
  .root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
  for (f in c("utils_general.R", "iteration_helpers.R")) source(file.path(.root, "R", f))
  res <- sigma_window_census(readRDS(e_path), readRDS(l_path), readRDS(f_path))
  meta <- list(early = e_path, late = l_path, full = f_path, label = label,
               git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(c(list(meta = meta), res), out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  f3 <- function(x) formatC(x, digits = 3, format = "f"); pc <- function(x) sprintf("%.1f%%", 100 * x); fi <- function(x) format(x, big.mark = ",", scientific = FALSE)
  y <- res$yield; el <- res$early_vs_late; fl <- res$full_vs_late
  verdict <- { s <- el$share_z$se_x1.5; if (!is.finite(s)) "undetermined" else if (s <= 0.10) "sigma stable: hybrid" else if (s > 0.25) "sigma drifts: full window re-estimation" else "between" }
  md <- c(sprintf("# Is sigma stable across periods? (%s)", label), "",
          sprintf("Stage 1 on the 2%% product subsample (%d goods): 1995-2009 `%s`, 2010-2024 `%s`, full panel `%s` (restricted to the same goods). Clean sets as shipped (edge and pole fallback, c = 1). Rev %s, %s.",
                  res$goods, basename(e_path), basename(l_path), basename(f_path), meta$git_rev, meta$timestamp), "",
          "| table | cells | converged sigma > 1 | clean | clean share |", "|---|---|---|---|---|",
          sprintf("| %s | %s | %s | %s | %s |", c("1995-2009", "2010-2024", "full panel"), fi(c(y$early$cells, y$late$cells, y$full$cells)),
                  fi(c(y$early$converged, y$late$converged, y$full$converged)), fi(c(y$early$clean, y$late$clean, y$full$clean)),
                  pc(c(y$early$clean_share, y$late$clean_share, y$full$clean_share))), "",
          sprintf("Full-panel clean cells without a clean 2010-2024 sigma: %s. Clean-set median sigma (the fallback value): full panel %.4f, 2010-2024 %.4f.",
                  fi(res$full_clean_lost_late), res$global_fallback_full, res$global_fallback_late), "",
          "| comparison | cells clean in both | with both SEs | abs(z) > 1.96, SE as published | at 1.5x SE | rank rho, ln(sigma - 1) | median abs change | median signed change | change > x2 |", "|---|---|---|---|---|---|---|---|---|",
          sprintf("| 1995-2009 vs 2010-2024 | %s | %s | %s | %s | %s | %s | %s | %s |", fi(el$cells), fi(el$cells_with_se), pc(el$share_z$se_x1), pc(el$share_z$se_x1.5), f3(el$rho), f3(el$median_abs_change), f3(el$median_signed_change), pc(el$share_change_gt_x2)),
          sprintf("| full panel vs 2010-2024 | %s | %s | %s | %s | %s | %s | %s | %s |", fi(fl$cells), fi(fl$cells_with_se), pc(fl$share_z$se_x1), pc(fl$share_z$se_x1.5), f3(fl$rho), f3(fl$median_abs_change), f3(fl$median_signed_change), pc(fl$share_change_gt_x2)), "",
          sprintf("Reading (rule fixed in patch 0119, on 1995-2009 vs 2010-2024 at 1.5x SE): **%s**.", verdict), "")
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n")
  cat(sprintf("sigma_window_census: wrote %s and %s\n", out_json, out_md))
}
