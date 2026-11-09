# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `..\te_ship\runs_Q.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-11-08 18:17:35 EST.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ship | 8.54e+04 | 3.99e+03 | 0.38 | 0.367 | 0.591 | 0.465 | 0.468 |
| Q | 8.54e+04 | 3.99e+03 | 0.379 | 0.367 | 0.59 | 0.466 | 0.469 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `ship` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ship |   25 | 0.38 | 0.358 |  0.4 | NA |   NA |   NA |   NA |   NA |
| Q |   25 | 0.379 | 0.357 | 0.399 | ship | -0.000636 | -0.00156 | 0.000133 | 0.938 |

