# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\v091_pole_runs.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-11 21:53:11 EDT.

## Full-panel summaries

| config | rows | n_estimated | share_non_converged | share_gamma_le_0_01 | share_gamma_le_1e_4 | share_gamma_ge_10 | shrink_wt_median | within_cell_sd_median | abs_dev_median | abs_dev_p90 | opt_tariff_median | gamma_median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| base | 1.52e+05 | 1.13e+05 | 0.0233 | 0.00392 |    0 | 0.00443 | 0.915 | 0.655 | 0.108 |  1.3 | 0.585 | 0.539 |
| pole05 | 1.52e+05 | 1.13e+05 | 0.00817 |    0 |    0 | 0.000852 | 0.926 | 0.573 | 0.0874 | 1.06 | 0.594 | 0.548 |
| pole1 | 1.52e+05 | 1.13e+05 | 0.00624 |    0 |    0 |    0 | 0.934 | 0.546 | 0.0772 | 0.959 | 0.606 | 0.556 |
| pole2 | 1.52e+05 | 1.13e+05 | 0.002 |    0 |    0 |    0 | 0.944 | 0.498 | 0.0657 | 0.838 | 0.618 | 0.562 |
| pole25 | 1.52e+05 | 1.13e+05 | 0.00254 |    0 |    0 |    0 | 0.947 | 0.482 | 0.0619 | 0.795 | 0.621 | 0.565 |

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 8.53e+04 | 4.03e+03 | 0.333 | 0.343 | 0.473 | 0.826 | 0.838 |
| pole05 | 8.51e+04 | 4.03e+03 | 0.355 | 0.355 | 0.497 | 0.672 | 0.676 |
| pole1 | 8.51e+04 | 4.02e+03 | 0.365 | 0.364 | 0.507 | 0.621 | 0.626 |
| pole2 | 8.5e+04 | 4.01e+03 | 0.368 | 0.366 | 0.52 | 0.554 | 0.557 |
| pole25 | 8.52e+04 | 4.01e+03 | 0.372 | 0.37 | 0.527 | 0.532 | 0.534 |

