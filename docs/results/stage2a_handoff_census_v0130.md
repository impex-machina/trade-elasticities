# Stage-2a rows handed to Stage 2b: all vs published (patch 0110)

Table: `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds` (428,035 rows, sha256 e2f958608e09); generated 2026-11-19 01:08:12 EST at rev 215a579.

Flagged (trimmed) rows in the table: 3,992 (gamma_hi 1996, gamma_lo 1996).
Rows behind the priors (directly estimated, gamma > 0): all 399,154, published 395,162.

| input | units | moved | missing in one | abs d ln |
|---|---|---|---|---|
| good-level prior | 1240 goods | 708 | 0 | p50 4.31e-05 / p90 0.00667 / p99 0.0926 / max 0.302 |
| regional gamma_V | 25064 region x good | 2754 | 8 | p50 0 / p90 0.00161 / p99 0.331 / max 4.98 |

Starting values (init_from_regional()) move with the same rows and are not censused; they affect only the optimizer's path.
