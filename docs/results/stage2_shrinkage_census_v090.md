# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (6,806,221 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-10-10 03:06:19 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,986,810; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.198 | 0.569 | 0.895 | 0.989 | 0.999 |
| implied data share | 0.001 | 0.011 | 0.105 | 0.431 | 0.802 |

Mean shrink_wt 0.745; share > 0.9: 0.493, > 0.95: 0.405, > 0.99: 0.246. Implied data share: mean 0.255, trade-weighted 0.274 (trade-weighted 1 - s: 0.274).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 196003.000 | 0.551 | 0.449 | 0.299 |
| 1.000 | 4606261.000 | 0.905 | 0.095 | 0.264 |
| 2.000 | 13541.000 | 0.995 | 0.005 | 0.399 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 201188.000 | 0.580 | 0.420 | 0.322 |
| 2-3 | 388127.000 | 0.582 | 0.418 | 0.282 |
| 4-10 | 1090162.000 | 0.735 | 0.265 | 0.244 |
| >10 | 3136328.000 | 0.957 | 0.043 | 0.189 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4986810 | 0.885 | 0.174 | 0.154 | 0.672 |
| trade-weighted | 4986810 | 1.393 | 0.325 | 0.222 | 0.453 |
| tier 1 only | 4767358 | 0.846 | 0.182 | 0.162 | 0.656 |
| prior (sanity) | 4986810 | 0.167 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.003 | 0.017 | 0.131 | 0.599 | 1.406 |
| dev signed | -1.059 | -0.255 | -0.002 | 0.055 | 0.492 |
| |dev|, reference rows | 0.081 | 0.262 | 0.692 | 1.356 | 2.094 |

Share within 1%: 0.198, within 5%: 0.371, within 20%: 0.564; trade-weighted mean |dev| 0.640; reference rows within 1%: 0.016 (n = 204651).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 204651.000 | 0.692 | 2.094 | 0.068 |
| 1.000 | 4767358.000 | 0.118 | 1.352 | 0.383 |
| 2.000 | 14801.000 | 0.024 | 0.793 | 0.605 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.189 | 0.393 | 0.697 | 1.070 | 1.462 |

Across-good sd of ln prior: 0.431; sd of log gamma over all estimated rows: 0.941; median within-cell sd / prior sd: 1.615 (n cells = 209,594).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.045 | 0.134 | 0.344 | 0.701 | 1.176 |

Cells: 210,095; within 5%: 0.110; within 20%: 0.341.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 1042174.000 | 0.726 | 1.916 | 0.778 |
| 0.5-0.9 | 1397518.000 | 0.379 | 1.750 | 0.247 |
| 0.9-0.95 | 426837.000 | 0.113 | 0.638 | 0.072 |
| 0.95-0.99 | 764633.000 | 0.040 | 0.194 | 0.024 |
| >=0.99 | 1184643.000 | 0.004 | 0.031 | 0.001 |

