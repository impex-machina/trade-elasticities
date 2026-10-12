# Release gate (v0101): baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds -> baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds

Stage 1 `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`; rules: edge fallback, pole fallback (c = 1). Generated 2026-10-12 19:18 EDT.

## Rows and schema

- old: 6,892,008 rows (6,801,807 published), 22 columns; new: 6,892,008 rows (6,801,807 published), 23 columns; published change +0.00%.

## Sigma

- fallback sigma 2.4728 on 41.0% of published rows (old table: 2.4728 on 41.0%).
- published rows by source: estimated 4,016,300, fallback_no_estimate   734,207, fallback_sigma_edge   299,337, fallback_sigma_pole 1,751,963.

## Headline (published rows)

| | old | new |
|---|---|---|
| gamma median | 0.8064 | 0.8064 |
| opt_tariff median | 0.8687 | 0.8687 |
| sigma median | 2.4728 | 2.4728 |
| optimizer non-converged (tier < 3) | 0.42% | 0.42% |
| Tier 3 | 26.4% | 26.4% |
| sigma_robust TRUE | 24.2% | 24.2% |

## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by sigma source

| source | rows | p50 | p90 | p99 | below 1e-2 |
|---|---|---|---|---|---|
| estimated | 2,968,424 | 0.00e+00 | 0.000 | 0.000 | 100.0% |
| fallback_no_estimate |   486,937 | 0.00e+00 | 0.000 | 0.000 | 100.0% |
| fallback_sigma_edge |   204,036 | 0.00e+00 | 0.000 | 0.000 | 100.0% |
| fallback_sigma_pole | 1,280,596 | 0.00e+00 | 0.000 | 0.000 | 100.0% |

## Result

**PASS**
