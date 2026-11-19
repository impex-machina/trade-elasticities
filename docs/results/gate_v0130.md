# Release gate (v0130): baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds -> baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`; rules: edge fallback, pole fallback (c = 1). Generated 2026-11-19 01:02 EST.

## Rows and schema

- old: 6,892,008 rows (6,829,595 published), 28 columns; new: 6,892,008 rows (6,841,382 published), 28 columns; published change +0.17%.

## Sigma (the update, patch 0152-0155)

- update pass 1: 211,313 cells profiled, 199,888 updated, 42 at the floor, 11383 at the cap; level sigma 2.6779; B 0.146, b_full 0.2547993.
- published rows by source: fallback_no_estimate    49,508, fallback_sigma_edge     2,928, fallback_sigma_pole     3,635, updated_import_shrunk 6,630,683, updated_level   154,628.
- published rows by Stage-1 source: estimated 4,066,955, fallback_no_estimate   730,779, fallback_sigma_edge   297,659, fallback_sigma_pole 1,745,989.
- old table: fallback sigma 2.6779 on 3.0% of published rows.

## Headline (published rows)

| | old | new |
|---|---|---|
| gamma median | 0.8219 | 0.8262 |
| opt_tariff median | 0.8976 | 0.8983 |
| sigma median | 2.6636 | 2.6635 |
| optimizer non-converged (directly estimated rows) | 0.18% | 0.19% |
| optimizer non-converged cells | 646 | 678 |
| imputed reference rows (all-Tier-3 cells; share of tier < 3 rows) | 0.40% | 0.42% |
| Tier 3 | 26.4% | 26.4% |
| sigma_robust TRUE | 0.0% | 0.0% |

## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by sigma source

| source | rows | p50 | p90 | p99 | below 1e-2 |
|---|---|---|---|---|---|
| updated_import_shrunk | 4,896,672 | 3.11e-03 | 0.033 | 0.275 | 74.3% |
| updated_level |    89,773 | 6.59e-03 | 0.089 | 0.794 | 58.1% |

## gamma_V pass log

        pass from_pass usable_rows tier1_rows abs_dlng_p50 abs_dlng_p90
       <int>     <int>       <int>      <int>        <num>        <num>
    1:     2         1     4943298    4700278 0.0015385016   0.06452659
    2:     3         2     4946753    4707236 0.0002061403   0.01250359
       abs_dlng_p99 abs_dlng_max share_lt_1e2
              <num>        <num>        <num>
    1:    0.6317554     6.161689    0.7232806
    2:    0.2218218     6.058366    0.8862451

## Result

**PASS**
