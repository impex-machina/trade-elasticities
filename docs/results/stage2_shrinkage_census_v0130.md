# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,841,382 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-11-19 01:06:39 EST.

Directly estimated rows (tier 0/1/2, fitted): 5,011,870; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 1 - s

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.436 | 0.744 | 0.940 | 0.992 | 0.999 |
| implied data share | 0.001 | 0.008 | 0.060 | 0.256 | 0.564 |

Mean shrink_wt 0.824; share > 0.9: 0.582, > 0.95: 0.473, > 0.99: 0.274. Implied data share: mean 0.176, trade-weighted 0.182 (trade-weighted 1 - s: 0.182).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 196072.000 | 0.688 | 0.312 | 0.185 |
| 1.000 | 4785508.000 | 0.946 | 0.054 | 0.181 |
| 2.000 | 14204.000 | 0.997 | 0.003 | 0.123 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 207844.000 | 0.694 | 0.306 | 0.216 |
| 2-3 | 399782.000 | 0.685 | 0.315 | 0.201 |
| 4-10 | 1127368.000 | 0.820 | 0.180 | 0.156 |
| >10 | 3260790.000 | 0.975 | 0.025 | 0.106 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 5011870 | 0.410 | 0.416 | 0.058 | 0.526 |
| trade-weighted | 5011870 | 0.720 | 0.562 | 0.131 | 0.307 |
| tier 1 only | 4797808 | 0.384 | 0.446 | 0.064 | 0.490 |
| prior (sanity) | 5011870 | 0.196 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.002 | 0.011 | 0.069 | 0.318 | 0.819 |
| dev signed | -0.511 | -0.098 | -0.000 | 0.046 | 0.346 |
| |dev|, reference rows | 0.062 | 0.199 | 0.550 | 1.078 | 1.584 |

Share within 1%: 0.243, within 5%: 0.450, within 20%: 0.672; trade-weighted mean |dev| 0.371; reference rows within 1%: 0.020 (n = 199186).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 199186.000 | 0.550 | 1.584 | 0.083 |
| 1.000 | 4797808.000 | 0.063 | 0.757 | 0.465 |
| 2.000 | 14876.000 | 0.013 | 0.380 | 0.704 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.171 | 0.300 | 0.485 | 0.702 | 0.945 |

Across-good sd of ln prior: 0.485; sd of log gamma over all estimated rows: 0.640; median within-cell sd / prior sd: 0.999 (n cells = 209,548).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.034 | 0.100 | 0.252 | 0.511 | 0.857 |

Cells: 211,119; within 5%: 0.140; within 20%: 0.426.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 612487.000 | 0.631 | 1.555 | 0.700 |
| 0.5-0.9 | 1475739.000 | 0.295 | 1.077 | 0.230 |
| 0.9-0.95 | 544380.000 | 0.098 | 0.379 | 0.071 |
| 0.95-0.99 | 993669.000 | 0.035 | 0.148 | 0.024 |
| >=0.99 | 1369509.000 | 0.004 | 0.027 | 0.002 |

