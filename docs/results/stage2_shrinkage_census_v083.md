# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,813,953 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-02 22:49:35 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,992,390; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.210 | 0.588 | 0.903 | 0.990 | 0.999 |
| implied data share | 0.001 | 0.010 | 0.097 | 0.412 | 0.790 |

Mean shrink_wt 0.752; share > 0.9: 0.505, > 0.95: 0.415, > 0.99: 0.253. Implied data share: mean 0.248, trade-weighted 0.263 (trade-weighted 1 - s: 0.263).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 196083.000 | 0.594 | 0.406 | 0.286 |
| 1.000 | 4620326.000 | 0.913 | 0.087 | 0.254 |
| 2.000 | 13567.000 | 0.995 | 0.005 | 0.304 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 201674.000 | 0.612 | 0.388 | 0.308 |
| 2-3 | 389112.000 | 0.612 | 0.388 | 0.272 |
| 4-10 | 1092961.000 | 0.755 | 0.245 | 0.234 |
| >10 | 3146229.000 | 0.960 | 0.040 | 0.183 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4992390 | 0.854 | 0.178 | 0.156 | 0.666 |
| trade-weighted | 4992390 | 1.348 | 0.333 | 0.223 | 0.444 |
| tier 1 only | 4773161 | 0.815 | 0.187 | 0.164 | 0.650 |
| prior (sanity) | 4992390 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.003 | 0.016 | 0.123 | 0.579 | 1.375 |
| dev signed | -1.021 | -0.230 | -0.001 | 0.058 | 0.493 |
| |dev|, reference rows | 0.079 | 0.260 | 0.690 | 1.349 | 2.070 |

Share within 1%: 0.206, within 5%: 0.380, within 20%: 0.573; trade-weighted mean |dev| 0.621; reference rows within 1%: 0.017 (n = 204418).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 204418.000 | 0.690 | 2.070 | 0.068 |
| 1.000 | 4773161.000 | 0.111 | 1.320 | 0.392 |
| 2.000 | 14811.000 | 0.021 | 0.748 | 0.625 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.175 | 0.370 | 0.666 | 1.039 | 1.430 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 0.924; median within-cell sd / prior sd: 1.560 (n cells = 209,839).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.044 | 0.131 | 0.336 | 0.685 | 1.155 |

Cells: 210,315; within 5%: 0.113; within 20%: 0.347.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 1005103.000 | 0.724 | 1.912 | 0.778 |
| 0.5-0.9 | 1386950.000 | 0.381 | 1.740 | 0.245 |
| 0.9-0.95 | 431927.000 | 0.114 | 0.622 | 0.072 |
| 0.95-0.99 | 783486.000 | 0.040 | 0.189 | 0.024 |
| >=0.99 | 1222510.000 | 0.004 | 0.030 | 0.001 |

