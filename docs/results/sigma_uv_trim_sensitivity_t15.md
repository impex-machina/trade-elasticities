# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (obs variant)

Subsample of 5,613 (importer, good) cells (frac 0.020, seed 20260921); trim |d ln p| >= 1.5 applied to the differenced observation inside prepare_cell_moments() (Stage 2's rule). Generated 2026-09-22 14:17:30 EDT.

- rows: 2,238,760 -> 2,238,760 (0.0% dropped by the trim)
- ok cells: shipped 3,652, trimmed 3,551, both 3,187
- sigma median: shipped 2.466 -> trimmed 4.536; quartiles 1.556 / 2.466 / 4.802 -> 2.309 / 4.536 / 9.234
- on cells ok in both: |dsigma|/sigma median 0.679 (p75 1.907, p90 4.255); > 10%: 85.5%; identical: 4.9%; signed median +0.466
- route changed on 54.3% of cells ok in both; sigma_se median 0.760 -> 1.502

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 828 |
| hliml_boundary | hliml | 375 |
| hliml | step2_weighted | 359 |
| hliml_boundary | hliml_boundary | 331 |
| step2_weighted | hliml | 325 |
| step2_weighted | step2_weighted | 296 |
| hliml_boundary | step2_weighted | 264 |
| hliml | hliml_boundary | 257 |
| step2_weighted | hliml_boundary | 152 |

