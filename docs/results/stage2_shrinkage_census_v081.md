# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,812,560 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-29 11:42:31 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,990,997; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.203 | 0.583 | 0.902 | 0.990 | 0.999 |
| implied data share | 0.001 | 0.010 | 0.098 | 0.417 | 0.797 |

Mean shrink_wt 0.750; share > 0.9: 0.503, > 0.95: 0.414, > 0.99: 0.252. Implied data share: mean 0.250, trade-weighted 0.261 (trade-weighted 1 - s: 0.261).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 198310.000 | 0.585 | 0.415 | 0.283 |
| 1.000 | 4638284.000 | 0.912 | 0.088 | 0.252 |
| 2.000 | 13741.000 | 0.995 | 0.005 | 0.413 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 204268.000 | 0.603 | 0.397 | 0.306 |
| 2-3 | 394032.000 | 0.604 | 0.396 | 0.270 |
| 4-10 | 1105122.000 | 0.751 | 0.249 | 0.232 |
| >10 | 3146913.000 | 0.960 | 0.040 | 0.179 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4990997 | 0.820 | 0.183 | 0.145 | 0.672 |
| trade-weighted | 4990997 | 1.275 | 0.346 | 0.223 | 0.431 |
| tier 1 only | 4771886 | 0.783 | 0.192 | 0.153 | 0.655 |
| prior (sanity) | 4990997 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.001 | 0.014 | 0.125 | 0.577 | 1.349 |
| dev signed | -1.002 | -0.226 | -0.002 | 0.059 | 0.506 |
| |dev|, reference rows | 0.078 | 0.256 | 0.678 | 1.325 | 2.035 |

Share within 1%: 0.219, within 5%: 0.380, within 20%: 0.570; trade-weighted mean |dev| 0.595; reference rows within 1%: 0.018 (n = 204320).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 204320.000 | 0.678 | 2.035 | 0.069 |
| 1.000 | 4771886.000 | 0.113 | 1.296 | 0.392 |
| 2.000 | 14791.000 | 0.012 | 0.753 | 0.638 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.175 | 0.370 | 0.665 | 1.033 | 1.412 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 0.906; median within-cell sd / prior sd: 1.558 (n cells = 209,808).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.043 | 0.131 | 0.338 | 0.696 | 1.184 |

Cells: 210,312; within 5%: 0.114; within 20%: 0.346.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 1022084.000 | 0.726 | 1.915 | 0.782 |
| 0.5-0.9 | 1389293.000 | 0.382 | 1.738 | 0.246 |
| 0.9-0.95 | 431832.000 | 0.114 | 0.616 | 0.072 |
| 0.95-0.99 | 783747.000 | 0.040 | 0.187 | 0.024 |
| >=0.99 | 1223379.000 | 0.003 | 0.025 | 0.001 |

