# EB sigma shrinkage on the period split (v0110)

Inputs: `C:\Users\maxxj\te_m3\w0_1995_2009\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` (1995-2009) and `C:\Users\maxxj\te_m3\w1_2010_2024\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` (2010-2024); rev 8fb8838, 2026-10-15 07:09:30 EDT. Errors on z = ln(sigma - 1) against the other period's own estimate.

### Early predicts late (3,476 target cells, 25 goods)

Source-period fit: fallback sigma 2.5278; EB prior mu 0.4274, tau^2 0.6184 on 3,192 cells; 25 goods with their own prior.

| predictor | median abs error | weighted MSE |
|---|---|---|
| published rule | 0.9982 | 2.7150 |
| EB (global prior) | 0.9510 | 2.2932 |
| EB (prior per good) | 0.9566 | 2.0726 |
| constant (fallback) | 0.8745 | 1.5019 |

### Late predicts early (3,192 target cells, 25 goods)

Source-period fit: fallback sigma 2.5403; EB prior mu 0.4527, tau^2 0.6602 on 3,476 cells; 25 goods with their own prior.

| predictor | median abs error | weighted MSE |
|---|---|---|
| published rule | 0.9826 | 0.1135 |
| EB (global prior) | 0.9354 | 0.0708 |
| EB (prior per good) | 0.9440 | 0.0862 |
| constant (fallback) | 0.8327 | 0.0474 |

**Reading (fixed in patch 0122): passes** -- EB weighted MSE >= 5% below the published rule's and median |error| not higher, in both directions; early -> late TRUE, late -> early TRUE.
