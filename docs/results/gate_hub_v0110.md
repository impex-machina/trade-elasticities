# Release gate (hub_v0110): baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds -> baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`; rules: edge fallback, pole fallback (c = 1). Generated 2026-10-15 19:55 EDT.

## Rows and schema

- old: 6,892,008 rows (6,801,742 published), 23 columns; new: 6,892,008 rows (6,801,742 published), 23 columns; published change +0.00%.

## Sigma

- fallback sigma 2.4728 on 41.0% of published rows (old table: 2.4728 on 41.0%).
- published rows by source: estimated 4,016,326, fallback_no_estimate   734,198, fallback_sigma_edge   299,320, fallback_sigma_pole 1,751,898.

## Headline (published rows)

| | old | new |
|---|---|---|
| gamma median | 0.8044 | 0.8044 |
| opt_tariff median | 0.8523 | 0.8523 |
| sigma median | 2.4728 | 2.4728 |
| optimizer non-converged (directly estimated rows) | 0.72% | 0.72% |
| optimizer non-converged cells | 1,775 | 1,775 |
| imputed reference rows (all-Tier-3 cells; share of tier < 3 rows) | 0.42% | 0.42% |
| Tier 3 | 26.4% | 26.4% |
| sigma_robust TRUE | 24.2% | 24.2% |

## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by sigma source

| source | rows | p50 | p90 | p99 | below 1e-2 |
|---|---|---|---|---|---|
| estimated | 2,971,881 | 0.00e+00 | 0.000 | 0.000 | 100.0% |
| fallback_no_estimate |   487,933 | 0.00e+00 | 0.000 | 0.000 | 100.0% |
| fallback_sigma_edge |   204,628 | 0.00e+00 | 0.000 | 0.000 | 100.0% |
| fallback_sigma_pole | 1,281,992 | 0.00e+00 | 0.000 | 0.000 | 100.0% |

## Result

**PASS**
