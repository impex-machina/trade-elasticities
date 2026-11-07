# The sigma update across windows (patch 0153)

Early `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, late `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`; cells updated in both windows 3390; global medians 2.775 / 2.856.

| window | cells | updated | Stage-1 estimated | at floor | at cap |
|---|---|---|---|---|---|
| early | 4455 | 3685 | 2207 | 2 | 230 |
| late | 4654 | 4045 | 2399 | 0 | 221 |

| predictor | cells | median abs cross-window diff of ln(sigma - 1) | r |
|---|---|---|---|
| updated (cell) | 3390 | 0.474 | 0.145 |
| global median (window) | 3390 | 0.364 | -- |
| stage1 (cell) | 1189 | 0.965 | 0.041 |
| updated (cell), same cells | 1189 | 0.481 | 0.111 |
| global median (window), same cells | 1189 | 0.378 | -- |

**Reading:** beats the Stage-1 sigma but not the global median (or r lower): does not advance under the rule

Shrinkage block (two-fold, both directions pooled; b = reliability ratio):

| predictor | mode | cells | b | median abs out-of-sample diff | r |
|---|---|---|---|---|---|
| updated sigma | level (b = 0) | 3390 | 0.000 | 0.376 | -- |
| updated sigma | cell (b = 1) | 3390 | 1.000 | 0.472 | 0.145 |
| updated sigma | shrunk (b fitted) | 3390 | 0.146 | 0.365 | 0.142 |
| Stage-1 sigma | level (b = 0) | 1189 | 0.000 | 0.688 | -- |
| Stage-1 sigma | cell (b = 1) | 1189 | 1.000 | 0.960 | 0.040 |
| Stage-1 sigma | shrunk (b fitted) | 1189 | 0.042 | 0.690 | 0.023 |
| updated sigma, same cells | level (b = 0) | 1189 | 0.000 | 0.377 | -- |
| updated sigma, same cells | cell (b = 1) | 1189 | 1.000 | 0.482 | 0.106 |
| updated sigma, same cells | shrunk (b fitted) | 1189 | 0.113 | 0.379 | 0.081 |

**Reading (shrinkage rule):** ADVANCES: the shrunk updated sigma (b = 0.15) beats the level predictor (0.365 vs 0.376) and the shrunk Stage-1 sigma (0.379 vs 0.690)

Robustness of the shrinkage gain (updated sigma, all common cells): gain over the level predictor 0.0109 in median |diff|, paired bootstrap 95% CI [0.0037, 0.0158], shrunk sigma closer in 55.7% of cell-directions; over 10 fold seeds b 0.142-0.146, gain 0.0063-0.0109 (negative in 0 of 10). **Robust.**
