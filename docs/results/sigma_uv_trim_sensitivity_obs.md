# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (obs variant)

Subsample of 5,613 (importer, good) cells (frac 0.020, seed 20260921); trim |d ln p| >= 2.0 applied to the differenced observation inside prepare_cell_moments() (Stage 2's rule). Generated 2026-09-21 17:55:15 EDT.

- rows: 2,238,760 -> 2,238,760 (0.0% dropped by the trim)
- ok cells: shipped 3,652, trimmed 3,592, both 3,252
- sigma median: shipped 2.466 -> trimmed 3.636; quartiles 1.556 / 2.466 / 4.802 -> 2.060 / 3.636 / 7.399
- on cells ok in both: |dsigma|/sigma median 0.519 (p75 1.207, p90 3.358); > 10%: 82.6%; identical: 7.0%; signed median +0.238
- route changed on 51.0% of cells ok in both; sigma_se median 0.760 -> 1.334

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 895 |
| hliml_boundary | hliml_boundary | 380 |
| hliml_boundary | hliml | 341 |
| hliml | step2_weighted | 328 |
| step2_weighted | step2_weighted | 320 |
| step2_weighted | hliml | 308 |
| hliml_boundary | step2_weighted | 266 |
| hliml | hliml_boundary | 247 |
| step2_weighted | hliml_boundary | 167 |

