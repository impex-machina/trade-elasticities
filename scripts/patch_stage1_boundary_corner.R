#!/usr/bin/env Rscript
# Add the `boundary_corner` column (patch 0047) to a Stage-1 artifact produced
# before the wrapper carried it (the v0.7.0-rc table, estimated at 554236d =
# patch 0046). The flag is provenance-defined, so it reconstructs exactly from
# columns the table already has:
#
#   boundary_corner := final_source == "hliml_boundary" &
#                      hliml_boundary_edge == "omega_floor" &
#                      hliml_cf_inversion  == "constraint_violated"
#
# i.e. a constrained optimum on the omega-FLOOR edge reached from a closed-form
# point that lay beyond omega = +Inf -- the opposite end of the omega axis.
# On the rc these cells sit near sigma = 1 with a flat objective
# (docs/methodology/v061_v070rc_comparison.md, section 3). Same definition as
# the estimator's (R/liml_estimator.R, estimate_cell_liml), so a re-run and a
# patched table agree bit-for-bit on the column.
#
# Precedent: scripts/patch_stage1_boundary_flags.R (v0.6.0). Dry-run by
# default; --execute writes in place through finalize_saved_output().
# Re-run scripts/rehash_manifest.R and analysis/master.R after.
#
# Usage:
#   Rscript scripts/patch_stage1_boundary_corner.R --input <stage1 rds> [--execute]
suppressPackageStartupMessages(library(data.table))
source(file.path("R", "utils_general.R"))  # finalize_saved_output
args <- commandArgs(trailingOnly = TRUE)
getopt <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) == 1 && i < length(args)) args[i + 1] else default
}
input   <- getopt("--input")
execute <- "--execute" %in% args
if (is.null(input) || !file.exists(input)) stop("--input <stage1 rds> required and must exist")
d <- setDT(readRDS(input))
need <- c("final_source", "hliml_boundary_edge", "hliml_cf_inversion")
miss <- setdiff(need, names(d))
if (length(miss)) stop("missing columns: ", paste(miss, collapse = ", "),
                       " -- the table predates patch 0046; re-run Stage 1 instead")
new_flag <- d$final_source %in% "hliml_boundary" &
            d$hliml_boundary_edge %in% "omega_floor" &
            d$hliml_cf_inversion %in% "constraint_violated"
had <- "boundary_corner" %in% names(d)
cat(sprintf("rows: %d | boundary_corner column present: %s\n", nrow(d), had))
if (had) cat(sprintf("existing TRUE: %d | recomputed TRUE: %d | disagreements: %d\n",
                     sum(d$boundary_corner %in% TRUE), sum(new_flag),
                     sum((d$boundary_corner %in% TRUE) != new_flag)))
cat("-- recomputed flag by boundary edge (ok rows) --\n")
d[, .corner_tmp := new_flag]
print(d[status == "ok" & final_source == "hliml_boundary",
        .N, by = .(edge = hliml_boundary_edge, cf = hliml_cf_inversion, corner = .corner_tmp)][order(edge, -N)])
d[, .corner_tmp := NULL]
cat(sprintf("\nboundary_corner TRUE: %d (%.2f%% of cells); sigma p10/med/p90 on them: %s\n",
            sum(new_flag), 100 * mean(new_flag),
            if (any(new_flag)) paste(sprintf("%.3f", quantile(d$sigma[new_flag], c(.1, .5, .9))), collapse = " / ") else "-"))
if (!execute) {
  cat("\nDRY RUN -- no file written. Re-run with --execute to apply.\n")
} else {
  d[, boundary_corner := new_flag]
  saveRDS(finalize_saved_output(d), input)
  cat(sprintf("\nWROTE %s\nNow re-run: Rscript analysis/master.R ; Rscript scripts/build_readme.R ; Rscript scripts/rehash_manifest.R\n", input))
}
