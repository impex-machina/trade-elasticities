# Does gamma drift by more than half-panel noise? (v0110)

Parity halves `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` / `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`; period halves `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (1995-2009) / `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (2010-2024). Rev 312a437, 2026-10-14 23:03:43 EDT.

Robust SD of the between-half difference (1.4826 x MAD); ratio = V_period / V_parity. A recent-window estimate beats the full-panel average for current use when the ratio exceeds 2 (reading rule, patch 0119).

| quantity | units (parity / period) | r (parity / period) | SD of difference (parity / period) | ratio | reading |
|---|---|---|---|---|---|
| cell log opt_tariff | 4,082 / 3,692 | 0.545 / 0.396 | 0.416 / 0.496 | 1.420 | **full panel as good** |
| cell mean log gamma | 4,082 / 3,692 | 0.676 / 0.596 | 0.188 / 0.214 | 1.287 | **full panel as good** |
| row log gamma | 85,106 / 61,122 | 0.537 / 0.352 | 0.303 / 0.322 | 1.130 | **full panel as good** |

Coverage -- directly estimated rows: odd 89,975, even 91,844, 1995-2009 73,148, 2010-2024 97,430; cells: 4,762 / 4,771 / 4,433 / 4,630; Tier 3: 33.8% / 33.6% / 29.3% / 25.8%.

Exporters with the most directly estimated rows in both periods: change in log gamma, 2010-2024 minus 1995-2009 (negative = more elastic supply recently).

| exporter | rows | median change | p25 | p75 |
|---|---|---|---|---|
| 276 | 2,477 | 0.003 | -0.374 | 0.383 |
| 156 | 2,439 | 0.062 | -0.267 | 0.730 |
| 842 | 2,387 | 0.004 | -0.427 | 0.484 |
| 251 | 2,240 | 0.011 | -0.290 | 0.387 |
| 380 | 2,224 | 0.003 | -0.315 | 0.350 |
| 826 | 2,120 | -0.011 | -0.382 | 0.277 |
| 528 | 1,881 | 0.004 | -0.333 | 0.328 |
| 56 | 1,864 | 0.015 | -0.224 | 0.377 |
| 724 | 1,817 | 0.006 | -0.238 | 0.312 |
| 699 | 1,746 | 0.017 | -0.267 | 0.446 |

