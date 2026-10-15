# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\RtmpeMB3eU\file8aac757925e6.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 21:57:36 EDT.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 8.51e+04 | 4.02e+03 | 0.368 | 0.368 | 0.542 | 0.638 | 0.644 |
| exptot_all | 8.51e+04 | 4.02e+03 | 0.367 | 0.368 | 0.542 | 0.638 | 0.643 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `base` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| base |   25 | 0.368 | 0.34 | 0.39 | NA |   NA |   NA |   NA |   NA |
| exptot_all |   25 | 0.367 | 0.341 | 0.389 | base | -0.000415 | -0.00345 | 0.00267 | 0.599 |

