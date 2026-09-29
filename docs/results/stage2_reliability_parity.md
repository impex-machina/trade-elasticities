# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\te_grid\runs_parity.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-28 21:20:28 EDT.

## Full-panel summaries

| config | rows | n_estimated | share_non_converged | share_gamma_le_0_01 | share_gamma_le_1e_4 | share_gamma_ge_10 | shrink_wt_median | within_cell_sd_median | abs_dev_median | abs_dev_p90 | opt_tariff_median | gamma_median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| shiftlog_eps0.01_l0.1 | 1.52e+05 | 1.13e+05 | 0.0775 | 0.00328 |    0 |    0 | 0.934 | 0.571 | 0.0807 | 1.04 | 0.596 | 0.563 |
| shiftlog_eps0.05_l0.1 | 1.52e+05 | 1.13e+05 | 0.0641 | 0.0166 | 0.0132 | 3.53e-05 | 0.92 | 0.643 | 0.0948 | 1.18 | 0.591 | 0.558 |
| shipped_l0.1_maxit2000 | 1.52e+05 | 1.13e+05 | 0.0266 | 0.00189 |    0 | 0.00224 | 0.922 | 0.611 | 0.0992 | 1.19 | 0.603 | 0.555 |

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| shipped_l0.1 | 8.52e+04 | 4.02e+03 | 0.298 | 0.321 | 0.461 | 0.662 | 0.656 |
| log_l0.01 | 8.52e+04 | 3.99e+03 | 0.247 | 0.27 | 0.365 | 0.992 | 0.999 |
| shiftlog_eps0.01_l0.1 | 8.59e+04 | 4.03e+03 | 0.25 | 0.337 | 0.409 | 1.11 | 1.11 |
| shiftlog_eps0.05_l0.1 | 8.59e+04 | 4.02e+03 | 0.236 | 0.346 | 0.366 | 1.66 | 1.67 |
| level_l0.1 | 8.57e+04 | 4.02e+03 | 0.209 | 0.352 | 0.31 | 3.27 | 3.25 |

