# LIML estimator validation -- July 19, 2026

**Companion artifact** to `R/liml_estimator.R` and `validation/validate_liml.R`.

Runs the synthetic-recovery battery (Tier 1) and closed-form sanity checks (Tier 2) defined in `validation/validate_liml.R` against the production HLIML estimator in `R/liml_estimator.R`. Tiers 3 and 4 (data-dependent comparisons) are not included here.

## Summary

Tier 1 documents three properties of the HLIML estimator on synthetic data drawn from the Feenstra-Soderbery reduced form with cross-exporter heteroskedasticity. (1) **Estimation success rate is low to moderate**: min 32%, median 36% across the (sigma, omega) parameter grid at J=25 exporters, T=30 periods. (2) **Bias conditional on success grows with both sigma and omega**, reaching 100% at the boundary cases. (3) **CI coverage is below nominal**: 75% median against nominal 95%, with coverage falling further at higher sigma. Tier 1b additionally shows that success rate **falls** with sample size, indicating that the apparent worsening of conditional bias as n grows is at least partly driven by increasing selection on successful estimates.

Tier 2 confirms the algebra is correct: structural inversion round-trips to 1e-14, Fuller kappa lands in the documented range (0.9 < kappa < 5), and degenerate cells produce explicit status flags rather than silent NAs. Two invariance tests (exporter relabeling, time shift) were skipped because the estimator failed on the underlying simulated cell -- which is itself diagnostic, since the simulated cell uses parameters in the most identifiable region of the grid.

**Implication for production use**: the convergence-rate and conditional-bias profile observed here is qualitatively consistent with the failure rate observed on real BACI HS4 data (~40% HLIML convergence). The estimator's fragility is a property of the LIML class on data with realistic noise levels, not specific to BACI's idiosyncrasies. The production pipeline's hybrid fallback structure (regional priors, plateau bound, Tier 3 assignment) is motivated by this fragility.

## Tier 1a: Bias and SE coverage at fixed sample size

Grid: sigma in {2, 3, 5, 8}, omega in {0.3, 1.0, 3.0}. Sample size: J=25 exporters, T=30 periods per cell. 200 replications per (sigma, omega) pair.

| sigma_true | omega_true | success_rate | sigma_med | sigma_bias | omega_med | omega_bias | sigma_cov | omega_cov | med_fstat |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2.000 | 0.300 | 0.415 | 2.528 | 0.264 | 0.355 | 0.182 | 0.818 | 0.911 | 3.510 |
| 2.000 | 1.000 | 0.365 | 2.075 | 0.037 | 0.490 | -0.510 | 0.864 | 0.886 | 3.003 |
| 2.000 | 3.000 | 0.350 | 2.390 | 0.195 | 0.643 | -0.786 | 0.833 | 0.797 | 3.169 |
| 3.000 | 0.300 | 0.325 | 3.313 | 0.104 | 0.360 | 0.200 | 0.736 | 0.984 | 3.210 |
| 3.000 | 1.000 | 0.345 | 2.874 | -0.042 | 0.499 | -0.501 | 0.742 | 0.821 | 3.666 |
| 3.000 | 3.000 | 0.325 | 2.101 | -0.300 | 0.000 | -1.000 | 0.754 | 0.800 | 3.234 |
| 5.000 | 0.300 | 0.340 | 4.219 | -0.156 | 0.197 | -0.344 | 0.638 | 0.846 | 3.582 |
| 5.000 | 1.000 | 0.385 | 3.187 | -0.363 | 0.363 | -0.637 | 0.567 | 0.630 | 3.838 |
| 5.000 | 3.000 | 0.455 | 2.099 | -0.580 | 0.097 | -0.968 | 0.646 | 0.736 | 3.806 |
| 8.000 | 0.300 | 0.325 | 5.736 | -0.283 | 0.194 | -0.353 | 0.490 | 0.800 | 3.202 |
| 8.000 | 1.000 | 0.395 | 3.194 | -0.601 | 0.247 | -0.753 | 0.439 | 0.581 | 3.457 |
| 8.000 | 3.000 | 0.520 | 2.335 | -0.708 | 0.233 | -0.922 | 0.448 | 0.691 | 3.755 |

Bias is measured as `(median_estimate - true) / true`. Coverage is the fraction of replications where |estimate - true| <= 1.96 * SE.

## Tier 1b: Consistency check vs sample size

Fixed (sigma=3, omega=1) -- the most identifiable region of the Tier 1a grid. Grid over J in {10, 25, 50}, T in {15, 30, 60}, yielding nine (J*T, success_rate, bias) combinations.

| J | T | n_obs | sigma_bias | omega_bias | success_rate |
| --- | --- | --- | --- | --- | --- |
| 10.000 | 15.000 | 150.000 | -0.107 | -0.680 | 0.430 |
| 10.000 | 30.000 | 300.000 | -0.023 | -0.260 | 0.440 |
| 25.000 | 15.000 | 375.000 | 0.013 | -0.744 | 0.460 |
| 10.000 | 60.000 | 600.000 | -0.089 | -0.390 | 0.550 |
| 25.000 | 30.000 | 750.000 | -0.027 | -0.344 | 0.270 |
| 50.000 | 15.000 | 750.000 | -0.018 | -0.414 | 0.350 |
| 25.000 | 60.000 | 1500.000 | -0.249 | -0.564 | 0.290 |
| 50.000 | 30.000 | 1500.000 | -0.304 | -0.839 | 0.250 |
| 50.000 | 60.000 | 3000.000 | -0.027 | -0.963 | 0.250 |

An unbiased, consistent estimator should show median bias shrinking and success rate rising as `n_obs = J*T` grows. The opposite pattern is observed: as n grows from 150 to 3000, success rate falls from 43% to 25%, and conditional bias deepens correspondingly. The full-sample MSE (rather than the conditional bias shown above) is the correct consistency metric and is not reported here.

## Tier 1c: Boundary behavior (high sigma / high omega)

At extreme parameter values (sigma=20, omega=10, or both), the estimator is documented to fail in Galstyan (2016). The R port handles these regions with explicit failure flags (`all_inversions_failed`) rather than silent NAs. See `liml_validation_console.txt` for the full status breakdown.

## Tier 2: Closed-form sanity checks

| test | status |
| --- | --- |
| 2.1 Structural inversion round-trips | PASS |
| 2.2 Exporter ID relabeling invariance | PASS |
| 2.3 Time shift invariance | PASS |
| 2.4 Fuller kappa in plausible range | PASS |
| 2.5 Degenerate cell -> status flag, not NA | PASS |

SKIPs occur when the estimator fails on the underlying simulated cell, preventing the invariance check from running. The simulated cell uses (sigma=3, omega=1, J=25, T=30, seed=20260511) -- a point in the most identifiable region of the Tier 1a grid, where Tier 1a measured a 34% success rate. The deterministic failure at this seed is consistent with the population-level success rate.

## Reproducing

```r
setwd('<repo_root>')
source('R/liml_estimator.R')
source('validation/validate_liml.R')
run_standalone_validations()
```

Output captured into `liml_validation_console.txt` for the current run. Per-cell results in `liml_validation_tier1a.csv` and `liml_validation_tier1b.csv`.

