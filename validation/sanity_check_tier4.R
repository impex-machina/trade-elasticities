# =============================================================================
# sanity_check_tier4.R
#
# Spot-check tier4_comp.csv: confirm shape, recompute headline numbers
# independently of the capture script, and verify nothing is silently broken.
#
# Run from repo root (data.table assumed attached):
#   source("tests/sanity_check_tier4.R")
# =============================================================================

COMP_PATH <- "docs/methodology/tier4_comp.csv"

stopifnot("tier4_comp.csv not found" = file.exists(COMP_PATH))

cmp <- fread(COMP_PATH)

cat("=== Shape ===\n")
cat(sprintf("Rows:    %d  (expected 140)\n", nrow(cmp)))
cat(sprintf("Cols:    %d  (expected 4)\n",   ncol(cmp)))
cat("Names:  ", paste(names(cmp), collapse = ", "), "\n", sep = "")

cat("\n=== Head ===\n")
print(head(cmp))

cat("\n=== Summary ===\n")
print(summary(cmp))

cat("\n=== Validity ===\n")
n_na_new   <- sum(!is.finite(cmp$sigma_new))
n_na_old   <- sum(!is.finite(cmp$sigma_stage1))
n_zero_old <- sum(cmp$sigma_stage1 <= 0, na.rm = TRUE)
cat(sprintf("sigma_new non-finite:      %d\n", n_na_new))
cat(sprintf("sigma_stage1 non-finite:   %d\n", n_na_old))
cat(sprintf("sigma_stage1 <= 0:         %d\n", n_zero_old))

# Censoring check — HLIML capped at 10.0 per smoke + full run marginals
n_at_cap <- sum(abs(cmp$sigma_new - 10.0) < 1e-6, na.rm = TRUE)
cat(sprintf("sigma_new at cap (10.0):   %d  (%.1f%%)\n",
            n_at_cap, 100 * n_at_cap / nrow(cmp)))

cat("\n=== Recompute headline (independent of capture script) ===\n")
valid <- is.finite(cmp$sigma_new) & is.finite(cmp$sigma_stage1) & cmp$sigma_stage1 > 0
cmp_v <- cmp[valid]

median_ratio   <- median(cmp_v$sigma_new / cmp_v$sigma_stage1)
mean_ratio     <- mean(  cmp_v$sigma_new / cmp_v$sigma_stage1)
ratio_of_meds  <- median(cmp_v$sigma_new) / median(cmp_v$sigma_stage1)
spearman       <- cor(cmp_v$sigma_new, cmp_v$sigma_stage1, method = "spearman")
pearson        <- cor(cmp_v$sigma_new, cmp_v$sigma_stage1, method = "pearson")

cat(sprintf("Median of ratios:           %.3f  (capture reported 0.724)\n", median_ratio))
cat(sprintf("Mean of ratios:             %.3f  (capture reported 1.068)\n", mean_ratio))
cat(sprintf("Ratio of medians:           %.3f  (harness reported 0.755)\n", ratio_of_meds))
cat(sprintf("Spearman rho:               %.3f  (capture reported 0.190)\n", spearman))
cat(sprintf("Pearson r:                  %.3f  (capture reported -0.062)\n", pearson))

cat("\n=== Cells where HLIML >> GMM (mean-ratio inflators) ===\n")
cmp_v[, ratio := sigma_new / sigma_stage1]
print(cmp_v[order(-ratio)][1:10])

cat("\n=== Cells where HLIML << GMM (bias-correction exemplars) ===\n")
print(cmp_v[order(ratio)][1:10])

# -----------------------------------------------------------------------------
# Follow-up diagnostics added 2026-05-20 after first-pass review surfaced:
#   (a) GMM right-tail outliers (max sigma_stage1 = 11,023.6 — likely numerical
#       failures escaping legacy pipeline QA)
#   (b) HLIML boundary-hitting on 16.4% of "successful" cells (sigma = 10.0
#       with omega = 0.0001 = corner of estimator parameter box)
# Both inflate apparent estimator disagreement; the honest headline excludes
# them.
# -----------------------------------------------------------------------------

cat("\n=== GMM right-tail outliers ===\n")
n_gmm_big <- sum(cmp_v$sigma_stage1 > 50)
cat(sprintf("Cells with sigma_stage1 > 50:   %d  (%.1f%%)\n",
            n_gmm_big, 100 * n_gmm_big / nrow(cmp_v)))
cat(sprintf("Cells with sigma_stage1 > 100:  %d\n", sum(cmp_v$sigma_stage1 > 100)))
cat(sprintf("Cells with sigma_stage1 > 1000: %d\n", sum(cmp_v$sigma_stage1 > 1000)))
cat(sprintf("Max sigma_stage1:               %.1f\n", max(cmp_v$sigma_stage1)))
cat(sprintf("Mean sigma_stage1:              %.2f  (vs median %.2f — %.1fx)\n",
            mean(cmp_v$sigma_stage1),
            median(cmp_v$sigma_stage1),
            mean(cmp_v$sigma_stage1) / median(cmp_v$sigma_stage1)))

cat("\n=== HLIML boundary-hitting ===\n")
cmp_v[, boundary := abs(sigma_new - 10.0) < 1e-6]
n_boundary <- sum(cmp_v$boundary)
cat(sprintf("Cells at HLIML boundary (sigma=10):  %d  (%.1f%%)\n",
            n_boundary, 100 * n_boundary / nrow(cmp_v)))
cat(sprintf("Of those, with omega at floor (1e-4): %d\n",
            sum(cmp_v$boundary & abs(cmp_v$omega_new - 1e-4) < 1e-6)))

cat("\n=== Stratified comparison (boundary vs interior) ===\n")
print(cmp_v[, .(n = .N,
                median_ratio     = median(ratio),
                median_sigma_new = median(sigma_new),
                median_sigma_old = median(sigma_stage1)),
            by = boundary])

cat("\n=== Headline on clean interior subset ===\n")
# Drop both failure modes: HLIML boundary AND GMM extreme outliers.
clean <- cmp_v[!boundary & sigma_stage1 < 50]
cat(sprintf("Clean n (excl. boundary & GMM>50): %d of %d  (%.1f%% retained)\n",
            nrow(clean), nrow(cmp_v), 100 * nrow(clean) / nrow(cmp_v)))
cat(sprintf("Clean median ratio:                %.3f\n",
            median(clean$ratio)))
cat(sprintf("Clean mean ratio:                  %.3f\n",
            mean(clean$ratio)))
cat(sprintf("Clean Spearman rho:                %.3f\n",
            cor(clean$sigma_new, clean$sigma_stage1, method = "spearman")))
cat(sprintf("Clean Pearson r:                   %.3f\n",
            cor(clean$sigma_new, clean$sigma_stage1, method = "pearson")))
cat(sprintf("Clean median sigma_new:            %.3f\n", median(clean$sigma_new)))
cat(sprintf("Clean median sigma_stage1:         %.3f\n", median(clean$sigma_stage1)))

cat("\n=== Done ===\n")