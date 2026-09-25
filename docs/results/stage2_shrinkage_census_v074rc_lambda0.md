# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `out_l0.rds` (6,744,736 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-25 17:59:30 EDT.

Directly estimated rows (tier 0/1/2, fitted): 4,996,055; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| implied data share | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |

Mean shrink_wt 0.000; share > 0.9: 0.000, > 0.95: 0.000, > 0.99: 0.000. Implied data share: mean 1.000, trade-weighted 1.000 (trade-weighted 1 - s: 1.000).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 115292.000 | 0.000 | 1.000 | 1.000 |
| 1.000 | 1760159.000 | 0.000 | 1.000 | 1.000 |
| 2.000 | 6614.000 | 0.000 | 1.000 | 1.000 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 121806.000 | 0.000 | 1.000 | 1.000 |
| 2-3 | 241166.000 | 0.000 | 1.000 | 1.000 |
| 4-10 | 618847.000 | 0.000 | 1.000 | 1.000 |
| >10 | 900246.000 | 0.000 | 1.000 | 1.000 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 4996055 | 26.877 | 0.034 | 0.156 | 0.810 |
| trade-weighted | 4996055 | 17.453 | 0.083 | 0.327 | 0.590 |
| tier 1 only | 4778634 | 26.443 | 0.041 | 0.173 | 0.786 |
| prior (sanity) | 4996055 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.012 | 0.048 | 0.271 | 2.191 | 12.525 |
| dev signed | -6.380 | -0.443 | 0.002 | 0.187 | 4.110 |
| |dev|, reference rows | 0.098 | 0.338 | 1.044 | 7.191 | 11.310 |

Share within 1%: 0.083, within 5%: 0.255, within 20%: 0.457; trade-weighted mean |dev| 1.767; reference rows within 1%: 0.011 (n = 202678).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 202678.000 | 1.044 | 11.310 | 0.053 |
| 1.000 | 4778634.000 | 0.248 | 12.678 | 0.264 |
| 2.000 | 14743.000 | 0.480 | 13.172 | 0.201 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.234 | 0.977 | 5.682 | 7.828 | 9.842 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 5.184; median within-cell sd / prior sd: 13.313 (n cells = 207,523).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.044 | 0.161 | 0.555 | 1.285 | 2.199 |

Cells: 209,380; within 5%: 0.110; within 20%: 0.285.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 1882065.000 | 5.080 | 13.488 | 1.000 |

