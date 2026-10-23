# The precision-scaled ridge at the empirical-Bayes tau^2, on real data (patch 0133)

2% product subsample, alternate four-year blocks; tau2_eb = 0.890; candidate and shipped halves on the same blocks; rev ce2e2bf, 2026-10-23 02:30:54 EDT.

- Importer differences within a product, split-half correlation of the cells' mean deviation from the prior: 0.292 at tau2_eb (3,914 cells) against 0.266 shipped (3,922 cells).
- Product medians of gamma against the shipped halves: median |difference in logs| 0.040.
- Conditions: known-truth validation TRUE; tau2 in [0.02, 2] TRUE; reproducibility at least shipped TRUE; level shift <= 0.10 TRUE.

**Reading (fixed in patch 0133): adopt-candidate.**
