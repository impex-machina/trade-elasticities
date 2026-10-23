# Known-truth recovery of the shipped pipeline (patch 0133)

Synthetic BACI worlds from `validation/synthetic_baci.R` (Soderbery's model, known sigma and gamma; 12 goods, 15 countries, years 1995:2024); seeds 20261015, 20261016, 20261017; shock scales 1, 3; rev 236c7e6, 2026-10-22 20:36:59 EDT.

## Structured worlds (patch 0123)

ln gamma carries a good effect, or a good and an importer effect (s.d.): `good_importer` (between goods 0.7, between importers 0.5, within 0.35). Sigma, shocks and trade pattern as in the unstructured world of the same seed. Medians over seeds.

| structure | scale | arm | worlds | within-cell r | between-good gamma r | between-good tariff r | within-good gamma r | within-good gamma sd ratio | within-good tariff r | cell opt_tariff r | composite r |
|---|---|---|---|---|---|---|---|---|---|---|---|
| good_importer | x1 | shipped | 3 | 0.027 | 0.816 | 0.840 | 0.157 | 0.019 | 0.100 | 0.670 | 0.547 |
| good_importer | x1 | half_a_t1 | 3 | 0.113 | 0.856 | 0.893 | 0.408 | 0.779 | 0.266 | 0.636 | 0.589 |
| good_importer | x1 | half_b_t1 | 3 | 0.077 | 0.847 | 0.885 | 0.332 | 0.727 | 0.275 | 0.643 | 0.602 |
| good_importer | x3 | shipped | 3 | 0.074 | 0.928 | 0.889 | 0.234 | 0.213 | 0.135 | 0.734 | 0.641 |
| good_importer | x3 | half_a_t1 | 3 | 0.109 | 0.950 | 0.908 | 0.465 | 0.867 | 0.311 | 0.597 | 0.661 |
| good_importer | x3 | half_b_t1 | 3 | 0.059 | 0.927 | 0.901 | 0.300 | 0.845 | 0.157 | 0.521 | 0.629 |

## Reading R4 (rules fixed in patch 0123; see the script header)

- **R4a between goods: not measured.** Between-good correlation of the log median gamma by scale: ; of the mean ln opt_tariff: .
- **R4b within goods, across importers: partial.** Within-good correlation of the cell mean ln gamma by scale: x1 0.157, x3 0.234; s.d. ratio: x1 0.019, x3 0.213; within-good correlation of ln opt_tariff: x1 0.100, x3 0.135.
- **Good-level reading: no.**

## Reading R6: the empirical-Bayes tau^2 (patch 0133; good_importer worlds)

| world | rows in both halves | tau2_eb (2.5% trim) | untrimmed | Spearman of the deviations between halves | true variance of ln gamma - ln prior | exporter-product effects: split-half r | against the truth r |
|---|---|---|---|---|---|---|---|
| w20261015_x1_good_importer | 1,826 | 0.406 | 0.834 | 0.127 | 0.417 | 0.219 | -0.007 |
| w20261015_x3_good_importer | 1,814 | 0.609 | 1.100 | 0.133 | 0.352 | 0.332 | 0.025 |
| w20261016_x1_good_importer | 1,842 | 0.539 | 1.029 | 0.141 | 0.394 | 0.240 | 0.051 |
| w20261016_x3_good_importer | 1,817 | 0.532 | 0.894 | 0.126 | 0.358 | 0.287 | 0.093 |
| w20261017_x1_good_importer | 1,815 | 0.440 | 0.698 | 0.130 | 0.896 | 0.027 | 0.008 |
| w20261017_x3_good_importer | 1,830 | 0.466 | 0.776 | 0.109 | 0.458 | 0.111 | 0.039 |

The worlds carry no exporter component: an exporter-product's true effect is the mean of its pair-specific deviations. Effects that reproduce across halves without tracking that truth come from the data or the estimator, not from gamma.

- **R6: EB validated** (100% of worlds in [0.05, 1]; rule fixed in patch 0133: at least five sixths).

A synthetic world satisfies every assumption the estimator makes and has no unit-value measurement error: the most favourable case, not a calibration to BACI.
