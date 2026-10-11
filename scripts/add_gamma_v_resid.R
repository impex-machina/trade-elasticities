#!/usr/bin/env Rscript
# ============================================================================
# scripts/add_gamma_v_resid.R  (patch 0093, 2026-10-11)
#
# Attaches gamma_v_resid = |ln gamma - ln gamma_prev| to an EXISTING final
# Stage-2b table from its previous gamma_V pass table (the _fixed_sigma_pass<K-1>.rds
# the runner saves beside the final table), with attach_gamma_v_resid()
# (R/iteration_helpers.R) -- the same function the pipeline applies after its
# last native pass, so the result is what a re-run under patch 0093 publishes.
# NA where either pass has no published directly estimated converged gamma
# for the row (Tier 3, non-converged, flagged trimmed, absent). Idempotent.
#
# Usage (repo root):
#   Rscript scripts/add_gamma_v_resid.R --prev PASS_TABLE.rds --in TABLE.rds [--out PATH] [--csv]
# ============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
prev_path <- get_arg("--prev", NA_character_); in_path <- get_arg("--in", NA_character_)
out_path <- get_arg("--out", in_path); write_csv <- "--csv" %in% args
if (is.na(in_path) || is.na(prev_path)) stop("usage: Rscript scripts/add_gamma_v_resid.R --prev PASS_TABLE.rds --in TABLE.rds [--out PATH] [--csv]")
for (p in c(in_path, prev_path)) if (!file.exists(p)) stop("not found: ", p)
.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()
dt <- readRDS(in_path); setDT(dt); prev <- readRDS(prev_path); setDT(prev)
n_rows <- nrow(dt)
cen <- attach_gamma_v_resid(dt, prev)
stopifnot(nrow(dt) == n_rows)
out <- finalize_saved_output(dt)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, out_path); if (write_csv) fwrite(out, sub("\\.rds$", ".csv", out_path))
cat(sprintf("add_gamma_v_resid: %s (+ %s) -> %s\n", in_path, prev_path, out_path))
cat(sprintf("  gamma_v_resid filled on %s of %s rows | p50 %.2e p90 %.3f p99 %.3f max %.3f | %.1f%% below 1e-2\n",
            format(cen$n_filled, big.mark = ","), format(cen$n_rows, big.mark = ","), cen$p50, cen$p90, cen$p99, cen$max, 100 * cen$share_lt_1e2))
