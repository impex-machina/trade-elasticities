# Empirical-Bayes tau^2 for the precision-scaled ridge (patch 0133)

Half a `C:\Users\maxxj\te_eb\t1_a\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, half b `C:\Users\maxxj\te_eb\t1_b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (Stage 2b on alternate four-year blocks at tau^2 = 1, same Stage 1 and Stage-2a priors); rev ce2e2bf, 2026-10-22 23:42:06 EDT.

- **tau2_eb = 0.890** (2.5% trim; 1.312 untrimmed) on 65,445 rows directly estimated in both halves, 62,310 after the trim (mean data share 0.362 / 0.351; Spearman of the deviations between halves 0.149).
- Exporter-product effects, for information only: split-half correlation 0.254 (Spearman 0.297) over 2,118 exporter-products seen with at least 3 importers in both halves. At known truth such effects reproduce across halves without tracking any true exporter difference (reading R6 of `docs/results/known_truth_eb.md`), so this number is not evidence that exporter differences within a cell are recoverable.
