# =============================================================================
# tier4_recompute_with_adjust.R
#
# Recompute Tier 4 headline statistics using the production `adjust` flag
# rather than the sigma=10 heuristic. Inputs the augmented comparison frame
# written by tier4_adjust_join.R.
#
# Run from repo root (data.table assumed attached):
#   source("tests/tier4_recompute_with_adjust.R")
# =============================================================================

COMP_PATH <- "docs/methodology/tier4_comp_with_adjust.csv"

stopifnot("augmented comparison not found" = file.exists(COMP_PATH))

j <- fread(COMP_PATH)

cat("=== Shape ===\n")
cat(sprintf("Rows: %d  (expected 140)\n", nrow(j)))
cat(sprintf("Cols: %d\n", ncol(j)))

# ---- Adjust composition of Tier 4 sample ------------------------------------
cat("\n=== Adjust composition (n=140) ===\n")
print(j[, .(n = .N, pct = round(100 * .N / nrow(j), 1)), by = adjust][order(adjust)])

# ---- Tag the three groups ---------------------------------------------------
j[, censored := adjust %in% c(4L, 5L)]
j[, gmm_outlier := sigma_stage1 >= 50]
j[, ratio := sigma_new / sigma_stage1]

cat("\n=== Subset definitions ===\n")
cat(sprintf("Censored (adjust ∈ {4,5}):                %d\n", sum(j$censored)))
cat(sprintf("GMM outlier (sigma_stage1 >= 50):         %d\n", sum(j$gmm_outlier)))
cat(sprintf("Both:                                     %d\n",
            sum(j$censored & j$gmm_outlier)))

# ---- Headline on three subsets ---------------------------------------------
compute_headline <- function(x, label) {
  if (nrow(x) == 0) {
    cat(sprintf("\n%s: empty subset\n", label))
    return(invisible(NULL))
  }
  cat(sprintf("\n=== %s (n=%d) ===\n", label, nrow(x)))
  cat(sprintf("  Median ratio (HLIML/GMM): %.3f\n", median(x$ratio)))
  cat(sprintf("  Mean ratio (HLIML/GMM):   %.3f\n", mean(x$ratio)))
  cat(sprintf("  Ratio of medians:         %.3f\n",
              median(x$sigma_new) / median(x$sigma_stage1)))
  cat(sprintf("  Spearman rho:             %.3f\n",
              cor(x$sigma_new, x$sigma_stage1, method = "spearman")))
  cat(sprintf("  Pearson r:                %.3f\n",
              cor(x$sigma_new, x$sigma_stage1, method = "pearson")))
  cat(sprintf("  Median sigma (HLIML):     %.3f\n", median(x$sigma_new)))
  cat(sprintf("  Median sigma (GMM):       %.3f\n", median(x$sigma_stage1)))
}

compute_headline(j, "Full sample")

# Original methodology doc's "clean" definition: heuristic boundary + GMM outlier
j[, heuristic_boundary := abs(sigma_new - 10.0) < 1e-6]
clean_original <- j[!heuristic_boundary & !gmm_outlier]
compute_headline(clean_original, "Original clean subset (heuristic boundary excluded)")

# Corrected definition using production adjust flag
clean_corrected <- j[!censored & !gmm_outlier]
compute_headline(clean_corrected, "Corrected clean subset (adjust ∈ {4,5} excluded)")

# Sub-decomposition: HLIML-success interior only (the strictest comparison)
hliml_only <- j[adjust == 0L & !gmm_outlier]
compute_headline(hliml_only,
                 "HLIML-success-only subset (adjust = 0, excludes Step 2 fallbacks)")

# Step 2 fallback only (adjust = 1)
step2_only <- j[adjust == 1L & !gmm_outlier]
compute_headline(step2_only,
                 "Step 2 fallback subset (adjust = 1, excludes HLIML-success and censored)")

# ---- Delta from prior headline numbers --------------------------------------
cat("\n=== Delta vs methodology doc as drafted ===\n")
cat("Methodology doc currently reports clean subset n=116, median ratio 0.675.\n")
cat("Corrected clean subset (adjust-based):\n")
cat(sprintf("  n=%d (was 116, delta %+d)\n",
            nrow(clean_corrected), nrow(clean_corrected) - 116L))
cat(sprintf("  median ratio = %.3f (was 0.675, delta %+.3f)\n",
            median(clean_corrected$ratio),
            median(clean_corrected$ratio) - 0.675))
cat(sprintf("  Spearman rho = %.3f (was 0.213, delta %+.3f)\n",
            cor(clean_corrected$sigma_new, clean_corrected$sigma_stage1,
                method = "spearman"),
            cor(clean_corrected$sigma_new, clean_corrected$sigma_stage1,
                method = "spearman") - 0.213))

# ---- Non-determinism check --------------------------------------------------
# Two cells with |sigma_new - sigma_prod| > 0.01 per tier4_adjust_join. Surface
# them for the methodology doc footnote.
cat("\n=== Estimator non-determinism (|sigma_new - sigma_prod| > 0.01) ===\n")
nondet <- j[abs(sigma_new - sigma_prod) > 0.01]
if (nrow(nondet) > 0) {
  print(nondet[, .(cell_id, sigma_new, sigma_prod,
                   diff = sigma_new - sigma_prod,
                   adjust, hliml_status)])
} else {
  cat("No cells with |diff| > 0.01\n")
}

cat("\n=== Done ===\n")
