# Known-truth recovery of the shipped pipeline (patch 0123)

Synthetic BACI worlds from `validation/synthetic_baci.R` (Soderbery's model, known sigma and gamma; 12 goods, 15 countries, years 1995:2024); seeds 20261015, 20261016, 20261017; shock scales 1, 3; rev 4ab7935, 2026-10-15 10:08:45 EDT.

## Structured worlds (patch 0123)

ln gamma carries a good effect, or a good and an importer effect (s.d.): `good` (between goods 0.7, between importers 0, within 0.35); `good_importer` (between goods 0.7, between importers 0.5, within 0.35). Sigma, shocks and trade pattern as in the unstructured world of the same seed. Medians over seeds.

| structure | scale | arm | worlds | within-cell r | between-good gamma r | between-good tariff r | within-good gamma r | within-good gamma sd ratio | within-good tariff r | cell opt_tariff r | composite r |
|---|---|---|---|---|---|---|---|---|---|---|---|
| good | x1 | shipped | 3 | 0.039 | 0.878 | 0.894 | 0.042 | 0.047 | 0.065 | 0.877 | 0.712 |
| good | x3 | shipped | 3 | 0.051 | 0.905 | 0.894 | 0.032 | 0.820 | -0.040 | 0.814 | 0.709 |
| good_importer | x1 | shipped | 3 | 0.027 | 0.816 | 0.840 | 0.157 | 0.019 | 0.100 | 0.670 | 0.547 |
| good_importer | x3 | shipped | 3 | 0.074 | 0.928 | 0.889 | 0.234 | 0.213 | 0.135 | 0.734 | 0.641 |

## Reading R4 (rules fixed in patch 0123; see the script header)

- **R4a between goods: recovered.** Between-good correlation of the log median gamma by scale: x1 0.878, x3 0.905; of the mean ln opt_tariff: x1 0.894, x3 0.894.
- **R4b within goods, across importers: partial.** Within-good correlation of the cell mean ln gamma by scale: x1 0.157, x3 0.234; s.d. ratio: x1 0.019, x3 0.213; within-good correlation of ln opt_tariff: x1 0.100, x3 0.135.
- **Good-level reading: no.**

A synthetic world satisfies every assumption the estimator makes and has no unit-value measurement error: the most favourable case, not a calibration to BACI.
