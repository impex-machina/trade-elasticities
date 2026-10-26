# A hierarchical sigma fallback, sized (v0113)

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`, Stage 2b `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`; rules as shipped (edge and pole fallback, c = 1); a level is used when it holds >= 3 clean cells. Rev 71c608e, 2026-10-26 19:46:52 EDT.

- Clean cells: 113,706; the global fallback (their median) 2.4728.
- Share of the variance of ln(sigma - 1) across clean cells explained by the good: 5.7%; by region x good: 23.3%.
- Good-level medians (goods with >= 3 clean cells): p10 2.007, p25 2.227, median 2.463, p75 2.766, p90 3.116.
- Leave-one-out on the estimated cells, median |ln((sigma_pred - 1)/(sigma - 1))|: global 0.693, good 0.674, ladder 0.699 (-1% lower than global).
- Fallback cells in the published table: 118,547 (2,785,416 rows). The ladder resolves them at global      29, good  13,712, region_good 104,806.
- Their ladder sigma: p10 1.869, p25 2.113, median 2.443, p75 2.893, p90 3.532; it moves (sigma - 1) by more than 25% from the global value on 67,315 cells (1,551,063 rows).

| sigma_source | cells | rows | ladder median | median move (log sigma - 1) | cells moved > 25% | rows moved > 25% |
|---|---|---|---|---|---|---|
| fallback_no_estimate | 49,357 |   734,198 | 2.431 | 0.271 | 28,139 | 409,923 |
| fallback_sigma_edge | 13,804 |   299,320 | 2.439 | 0.269 |  7,840 | 166,342 |
| fallback_sigma_pole | 55,386 | 1,751,898 | 2.456 | 0.262 | 31,336 | 974,798 |

Reading rule (fixed before the run): docs/methodology/stage2_country.md, "A hierarchical sigma fallback".

