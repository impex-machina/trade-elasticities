# The sigma update: profile method, gamma_V refresh, unit-value threshold (patch 0165)

Run `..\te_m0165\full`; rev b4bf94e, 2026-11-11 03:05:08 EST. Rules: the header of `analysis/sigma_update_sensitivity_census.R`, fixed before the numbers.

## 1. Closed-form profile against the grid

4,499 cells profiled; the two give the same status on 100.0%; on the 4,310 cells 'ok' under both, |d ln(sigma - 1)| p99 3.86e-08, max 6.76e-07; grid fallbacks 0.

| grid | closed form | cells |
|---|---|---|
| floor | ok | 1 |

**Reading: ADOPTABLE.**

## 2. One gamma_V refresh after the update

112,854 directly estimated rows: |d ln gamma| p50 4.72e-04, p90 1.88e-02, p99 2.30e-01; moved by more than 1%: 15.0% of rows; opt_tariff moved by more than 1% in 37.5% of 4,471 cells.

**Reading: ADOPT.**

## 3. The unit-value threshold, gammas held

Reference: the run's own threshold (|d ln p| < 2). Cells 'ok' at both thresholds are compared on ln(sigma - 1).

| threshold | cells | ok | median sigma (ok) | level ln(sigma - 1) | vs reference: cells | median abs diff | Spearman | moved > 10% |
|---|---|---|---|---|---|---|---|---|
| 1.5 | 4437 | 4200 | 3.215 | 0.795 | 4173 | 0.179 | 0.760 | 66.1% |
| 2 | 4499 | 4330 | 2.748 | 0.558 | -- | -- | -- | -- |
| 3 | 4556 | 4223 | 2.499 | 0.405 | 4145 | 0.156 | 0.767 | 63.1% |
| off | 4593 | 3930 | 2.286 | 0.251 | 3835 | 0.306 | 0.605 | 78.1% |

**Reading: THRESHOLD-DEPENDENT.** Between 1.5 and 3: level gap 0.391, Spearman 0.594 on 4022 cells.

## 4. The final table by trim reason

| trim_reason | rows |
|---|---|
| published | 152,283 |
| gamma_lo |     570 |
| gamma_hi |     570 |
| sigma_lo |     278 |
