# Stage-1 routing A/B: Step 2 against the boundary search (patch 0129)

Cells routed through the Step-2 cascade whose boundary optimum is usable (both stored in the Stage-1 table; no re-estimation). 18 known-truth worlds under `C:\Users\maxxj\te_known_truth`; period windows `C:\Users\maxxj\te_m3\w0_1995_2009\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` / `C:\Users\maxxj\te_m3\w1_2010_2024\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`; shipped Stage 1 `data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`; rev d3c2fe0, 2026-10-17 15:13:51 EDT.

## A. Known truth (ln(sigma - 1) against the truth; Step 2 / boundary)

| scale | cells | bias | error (raw) | error (published) | boundary on the sigma cap |
|---|---|---|---|---|---|
| x1 | 121 | 0.325 / 0.102 | 0.325 / 0.365 | 0.241 / 0.361 | 4.1% |
| x3 | 134 | 0.282 / 0.145 | 0.312 / 0.368 | 0.197 / 0.320 | 7.5% |
| all | 255 | 0.311 / 0.121 | 0.313 / 0.367 | 0.222 / 0.331 | 5.9% |

## B. Real data: predicting the other period's estimate (median absolute error on ln(sigma - 1); Step 2 / boundary)

- 1995-2009 -> 2010-2024: 361 cells, 1.198 / 1.328
- 2010-2024 -> 1995-2009: 367 cells, 1.225 / 1.421

## C. The shipped Stage 1

- Step-2 cells: 45,305; with a usable boundary optimum: 23,592 (52.1%); their edges: omega_cap 15,303, omega_floor  6,420, sigma_cap  1,869.
- ln((sigma_bd - 1) / (sigma_step2 - 1)) on those cells: p10 -1.786, p50 0.000, p90 1.918.
- Fallback sigma (the clean-set median): 2.4728 now, 2.4859 after the switch.

**Reading (fixed in patch 0129): keep Step 2** (known-truth part FALSE, period part FALSE). Switch if, at every shock scale, the boundary sigma's raw error is at least 10% below Step 2's and its |bias| smaller, AND it predicts the other period no worse in both directions.
