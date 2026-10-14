# Stage-2a rows handed to Stage 2b: all vs published (patch 0110)

Table: `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds` (428,035 rows, sha256 28d670e68f13); generated 2026-10-13 19:38:12 EDT at rev 1e5d5ac.

Flagged (trimmed) rows in the table: 5,798 (gamma_hi 1834, gamma_lo 1873, sigma_lo 2091).
Rows behind the priors (directly estimated, gamma > 0): all 399,154, published 393,486.

| input | units | moved | missing in one | abs d ln |
|---|---|---|---|---|
| good-level prior | 1240 goods | 757 | 0 | p50 0.000123 / p90 0.0093 / p99 0.112 / max 0.447 |
| regional gamma_V | 25064 region x good | 2499 | 135 | p50 0 / p90 2.38e-05 / p99 0.398 / max 5.41 |

Starting values (init_from_regional()) move with the same rows and are not censused; they affect only the optimizer's path.
