# Exporter-specific gamma_V: fixed-point census (patch 0085)

Passes: 1 `C:\Users\maxxj\te_rc\v090rel\out_G2\baci_hs92_v202601_elast_country_hs4_fixed_sigma_pass1.rds`, 2 `C:\Users\maxxj\te_rc\v090rel\out_G2\baci_hs92_v202601_elast_country_hs4_fixed_sigma_pass2.rds`, 3 `data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (rev 7af3f5a, 2026-10-10 03:05:37 EDT).

| step | shared rows | Tier-1 rows compared | abs d ln gamma p50 | p90 | p99 | max | share < 1e-3 | share < 1e-2 | gamma median a -> b | opt_tariff median a -> b |
|---|---|---|---|---|---|---|---|---|---|---|
| 1->2 | 6,799,377 | 4,522,282 | 0.002073 | 0.09317 | 0.8795 | 8.674 | 42.0% | 68.3% | 0.6444 -> 0.6444 | 0.7367 -> 0.7341 |
| 2->3 | 6,802,354 | 4,534,461 | 0.0003651 | 0.02528 | 0.4033 | 8.255 | 61.1% | 83.6% | 0.6444 -> 0.6441 | 0.7341 -> 0.7327 |

Contraction ratio (median |d ln gamma| of 2->3 over 1->2): 0.1761.

Reading: a ratio well below 1 means the iteration contracts and one exporter-specific pass is enough for the published table; near 1 means it does not settle and the regional proxy should stay. Rows outside Tier 1 move only through the joint fit of their cell.
