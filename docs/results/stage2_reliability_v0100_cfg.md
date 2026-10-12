# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\v0100_cfg_runs.csv`; priors from `stage2a_v0100.rds`. Generated 2026-10-12 17:41:43 EDT.

## Full-panel summaries

| config | rows | n_estimated | share_non_converged | share_gamma_le_0_01 | share_gamma_le_1e_4 | share_gamma_ge_10 | shrink_wt_median | within_cell_sd_median | abs_dev_median | abs_dev_p90 | opt_tariff_median | gamma_median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| base | 1.52e+05 | 1.13e+05 | 0.0233 | 0.00392 |    0 | 0.00443 | 0.915 | 0.655 | 0.295 | 1.39 | 0.585 | 0.539 |
| pole1_old2a | 1.52e+05 | 1.13e+05 | 0.00624 |    0 |    0 |    0 | 0.934 | 0.546 | 0.277 | 1.02 | 0.606 | 0.556 |
| v0100_cfg | 1.52e+05 | 1.13e+05 | 0.00629 |    0 |    0 | 5.33e-05 | 0.931 | 0.558 | 0.0811 |    1 | 0.672 | 0.647 |

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 8.53e+04 | 4.03e+03 | 0.333 | 0.343 | 0.473 | 0.826 | 0.838 |
| pole1_old2a | 8.51e+04 | 4.02e+03 | 0.365 | 0.364 | 0.507 | 0.621 | 0.626 |
| v0100_cfg | 8.51e+04 | 4.02e+03 | 0.369 | 0.368 | 0.543 | 0.639 | 0.644 |

