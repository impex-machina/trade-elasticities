# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (obs variant)

Subsample of 8,419 (importer, good) cells (frac 0.030, seed 20260921); trim |d ln p| >= 2.0 applied to the differenced observation inside prepare_cell_moments() (Stage 2's rule). Generated 2026-10-26 22:00:29 EDT.

- rows: 3,339,997 -> 3,339,997 (0.0% dropped by the trim)
- ok cells: shipped 5,513, trimmed 5,503, both 4,985
- sigma median: shipped 2.496 -> trimmed 3.781; quartiles 1.571 / 2.496 / 5.027 -> 2.085 / 3.781 / 8.062
- on cells ok in both: |dsigma|/sigma median 0.619 (p75 1.512, p90 5.719); > 10%: 85.2%; identical: 5.0%; signed median +0.282
- route changed on 50.4% of cells ok in both; sigma_se median 0.677 -> 1.212
- sigma at the cap (ok cells): 8.2% -> 8.9%; sigma_se finite: 95.0% -> 92.7%; omega at the cap: 22.8% -> 13.2%
- route mix (ok cells), shipped: hliml 2486, hliml_boundary 1741, step2_weighted 1286 | trimmed: hliml 2828, hliml_boundary 1382, step2_weighted 1293

- the untrimmed run reproduces the published Stage-1 table (baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds) on 100.0% of 5,513 cells ok in both (within 1e-6 relative; identical: 66.0%), status agreeing on 100.0%
- time: untrimmed 231 s, trimmed 196 s (10 cores, sigma cap 50)

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 1464 |
| hliml_boundary | hliml |  600 |
| hliml_boundary | hliml_boundary |  598 |
| step2_weighted | hliml |  504 |
| hliml | step2_weighted |  448 |
| step2_weighted | step2_weighted |  411 |
| hliml | hliml_boundary |  382 |
| hliml_boundary | step2_weighted |  320 |
| step2_weighted | hliml_boundary |  258 |

