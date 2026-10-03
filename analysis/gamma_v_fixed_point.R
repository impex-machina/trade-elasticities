#!/usr/bin/env Rscript
# ============================================================================
# analysis/gamma_v_fixed_point.R  (patch 0085, 2026-10-03)
#
# The exporter-specific gamma_V of Eq. (11) comes from a PREVIOUS Stage-2b
# pass (--stage2-gamma-v-source table), so the system is solved by
# iteration: pass 1 (regional median), pass 2 (gamma_jV from pass 1), pass 3
# (gamma_jV from pass 2), ... This script measures how much the table moves
# between consecutive passes on the rows the iteration touches -- Tier-1
# rows, directly estimated and converged in both passes -- and, with three
# passes, the contraction ratio (median |d ln gamma| of 2->3 over 1->2). A
# ratio well below 1 says the iteration contracts and one extra pass is
# enough for the published table; a ratio near 1 says it does not settle and
# the regional proxy should stay.
#
# Usage (repo root):
#   Rscript analysis/gamma_v_fixed_point.R --pass1 A.rds --pass2 B.rds [--pass3 C.rds]
#                                          [--out results/gamma_v_fixed_point.json]
#                                          [--md docs/results/gamma_v_fixed_point.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
p1 <- get_arg("--pass1", NA_character_); p2 <- get_arg("--pass2", NA_character_); p3 <- get_arg("--pass3", NA_character_)
out_json <- get_arg("--out", "results/gamma_v_fixed_point.json")
out_md   <- get_arg("--md",  "docs/results/gamma_v_fixed_point.md")
if (is.na(p1) || is.na(p2)) stop("usage: --pass1 A.rds --pass2 B.rds [--pass3 C.rds]")
for (p in c(p1, p2, p3)) if (!is.na(p) && !file.exists(p)) stop("not found: ", p)

.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                      error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()

key <- c("importer", "exporter", "good")
load_pass <- function(p) {
  x <- readRDS(p); setDT(x)
  for (k in key) x[[k]] <- as.character(x[[k]])
  x
}
step <- function(a, b, label) {
  m <- merge(a[, c(key, "gamma", "tier", "convergence", "opt_tariff"), with = FALSE],
             b[, c(key, "gamma", "tier", "convergence", "opt_tariff"), with = FALSE], by = key, suffixes = c(".a", ".b"))
  t1 <- m[tier.a == 1L & tier.b == 1L & convergence.a == 0L & convergence.b == 0L & gamma.a > 0 & gamma.b > 0]
  d <- abs(log(t1$gamma.b) - log(t1$gamma.a))
  q <- function(p) if (length(d)) unname(quantile(d, p)) else NA_real_
  list(label = label, n_shared = nrow(m), n_tier1 = nrow(t1),
       abs_dlng_p50 = q(.5), abs_dlng_p90 = q(.9), abs_dlng_p99 = q(.99), abs_dlng_max = if (length(d)) max(d) else NA_real_,
       share_below_1e3 = if (length(d)) mean(d < 1e-3) else NA_real_, share_below_1e2 = if (length(d)) mean(d < 1e-2) else NA_real_,
       gamma_median_a = median(a$gamma, na.rm = TRUE), gamma_median_b = median(b$gamma, na.rm = TRUE),
       opt_tariff_median_a = median(a$opt_tariff, na.rm = TRUE), opt_tariff_median_b = median(b$opt_tariff, na.rm = TRUE))
}
a <- load_pass(p1); b <- load_pass(p2)
steps <- list(step(a, b, "1->2"))
if (!is.na(p3)) { c3 <- load_pass(p3); steps[[2]] <- step(b, c3, "2->3") }
contraction <- if (length(steps) == 2L && is.finite(steps[[1]]$abs_dlng_p50) && steps[[1]]$abs_dlng_p50 > 0)
  steps[[2]]$abs_dlng_p50 / steps[[1]]$abs_dlng_p50 else NA_real_

out <- list(meta = list(pass1 = p1, pass2 = p2, pass3 = if (is.na(p3)) NULL else p3,
                        git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
                        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
            steps = steps, contraction_ratio_p50 = contraction)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

f <- function(x) if (is.null(x) || is.na(x)) "NA" else formatC(x, format = "g", digits = 4)
pc <- function(x) if (is.null(x) || is.na(x)) "NA" else sprintf("%.1f%%", 100 * x)
md <- c("# Exporter-specific gamma_V: fixed-point census (patch 0085)", "",
        sprintf("Passes: 1 `%s`, 2 `%s`%s (rev %s, %s).", p1, p2, if (is.na(p3)) "" else sprintf(", 3 `%s`", p3), out$meta$git_rev, out$meta$timestamp), "",
        "| step | shared rows | Tier-1 rows compared | abs d ln gamma p50 | p90 | p99 | max | share < 1e-3 | share < 1e-2 | gamma median a -> b | opt_tariff median a -> b |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
        sapply(steps, function(s) sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s -> %s | %s -> %s |",
          s$label, format(s$n_shared, big.mark = ","), format(s$n_tier1, big.mark = ","), f(s$abs_dlng_p50), f(s$abs_dlng_p90), f(s$abs_dlng_p99), f(s$abs_dlng_max),
          pc(s$share_below_1e3), pc(s$share_below_1e2), f(s$gamma_median_a), f(s$gamma_median_b), f(s$opt_tariff_median_a), f(s$opt_tariff_median_b))), "",
        sprintf("Contraction ratio (median |d ln gamma| of 2->3 over 1->2): %s.", f(contraction)), "",
        "Reading: a ratio well below 1 means the iteration contracts and one exporter-specific pass is enough for the published table; near 1 means it does not settle and the regional proxy should stay. Rows outside Tier 1 move only through the joint fit of their cell.")
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(sprintf("Wrote %s and %s\n", out_json, out_md))
for (s in steps) cat(sprintf("%s: Tier-1 rows %s | abs d ln gamma p50 %s p90 %s p99 %s | gamma median %s -> %s\n",
                             s$label, format(s$n_tier1, big.mark = ","), f(s$abs_dlng_p50), f(s$abs_dlng_p90), f(s$abs_dlng_p99), f(s$gamma_median_a), f(s$gamma_median_b)))
if (!is.na(contraction)) cat(sprintf("contraction ratio (p50): %s\n", f(contraction)))
