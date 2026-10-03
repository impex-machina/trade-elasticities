# Exporter-specific gamma_V: fixed-point census (patch 0085)

Passes: 1 `C:\Users\maxxj\te_grid\gv_pass1\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, 2 `C:\Users\maxxj\te_grid\pc_panel\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (rev 86117a7, 2026-10-03 13:08:24 EDT).

| step | shared rows | Tier-1 rows compared | abs d ln gamma p50 | p90 | p99 | max | share < 1e-3 | share < 1e-2 | gamma median a -> b | opt_tariff median a -> b |
|---|---|---|---|---|---|---|---|---|---|---|
| 1->2 | 151,830 | 103,963 | 0.0001367 | 0.01021 | 0.2171 | 4.565 | 72.2% | 89.9% | 0.5568 -> 0.5568 | 0.6691 -> 0.6711 |

Contraction ratio (median |d ln gamma| of 2->3 over 1->2): NA.

Reading: a ratio well below 1 means the iteration contracts and one exporter-specific pass is enough for the published table; near 1 means it does not settle and the regional proxy should stay. Rows outside Tier 1 move only through the joint fit of their cell.
