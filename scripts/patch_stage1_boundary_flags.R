#!/usr/bin/env Rscript
# Recompute sigma_capped / omega_capped on hliml_boundary rows of a shipped
# Stage-1 artifact, using the SAME boundary_flags() helper the pipeline now
# uses (patch 0033). Corrects corner solutions the edge-label flags missed
# (v0.6.0-rc: 1,934 cells at sigma >= 9.999 unflagged).
#
# Precedent: scripts/patch_stage1_diagnostics.R (G3 arc). Dry-run by default;
# pass --execute to write in place. Re-run scripts/rehash_manifest.R after.
#
# Usage:
#   Rscript scripts/patch_stage1_boundary_flags.R --input <stage1 rds>
#           [--sigma-cap 10] [--omega-cap 10] [--execute]

suppressPackageStartupMessages(library(data.table))
source(file.path("R", "utils_general.R"))  # boundary_flags + finalize_saved_output

args <- commandArgs(trailingOnly = TRUE)
getopt <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) == 1 && i < length(args)) args[i + 1] else default
}
input     <- getopt("--input")
sigma_cap <- as.numeric(getopt("--sigma-cap", "10"))
omega_cap <- as.numeric(getopt("--omega-cap", "10"))
execute   <- "--execute" %in% args
if (is.null(input) || !file.exists(input)) stop("--input <stage1 rds> required and must exist")

d <- setDT(readRDS(input))
need <- c("final_source", "hliml_boundary_edge", "sigma", "omega",
          "sigma_capped", "omega_capped")
miss <- setdiff(need, names(d))
if (length(miss)) stop("missing columns: ", paste(miss, collapse = ", "))

bd <- which(d$final_source == "hliml_boundary")
cat(sprintf("Input: %s\nRows: %s | hliml_boundary rows: %s\n",
            input, format(nrow(d), big.mark = ","), format(length(bd), big.mark = ",")))
if (length(bd) == 0) stop("no hliml_boundary rows; nothing to do")

new_flags <- mapply(function(e, s, o) {
  b <- boundary_flags(e, s, o, sigma_cap, omega_cap)
  c(b$sigma_capped, b$omega_capped)
}, d$hliml_boundary_edge[bd], d$sigma[bd], d$omega[bd])

sc_old <- d$sigma_capped[bd] %in% TRUE; sc_new <- as.logical(new_flags[1, ])
oc_old <- d$omega_capped[bd] %in% TRUE; oc_new <- as.logical(new_flags[2, ])

cat("\n-- sigma_capped transitions on boundary rows (by edge) --\n")
print(data.table(edge = d$hliml_boundary_edge[bd], old = sc_old, new = sc_new)[
  , .N, by = .(edge, old, new)][order(edge, old, new)])
cat("-- omega_capped transitions on boundary rows (by edge) --\n")
print(data.table(edge = d$hliml_boundary_edge[bd], old = oc_old, new = oc_new)[
  , .N, by = .(edge, old, new)][order(edge, old, new)])
cat(sprintf("\nsigma_capped: %d -> %d (+%d) | omega_capped: %d -> %d (%+d)\n",
            sum(sc_old), sum(sc_new), sum(sc_new) - sum(sc_old),
            sum(oc_old), sum(oc_new), sum(oc_new) - sum(oc_old)))

if (!execute) {
  cat("\nDRY RUN — no file written. Re-run with --execute to apply.\n")
} else {
  d$sigma_capped[bd] <- sc_new
  d$omega_capped[bd] <- oc_new
  saveRDS(finalize_saved_output(d), input)
  cat(sprintf("\nWROTE %s\nNow re-run: Rscript scripts/rehash_manifest.R\n", input))
}
