# A hierarchical sigma fallback, sized (v0130)

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`, Stage 2b `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`; rules as shipped (edge and pole fallback, c = 1); a level is used when it holds >= 3 clean cells. Rev 215a579, 2026-11-19 01:07:30 EST.

- Clean cells: 113,706; the global fallback (their median) 2.4728.
- Share of the variance of ln(sigma - 1) across clean cells explained by the good: 5.7%; by region x good: 23.3%.
- Good-level medians (goods with >= 3 clean cells): p10 2.007, p25 2.227, median 2.463, p75 2.766, p90 3.116.
- Leave-one-out on the estimated cells, median |ln((sigma_pred - 1)/(sigma - 1))|: global 0.693, good 0.674, ladder 0.699 (-1% lower than global).
- Cells without a usable Stage-1 sigma in the published table (read from `sigma_source_stage1`): 118,527 (2,774,427 rows). The ladder resolves them at global      29, good  13,711, region_good 104,787.
- Their ladder sigma: p10 1.869, p25 2.113, median 2.443, p75 2.893, p90 3.532; it moves (sigma - 1) by more than 25% from the global value on 67,302 cells (1,544,946 rows).

| sigma_source | cells | rows | ladder median | median move (log sigma - 1) | cells moved > 25% | rows moved > 25% |
|---|---|---|---|---|---|---|
| fallback_no_estimate | 49,338 |   730,779 | 2.431 | 0.271 | 28,126 | 408,038 |
| fallback_sigma_edge | 13,804 |   297,659 | 2.439 | 0.269 |  7,840 | 165,419 |
| fallback_sigma_pole | 55,385 | 1,745,989 | 2.456 | 0.262 | 31,336 | 971,489 |

Reading rule (fixed before the run): docs/methodology/stage2_country.md, "A hierarchical sigma fallback".

