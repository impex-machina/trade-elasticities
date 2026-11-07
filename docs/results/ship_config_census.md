# Ship-config census (patch 0155)

Base `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (current defaults) against ship `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (configuration as it will ship), published rows.

| table | rows | cells | sigma q25/50/75 | gamma q25/50/75 | opt_tariff q25/50/75 | fallback cells | sigma_robust share | Tier-3 share |
|---|---|---|---|---|---|---|---|---|
| base | 151773 | 4863 | 2.426 / 2.478 / 2.591 | 0.511 / 0.645 / 0.980 | 0.460 / 0.666 / 1.001 | 2328 | 0.267 | 0.255 |
| ship | 152277 | 4847 | 2.570 / 2.687 / 2.836 | 0.532 / 0.689 / 0.986 | 0.507 / 0.692 / 1.023 | 356 | 0.000 | 0.255 |

Cell by cell: 4825 common cells; sigma moved in 99.7% (median |d ln(sigma-1)| among moved 0.246; r 0.287); opt_tariff moved by > 1% in 90.7% of cells (median |d ln tau| 0.0887); gamma moved by > 1% in 49.2% of 150828 common rows (median |d ln gamma| 0.0092, p90 0.3459).

sigma_source (published rows):

| sigma_source | base | ship |
|---|---|---|
| estimated | 95846 | 75 |
| fallback_no_estimate | 12202 | 911 |
| fallback_sigma_edge | 5632 | 31 |
| fallback_sigma_pole | 38093 | 56 |
| updated_import_shrunk | 0 | 149032 |
| updated_level | 0 | 2172 |
