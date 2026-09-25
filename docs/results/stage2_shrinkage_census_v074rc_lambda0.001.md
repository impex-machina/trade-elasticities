# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `out_l0001.rds` (6,812,090 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-25 17:58:06 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,990,527; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.004 | 0.054 | 0.522 | 0.908 | 0.985 |
| implied data share | 0.030 | 0.168 | 0.646 | 0.972 | 0.998 |

Mean shrink_wt 0.495; share > 0.9: 0.260, > 0.95: 0.187, > 0.99: 0.079. Implied data share: mean 0.573, trade-weighted 0.522 (trade-weighted 1 - s: 0.455).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 97825.000 | 0.182 | 0.900 | 0.567 |
| 1.000 | 1632486.000 | 0.536 | 0.634 | 0.505 |
| 2.000 | 6105.000 | 0.833 | 0.286 | 0.539 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 106128.000 | 0.134 | 0.928 | 0.550 |
| 2-3 | 210048.000 | 0.181 | 0.901 | 0.524 |
| 4-10 | 510118.000 | 0.371 | 0.772 | 0.498 |
| >10 | 910122.000 | 0.684 | 0.480 | 0.483 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4990527 | 2.191 | 0.092 | 0.162 | 0.746 |
| trade-weighted | 4990527 | 2.421 | 0.162 | 0.309 | 0.528 |
| tier 1 only | 4774886 | 2.140 | 0.104 | 0.182 | 0.714 |
| prior (sanity) | 4990527 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.011 | 0.043 | 0.201 | 0.848 | 2.307 |
| dev signed | -1.737 | -0.313 | -0.001 | 0.142 | 0.695 |
| |dev|, reference rows | 0.100 | 0.324 | 0.845 | 1.686 | 3.164 |

Share within 1%: 0.090, within 5%: 0.272, within 20%: 0.499; trade-weighted mean |dev| 0.770; reference rows within 1%: 0.012 (n = 200856).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 200856.000 | 0.845 | 3.164 | 0.053 |
| 1.000 | 4774886.000 | 0.186 | 2.248 | 0.281 |
| 2.000 | 14785.000 | 0.193 | 2.231 | 0.285 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.263 | 0.851 | 1.469 | 2.175 | 2.851 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 1.480; median within-cell sd / prior sd: 3.443 (n cells = 208,257).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.046 | 0.153 | 0.474 | 1.049 | 1.772 |

Cells: 209,674; within 5%: 0.108; within 20%: 0.297.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 852098.000 | 0.834 | 2.445 | 0.974 |
| 0.5-0.9 | 432365.000 | 1.197 | 3.782 | 0.399 |
| 0.9-0.95 | 127338.000 | 1.169 | 4.827 | 0.134 |
| 0.95-0.99 | 187956.000 | 0.585 | 5.644 | 0.051 |
| >=0.99 | 136659.000 | 0.021 | 5.565 | 0.005 |

