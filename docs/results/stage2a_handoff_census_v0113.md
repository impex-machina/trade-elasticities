# Stage-2a rows handed to Stage 2b: all vs published (patch 0110)

Table: `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds` (428,035 rows, sha256 3318172bb998); generated 2026-10-26 19:47:35 EDT at rev 71c608e.

Flagged (trimmed) rows in the table: 5,823 (gamma_hi 1862, gamma_lo 1870, sigma_lo 2091).
Rows behind the priors (directly estimated, gamma > 0): all 399,154, published 393,461.

| input | units | moved | missing in one | abs d ln |
|---|---|---|---|---|
| good-level prior | 1240 goods | 756 | 0 | p50 7.38e-05 / p90 0.00717 / p99 0.0894 / max 0.367 |
| regional gamma_V | 25064 region x good | 2501 | 137 | p50 0 / p90 3.7e-05 / p99 0.386 / max 7.02 |

Starting values (init_from_regional()) move with the same rows and are not censused; they affect only the optimizer's path.
