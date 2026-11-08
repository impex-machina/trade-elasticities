# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `..\te_ship\D_split\runs_other.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-11-08 11:15:49 EST.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ship | 4.53e+03 |  685 | 0.0427 | 0.0436 | 0.48 | 0.534 | 0.525 |
| D | 4.28e+03 |  646 | -0.0761 | -0.106 | 0.486 | 0.556 | 0.557 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `ship` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ship |   25 | 0.0427 | -0.0462 | 0.133 | NA |   NA |   NA |   NA |   NA |
| D |   25 | -0.0761 | -0.16 | 0.0201 | ship | -0.119 | -0.194 | -0.0341 | 0.997 |

