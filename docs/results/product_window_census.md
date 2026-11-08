# Product-level table: independent periods (patch 0130)

Windows `..\te_su_window2\early` (1995-2009) and `..\te_su_window2\late` (2010-2024): each period's own Stage 1 (patch 0119), Stage 2a and Stage 2b; rev 2eae5c4, 2026-11-08 01:47:27 EST.

Checks: the two windows' Stage-1 tables differ: TRUE; each window's Stage-2b goods are among its Stage-1 goods: TRUE / TRUE; same goods in both windows: TRUE.

| product median | products | Spearman [95% interval over products] | level gap p50 / p90 |
|---|---|---|---|
| gamma_median | 25 | 0.63 [0.28, 0.81] | 26.1% / 95.7% |
| opt_tariff_median | 25 | 0.73 [0.45, 0.88] | 18.4% / 60.8% |

## Did the earlier halves share their inputs?

| run A | run B | Stage-1 table | Stage-2a table |
|---|---|---|---|
| (none given) | | | |

**Reading (fixed in patch 0130): reproduces.** Reproduces if both correlations are at least 0.50; does not reproduce if both are below 0.30; otherwise partial. The windows differ in time as well as in data, so drift lowers the correlation too.
