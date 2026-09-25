# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,814,229 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-25 09:37:54 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,992,699; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.518 | 0.847 | 0.980 | 0.999 | 1.000 |
| implied data share | 0.000 | 0.002 | 0.040 | 0.266 | 0.651 |

Mean shrink_wt 0.864; share > 0.9: 0.692, > 0.95: 0.602, > 0.99: 0.428. Implied data share: mean 0.185, trade-weighted 0.207 (trade-weighted 1 - s: 0.153).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 182063.000 | 0.795 | 0.340 | 0.309 |
| 1.000 | 4465961.000 | 0.982 | 0.035 | 0.168 |
| 2.000 | 13288.000 | 0.999 | 0.002 | 0.292 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 187189.000 | 0.853 | 0.257 | 0.284 |
| 2-3 | 373841.000 | 0.888 | 0.201 | 0.197 |
| 4-10 | 1080217.000 | 0.938 | 0.117 | 0.157 |
| >10 | 3020065.000 | 0.991 | 0.018 | 0.119 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4992699 | 25.603 | 0.374 | 0.297 | 0.329 |
| trade-weighted | 4992699 | 38.027 | 0.512 | 0.281 | 0.207 |
| tier 1 only | 4772662 | 25.885 | 0.374 | 0.306 | 0.320 |
| prior (sanity) | 4992699 | 7.494 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.001 | 0.014 | 0.140 | 0.777 | 12.741 |
| dev signed | -12.720 | -0.380 | -0.003 | 0.041 | 0.433 |
| |dev|, reference rows | 0.017 | 0.212 | 0.737 | 1.501 | 2.383 |

Share within 1%: 0.226, within 5%: 0.374, within 20%: 0.549; trade-weighted mean |dev| 2.534; reference rows within 1%: 0.090 (n = 205239).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 205239.000 | 0.737 | 2.383 | 0.135 |
| 1.000 | 4772662.000 | 0.128 | 12.788 | 0.384 |
| 2.000 | 14798.000 | 0.016 | 12.346 | 0.598 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.058 | 0.372 | 2.108 | 4.737 | 6.520 |

Across-good sd of ln prior: 2.388; sd of log gamma over all estimated rows: 5.060; median within-cell sd / prior sd: 0.883 (n cells = 210,088).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.045 | 0.172 | 0.474 | 1.056 | 2.310 |

Cells: 210,442; within 5%: 0.106; within 20%: 0.279.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 446528.000 | 0.649 | 1.762 | 0.863 |
| 0.5-0.9 | 990390.000 | 0.513 | 1.660 | 0.357 |
| 0.9-0.95 | 417605.000 | 0.230 | 1.269 | 0.133 |
| 0.95-0.99 | 811671.000 | 0.082 | 0.523 | 0.046 |
| >=0.99 | 1995118.000 | 0.011 | 13.354 | 0.001 |

