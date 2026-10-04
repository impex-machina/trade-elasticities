# Exporter-specific gamma_V: fixed-point census (patch 0085)

Passes: 1 `C:\Users\maxxj\te_rc\v090\out_B\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, 2 `C:\Users\maxxj\te_rc\v090\out_C\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (rev 57df7d4, 2026-10-04 01:22:28 EDT).

| step | shared rows | Tier-1 rows compared | abs d ln gamma p50 | p90 | p99 | max | share < 1e-3 | share < 1e-2 | gamma median a -> b | opt_tariff median a -> b |
|---|---|---|---|---|---|---|---|---|---|---|
| 1->2 | 6,799,510 | 4,476,440 | 0.001941 | 0.09376 | 0.919 | 9.295 | 42.8% | 68.8% | 0.6466 -> 0.6464 | 0.7363 -> 0.7334 |

Contraction ratio (median |d ln gamma| of 2->3 over 1->2): NA.

Reading: a ratio well below 1 means the iteration contracts and one exporter-specific pass is enough for the published table; near 1 means it does not settle and the regional proxy should stay. Rows outside Tier 1 move only through the joint fit of their cell.
