# EB calibration of the Stage-2b shrinkage lambda (shipped_l0.1, fixed lambda =  0.1)

Passes: `shipped_l0.1_odd` / `shipped_l0.1_even` under `C:\Users\maxxj/te_grid`; prior rebuilt from `2a_log` with rows = all; rows with gamma_shrink_wt > 0.99 excluded (rev 8c69472, 2026-10-02 23:11:04 EDT).

Method: per good, tau^2 = sum(dev_o dev_e) / sum((1-s_o)(1-s_e)) from the two calendar halves, s^2 from the halves' own dispersion net of tau^2 (see the script header); lambda* = s^2 / tau^2 on the half sample, and lambda* / 2 as the approximate full-sample value (each half averages the moments over half the years).

- 25 goods, 49,356 shared rows; usable lambda on 25 goods (tau^2 <= 0 on 0, s^2 <= 0 on 0).
- lambda* (half sample) p10 / p25 / p50 / p75 / p90: 0.0933 / 0.115 / 0.145 / 0.23 / 0.313.
- lambda* (full-sample approx.) p10 / p25 / p50 / p75 / p90: 0.0466 / 0.0575 / 0.0724 / 0.115 / 0.156; sd of log10 across goods 0.216.
- Share of goods whose full-sample lambda* lies within a factor 2 of the fixed  0.1: 72%; within an order of magnitude: 100%.
- Pooled over all rows: tau^2 1.81, s^2 0.244, lambda* half 0.135, full approx. 0.0673, parity correlation of the deviations 0.432, median shrink_wt 0.736.

| good | rows | tau^2 | s^2 | lambda* half | lambda* full | r parity | median s |
|---|---|---|---|---|---|---|---|
| 0803 | 1128 | 2.02 | 0.255 | 0.126 | 0.0629 | 0.36 | 0.722 |
| 2201 | 1854 |  1.6 | 0.301 | 0.188 | 0.0942 | 0.376 | 0.727 |
| 2202 | 3565 | 1.52 | 0.175 | 0.115 | 0.0575 | 0.448 | 0.787 |
| 2812 | 482 | 1.14 | 0.511 | 0.448 | 0.224 | 0.302 | 0.558 |
| 2817 | 1014 | 1.42 | 0.279 | 0.196 | 0.0979 | 0.372 | 0.71 |
| 2901 | 1420 | 3.41 | 0.31 | 0.0911 | 0.0456 | 0.465 | 0.623 |
| 2905 | 2449 | 1.77 | 0.253 | 0.143 | 0.0714 | 0.394 | 0.728 |
| 2917 | 1749 | 2.43 | 0.24 | 0.0986 | 0.0493 | 0.421 | 0.677 |
| 3201 | 713 | 1.55 | 0.481 | 0.311 | 0.156 | 0.264 | 0.698 |
| 3307 | 3833 | 1.69 | 0.163 | 0.0965 | 0.0482 | 0.444 | 0.803 |
| 3404 | 2183 | 1.59 | 0.213 | 0.134 | 0.067 | 0.431 | 0.727 |
| 4302 | 973 | 1.55 | 0.276 | 0.178 | 0.0892 | 0.421 | 0.688 |
| 4504 | 1386 |  1.4 | 0.353 | 0.252 | 0.126 | 0.342 | 0.718 |
| 5209 | 2442 | 1.56 | 0.239 | 0.153 | 0.0764 | 0.402 | 0.74 |
| 5303 | 320 | 1.49 | 0.631 | 0.423 | 0.212 | 0.198 | 0.499 |
| 5404 | 1649 | 1.48 | 0.34 | 0.23 | 0.115 | 0.379 | 0.646 |
| 5702 | 2565 | 1.36 | 0.21 | 0.154 | 0.0768 | 0.45 | 0.725 |
| 5705 | 2737 |    2 | 0.269 | 0.134 | 0.0672 | 0.435 | 0.689 |
| 7321 | 3177 | 2.26 | 0.151 | 0.0668 | 0.0334 | 0.527 | 0.792 |
| 7325 | 2571 | 2.29 | 0.243 | 0.106 | 0.0531 | 0.462 | 0.643 |
| 8432 | 2824 |  1.9 | 0.166 | 0.087 | 0.0435 | 0.544 | 0.697 |
| 8433 | 2912 | 1.66 | 0.241 | 0.145 | 0.0724 | 0.409 | 0.739 |
| 9018 | 4486 | 1.51 |  0.2 | 0.132 | 0.0662 | 0.381 | 0.832 |
| 9109 | 401 | 1.85 | 0.581 | 0.314 | 0.157 | 0.276 | 0.574 |
| 9111 | 523 | 2.18 | 0.54 | 0.248 | 0.124 | 0.328 | 0.627 |

Reading: a tight cluster of lambda* near the fixed value says the constant is defensible and the calibration goes in the paper; a spread across orders of magnitude says lambda should vary by good, which is an estimator change (v0.9). The quadratic one-dimensional approximation behind s_i is crude where the data curvature is small, so weight the pooled and median figures over the individual goods.
