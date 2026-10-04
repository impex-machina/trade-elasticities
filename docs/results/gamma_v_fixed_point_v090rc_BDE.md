# Exporter-specific gamma_V: fixed-point census (patch 0085)

Passes: 1 `C:\Users\maxxj\te_rc\v090\out_B\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, 2 `C:\Users\maxxj\te_rc\v090\out_D\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, 3 `C:\Users\maxxj\te_rc\v090\out_E\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (rev 57df7d4, 2026-10-04 01:23:42 EDT).

| step | shared rows | Tier-1 rows compared | abs d ln gamma p50 | p90 | p99 | max | share < 1e-3 | share < 1e-2 | gamma median a -> b | opt_tariff median a -> b |
|---|---|---|---|---|---|---|---|---|---|---|
| 1->2 | 6,799,174 | 4,473,707 | 0.002899 | 0.1104 | 0.9809 | 9.299 | 37.9% | 65.2% | 0.6466 -> 0.6466 | 0.7363 -> 0.733 |
| 2->3 | 6,801,868 | 4,479,301 | 0.0003635 | 0.02755 | 0.4582 | 8.902 | 60.9% | 83.1% | 0.6466 -> 0.6463 | 0.733 -> 0.7316 |

Contraction ratio (median |d ln gamma| of 2->3 over 1->2): 0.1254.

Reading: a ratio well below 1 means the iteration contracts and one exporter-specific pass is enough for the published table; near 1 means it does not settle and the regional proxy should stay. Rows outside Tier 1 move only through the joint fit of their cell.
