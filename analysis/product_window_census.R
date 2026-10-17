#!/usr/bin/env Rscript
# ============================================================================
# analysis/product_window_census.R  (patch 0130)
#
# The independent test of the product-level table (analysis/product_summary.R).
# Patch 0127's census compared halves of the 2% product subsample that re-ran
# Stage 2b only, with the full-panel Stage 1 and Stage-2a priors; a product's
# median gamma is mostly that prior (median shrink weight 0.92), so those
# halves agreed by construction. Here each period is estimated from scratch:
# the 1995-2009 and 2010-2024 Stage-1 tables of patch 0119's M3 sizing (each
# estimated on its own years), then Stage 2a and 2b on the same window from
# that Stage 1 (scripts/run_estimation.R --minyear/--maxyear, same product
# sample). The census compares the two windows' product tables and, as a
# record, checks by hash whether the earlier halves shared their Stage-1 and
# Stage-2a tables.
#
# Reading (fixed in patch 0130, before the numbers; the thresholds are patch
# 0127's): "reproduces" if the Spearman correlation across products of the
# product median gamma AND of the product median opt_tariff between the two
# windows are both >= 0.5; "does not reproduce" if both are < 0.3; otherwise
# "partial". The windows differ in time as well as in data, so drift lowers
# the correlation too: "reproduces" is the stronger statement.
#
# Usage (repo root; seconds, once the window runs exist):
#   Rscript analysis/product_window_census.R --w0 DIR0 --w1 DIR1
#       [--pairs "A1,A2;B1,B2"]   (run directories whose shared inputs to check)
#       [--json results/product_window_census.json] [--md docs/results/product_window_census.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

PWC_PREFIX <- "baci_hs92_v202601_elast"

.pwc_sha <- function(p) {
  if (!file.exists(p)) return(NA_character_)
  con <- file(p, "rb"); on.exit(close(con))
  as.vector(unclass(as.character(openssl::sha256(con))))
}

#' One window: its Stage-1 and Stage-2b tables and their goods.
pwc_window <- function(dir) {
  s1p <- file.path(dir, paste0(PWC_PREFIX, "_country_hs4_feenstra_sigma.rds"))
  s2p <- file.path(dir, paste0(PWC_PREFIX, "_country_hs4_fixed_sigma.rds"))
  if (!file.exists(s1p) || !file.exists(s2p)) stop("window ", dir, " lacks its Stage-1 or Stage-2b table")
  s1 <- data.table::as.data.table(readRDS(s1p)); s2 <- readRDS(s2p)
  g1 <- sort(unique(as.character(s1$good)))
  g2 <- sort(unique(as.character(data.table::as.data.table(s2)$good)))
  list(dir = dir, table = product_summary(s2), goods_stage1 = g1, goods_stage2 = g2,
       stage1_sha = .pwc_sha(s1p), stage2b_rows = nrow(s2))
}

#' Shared-input check for pairs of run directories: are their Stage-1 and
#' Stage-2a tables the same files?
pwc_pairs <- function(pairs) {
  if (!length(pairs)) return(list())
  lapply(pairs, function(pr) {
    f1 <- function(d) file.path(d, paste0(PWC_PREFIX, "_country_hs4_feenstra_sigma.rds"))
    f2 <- function(d) file.path(d, paste0(PWC_PREFIX, "_regional_hs4_fixed_sigma.rds"))
    a <- c(s1 = .pwc_sha(f1(pr[1])), s2a = .pwc_sha(f2(pr[1]))); b <- c(s1 = .pwc_sha(f1(pr[2])), s2a = .pwc_sha(f2(pr[2])))
    same <- function(k) if (is.na(a[[k]]) || is.na(b[[k]])) "absent" else if (identical(a[[k]], b[[k]])) "shared" else "own"
    list(a = pr[1], b = pr[2], stage1 = same("s1"), stage2a = same("s2a"))
  })
}

pwc_reading <- function(rep) {
  r <- c(rep$gamma_median$spearman, rep$opt_tariff_median$spearman)
  if (any(!is.finite(r))) return("not measured")
  if (all(r >= 0.5)) "reproduces" else if (all(r < 0.3)) "does not reproduce" else "partial"
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  for (f in c("R/utils_general.R", "analysis/product_summary.R")) source(f)
  d0 <- get_arg("--w0", NA_character_); d1 <- get_arg("--w1", NA_character_)
  if (is.na(d0) || is.na(d1)) stop("usage: Rscript analysis/product_window_census.R --w0 DIR0 --w1 DIR1 [--pairs \"A1,A2;B1,B2\"] [--json F] [--md F]")
  json <- get_arg("--json", "results/product_window_census.json"); md <- get_arg("--md", "docs/results/product_window_census.md")
  ps <- get_arg("--pairs", "")
  pairs <- if (nzchar(ps)) lapply(strsplit(strsplit(ps, ";", fixed = TRUE)[[1]], ",", fixed = TRUE), trimws) else list()
  w0 <- pwc_window(d0); w1 <- pwc_window(d1)
  rep <- product_reproducibility(w0$table, w1$table)
  reading <- pwc_reading(rep)
  sh <- pwc_pairs(pairs)
  checks <- list(stage1_tables_differ = !identical(w0$stage1_sha, w1$stage1_sha),
                 goods_w0_stage2_in_stage1 = all(w0$goods_stage2 %in% w0$goods_stage1),
                 goods_w1_stage2_in_stage1 = all(w1$goods_stage2 %in% w1$goods_stage1),
                 goods_same_across_windows = identical(w0$goods_stage2, w1$goods_stage2))
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(w0 = d0, w1 = d1, products_w0 = nrow(w0$table), products_w1 = nrow(w1$table), git_rev = rev,
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  jsonlite::write_json(list(meta = meta, reading = reading, reproducibility = rep, checks = checks, shared_inputs = sh),
                       json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f2 <- function(x) formatC(x, digits = 2, format = "f"); pc <- function(x) sprintf("%.1f%%", 100 * (exp(x) - 1))
  rl <- function(k) sprintf("| %s | %d | %s [%s, %s] | %s / %s |", k, rep[[k]]$products, f2(rep[[k]]$spearman), f2(rep[[k]]$lo), f2(rep[[k]]$hi),
                           pc(rep[[k]]$gap_median), pc(rep[[k]]$gap_p90))
  shl <- if (length(sh)) vapply(sh, function(x) sprintf("| `%s` | `%s` | %s | %s |", x$a, x$b, x$stage1, x$stage2a), "") else "| (none given) | | | |"
  writeLines(enc2utf8(c("# Product-level table: independent periods (patch 0130)", "",
    sprintf("Windows `%s` (1995-2009) and `%s` (2010-2024): each period's own Stage 1 (patch 0119), Stage 2a and Stage 2b; rev %s, %s.", d0, d1, rev, meta$timestamp), "",
    sprintf("Checks: the two windows' Stage-1 tables differ: %s; each window's Stage-2b goods are among its Stage-1 goods: %s / %s; same goods in both windows: %s.",
            checks$stage1_tables_differ, checks$goods_w0_stage2_in_stage1, checks$goods_w1_stage2_in_stage1, checks$goods_same_across_windows), "",
    "| product median | products | Spearman [95% interval over products] | level gap p50 / p90 |", "|---|---|---|---|",
    rl("gamma_median"), rl("opt_tariff_median"), "",
    "## Did the earlier halves share their inputs?", "",
    "| run A | run B | Stage-1 table | Stage-2a table |", "|---|---|---|---|", shl, "",
    sprintf("**Reading (fixed in patch 0130): %s.** Reproduces if both correlations are at least 0.50; does not reproduce if both are below 0.30; otherwise partial. The windows differ in time as well as in data, so drift lowers the correlation too.", reading))),
    md, useBytes = TRUE)
  cat(sprintf("product window census: %s (gamma %.2f, opt_tariff %.2f, %d products) -> %s, %s\n", reading,
              rep$gamma_median$spearman, rep$opt_tariff_median$spearman, rep$gamma_median$products, json, md))
}
