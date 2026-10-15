# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,801,742 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-14 16:49:45 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,982,259; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 1 - s

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.316 | 0.663 | 0.924 | 0.992 | 0.999 |
| implied data share | 0.001 | 0.008 | 0.076 | 0.337 | 0.684 |

Mean shrink_wt 0.787; share > 0.9: 0.540, > 0.95: 0.443, > 0.99: 0.267. Implied data share: mean 0.213, trade-weighted 0.236 (trade-weighted 1 - s: 0.236).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 197710.000 | 0.631 | 0.369 | 0.255 |
| 1.000 | 4728121.000 | 0.932 | 0.068 | 0.229 |
| 2.000 | 13968.000 | 0.996 | 0.004 | 0.392 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 205752.000 | 0.636 | 0.364 | 0.279 |
| 2-3 | 396546.000 | 0.628 | 0.372 | 0.251 |
| 4-10 | 1118019.000 | 0.777 | 0.223 | 0.208 |
| >10 | 3219482.000 | 0.970 | 0.030 | 0.146 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4982259 | 0.583 | 0.300 | 0.108 | 0.592 |
| trade-weighted | 4982259 | 0.995 | 0.447 | 0.172 | 0.382 |
| tier 1 only | 4765628 | 0.552 | 0.318 | 0.116 | 0.566 |
| prior (sanity) | 4982259 | 0.197 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.002 | 0.013 | 0.094 | 0.448 | 1.095 |
| dev signed | -0.807 | -0.180 | -0.002 | 0.040 | 0.375 |
| |dev|, reference rows | 0.070 | 0.227 | 0.610 | 1.196 | 1.797 |

Share within 1%: 0.225, within 5%: 0.411, within 20%: 0.616; trade-weighted mean |dev| 0.487; reference rows within 1%: 0.018 (n = 201870).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 201870.000 | 0.610 | 1.797 | 0.076 |
| 1.000 | 4765628.000 | 0.085 | 1.038 | 0.425 |
| 2.000 | 14761.000 | 0.016 | 0.578 | 0.658 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.184 | 0.355 | 0.594 | 0.868 | 1.155 |

Across-good sd of ln prior: 0.484; sd of log gamma over all estimated rows: 0.764; median within-cell sd / prior sd: 1.227 (n cells = 209,101).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.039 | 0.118 | 0.300 | 0.616 | 1.039 |

Cells: 210,098; within 5%: 0.122; within 20%: 0.377.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 831728.000 | 0.714 | 1.788 | 0.734 |
| 0.5-0.9 | 1439356.000 | 0.344 | 1.354 | 0.240 |
| 0.9-0.95 | 479791.000 | 0.110 | 0.498 | 0.072 |
| 0.95-0.99 | 868891.000 | 0.039 | 0.176 | 0.024 |
| >=0.99 | 1320033.000 | 0.004 | 0.029 | 0.001 |

