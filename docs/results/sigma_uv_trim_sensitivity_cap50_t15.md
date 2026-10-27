# Stage-1 sigma sensitivity to the Stage-2 unit-value trim (obs variant)

Subsample of 8,419 (importer, good) cells (frac 0.030, seed 20260921); trim |d ln p| >= 1.5 applied to the differenced observation inside prepare_cell_moments() (Stage 2's rule). Generated 2026-10-26 22:04:32 EDT.

- rows: 3,339,997 -> 3,339,997 (0.0% dropped by the trim)
- ok cells: shipped 5,513, trimmed 5,461, both 4,904
- sigma median: shipped 2.496 -> trimmed 4.720; quartiles 1.571 / 2.496 / 5.027 -> 2.372 / 4.720 / 11.154
- on cells ok in both: |dsigma|/sigma median 0.826 (p75 2.611, p90 10.046); > 10%: 88.4%; identical: 2.8%; signed median +0.542
- route changed on 53.9% of cells ok in both; sigma_se median 0.677 -> 1.617
- sigma at the cap (ok cells): 8.2% -> 10.6%; sigma_se finite: 95.0% -> 91.1%; omega at the cap: 22.8% -> 11.3%
- route mix (ok cells), shipped: hliml 2486, hliml_boundary 1741, step2_weighted 1286 | trimmed: hliml 2906, hliml_boundary 1367, step2_weighted 1188

- the untrimmed run reproduces the published Stage-1 table (baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds) on 100.0% of 5,513 cells ok in both (within 1e-6 relative; identical: 66.0%), status agreeing on 100.0%
- time: untrimmed 231 s, trimmed 243 s (10 cores, sigma cap 50)

Route transitions (rows shipped, cols trimmed):

| shipped | trimmed | N |
|---|---|---|
| hliml | hliml | 1407 |
| hliml_boundary | hliml |  668 |
| step2_weighted | hliml |  559 |
| hliml_boundary | hliml_boundary |  514 |
| hliml | step2_weighted |  430 |
| hliml | hliml_boundary |  420 |
| step2_weighted | step2_weighted |  342 |
| hliml_boundary | step2_weighted |  315 |
| step2_weighted | hliml_boundary |  249 |

