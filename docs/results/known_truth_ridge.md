# Known-truth recovery of the shipped pipeline (patch 0132)

Synthetic BACI worlds from `validation/synthetic_baci.R` (Soderbery's model, known sigma and gamma; 12 goods, 15 countries, years 1995:2024); seeds 20261015, 20261016, 20261017; shock scales 1, 3; rev 9f55380, 2026-10-17 19:30:15 EDT.

## Structured worlds (patch 0123)

ln gamma carries a good effect, or a good and an importer effect (s.d.): `good_importer` (between goods 0.7, between importers 0.5, within 0.35). Sigma, shocks and trade pattern as in the unstructured world of the same seed. Medians over seeds.

| structure | scale | arm | worlds | within-cell r | between-good gamma r | between-good tariff r | within-good gamma r | within-good gamma sd ratio | within-good tariff r | cell opt_tariff r | composite r |
|---|---|---|---|---|---|---|---|---|---|---|---|
| good_importer | x1 | shipped | 3 | 0.027 | 0.816 | 0.840 | 0.157 | 0.019 | 0.100 | 0.670 | 0.547 |
| good_importer | x1 | ridge_t002 | 3 | 0.037 | 0.822 | 0.858 | 0.446 | 0.184 | 0.285 | 0.705 | 0.556 |
| good_importer | x1 | ridge_t01 | 3 | 0.065 | 0.839 | 0.881 | 0.488 | 0.413 | 0.385 | 0.746 | 0.585 |
| good_importer | x1 | ridge_t05 | 3 | 0.089 | 0.886 | 0.905 | 0.551 | 0.693 | 0.399 | 0.720 | 0.621 |
| good_importer | x3 | shipped | 3 | 0.074 | 0.928 | 0.889 | 0.234 | 0.213 | 0.135 | 0.734 | 0.641 |
| good_importer | x3 | ridge_t002 | 3 | 0.066 | 0.927 | 0.924 | 0.342 | 0.102 | 0.235 | 0.769 | 0.633 |
| good_importer | x3 | ridge_t01 | 3 | 0.069 | 0.936 | 0.930 | 0.426 | 0.307 | 0.254 | 0.738 | 0.648 |
| good_importer | x3 | ridge_t05 | 3 | 0.093 | 0.960 | 0.925 | 0.458 | 0.710 | 0.279 | 0.635 | 0.677 |

## Reading R4 (rules fixed in patch 0123; see the script header)

- **R4a between goods: not measured.** Between-good correlation of the log median gamma by scale: ; of the mean ln opt_tariff: .
- **R4b within goods, across importers: partial.** Within-good correlation of the cell mean ln gamma by scale: x1 0.157, x3 0.234; s.d. ratio: x1 0.019, x3 0.213; within-good correlation of ln opt_tariff: x1 0.100, x3 0.135.
- **Good-level reading: no.**

## Reading R5: the precision-scaled ridge (patch 0132; good_importer worlds, shock scales in order)

| arm | within-good gamma r | within-cell r | between-good gamma r |
|---|---|---|---|
| shipped | 0.157 / 0.234 | 0.027 / 0.074 | 0.816 / 0.928 |
| ridge_t002 | 0.446 / 0.342 | 0.037 / 0.066 | 0.822 / 0.927 |
| ridge_t01 | 0.488 / 0.426 | 0.065 / 0.069 | 0.839 / 0.936 |
| ridge_t05 | 0.551 / 0.458 | 0.089 / 0.093 | 0.886 / 0.960 |

- **R5: calibrate on real data.** Calibrate on real data if some tau2 arm reaches a within-good gamma r >= 0.40 or a within-cell r >= 0.30 at every scale, keeping the between-good gamma r >= 0.80. Passing: ridge_t01, ridge_t05.

A synthetic world satisfies every assumption the estimator makes and has no unit-value measurement error: the most favourable case, not a calibration to BACI.
