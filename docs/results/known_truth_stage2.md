# Known-truth recovery of the shipped pipeline (patch 0122)

Synthetic BACI worlds from `validation/synthetic_baci.R` (Soderbery's model, known sigma and gamma; 5 goods, 15 countries, years 1995:2024); seeds 20261015, 20261016, 20261017; shock scales 1, 3; rev 8fb8838, 2026-10-15 02:12:07 EDT.

Medians over seeds. Within-cell: estimated vs true ln gamma, each demeaned by (importer, good); cell level: across (importer, good) cells; sigma error: median |error| in ln(sigma - 1) of the sigma Stage 2 used.

| scale | arm | worlds | shrink wt | within r | within rank r | within sd ratio | cell mean ln gamma r | composite r | opt_tariff r | opt_tariff \|log err\| | sigma \|err\| |
|---|---|---|---|---|---|---|---|---|---|---|---|
| x1 | shipped | 3 | 0.999 | 0.047 | 0.077 | 0.022 | 0.041 | 0.472 | 0.114 | 0.428 | 0.219 |
| x1 | lambda0 | 3 | 0.000 | 0.171 | 0.145 | 8.646 | -0.009 | 0.304 | 0.127 | 0.837 | 0.219 |
| x1 | truesigma | 3 | 0.999 | 0.097 | 0.112 | 0.021 | 0.017 | 0.741 | 0.148 | 0.382 | 0.000 |
| x1 | truesigma0 | 3 | 0.000 | 0.207 | 0.205 | 8.380 | 0.026 | 0.487 | 0.187 | 0.882 | 0.000 |
| x1 | sigma_eb | 3 | 0.999 | 0.067 | 0.067 | 0.018 | 0.028 | 0.387 | 0.139 | 0.378 | 0.160 |
| x3 | shipped | 3 | 0.968 | 0.093 | 0.171 | 0.441 | -0.048 | 0.517 | 0.125 | 0.533 | 0.187 |
| x3 | lambda0 | 3 | 0.000 | 0.196 | 0.185 | 10.608 | 0.096 | 0.401 | 0.102 | 1.049 | 0.187 |
| x3 | truesigma | 3 | 0.958 | 0.123 | 0.176 | 0.423 | 0.003 | 0.880 | 0.103 | 0.483 | 0.000 |
| x3 | truesigma0 | 3 | 0.000 | 0.181 | 0.164 | 10.530 | 0.074 | 0.470 | 0.042 | 0.992 | 0.000 |
| x3 | sigma_eb | 3 | 0.970 | 0.084 | 0.170 | 0.400 | 0.024 | 0.553 | 0.129 | 0.467 | 0.182 |

## Sigma without Stage 2 (every true cell)

| seed | scale | cells | raw estimates | published rule | EB posterior | EB tau^2 | EB weight (median) | fallback cells |
|---|---|---|---|---|---|---|---|---|
| 20261015 | x1 | 75 | 0.257 | 0.228 | 0.168 | 0.059 | 0.404 | 0.160 |
| 20261015 | x3 | 75 | 0.199 | 0.187 | 0.178 | 0.066 | 0.543 | 0.107 |
| 20261016 | x1 | 75 | 0.271 | 0.235 | 0.262 | 0.040 | 0.317 | 0.093 |
| 20261016 | x3 | 75 | 0.291 | 0.251 | 0.237 | 0.047 | 0.338 | 0.133 |
| 20261017 | x1 | 75 | 0.206 | 0.164 | 0.157 | 0.037 | 0.243 | 0.227 |
| 20261017 | x3 | 75 | 0.186 | 0.159 | 0.134 | 0.077 | 0.535 | 0.200 |

## Readings (rules fixed in patch 0122; see the script header)

- **R1 within-cell gamma: not recovered.** Shipped within-cell r by scale: x1 0.047, x3 0.093; true sigma at lambda 0: x1 0.207, x3 0.181.
- **R2 cell-level opt_tariff: weak.** Shipped correlation of ln opt_tariff with the truth by scale: x1 0.114, x3 0.125.
- **R3 sigma EB: closed at known truth.** Sigma error at least 10% below the published rule's in 2 of 6 worlds; opt_tariff |log err| shipped 0.440 vs sigma_eb 0.402.

A synthetic world satisfies every assumption the estimator makes and has no unit-value measurement error: the most favourable case, not a calibration to BACI.
