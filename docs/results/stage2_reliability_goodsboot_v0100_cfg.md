# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\RtmpeMB3eU\file8aac2fec5e27.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 21:57:56 EDT.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 8.53e+04 | 4.03e+03 | 0.333 | 0.343 | 0.473 | 0.826 | 0.838 |
| pole1_old2a | 8.51e+04 | 4.02e+03 | 0.365 | 0.364 | 0.507 | 0.621 | 0.626 |
| v0100_cfg | 8.51e+04 | 4.02e+03 | 0.369 | 0.368 | 0.543 | 0.639 | 0.644 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `base` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| base |   25 | 0.333 | 0.312 | 0.353 | NA |   NA |   NA |   NA |   NA |
| pole1_old2a |   25 | 0.365 | 0.338 | 0.387 | base | 0.0319 | 0.00904 | 0.057 | 0.0005 |
| v0100_cfg |   25 | 0.369 | 0.343 | 0.391 | base | 0.0362 | 0.0137 | 0.0616 | 0.0005 |

