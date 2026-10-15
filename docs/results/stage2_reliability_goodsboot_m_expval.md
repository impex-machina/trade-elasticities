# Stage-2 design grid: summaries and split-half reliability (patch 0071)

Runs manifest: `C:\Users\maxxj\AppData\Local\Temp\RtmpeMB3eU\file8aac5152665a.csv`; priors from `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 21:57:31 EDT.

## Full-panel summaries

(none)

## Split-half reliability (within-cell-demeaned log gamma, keys estimated in both halves)

| config | n_keys | n_cells | r_within | rho_rank | r_raw | sd_within_a | sd_within_b |
| --- | --- | --- | --- | --- | --- | --- | --- |
| m_ref_base | 8.51e+04 | 4.02e+03 | 0.368 | 0.368 | 0.542 | 0.638 | 0.644 |
| m_expval | 8.51e+04 | 4.02e+03 | 0.36 | 0.362 | 0.537 | 0.633 | 0.637 |

## Goods bootstrap (patch 0117): 2000 draws over 25 goods, seed 20261015, differences from `m_ref_base` on the same draws

r_lo / r_hi and delta_lo / delta_hi are 2.5% / 97.5% percentiles.

| config | n_goods | r_within | r_lo | r_hi | base | delta | delta_lo | delta_hi | share_delta_le_0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| m_ref_base |   25 | 0.368 | 0.34 | 0.39 | NA |   NA |   NA |   NA |   NA |
| m_expval |   25 | 0.36 | 0.337 | 0.379 | m_ref_base | -0.00781 | -0.0141 | -0.0013 | 0.992 |

