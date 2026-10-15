# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\RtmpeMB3eU\file8aac6e3936ab.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 21:57:26 EDT.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 8.53e+04 | 4.03e+03 | 0.333 | 0.343 | 0.473 | 0.826 | 0.838 |
| raw | 8.53e+04 | 4.03e+03 | 0.303 | 0.32 | 0.45 | 0.721 | 0.726 |
| bwsum | 8.54e+04 | 4.04e+03 | 0.314 | 0.338 | 0.416 | 1.15 | 1.16 |
| both | 8.53e+04 | 4.03e+03 | 0.307 | 0.319 | 0.439 | 0.836 | 0.848 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `base` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| base |   25 | 0.333 | 0.312 | 0.353 | NA |   NA |   NA |   NA |   NA |
| raw |   25 | 0.303 | 0.271 | 0.333 | base | -0.0304 | -0.0495 | -0.00986 | 0.998 |
| bwsum |   25 | 0.314 | 0.29 | 0.335 | base | -0.0186 | -0.0299 | -0.00758 |    1 |
| both |   25 | 0.307 | 0.276 | 0.336 | base | -0.0259 | -0.0443 | -0.00736 | 0.997 |

