# Stage-2b shrinkage census (patch 0067 input, F1 of fresh_eyes_review_20260924.md)

Inputs: `out_l00001.rds` (6,832,756 rows), `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds`. Generated 2026-09-25 17:58:49 EDT.

Directly estimated rows (tier 0/1/2, fitted): 5,011,193; goods with a Stage-2b prior: 1240.

## Q1 gamma_shrink_wt and the implied data share d = 2(1-s)/(2-s)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| gamma_shrink_wt | 0.000 | 0.004 | 0.106 | 0.818 | 0.983 |
| implied data share | 0.034 | 0.308 | 0.944 | 0.998 | 1.000 |

Mean shrink_wt 0.356; share > 0.9: 0.204, > 0.95: 0.157, > 0.99: 0.079. Implied data share: mean 0.691, trade-weighted 0.719 (trade-weighted 1 - s: 0.677).

By tier:

| tier | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 0.000 | 95844.000 | 0.018 | 0.991 | 0.791 |
| 1.000 | 1638793.000 | 0.112 | 0.940 | 0.691 |
| 2.000 | 6136.000 | 0.568 | 0.603 | 0.680 |

By within-cell trade rank of the exporter:

| rank_bin | n | shrink_wt_median | data_share_median | data_share_trade_weighted |
| --- | --- | --- | --- | --- |
| 1.000 | 103922.000 | 0.016 | 0.992 | 0.737 |
| 2-3 | 205597.000 | 0.024 | 0.988 | 0.696 |
| 4-10 | 500060.000 | 0.068 | 0.965 | 0.714 |
| >10 | 931194.000 | 0.169 | 0.908 | 0.726 |

## Q2 Variance decomposition of log gamma (estimated rows)

| sample | n | var(log gamma) | good | importer x good within good | exporter within cell |
|---|---|---|---|---|---|
| unweighted | 5011193 | 5.443 | 0.052 | 0.224 | 0.724 |
| trade-weighted | 5011193 | 4.849 | 0.123 | 0.321 | 0.556 |
| tier 1 only | 4794841 | 5.399 | 0.059 | 0.242 | 0.700 |
| prior (sanity) | 5011193 | 0.162 | 1.000 | 0.000 | 0.000 |

## Q3 Distance from the Stage-2b prior, |log gamma - ln prior|

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |dev|, all estimated | 0.012 | 0.046 | 0.228 | 1.071 | 3.429 |
| dev signed | -2.451 | -0.403 | -0.003 | 0.147 | 0.798 |
| |dev|, reference rows | 0.103 | 0.334 | 0.868 | 1.935 | 4.322 |

Share within 1%: 0.086, within 5%: 0.262, within 20%: 0.478; trade-weighted mean |dev| 0.940; reference rows within 1%: 0.011 (n = 201531).

| tier | n | abs_dev_median | abs_dev_p90 | share_within_5pct |
| --- | --- | --- | --- | --- |
| 0.000 | 201531.000 | 0.868 | 4.322 | 0.051 |
| 1.000 | 4794841.000 | 0.211 | 3.371 | 0.271 |
| 2.000 | 14821.000 | 0.238 | 3.266 | 0.256 |

## Q4 Within-cell dispersion vs across-good prior dispersion

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| within-cell sd(log gamma), cells with >= 2 estimated exporters | 0.263 | 0.980 | 2.037 | 3.127 | 4.369 |

Across-good sd of ln prior: 0.427; sd of log gamma over all estimated rows: 2.333; median within-cell sd / prior sd: 4.772 (n cells = 208,731).

## Q5 opt_tariff vs prior (cells)

| quantity | p10 | p25 | p50 | p75 | p90 |
|---|---|---|---|---|---|
| |log opt_tariff - ln prior| | 0.047 | 0.158 | 0.506 | 1.138 | 1.965 |

Cells: 210,229; within 5%: 0.106; within 20%: 0.290.

## Q6 |dev| by shrink_wt bin

| s_bin | n | abs_dev_median | abs_dev_p90 | data_share_median |
| --- | --- | --- | --- | --- |
| <0.5 | 1124807.000 | 0.890 | 2.863 | 0.995 |
| 0.5-0.9 | 260947.000 | 2.388 | 5.342 | 0.404 |
| 0.9-0.95 | 81252.000 | 3.887 | 6.298 | 0.134 |
| 0.95-0.99 | 135583.000 | 4.734 | 6.653 | 0.049 |
| >=0.99 | 138184.000 | 7.120 | 13.695 | 0.002 |

