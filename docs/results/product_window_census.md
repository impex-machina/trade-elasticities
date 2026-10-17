# Product-level table: independent periods (patch 0130)

Windows `C:\Users\maxxj\te_m3\w0_stage2` (1995-2009) and `C:\Users\maxxj\te_m3\w1_stage2` (2010-2024): each period's own Stage 1 (patch 0119), Stage 2a and Stage 2b; rev cea2752, 2026-10-17 16:59:52 EDT.

Checks: the two windows' Stage-1 tables differ: TRUE; each window's Stage-2b goods are among its Stage-1 goods: TRUE / TRUE; same goods in both windows: TRUE.

| product median | products | Spearman [95% interval over products] | level gap p50 / p90 |
|---|---|---|---|
| gamma_median | 25 | 0.64 [0.30, 0.81] | 25.5% / 94.9% |
| opt_tariff_median | 25 | 0.76 [0.49, 0.90] | 16.0% / 56.4% |

## Did the earlier halves share their inputs?

| run A | run B | Stage-1 table | Stage-2a table |
|---|---|---|---|
| `C:\Users\maxxj\te_grid\v0110_cfg_odd` | `C:\Users\maxxj\te_grid\v0110_cfg_even` | shared | shared |
| `C:\Users\maxxj\te_grid\v0110_period_a` | `C:\Users\maxxj\te_grid\v0110_period_b` | shared | own |

**Reading (fixed in patch 0130): reproduces.** Reproduces if both correlations are at least 0.50; does not reproduce if both are below 0.30; otherwise partial. The windows differ in time as well as in data, so drift lowers the correlation too.
