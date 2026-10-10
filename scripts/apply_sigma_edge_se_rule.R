#!/usr/bin/env Rscript
# ============================================================================
# scripts/apply_sigma_edge_se_rule.R  (patch 0090, 2026-10-10)
#
# Applies apply_sigma_edge_se_rule() (R/iteration_helpers.R) to an EXISTING
# Stage-2b table: for every cell whose Stage-1 sigma was a box edge (status
# "ok", sigma_capped TRUE -- the cells --stage2-sigma-edge fallback drops from
# the clean set), the sigma-propagation columns are reset to what the patched
# pipeline publishes on a fallback cell: sigma_se, dgamma_dsigma and
# gamma_se_total NA, sigma_robust FALSE where a flag is carried. gamma,
# gamma_se and every other column are untouched (the optimizer never read
# the SE), so the result is what a re-run under patch 0090 would publish.
# Idempotent: a table produced by the patched pipeline comes back unchanged.
#
# This is how the v0.9.1 table is corrected from the shipped v0.9.0 table
# without re-estimation, and the reproducibility record of that step.
#
# Usage (repo root):
#   Rscript scripts/apply_sigma_edge_se_rule.R --stage1 PATH --in PATH [--out PATH] [--csv]
# --out defaults to --in (overwrite). --csv also rewrites the CSV mirror
# beside --out (same basename, .csv). The output is passed through
# finalize_saved_output() so its layout matches a pipeline-written table.
# ============================================================================

suppressPackageStartupMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
s1_path  <- get_arg("--stage1", NA_character_)
in_path  <- get_arg("--in", NA_character_)
out_path <- get_arg("--out", in_path)
write_csv <- "--csv" %in% args
if (is.na(in_path) || is.na(s1_path))
  stop("usage: Rscript scripts/apply_sigma_edge_se_rule.R --stage1 PATH --in PATH [--out PATH] [--csv]")
if (!file.exists(in_path)) stop("table not found: ", in_path)
if (!file.exists(s1_path)) stop("Stage-1 table not found: ", s1_path)

.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                      error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()

s1 <- readRDS(s1_path); setDT(s1)
dt <- readRDS(in_path); setDT(dt)
n_rows <- nrow(dt)
cen <- apply_sigma_edge_se_rule(dt, s1)
stopifnot(nrow(dt) == n_rows)
out <- finalize_saved_output(dt)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, out_path)
if (write_csv) fwrite(out, sub("\\.rds$", ".csv", out_path))

cat(sprintf("apply_sigma_edge_se_rule: %s -> %s (Stage 1: %s)\n", in_path, out_path, s1_path))
cat(sprintf("  %s rows | Stage-1 edge cells %s, of which %s in the table (%s rows) at sigma = %s\n",
            format(n_rows, big.mark = ","), format(cen$n_edge_cells_stage1, big.mark = ","),
            format(cen$n_edge_cells_in_table, big.mark = ","), format(cen$n_edge_rows, big.mark = ","),
            format(cen$sigma_edge_value, digits = 6)))
cat(sprintf("  reset on edge rows: sigma_se finite %s -> 0 | dgamma_dsigma finite %s -> 0 | gamma_se_total finite %s -> 0 | sigma_robust TRUE %s -> 0 (%.1f%% of edge rows had passed the screen)\n",
            format(cen$before$sigma_se, big.mark = ","), format(cen$before$dgamma_dsigma, big.mark = ","),
            format(cen$before$gamma_se_total, big.mark = ","), format(cen$before$sigma_robust_true, big.mark = ","),
            100 * cen$share_robust_true_before))
cat(sprintf("  sigma_robust over the table: TRUE %s (%.1f%% of rows) after the rule\n",
            format(sum(out$sigma_robust %in% TRUE), big.mark = ","), 100 * mean(out$sigma_robust %in% TRUE)))
