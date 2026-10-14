# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,801,807 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-13 19:38:09 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,982,324; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.303 | 0.648 | 0.917 | 0.991 | 0.999 |
| implied data share | 0.002 | 0.018 | 0.153 | 0.521 | 0.821 |

Mean shrink_wt 0.780; share > 0.9: 0.528, > 0.95: 0.431, > 0.99: 0.257. Implied data share: mean 0.290, trade-weighted 0.304 (trade-weighted 1 - s: 0.227).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 197442.000 | 0.610 | 0.561 | 0.321 |
| 1.000 | 4721958.000 | 0.925 | 0.139 | 0.298 |
| 2.000 | 13951.000 | 0.996 | 0.008 | 0.400 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 205439.000 | 0.622 | 0.548 | 0.352 |
| 2-3 | 395993.000 | 0.610 | 0.562 | 0.316 |
| 4-10 | 1116248.000 | 0.762 | 0.384 | 0.274 |
| >10 | 3215671.000 | 0.967 | 0.064 | 0.209 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4982324 | 0.600 | 0.298 | 0.108 | 0.594 |
| trade-weighted | 4982324 | 0.998 | 0.455 | 0.167 | 0.378 |
| tier 1 only | 4765651 | 0.568 | 0.316 | 0.115 | 0.569 |
| prior (sanity) | 4982324 | 0.198 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.002 | 0.014 | 0.100 | 0.462 | 1.113 |
| dev signed | -0.819 | -0.185 | -0.002 | 0.046 | 0.394 |
| |dev|, reference rows | 0.073 | 0.236 | 0.624 | 1.213 | 1.816 |

Share within 1%: 0.215, within 5%: 0.401, within 20%: 0.608; trade-weighted mean |dev| 0.487; reference rows within 1%: 0.017 (n = 201909).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 201909.000 | 0.624 | 1.816 | 0.073 |
| 1.000 | 4765651.000 | 0.090 | 1.055 | 0.415 |
| 2.000 | 14764.000 | 0.018 | 0.585 | 0.640 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.190 | 0.365 | 0.605 | 0.879 | 1.163 |

Across-good sd of ln prior: 0.485; sd of log gamma over all estimated rows: 0.775; median within-cell sd / prior sd: 1.246 (n cells = 209,111).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.042 | 0.123 | 0.308 | 0.628 | 1.052 |

Cells: 210,090; within 5%: 0.117; within 20%: 0.367.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 864095.000 | 0.711 | 1.784 | 0.847 |
| 0.5-0.9 | 1466514.000 | 0.341 | 1.360 | 0.389 |
| 0.9-0.95 | 478358.000 | 0.107 | 0.481 | 0.134 |
| 0.95-0.99 | 857850.000 | 0.038 | 0.168 | 0.047 |
| >=0.99 | 1266534.000 | 0.004 | 0.030 | 0.003 |

