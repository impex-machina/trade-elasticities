# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,811,572 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-28 15:55:00 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,990,009; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.267 | 0.644 | 0.923 | 0.992 | 0.999 |
| implied data share | 0.001 | 0.008 | 0.077 | 0.356 | 0.733 |

Mean shrink_wt 0.776; share > 0.9: 0.537, > 0.95: 0.445, > 0.99: 0.273. Implied data share: mean 0.224, trade-weighted 0.237 (trade-weighted 1 - s: 0.237).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 183628.000 | 0.599 | 0.401 | 0.262 |
| 1.000 | 4172972.000 | 0.932 | 0.068 | 0.227 |
| 2.000 | 12438.000 | 0.996 | 0.004 | 0.398 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 191606.000 | 0.618 | 0.382 | 0.284 |
| 2-3 | 368069.000 | 0.625 | 0.375 | 0.248 |
| 4-10 | 1016105.000 | 0.782 | 0.218 | 0.205 |
| >10 | 2793258.000 | 0.972 | 0.028 | 0.151 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4990009 | 0.630 | 0.255 | 0.142 | 0.602 |
| trade-weighted | 4990009 | 0.930 | 0.406 | 0.219 | 0.375 |
| tier 1 only | 4773016 | 0.600 | 0.270 | 0.150 | 0.579 |
| prior (sanity) | 4990009 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.001 | 0.013 | 0.095 | 0.437 | 1.103 |
| dev signed | -0.771 | -0.142 | -0.000 | 0.064 | 0.418 |
| |dev|, reference rows | 0.065 | 0.217 | 0.600 | 1.197 | 1.830 |

Share within 1%: 0.225, within 5%: 0.407, within 20%: 0.618; trade-weighted mean |dev| 0.468; reference rows within 1%: 0.020 (n = 202194).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 202194.000 | 0.600 | 1.830 | 0.080 |
| 1.000 | 4773016.000 | 0.086 | 1.043 | 0.420 |
| 2.000 | 14799.000 | 0.015 | 0.664 | 0.625 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.152 | 0.335 | 0.603 | 0.924 | 1.267 |

Across-good sd of ln prior: 0.426; sd of log gamma over all estimated rows: 0.793; median within-cell sd / prior sd: 1.416 (n cells = 209,399).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.037 | 0.115 | 0.308 | 0.650 | 1.127 |

Cells: 210,246; within 5%: 0.129; within 20%: 0.375.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 793126.000 | 0.689 | 1.818 | 0.763 |
| 0.5-0.9 | 1230725.000 | 0.354 | 1.488 | 0.241 |
| 0.9-0.95 | 403078.000 | 0.110 | 0.519 | 0.072 |
| 0.95-0.99 | 748804.000 | 0.039 | 0.176 | 0.024 |
| >=0.99 | 1193305.000 | 0.003 | 0.025 | 0.001 |

