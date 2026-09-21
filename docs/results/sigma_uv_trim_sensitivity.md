# Stage-1 sigma sensitivity to the Stage-2 unit-value trim

Subsample of 5,613 (importer, good) cells (frac 0.020, seed 20260921); trim |d ln p| >= 2.0 applied upstream of Stage 1. Generated 2026-09-21 17:33:13 EDT.

- rows: 2,238,760 -> 2,093,569 (6.5% dropped by the trim)
- ok cells: shipped 3,652, trimmed 3,563, both 3,207
- sigma median: shipped 2.466 -> trimmed 3.757; quartiles 1.556 / 2.466 / 4.802 -> 2.114 / 3.757 / 7.829
- on cells ok in both: |dsigma|/sigma median 0.539 (p75 1.267, p90 3.733); > 10%: 82.9%; identical: 6.7%; signed median +0.266
- route changed on 52.1% of cells ok in both; sigma_se median 0.760 -> 1.352

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 845 |
| hliml_boundary | hliml_boundary | 367 |
| hliml_boundary | hliml | 346 |
| hliml | step2_weighted | 343 |
| step2_weighted | step2_weighted | 324 |
| step2_weighted | hliml | 295 |
| hliml_boundary | step2_weighted | 265 |
| hliml | hliml_boundary | 256 |
| step2_weighted | hliml_boundary | 166 |

