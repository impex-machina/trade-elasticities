# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `..\te_ship\D_split\runs_tier1.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-11-08 11:15:40 EST.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ship | 8.09e+04 | 3.71e+03 | 0.358 | 0.354 | 0.597 | 0.439 | 0.442 |
| D | 8.12e+04 | 3.72e+03 | 0.332 | 0.341 | 0.644 | 0.366 | 0.369 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `ship` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ship |   25 | 0.358 | 0.334 | 0.378 | NA |   NA |   NA |   NA |   NA |
| D |   25 | 0.332 | 0.31 | 0.352 | ship | -0.0252 | -0.0383 | -0.0109 | 0.999 |

