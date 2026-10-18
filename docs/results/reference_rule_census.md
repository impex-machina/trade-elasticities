# Stage-1 reference rule: levels against stable, on the period split (patch 0132)

2% product subsample; Stage 1 on 1995-2009 and 2010-2024 under each rule; 2498 cells estimated in both periods under both rules; rev 9f55380, 2026-10-17 23:10:55 EDT.

| rule | sigma: median abs. difference in ln(sigma - 1) between periods | sigma: Spearman between periods | product prior: Spearman between periods | products |
|---|---|---|---|---|
| levels | 1.230 | 0.022 | 0.641 | 25 |
| stable | 1.224 | 0.032 | 0.638 | 25 |

**Reading (fixed in patch 0132): closed.** Stable helps if its median difference is at least 5% below the levels rule's and its product-prior correlation is no more than 0.05 lower.
