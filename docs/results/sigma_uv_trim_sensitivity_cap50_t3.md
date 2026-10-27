# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (obs variant)

Subsample of 8,419 (importer, good) cells (frac 0.030, seed 20260921); trim |d ln p| >= 3.0 applied to the differenced observation inside prepare_cell_moments() (Stage 2's rule). Generated 2026-10-26 21:57:13 EDT.

- rows: 3,339,997 -> 3,339,997 (0.0% dropped by the trim)
- ok cells: shipped 5,513, trimmed 5,561, both 5,131
- sigma median: shipped 2.496 -> trimmed 3.043; quartiles 1.571 / 2.496 / 5.027 -> 1.803 / 3.043 / 6.055
- on cells ok in both: |dsigma|/sigma median 0.323 (p75 0.855, p90 2.515); > 10%: 71.5%; identical: 13.4%; signed median +0.043
- route changed on 39.1% of cells ok in both; sigma_se median 0.677 -> 0.867
- sigma at the cap (ok cells): 8.2% -> 7.5%; sigma_se finite: 95.0% -> 94.3%; omega at the cap: 22.8% -> 15.9%
- route mix (ok cells), shipped: hliml 2486, hliml_boundary 1741, step2_weighted 1286 | trimmed: hliml 2832, hliml_boundary 1451, step2_weighted 1278

- the untrimmed run reproduces the published Stage-1 table (baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds) on 100.0% of 5,513 cells ok in both (within 1e-6 relative; identical: 66.0%), status agreeing on 100.0%
- time: untrimmed 231 s, trimmed 235 s (10 cores, sigma cap 50)

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 1749 |
| hliml_boundary | hliml_boundary |  823 |
| step2_weighted | step2_weighted |  554 |
| hliml_boundary | hliml |  459 |
| step2_weighted | hliml |  414 |
| hliml | step2_weighted |  340 |
| hliml_boundary | step2_weighted |  292 |
| hliml | hliml_boundary |  278 |
| step2_weighted | hliml_boundary |  222 |

