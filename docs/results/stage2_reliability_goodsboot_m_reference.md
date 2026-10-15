# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\RtmpeMB3eU\file8aac61f351c4.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 21:57:43 EDT.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ref_base | 8.51e+04 | 4.02e+03 | 0.368 | 0.368 | 0.542 | 0.638 | 0.644 |
| ref_stable | 8.51e+04 | 4.02e+03 | 0.367 | 0.369 | 0.546 | 0.617 | 0.626 |
| ref_value | 8.31e+04 | 3.88e+03 | 0.367 | 0.369 | 0.538 | 0.642 | 0.649 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `ref_base` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ref_base |   25 | 0.368 | 0.34 | 0.39 | NA |   NA |   NA |   NA |   NA |
| ref_stable |   25 | 0.367 | 0.342 | 0.387 | ref_base | -0.000865 | -0.00654 | 0.00473 | 0.632 |
| ref_value |   25 | 0.367 | 0.341 | 0.388 | ref_base | -0.000447 | -0.0073 | 0.00563 | 0.54 |

