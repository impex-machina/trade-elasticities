# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `out_se_sand.rds` (6,811,822 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-25 17:56:40 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,990,259; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.306 | 0.668 | 0.928 | 0.993 | 0.999 |
| implied data share | 0.001 | 0.007 | 0.072 | 0.332 | 0.694 |

Mean shrink_wt 0.787; share > 0.9: 0.546, > 0.95: 0.452, > 0.99: 0.279. Implied data share: mean 0.213, trade-weighted 0.227 (trade-weighted 1 - s: 0.227).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 170543.000 | 0.686 | 0.314 | 0.276 |
| 1.000 | 4166777.000 | 0.935 | 0.065 | 0.208 |
| 2.000 | 12376.000 | 0.996 | 0.004 | 0.355 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 178340.000 | 0.657 | 0.343 | 0.290 |
| 2-3 | 355712.000 | 0.671 | 0.329 | 0.224 |
| 4-10 | 1016910.000 | 0.800 | 0.200 | 0.187 |
| >10 | 2798734.000 | 0.973 | 0.027 | 0.141 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4990259 | 0.689 | 0.244 | 0.156 | 0.599 |
| trade-weighted | 4990259 | 1.145 | 0.353 | 0.251 | 0.396 |
| tier 1 only | 4773193 | 0.656 | 0.262 | 0.173 | 0.566 |
| prior (sanity) | 4990259 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.001 | 0.014 | 0.101 | 0.475 | 1.185 |
| dev signed | -0.846 | -0.158 | -0.001 | 0.066 | 0.442 |
| |dev|, reference rows | 0.069 | 0.245 | 0.686 | 1.308 | 1.887 |

Share within 1%: 0.221, within 5%: 0.399, within 20%: 0.606; trade-weighted mean |dev| 0.568; reference rows within 1%: 0.021 (n = 202257).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 202257.000 | 0.686 | 1.887 | 0.078 |
| 1.000 | 4773193.000 | 0.092 | 1.119 | 0.412 |
| 2.000 | 14809.000 | 0.015 | 0.704 | 0.621 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.180 | 0.371 | 0.635 | 0.958 | 1.321 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 0.830; median within-cell sd / prior sd: 1.487 (n cells = 209,613).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.046 | 0.139 | 0.356 | 0.712 | 1.165 |

Cells: 210,222; within 5%: 0.106; within 20%: 0.331.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 730974.000 | 0.741 | 1.894 | 0.749 |
| 0.5-0.9 | 1244585.000 | 0.400 | 1.625 | 0.240 |
| 0.9-0.95 | 408872.000 | 0.123 | 0.651 | 0.072 |
| 0.95-0.99 | 752428.000 | 0.042 | 0.201 | 0.024 |
| >=0.99 | 1212837.000 | 0.003 | 0.027 | 0.001 |

