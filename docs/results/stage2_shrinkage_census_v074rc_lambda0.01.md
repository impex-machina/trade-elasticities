# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `out_l001.rds` (6,812,379 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-25 17:57:25 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,990,816; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.111 | 0.513 | 0.867 | 0.979 | 0.998 |
| implied data share | 0.004 | 0.041 | 0.234 | 0.655 | 0.941 |

Mean shrink_wt 0.713; share > 0.9: 0.452, > 0.95: 0.349, > 0.99: 0.188. Implied data share: mean 0.359, trade-weighted 0.347 (trade-weighted 1 - s: 0.273).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 134975.000 | 0.665 | 0.502 | 0.383 |
| 1.000 | 2931635.000 | 0.873 | 0.225 | 0.333 |
| 2.000 | 9355.000 | 0.981 | 0.037 | 0.515 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 143482.000 | 0.583 | 0.589 | 0.396 |
| 2-3 | 285429.000 | 0.583 | 0.589 | 0.349 |
| 4-10 | 771746.000 | 0.723 | 0.433 | 0.313 |
| >10 | 1875308.000 | 0.935 | 0.122 | 0.269 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4990816 | 1.337 | 0.140 | 0.167 | 0.693 |
| trade-weighted | 4990816 | 1.886 | 0.233 | 0.304 | 0.464 |
| tier 1 only | 4774885 | 1.285 | 0.154 | 0.186 | 0.660 |
| prior (sanity) | 4990816 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.009 | 0.043 | 0.211 | 0.791 | 1.784 |
| dev signed | -1.272 | -0.270 | 0.000 | 0.173 | 0.791 |
| |dev|, reference rows | 0.105 | 0.355 | 0.921 | 1.786 | 2.688 |

Share within 1%: 0.109, within 5%: 0.269, within 20%: 0.490; trade-weighted mean |dev| 0.780; reference rows within 1%: 0.012 (n = 201134).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 201134.000 | 0.921 | 2.688 | 0.053 |
| 1.000 | 4774885.000 | 0.196 | 1.711 | 0.278 |
| 2.000 | 14797.000 | 0.099 | 1.338 | 0.405 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.344 | 0.688 | 1.051 | 1.503 | 2.000 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 1.156; median within-cell sd / prior sd: 2.463 (n cells = 208,940).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.058 | 0.185 | 0.489 | 0.971 | 1.545 |

Cells: 209,970; within 5%: 0.088; within 20%: 0.265.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 752011.000 | 0.773 | 2.072 | 0.910 |
| 0.5-0.9 | 933092.000 | 0.743 | 2.455 | 0.379 |
| 0.9-0.95 | 317330.000 | 0.369 | 2.598 | 0.134 |
| 0.95-0.99 | 495554.000 | 0.128 | 1.820 | 0.049 |
| >=0.99 | 577978.000 | 0.008 | 0.092 | 0.004 |

