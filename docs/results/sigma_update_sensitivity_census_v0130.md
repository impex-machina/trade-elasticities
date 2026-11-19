# The sigma update: profile method, gamma_V refresh, unit-value threshold (patch 0165)

Run `..\te_release\v0.13.0rc1`; rev 215a579, 2026-11-19 02:00:29 EST. Rules: the header of `analysis/sigma_update_sensitivity_census.R`, fixed before the numbers.

## 1. Closed-form profile against the grid

Not measured (the run was not made with `--stage2-sigma-profile both`).

## 2. One gamma_V refresh after the update

Refresh 1: 4,991,241 directly estimated rows: |d ln gamma| p50 6.68e-04, p90 2.57e-02, p99 2.88e-01; moved by more than 1%: 17.9% of rows; opt_tariff moved by more than 1% in 40.3% of 211,104 cells.

**Reading (the first refresh): ADOPT.**

The run made 2 refreshes; each step against the table before it:

| refresh | rows | p50 | p90 | p99 | rows moved > 1% | cells | opt_tariff moved > 1% |
|---|---|---|---|---|---|---|---|
| 1 | 4,991,241 | 6.68e-04 | 2.57e-02 | 2.88e-01 | 17.9% | 211,104 | 40.3% |
| 2 | 4,992,802 | 8.55e-05 | 4.13e-03 | 8.75e-02 | 5.8% | 211,113 | 13.7% |

**Reading (the second refresh, rule of patch 0167): TWO SHIP.** One ships if the second refresh moves fewer than 1% of rows and of cells' opt_tariff by more than 1%; two otherwise.

## 3. The unit-value threshold, gammas held

Reference: the run's own threshold (|d ln p| < 2). Cells 'ok' at both thresholds are compared on ln(sigma - 1).

| threshold | cells | ok | median sigma (ok) | level ln(sigma - 1) | vs reference: cells | median abs diff | Spearman | moved > 10% |
|---|---|---|---|---|---|---|---|---|
| 1.5 | 208374 | 194863 | 3.250 | 0.811 | 192729 | 0.195 | 0.745 | 67.3% |
| 2 | 211313 | 200886 | 2.735 | 0.551 | -- | -- | -- | -- |
| 3 | 214052 | 195205 | 2.479 | 0.392 | 190852 | 0.160 | 0.755 | 62.7% |
| off | 215900 | 179503 | 2.289 | 0.254 | 173951 | 0.307 | 0.603 | 75.4% |

**Reading: THRESHOLD-DEPENDENT.** Between 1.5 and 3: level gap 0.419, Spearman 0.580 on 184712 cells.

## 4. The final table by trim reason

| trim_reason | rows |
|---|---|
| published | 6,841,382 |
| gamma_hi |    25,313 |
| gamma_lo |    25,313 |
