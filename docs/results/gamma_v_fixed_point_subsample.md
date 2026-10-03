# Exporter-specific gamma_V: fixed-point census (patch 0085)

Passes: 1 `C:\Users\maxxj\te_grid\gv_pass1\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, 2 `C:\Users\maxxj\te_grid\gv_pass2\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, 3 `C:\Users\maxxj\te_grid\gv_pass3\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (rev 86117a7, 2026-10-03 13:08:06 EDT).

| step | shared rows | Tier-1 rows compared | abs d ln gamma p50 | p90 | p99 | max | share < 1e-3 | share < 1e-2 | gamma median a -> b | opt_tariff median a -> b |
|---|---|---|---|---|---|---|---|---|---|---|
| 1->2 | 151,766 | 104,085 | 0.001081 | 0.05377 | 0.6516 | 5.293 | 49.1% | 75.3% | 0.5568 -> 0.5568 | 0.6691 -> 0.6662 |
| 2->3 | 151,832 | 104,287 | 0.0001446 | 0.01217 | 0.2437 | 5.456 | 70.4% | 88.9% | 0.5568 -> 0.5568 | 0.6662 -> 0.6656 |

Contraction ratio (median |d ln gamma| of 2->3 over 1->2): 0.1337.

Reading: a ratio well below 1 means the iteration contracts and one exporter-specific pass is enough for the published table; near 1 means it does not settle and the regional proxy should stay. Rows outside Tier 1 move only through the joint fit of their cell.
