#!/usr/bin/env Rscript
# ============================================================================
# scripts/recompute_opt_tariff.R  (patch 0081, 2026-10-03)
#
# Applies recompute_opt_tariff() -- opt_tariff / opt_tariff_all over the rows
# a table publishes, the definition estimate_all_fixed_sigma() uses since
# patch 0081 -- to an EXISTING Stage-2a or Stage-2b table, and prints the
# census (cells changed, cells with opt_tariff above their own largest gamma
# before and after, cell-level medians). Nothing else in the table changes.
# Idempotent: a table produced by the patched pipeline comes back unchanged.
#
# This is how the v0.8.3 tables were corrected from the rc run without
# re-estimation, and the reproducibility record of that step.
#
# Usage (repo root):
#   Rscript scripts/recompute_opt_tariff.R --in PATH [--out PATH]
# --out defaults to --in (overwrite). The output is passed through
# finalize_saved_output() so its layout matches a pipeline-written table.
# ============================================================================

suppressPackageStartupMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
in_path  <- get_arg("--in", NA_character_)
out_path <- get_arg("--out", in_path)
if (is.na(in_path)) stop("usage: Rscript scripts/recompute_opt_tariff.R --in PATH [--out PATH]")
if (!file.exists(in_path)) stop("table not found: ", in_path)

.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                      error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()

dt <- readRDS(in_path); setDT(dt)
n_rows <- nrow(dt)
ot <- recompute_opt_tariff(dt)
stopifnot(nrow(dt) == n_rows)
out <- finalize_saved_output(dt)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, out_path)

cat(sprintf("recompute_opt_tariff: %s -> %s\n", in_path, out_path))
cat(sprintf("  %s rows, %s cells | opt_tariff changed on %s cells (%.1f%%) | cells with opt_tariff above their max published gamma: %s -> %s | cell-level opt_tariff median %.4f -> %.4f\n",
            format(n_rows, big.mark = ","), format(ot$n_cells, big.mark = ","),
            format(ot$n_changed, big.mark = ","), 100 * ot$n_changed / ot$n_cells,
            format(ot$n_above_gmax_before, big.mark = ","), format(ot$n_above_gmax_after, big.mark = ","),
            ot$median_before, ot$median_after))
