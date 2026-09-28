# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\te_grid\runs_level.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-28 14:20:33 EDT.

## Full-panel summaries

| config | rows | n_estimated | share_non_converged | share_gamma_le_0_01 | share_gamma_le_1e_4 | share_gamma_ge_10 | shrink_wt_median | within_cell_sd_median | abs_dev_median | abs_dev_p90 | opt_tariff_median | gamma_median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| level_l0.1_base | 1.52e+05 | 1.13e+05 | 0.00541 | 0.0786 | 0.0738 |    0 | 0.919 | 2.54 | 0.108 | 2.27 | 0.454 | 0.512 |
| level_l0.1_moments | 1.52e+05 | 1.13e+05 | 0.00658 | 0.0661 | 0.062 |    0 | 0.913 | 2.21 | 0.103 | 1.85 | 0.49 | 0.523 |
| level_l0.01_base | 1.52e+05 | 1.13e+05 | 0.0137 | 0.129 | 0.123 |    0 | 0.637 | 4.26 | 0.441 | 12.9 | 0.451 | 0.495 |
| level_l0.01_moments | 1.52e+05 | 1.13e+05 | 0.0107 | 0.116 | 0.109 |    0 | 0.593 | 4.04 | 0.427 | 12.8 | 0.49 | 0.498 |
| level_l0.001_base | 1.52e+05 | 1.13e+05 | 0.0369 | 0.165 | 0.157 | 0.00404 | 0.203 | 4.97 | 0.852 | 13.1 | 0.47 | 0.495 |
| level_l0.001_moments | 1.52e+05 | 1.13e+05 | 0.0322 | 0.153 | 0.145 | 0.00451 | 0.164 | 4.85 | 0.819 |   13 | 0.523 | 0.496 |

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| level_l0.1_base | 6.15e+04 | 3.54e+03 | 0.0576 | 0.178 | 0.189 | 3.42 |  3.2 |
| level_l0.1_moments | 6.16e+04 | 3.54e+03 | 0.06 | 0.192 | 0.176 |  3.2 | 3.01 |
| level_l0.01_moments | 6.15e+04 | 3.53e+03 | 0.0628 | 0.146 | 0.129 | 4.19 | 3.96 |

