# =============================================================================
# analysis/lambda_diagnostic.R
#
# Report-only diagnostic for the Stage-2 shrinkage constant lambda.
#
# Background: lambda (2b default 0.1; 2a hardcoded 0.05) was calibrated in an
# out-of-repo session against two agreement statistics between the Stage-2a
# regional gammas and the Stage-2b country gammas (remembered as pair
# MAD ~0.125 and R^2 ~0.72). The original pairing code was never committed,
# so this script fixes a documented, reproducible definition going forward.
# The reference values for any comparison are therefore the numbers THIS
# script reports on the v0.3.0 outputs (run once during pre-launch prep and
# commit the JSON), not the remembered figures.
#
# Definitions (computed on rows with finite gamma):
#   Pairing A (fine):   key = (importer_region, exporter_region, good).
#     2a side: the regional gamma at that key.
#     2b side: median of country-level gammas over all importer countries in
#              the importer region x exporter countries in the exporter
#              region, for that good.
#   Pairing B (coarse): key = (importer_region, good).
#     2a side: median of regional gammas over exporter regions.
#     2b side: median of country-level gammas over member importer countries
#              and all exporters.
#   Each pairing is reported under two row filters applied to BOTH sides:
#     all      -- every finite gamma;
#     est_only -- tier != 3 (excludes prior-assigned cells, whose gammas are
#                 the prior by construction and inflate agreement).
#   Statistics per (pairing x filter): n_pairs, MAD = median |g2b - g2a|,
#   and R^2 = squared Pearson correlation of the paired values.
#
# Country -> region membership comes from the pipeline's own
# build_region_map() (R/region_map.R; Soderbery 2018 Table 1), so the
# diagnostic cannot drift from the estimation's region definitions.
# Unmapped codes map to "OTHER", matching prepare_data().
#
# Usage (from the repo root):
#   Rscript analysis/lambda_diagnostic.R --label v0.3.0 --out results/lambda_diagnostic_v030.json
#   Rscript analysis/lambda_diagnostic.R --label v0.4.0 --out results/lambda_diagnostic_v040.json
#   Rscript analysis/lambda_diagnostic.R --stage2a PATH --stage2b PATH   # explicit paths
#
# Lambda stays FROZEN for v0.4.0 regardless of what this reports; material
# drift motivates a v0.5.x recalibration as its own change with its own A/B.
# =============================================================================

suppressMessages(library(data.table))

if (!file.exists("R/region_map.R")) {
  stop("Run from the repo root (where R/region_map.R lives).")
}
source("R/region_map.R")

# ---- lightweight CLI --------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
getopt <- function(flag, default) {
  w <- which(args == flag)
  if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
p2a   <- getopt("--stage2a",
                "data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds")
p2b   <- getopt("--stage2b",
                "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
label <- getopt("--label", "unlabeled")
outp  <- getopt("--out", "")

for (p in c(p2a, p2b)) if (!file.exists(p)) stop("Missing input: ", p)

cat(sprintf("lambda_diagnostic | label: %s\n  2a: %s\n  2b: %s\n", label, p2a, p2b))

s2a <- as.data.table(readRDS(p2a))
s2b <- as.data.table(readRDS(p2b))
cat(sprintf("  rows: 2a %s | 2b %s\n",
            format(nrow(s2a), big.mark = ","), format(nrow(s2b), big.mark = ",")))

need <- c("importer", "exporter", "good", "gamma", "tier")
for (nm in need) {
  if (!nm %in% names(s2a)) stop("Stage-2a file lacks column: ", nm)
  if (!nm %in% names(s2b)) stop("Stage-2b file lacks column: ", nm)
}

# ---- map 2b countries to regions (pipeline's own mapping) ------------------
rmap <- build_region_map()
rmap[, cty_code := as.integer(cty_code)]
to_region <- function(x) {
  code <- suppressWarnings(as.integer(as.character(x)))
  reg <- rmap[data.table(cty_code = code), on = "cty_code", region]
  reg[is.na(reg)] <- "OTHER"
  reg
}
s2b[, imp_region := to_region(importer)]
s2b[, exp_region := to_region(exporter)]
setnames(s2a, c("importer", "exporter"), c("imp_region", "exp_region"))
cat(sprintf("  region map: %d coded units; 2b importers -> %d regions, exporters -> %d regions\n",
            nrow(rmap), uniqueN(s2b$imp_region), uniqueN(s2b$exp_region)))

stats_for <- function(a, b) {
  # Pairing A: (imp_region, exp_region, good)
  aA <- a[is.finite(gamma), .(g2a = median(gamma)), by = .(imp_region, exp_region, good)]
  bA <- b[is.finite(gamma), .(g2b = median(gamma)), by = .(imp_region, exp_region, good)]
  A  <- merge(aA, bA, by = c("imp_region", "exp_region", "good"))
  # Pairing B: (imp_region, good)
  aB <- a[is.finite(gamma), .(g2a = median(gamma)), by = .(imp_region, good)]
  bB <- b[is.finite(gamma), .(g2b = median(gamma)), by = .(imp_region, good)]
  B  <- merge(aB, bB, by = c("imp_region", "good"))
  one <- function(d) list(n_pairs = nrow(d),
                          mad = if (nrow(d)) median(abs(d$g2b - d$g2a)) else NA_real_,
                          r2  = if (nrow(d) > 2) suppressWarnings(cor(d$g2a, d$g2b))^2 else NA_real_)
  list(pairing_A_region_exporter_good = one(A),
       pairing_B_region_good          = one(B))
}

res <- list(
  all      = stats_for(s2a, s2b),
  est_only = stats_for(s2a[tier != 3], s2b[tier != 3])
)

cat("\n  filter    pairing                              n_pairs      MAD      R^2\n")
for (f in names(res)) for (p in names(res[[f]])) {
  x <- res[[f]][[p]]
  cat(sprintf("  %-9s %-36s %8s  %7.4f  %7.4f\n",
              f, p, format(x$n_pairs, big.mark = ","), x$mad, x$r2))
}
cat("\n  NOTE: lambda is FROZEN for v0.4.0 (2b 0.1 / 2a 0.05); this is a\n")
cat("  report-only diagnostic. Compare against the committed v0.3.0 baseline\n")
cat("  JSON, not the remembered ~0.125 / ~0.72.\n")

git_rev <- tryCatch(
  system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1],
  error = function(e) NA_character_)
summary_obj <- list(
  meta = list(label = label, stage2a = p2a, stage2b = p2b, git_rev = git_rev,
              n_rows_2a = nrow(s2a), n_rows_2b = nrow(s2b),
              definition = "pairing A: (imp_region, exp_region, good); pairing B: (imp_region, good); MAD = median |g2b - g2a|; R2 = squared Pearson; est_only = tier != 3 on both sides; regions via build_region_map(), unmapped -> OTHER",
              timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  results = res
)
if (nzchar(outp)) {
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    dir.create(dirname(outp), showWarnings = FALSE, recursive = TRUE)
    jsonlite::write_json(summary_obj, outp, auto_unbox = TRUE, digits = 8, pretty = TRUE)
    cat(sprintf("  written: %s\n", outp))
  } else {
    cat("  jsonlite not available; JSON output skipped.\n")
  }
}
invisible(summary_obj)
