# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\te_grid\runs_log.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-28 13:18:22 EDT.

## Full-panel summaries

| config | rows | n_estimated | share_non_converged | share_gamma_le_0_01 | share_gamma_le_1e_4 | share_gamma_ge_10 | shrink_wt_median | within_cell_sd_median | abs_dev_median | abs_dev_p90 | opt_tariff_median | gamma_median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| log_l0.1_base | 1.52e+05 | 1.13e+05 | 0.0783 | 0.000506 |    0 |    0 | 0.941 | 0.595 | 0.0845 |  1.1 | 0.571 | 0.557 |
| log_l0.1_moments | 1.52e+05 | 1.13e+05 | 0.0758 | 0.000426 |    0 |    0 | 0.936 | 0.555 | 0.0812 | 1.02 | 0.597 | 0.562 |
| log_l0.01_base | 1.52e+05 | 1.13e+05 | 0.23 | 0.0105 |    0 | 0.00952 | 0.787 | 1.02 | 0.215 | 1.77 | 0.573 | 0.575 |
| log_l0.01_moments | 1.52e+05 | 1.13e+05 | 0.221 | 0.00885 |    0 | 0.00934 | 0.766 | 0.976 | 0.209 | 1.67 | 0.599 | 0.576 |
| log_l0.001_base | 1.52e+05 | 1.13e+05 | 0.478 | 0.0294 |    0 | 0.0162 | 0.408 | 1.38 | 0.192 | 2.23 | 0.508 | 0.577 |
| log_l0.001_moments | 1.52e+05 | 1.13e+05 | 0.467 | 0.0264 |    0 | 0.0159 | 0.332 | 1.35 | 0.195 | 2.14 | 0.534 | 0.578 |

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| log_l0.1_moments | 6.13e+04 | 3.54e+03 | 0.0906 | 0.11 | 0.297 | 0.679 | 0.603 |

