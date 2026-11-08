# Release gate (v0120): baci_hs92_v202601_elast_country_hs4_fixed_sigma_pass3.rds -> baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`; rules: edge fallback, pole fallback (c = 1). Generated 2026-11-07 21:14 EST.

## Rows and schema

- old: 6,892,008 rows (6,801,742 published), 24 columns; new: 6,892,008 rows (6,829,595 published), 28 columns; published change +0.41%.

## Sigma (the update, patch 0152-0155)

- update pass 1: 211,313 cells profiled, 199,857 updated, 61 at the floor, 11395 at the cap; level sigma 2.6779; B 0.146, b_full 0.2547993.
- published rows by source: estimated     4,646, fallback_no_estimate    49,508, fallback_sigma_edge     2,928, fallback_sigma_pole     3,635, updated_import_shrunk 6,621,807, updated_level   147,071.
- published rows by Stage-1 source: estimated 4,058,156, fallback_no_estimate   729,541, fallback_sigma_edge   296,977, fallback_sigma_pole 1,744,921.
- old table: fallback sigma 2.4728 on 41.0% of published rows.

## Headline (published rows)

| | old | new |
|---|---|---|
| gamma median | 0.8044 | 0.8219 |
| opt_tariff median | 0.8523 | 0.8976 |
| sigma median | 2.4728 | 2.6636 |
| optimizer non-converged (directly estimated rows) | 0.72% | 0.18% |
| optimizer non-converged cells | 1,775 | 646 |
| imputed reference rows (all-Tier-3 cells; share of tier < 3 rows) | 0.42% | 0.40% |
| Tier 3 | 26.4% | 26.4% |
| sigma_robust TRUE | 24.2% | 0.0% |

## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by sigma source

| source | rows | p50 | p90 | p99 | below 1e-2 |
|---|---|---|---|---|---|
| updated_import_shrunk | 4,821,629 | 3.56e-02 | 0.483 | 1.740 | 32.3% |
| updated_level |    85,461 | 7.41e-02 | 0.912 | 2.680 | 22.6% |

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
