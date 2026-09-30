# Stage-2b priors: Stage-2a rows behind the medians (patch 0079 census)

Table: `data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds` (rev 588d198, 2026-09-29 22:15:09 EDT).

## What the v0.8.2 medians ran over

- 422,418 Stage-2a rows with gamma > 0; 393,668 (93.2%) directly estimated, 28,750 imputed (Tier 3 at the Stage-1 prior, or an all-Tier-3 early return).
- 1240 of 1240 goods carry at least one imputed row; 0 goods have no estimated row at all (their prior is the Stage-1 prior under either rule).

| tier | rows | share | imputed (convergence -1) |
|---|---|---|---|
| 0 |  24,766 | 5.9% |    272 |
| 1 | 368,678 | 87.3% |      0 |
| 2 |     496 | 0.1% |      0 |
| 3 |  28,478 | 6.7% | 28,478 |

## Good-level prior ln_gamma_prior: estimated-only minus all-rows

- Median prior gamma: 0.647 (all rows) vs 0.644 (estimated rows).
- |d ln prior| quantiles p50 / p90 / p95: 0.003 / 0.030 / 0.062; identical on 0.3% of goods; > 5% on 6.3%; > 20% on 1.5%.
- Signed d ln prior p10 / p50 / p90: -0.013 / 0.001 / 0.018.

## Reference-destination gamma_V (region x good medians)

- 25,212 (region, good) cells; median 0.638 (all) vs 0.635 (estimated); |d ln| p50 / p90: 0.001 / 0.135; identical on 40.6%; > 5% on 18.4%; > 20% on 7.2%; 280 cells have no estimated row.

## Reading

The prior is a median, so it moves only where imputed rows are numerous enough to cross it; the quantiles above say how often that happens. A shift of a few percent in ln prior is small beside the within-cell dispersion Stage 2b estimates around it, but it is a systematic pull toward the Stage-1 prior, and `--stage2b-prior-source estimated` removes it at no cost. The decision rule for the flip: if |d ln prior| > 5% on more than a handful of goods, ship `estimated` at the next data release (a Stage 2b-only rerun; Stage 2a and Stage 1 are unchanged).
