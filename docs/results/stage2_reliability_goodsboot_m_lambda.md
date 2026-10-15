# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\RtmpeMB3eU\file8aac32946aca.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 21:57:50 EDT.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| lam010_base | 8.51e+04 | 4.02e+03 | 0.369 | 0.368 | 0.543 | 0.639 | 0.644 |
| lam003 | 8.51e+04 | 4.01e+03 | 0.362 | 0.36 | 0.484 | 0.882 | 0.892 |
| lam030 | 8.51e+04 | 4.03e+03 | 0.368 | 0.375 | 0.621 | 0.456 | 0.457 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `lam010_base` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| lam010_base |   25 | 0.369 | 0.343 | 0.391 | NA |   NA |   NA |   NA |   NA |
| lam003 |   25 | 0.362 | 0.338 | 0.382 | lam010_base | -0.00704 | -0.0135 | -0.00176 | 0.995 |
| lam030 |   25 | 0.368 | 0.341 | 0.389 | lam010_base | -0.00152 | -0.00478 | 0.00211 | 0.81 |

