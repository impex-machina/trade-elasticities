# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\v091_runs.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-11 15:47:53 EDT.

## Full-panel summaries

| config | rows | n_estimated | share_non_converged | share_gamma_le_0_01 | share_gamma_le_1e_4 | share_gamma_ge_10 | shrink_wt_median | within_cell_sd_median | abs_dev_median | abs_dev_p90 | opt_tariff_median | gamma_median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| base | 1.52e+05 | 1.13e+05 | 0.0233 | 0.00392 |    0 | 0.00443 | 0.915 | 0.655 | 0.108 |  1.3 | 0.585 | 0.539 |
| raw | 1.52e+05 | 1.13e+05 | 0.019 | 0.00303 |    0 | 0.00446 | 0.912 | 0.623 | 0.107 | 1.27 | 0.586 | 0.54 |
| bwsum | 1.52e+05 | 1.13e+05 | 0.0199 | 0.00519 |    0 | 0.00549 | 0.864 | 0.682 | 0.17 |  1.4 | 0.592 | 0.538 |
| both | 1.52e+05 | 1.13e+05 | 0.0228 | 0.00485 |    0 | 0.00545 | 0.838 | 0.675 | 0.193 | 1.42 | 0.598 | 0.538 |

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 8.53e+04 | 4.03e+03 | 0.333 | 0.343 | 0.473 | 0.826 | 0.838 |
| raw | 8.53e+04 | 4.03e+03 | 0.303 | 0.32 | 0.45 | 0.721 | 0.726 |
| bwsum | 8.54e+04 | 4.04e+03 | 0.314 | 0.338 | 0.416 | 1.15 | 1.16 |
| both | 8.53e+04 | 4.03e+03 | 0.307 | 0.319 | 0.439 | 0.836 | 0.848 |

