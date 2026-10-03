# EB calibration of the Stage-2b shrinkage lambda (log_l0.01, fixed lambda = 0.01)

Passes: `log_l0.01_odd` / `log_l0.01_even` under `C:\Users\maxxj/te_grid`; prior rebuilt from `2a_log` with rows = all; rows with gamma_shrink_wt > 0.99 excluded (rev 8c69472, 2026-10-02 23:11:20 EDT).

Method: per good, tau^2 = sum(dev_o dev_e) / sum((1-s_o)(1-s_e)) from the two calendar halves, s^2 from the halves' own dispersion net of tau^2 (see the script header); lambda* = s^2 / tau^2 on the half sample, and lambda* / 2 as the approximate full-sample value (each half averages the moments over half the years).

- 25 goods, 38,557 shared rows; usable lambda on 25 goods (tau^2 <= 0 on 0, s^2 <= 0 on 0).
- lambda* (half sample) p10 / p25 / p50 / p75 / p90: 0.0206 / 0.0249 / 0.0292 / 0.0437 / 0.071.
- lambda* (full-sample approx.) p10 / p25 / p50 / p75 / p90: 0.0103 / 0.0124 / 0.0146 / 0.0219 / 0.0355; sd of log10 across goods 0.258.
- Share of goods whose full-sample lambda* lies within a factor 2 of the fixed 0.01: 68%; within an order of magnitude: 96%.
- Pooled over all rows: tau^2 2.18, s^2 0.0651, lambda* half 0.0298, full approx. 0.0149, parity correlation of the deviations 0.388, median shrink_wt 0.569.

| good | rows | tau^2 | s^2 | lambda* half | lambda* full | r parity | median s |
|---|---|---|---|---|---|---|---|
| 0803 | 1157 | 2.51 | 0.0621 | 0.0247 | 0.0124 | 0.368 | 0.502 |
| 2201 | 1460 | 2.29 | 0.0927 | 0.0405 | 0.0202 | 0.357 | 0.52 |
| 2202 | 3186 |  1.7 | 0.0409 | 0.0241 | 0.0121 | 0.38 | 0.664 |
| 2812 | 448 | 0.96 | 0.223 | 0.232 | 0.116 | 0.148 | 0.216 |
| 2817 | 1089 | 2.37 | 0.067 | 0.0283 | 0.0141 | 0.424 | 0.488 |
| 2901 | 1160 | 3.36 | 0.0989 | 0.0294 | 0.0147 | 0.341 | 0.415 |
| 2905 | 2269 | 2.13 | 0.0622 | 0.0292 | 0.0146 | 0.374 | 0.527 |
| 2917 | 1412 |  3.4 | 0.0566 | 0.0166 | 0.00832 | 0.451 | 0.546 |
| 3201 | 645 | 2.18 | 0.139 | 0.0637 | 0.0318 | 0.28 | 0.382 |
| 3307 | 3050 | 1.65 | 0.042 | 0.0255 | 0.0128 | 0.358 | 0.663 |
| 3404 | 2048 | 2.03 | 0.0577 | 0.0285 | 0.0142 | 0.414 | 0.531 |
| 4302 | 535 | 2.89 | 0.081 | 0.028 | 0.014 | 0.413 | 0.605 |
| 4504 | 1081 | 1.53 | 0.106 | 0.0689 | 0.0345 | 0.253 | 0.568 |
| 5209 | 1946 | 1.51 | 0.0597 | 0.0395 | 0.0197 | 0.317 | 0.627 |
| 5303 | 240 | 2.62 | 0.152 | 0.0581 | 0.029 | 0.292 | 0.229 |
| 5404 | 1194 | 1.97 | 0.0863 | 0.0437 | 0.0219 | 0.365 | 0.438 |
| 5702 | 2118 | 1.72 | 0.066 | 0.0383 | 0.0191 | 0.355 | 0.535 |
| 5705 | 1781 | 2.31 | 0.0734 | 0.0318 | 0.0159 | 0.385 | 0.513 |
| 7321 | 2587 | 2.44 | 0.044 | 0.018 | 0.00902 | 0.444 | 0.625 |
| 7325 | 1478 | 3.01 | 0.0748 | 0.0249 | 0.0124 | 0.433 | 0.447 |
| 8432 | 2205 | 1.93 | 0.0462 | 0.0239 | 0.012 | 0.441 | 0.562 |
| 8433 | 2434 | 1.88 | 0.0514 | 0.0274 | 0.0137 | 0.38 | 0.609 |
| 9018 | 2288 | 2.71 | 0.0496 | 0.0183 | 0.00916 | 0.409 | 0.732 |
| 9109 | 318 |  2.7 | 0.248 | 0.0918 | 0.0459 | 0.262 | 0.16 |
| 9111 | 428 | 1.98 | 0.143 | 0.0724 | 0.0362 | 0.26 | 0.411 |

Reading: a tight cluster of lambda* near the fixed value says the constant is defensible and the calibration goes in the paper; a spread across orders of magnitude says lambda should vary by good, which is an estimator change (v0.9). The quadratic one-dimensional approximation behind s_i is crude where the data curvature is small, so weight the pooled and median figures over the individual goods.
