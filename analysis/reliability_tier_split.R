#!/usr/bin/env Rscript
# ===========================================================================
# analysis/reliability_tier_split.R  (patch 0159)
#
# The A/B of an Eq. (11) variant has to be read on two populations
# separately, because the known-truth grid showed the hybrid arm D helping
# the exporters whose own export row it removes and hurting the thin
# exporters that row had been helping through the joint fit
# (docs/results/known_truth_eq11.md section 7). This script takes the four
# parity tables -- the shipped configuration's odd/even halves and the
# candidate's -- and writes filtered copies of all four on two key sets
# defined by the SHIPPED halves alone:
#   tier1  keys (importer, exporter, good) that are Tier 1 in both shipped halves
#   other  keys estimated (tier < 3) in both shipped halves and not in tier1
# plus a runs.csv for each, so analysis/stage2_reliability.R reads each
# population with --base ship and its goods bootstrap. The rule for arm D,
# fixed before its numbers (patch 0159): D advances if r_within on tier1
# rises by >= 0.03 over ship with the bootstrap interval above zero AND on
# other falls by no more than 0.03.
#
# Usage (repo root):
#   Rscript analysis/reliability_tier_split.R --ship-odd A.rds --ship-even B.rds --cand-odd C.rds --cand-even D.rds
#       --cand NAME --out DIR
# then, for pop in tier1 other:
#   Rscript analysis/stage2_reliability.R --runs DIR/runs_<pop>.csv --stage2a <2a table> --boot-goods 2000 --boot-seed 20261015
#       --base ship --md docs/results/stage2_reliability_<cand>_<pop>.md
# ===========================================================================
suppressPackageStartupMessages({ library(data.table) })
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
so <- get_arg("--ship-odd"); se <- get_arg("--ship-even"); co <- get_arg("--cand-odd"); ce <- get_arg("--cand-even")
cand <- get_arg("--cand", "cand"); out <- get_arg("--out")
for (f in c(so, se, co, ce)) if (is.na(f) || !file.exists(f)) stop("missing table: ", f)
if (is.na(out)) stop("--out is required")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
rd <- function(f) { t <- readRDS(f); setDT(t); t[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]; t }
S0 <- rd(so); S1 <- rd(se)
key <- function(t) paste(t$importer, t$exporter, t$good, sep = "\r")
est <- function(t) !is.na(t$tier) & t$tier < 3L & !(t$convergence %in% -1L) & is.finite(t$gamma) & t$gamma > 0
k_t1 <- intersect(key(S0)[S0$tier %in% 1L & est(S0)], key(S1)[S1$tier %in% 1L & est(S1)])
k_est <- intersect(key(S0)[est(S0)], key(S1)[est(S1)])
k_other <- setdiff(k_est, k_t1)
cat(sprintf("shipped halves: %s keys estimated in both | tier1 in both %s | other %s\n", format(length(k_est), big.mark = ","), format(length(k_t1), big.mark = ","), format(length(k_other), big.mark = ",")))
write_pop <- function(pop, keys) {
  d <- file.path(out, pop); dir.create(d, showWarnings = FALSE)
  rows <- list()
  for (lab in c("ship_A", "ship_B", "cand_A", "cand_B")) {
    src <- switch(lab, ship_A = so, ship_B = se, cand_A = co, cand_B = ce)
    t <- rd(src); t <- t[key(t) %in% keys]
    f <- file.path(d, paste0(lab, "_fixed_sigma.rds")); saveRDS(t, f)
    rows[[lab]] <- data.table(config = sub("_[AB]$", "", lab), split = sub("^.*_", "", lab), path = normalizePath(f, winslash = "/"))
    cat(sprintf("  %-6s %-7s %s rows\n", pop, lab, format(nrow(t), big.mark = ",")))
  }
  m <- rbindlist(rows); m[config == "cand", config := cand]
  fwrite(m, file.path(out, paste0("runs_", pop, ".csv")))
}
write_pop("tier1", k_t1); write_pop("other", k_other)
cat(sprintf("manifests: %s and %s\n", file.path(out, "runs_tier1.csv"), file.path(out, "runs_other.csv")))
