# Is sigma stable across periods? (v0110)

Stage 1 on the 2% product subsample (25 goods): 1995-2009 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`, 2010-2024 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`, full panel `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` (restricted to the same goods). Clean sets as shipped (edge and pole fallback, c = 1). Rev 312a437, 2026-10-14 23:18:12 EDT.

| table | cells | converged sigma > 1 | clean | clean share |
|---|---|---|---|---|
| 1995-2009 | 5,481 | 3,453 | 2,207 | 40.3% |
| 2010-2024 | 5,564 | 3,755 | 2,401 | 43.2% |
| full panel | 5,721 | 4,029 | 2,562 | 44.8% |

Full-panel clean cells without a clean 2010-2024 sigma: 866. Clean-set median sigma (the fallback value): full panel 2.4781, 2010-2024 2.5403.

| comparison | cells clean in both | with both SEs | abs(z) > 1.96, SE as published | at 1.5x SE | rank rho, ln(sigma - 1) | median abs change | median signed change | change > x2 |
|---|---|---|---|---|---|---|---|---|
| 1995-2009 vs 2010-2024 | 1,282 | 1,273 | 29.9% | 16.7% | 0.050 | 0.969 | 0.001 | 62.6% |
| full panel vs 2010-2024 | 1,696 | 1,673 | 16.2% | 8.1% | 0.546 | 0.419 | 0.000 | 34.3% |

Reading (rule fixed in patch 0119, on 1995-2009 vs 2010-2024 at 1.5x SE): **between**.

