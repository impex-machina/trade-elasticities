# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (obs variant)

Subsample of 5,613 (importer, good) cells (frac 0.020, seed 20260921); trim |d ln p| >= 3.0 applied to the differenced observation inside prepare_cell_moments() (Stage 2's rule). Generated 2026-09-22 14:05:21 EDT.

- rows: 2,238,760 -> 2,238,760 (0.0% dropped by the trim)
- ok cells: shipped 3,652, trimmed 3,675, both 3,387
- sigma median: shipped 2.466 -> trimmed 3.003; quartiles 1.556 / 2.466 / 4.802 -> 1.778 / 3.003 / 5.673
- on cells ok in both: |dsigma|/sigma median 0.292 (p75 0.748, p90 1.940); > 10%: 69.5%; identical: 14.9%; signed median +0.029
- route changed on 39.5% of cells ok in both; sigma_se median 0.760 -> 0.975

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 1117 |
| hliml_boundary | hliml_boundary |  531 |
| step2_weighted | step2_weighted |  401 |
| hliml_boundary | hliml |  285 |
| step2_weighted | hliml |  260 |
| hliml | step2_weighted |  246 |
| hliml_boundary | step2_weighted |  222 |
| hliml | hliml_boundary |  177 |
| step2_weighted | hliml_boundary |  148 |

