# v0.3.0 -> v0.4.0 comparison

## What changed and why

v0.4.0 corrects a transcription error in this repository's implementation of
Soderbery (2018) Eq. (10): the coefficient on the fourth import-side moment
(Delta^k ln s x Delta ln p_k) was implemented as
gamma_j * gamma_k / ((1+gamma_j)(1+gamma_k)(sigma-1)) where the paper's
model requires gamma_j * (1+gamma_k) / (gamma_k (1+gamma_j)(sigma-1)). The
Stage-2 system was implemented from the paper text alone (no Soderbery 2018
replication code exists), and the error survived three releases because the
validation stack generated its Monte Carlo truth from the same production
residual routine -- self-consistent by construction.

The defect was found in a fresh-eyes audit (2026-07-17) and confirmed three
independent ways: hand derivation from Eqs (5)-(6), the footnote-12
homogeneity limit (the paper's form collapses exactly to Feenstra 1994; the
implemented form does not), and a visual read of the printed equation. A
structural-DGP simulation quantified it: at true parameters the implemented
equation left a population residual of roughly 55% of the outcome scale and
biased per-exporter gamma recovery by a median |51%|, compressing
cross-exporter heterogeneity toward the reference exporter's value, with
bias increasing in the reference exporter's price volatility. After the
one-coefficient correction the residual at truth is simulation noise
(~1e-3 of the outcome scale) and recovery bias is ~0.2%.

The release also: plugs a small Stage-2a prior leak (double-capped
adjust-4 cells contributed omega = 10 to good-level priors; ~0.6% of ok
cells); aligns the weak-identification screens with Grant & Soderbery
(2024) by publishing pass flags at their 25% maximal-size rule of thumb
and their Sargan / pass-both protocol alongside the stricter 10% headline
screen (with the Stock-Yogo values correctly relabeled as maximal SIZE);
adds a per-row effective-shrinkage diagnostic (`gamma_shrink_wt`); and --
the structural change to the validation stack -- adds a DGP-based pillar
(`validation/stage2_structural_dgp.R` + a fast testthat regression lock)
that simulates from Eqs (5)-(6) independently of all pipeline code, so this
class of defect can no longer land silently.

A second audit finding (F10) corrected the Pillar-2 validation harness
itself: its simulated reduced form carried a supply slope of 1/omega
instead of (1+omega)/omega, so the system it generated equaled the
correct structural model at omega = omega_0/(1-omega_0). The omega
truth-labels were therefore wrong, while the pseudo-true sigma equaled
the label (proven algebraically and by feeding analytic population
moments through the production estimator: pre-fix data labeled (3, 0.3)
returned exactly (3.0000, 0.4286)). The estimator and all published
estimates were never affected; the casualties were the tier1a/1b
omega-bias and omega-coverage columns, and the previously reported
"omega flooring at high true omega" pattern, retracted as a mislabeling
artifact (the old label grid {0.3, 1.0, 3.0} corresponded to structural
omega {0.429, +Inf, -1.5} -- two of three were boundary or inadmissible
systems).

## The A/B: what did not change

Stage 1's point path is untouched by every v0.4.0 patch. Under the frozen
production stack (same AMI, R 4.5.3, identical numeric package versions),
the v0.4.0 sigma table is bit-identical to v0.3.0 on all shared columns:

```
rows: 280649 vs 280649
bit-identical on shared cols: TRUE
new cols: stockyogo_pass_gs25, stockyogo_cv_gs25, sargan_pass, gs_pass_both
```

The four new Stage-1 columns (`stockyogo_pass_gs25`, `stockyogo_cv_gs25`,
`sargan_pass`, `gs_pass_both`) are diagnostics only. Every sigma-side delta
in the table below reads zero -- the Stage-1 block on every metric and both
composition tables, and the sigma rows embedded in the Stage-2b block --
as required; anything nonzero would have indicated a stack difference and
invalidated the comparison.

## Headline deltas

- gamma median: 0.680 -> 0.674; IQR [0.481, 0.976] -> [0.473, 0.968]
  (width 0.495 in both runs). Implied export-supply elasticity median
  1/gamma: 1.471 -> 1.485.
- Direction and dispersion: the center of the distribution moved slightly
  DOWN -- median -0.006, p25 and p75 both -0.008. The direction was
  explicitly not predicted before the rerun; it is recorded as observed.
  The dispersion-up prior held only in the upper tail: IQR width is
  unchanged to three decimals, while p95 rose +0.013 (1.906 -> 1.918),
  the maximum rose +0.259 (13.574 -> 13.833), and the share with
  gamma > 1 fell 0.5 pp. The marginal stability conceals substantial
  cell-level movement: on the 6,824,224 matched (importer, exporter, HS4)
  cells, 44% moved by more than 0.01 and 11.5% by more than 10% of their
  v0.3.0 value (|dgamma| p50 0.0069, p90 0.101, p99 1.09, max 13.7) --
  within-system reshuffling that largely cancels in the marginals,
  consistent with the DGP finding that the misspecified term compressed
  cross-exporter heterogeneity. Membership also churned: 7,557 cells
  appear only in v0.3.0 and 7,178 only in v0.4.0 (about 0.11% each way;
  net -379), with no tier-3 rows on either side. Exits and entrants alike
  concentrate overwhelmingly in fragile optimizations -- 85% of exits and
  84% of entrants carry non-clean SE statuses (plateau, non-converged,
  boundary, singular) against roughly 11% in the estimated population --
  marginal cells flipping in or out as the corrected objective moved
  convergence boundaries; Stage-2a membership moved on the same scale
  (+56 rows). The high effective shrinkage recorded below (median
  `gamma_shrink_wt` 0.98) is consistent with the damped aggregate
  movement: cells whose curvature is dominated by the prior have little
  room to move.
- opt_tariff median: 0.675 -> 0.696 (+0.021). Note the sign: the
  opt_tariff median rose while the gamma median fell, contrary to the
  expectation that the two move together; the finite-opt_tariff subset
  itself changed composition (non-converged -0.3 pp, clean-SE +0.2 pp),
  so the median reflects both the correction and the subset shift.
  (opt_tariff_all is not emitted by compare_runs and is not re-tabulated
  in this release.)
- Soderbery Table-2 structural ratios (paper: 0.408 / 0.532 / 0.217):
  v0.3.0 anchors 0.405 / 0.532 / 0.204 -> v0.4.0 0.402 / 0.532 / 0.203.
  The first two are sigma- and gamma-level statistics that calibrated
  shrinkage can land regardless; the third composes gamma and sigma and is
  the informative one.
- Weak-identification screens (Stage 1, share of evaluated cells):
  strict 10% maximal-size pass 17.3% -> 17.3% (sigma path untouched, as
  required); NEW at the G&S 25% rule of thumb: pass 58.5%
  (82,965 / 141,817); Sargan pass (conventional p > 0.2): 61.7%
  (87,446 / 141,824); pass-both: 28.4% (40,315 / 141,817).
  The 82.7%-fail headline of v0.2.0/v0.3.0 was threshold-dependent; both
  framings now ship per cell.
- SE program: gamma_se median (finite) 0.647 -> 0.643, with the finite
  share up 64.9% -> 65.1%; sigma_robust share 10.6% -> 10.8% of all rows
  (14.4% -> 14.7% of non-NA); clean-SE share 64.9% -> 65.1%, with
  non-converged down 2.7% -> 2.4%; gamma_se_total median 0.607 -> 0.604.
  All move through the corrected Jacobian and dgamma_dsigma.
- NEW gamma_shrink_wt (share of curvature from the prior at the optimum):
  overall median 0.98 (p25 0.866, p75 0.998); by tier: tier 0 median
  0.831, tier 1 median 0.982, tier 2 median 0.999 (the expected near-1 --
  the import side alone is one equation short of identifying J+1
  parameters), tier 3 NA by construction (NA shares 17.9% / 3.7% / 7.2%
  for tiers 0/1/2).
- Lambda diagnostic (lambda FROZEN at 0.1 this release; fixed definition
  in analysis/lambda_diagnostic.R, computed from the committed JSONs
  results/lambda_diagnostic_v030.json / _v040.json): pairing A
  (imp-region, exp-region, good): pair MAD 0.0474 -> 0.0471 and
  R^2 0.181 -> 0.173 on all pairs; MAD 0.0621 -> 0.0618 and
  R^2 0.174 -> 0.168 est-only. Pairing B (imp-region, good): MAD
  0.0103 -> 0.0100 and R^2 0.805 -> 0.806 on all pairs; MAD
  0.0198 -> 0.0195 and R^2 0.641 -> 0.632 est-only. The drift is
  immaterial -- MADs move by under 3% relative and R^2 by less than
  0.01 in absolute terms -- so lambda stays frozen and this release
  triggers no v0.5.x recalibration.
- Pillar-2 columns, re-based (F10): against the corrected truth-labels,
  tier1a relative omega-bias spans -1.00 to +0.20 across the
  sigma x omega grid -- mildly positive at omega_true = 0.3, increasingly
  negative attenuation as omega_true rises, near-total at omega_true = 3
  -- with omega coverage between 0.58 and 0.98; tier1b omega-bias spans
  -0.96 to -0.26 over the (J, T) grid. The committed tier1a/1b baselines
  predate F10 (last regenerated in the v0.3.0 data commit), and F10
  corrects the harness's data-generating supply slope: at the same seed
  the simulated systems differ, so every tier1a/1b column -- sigma-side
  included -- moves relative to the committed CSVs. That movement is
  attributable to the corrected simulated DGP, not to the Stage-1
  point path: the sigma-unchanged claim rests on the production A/B above
  (bit-identical sigma table on 280,649 real cells). Stage-1 sources did
  change between v0.3.0 and v0.4.0, in three path-inert ways: the code
  computing the four new diagnostic columns; the Stock-Yogo threshold
  argument renamed to its correct maximal-size meaning (comments updated
  to match); and a hardened perfect-fit edge case in the step-2 weight
  floor (all-zero squared residuals previously produced an Inf floor)
  that no production cell triggers -- as the byte identity itself
  demonstrates.

## Consumer guidance

Anything consuming gamma, opt_tariff, gamma_se_total, sigma_robust, or the
Stock-Yogo screens should re-pull and re-run. Sigma-only consumers are
unaffected: sigma is bit-identical to v0.3.0. The pre-v0.4.0 HF revision is
pinned in the dataset card for anyone who needs the superseded gammas
(e.g., to reproduce an analysis published against v0.3.0).

# Run comparison: v0.3.0 vs v0.4.0

Generated by `analysis/compare_runs.R` on 2026-07-19.

- v0.3.0 Stage 2b: `data\derived_v030\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`
- v0.4.0 Stage 2b: `data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`
- v0.3.0 Stage 1: `data\derived_v030\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`
- v0.4.0 Stage 1: `data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`

## Stage 1 (sigma)

| Metric | v0.3.0 | v0.4.0 | Change |
|---|---|---|---|
| Cells attempted | 280,649 | 280,649 | +0 |
| status ok share | 50.5% | 50.5% | +0.0 pp |
| sigma median (ok) | 2.878 | 2.878 | +0.000 |
| sigma p25 (ok) | 1.802 | 1.802 | +0.000 |
| sigma p75 (ok) | 5.699 | 5.699 | +0.000 |
| share sigma at cap (ok, >= 9.999) | 13.5% | 13.5% | +0.0 pp |
| sigma_se median (ok, finite) | 1.370 | 1.370 | +0.000 |
| share sigma_se finite (ok) | 86.5% | 86.5% | +0.0 pp |
| omega_se median (ok, finite) | 1.693 | 1.693 | +0.000 |
| share omega_se finite (ok) | 95.7% | 95.7% | +0.0 pp |
| rho_se median (ok, finite) | 0.200 | 0.200 | +0.000 |
| share rho_se finite (ok) | 83.1% | 83.1% | +0.0 pp |
| omega median (ok) | 0.295 | 0.295 | +0.000 |
| omega_floored share (ok) | 31.1% | 31.1% | +0.0 pp |
| sigma_capped share (ok) | 13.5% | 13.5% | +0.0 pp |
| omega_capped share (ok) | 4.0% | 4.0% | +0.0 pp |
| fstat_kp median (ok) | 2.08 | 2.08 | +0.00 |
| stockyogo_pass share (ok, non-NA) | 17.3% | 17.3% | +0.0 pp |

### Stage 1 `adjust` composition (ok cells)

| Metric | v0.3.0 | v0.4.0 | Change |
|---|---|---|---|
| `adjust = 0` | 36.0% | 36.0% | +0.0 pp |
| `adjust = 1` | 47.1% | 47.1% | +0.0 pp |
| `adjust = 4` | 13.5% | 13.5% | +0.0 pp |
| `adjust = 5` | 3.4% | 3.4% | +0.0 pp |

### Stage 1 `final_source` composition (ok cells)

| Metric | v0.3.0 | v0.4.0 | Change |
|---|---|---|---|
| `final_source = hliml` | 36.0% | 36.0% | +0.0 pp |
| `final_source = step2_weighted` | 64.0% | 64.0% | +0.0 pp |

## Stage 2b (country-level gamma)

| Metric | v0.3.0 | v0.4.0 | Change |
|---|---|---|---|
| Rows (importer, exporter, HS4) | 6,831,781 | 6,831,402 | -379 |
| gamma median | 0.680 | 0.674 | -0.006 |
| gamma p25 | 0.481 | 0.473 | -0.008 |
| gamma p75 | 0.976 | 0.968 | -0.008 |
| gamma p95 | 1.906 | 1.918 | +0.013 |
| gamma max | 13.574 | 13.833 | +0.259 |
| share gamma > 1 | 23.3% | 22.8% | -0.5 pp |
| implied export-supply elasticity, median 1/gamma | 1.471 | 1.485 | +0.014 |
| sigma median | 2.878 | 2.878 | +0.000 |
| share sigma at cap (>= 9.999) | 11.1% | 11.1% | +0.0 pp |
| gamma_se median (finite) | 0.647 | 0.643 | -0.004 |
| share gamma_se finite | 64.9% | 65.1% | +0.2 pp |
| gamma_se_total median (finite) | 0.607 | 0.604 | -0.003 |
| sigma_se median (finite) | 1.378 | 1.378 | -0.000 |
| sigma_robust TRUE (share of all rows) | 10.6% | 10.8% | +0.2 pp |
| sigma_robust TRUE (share of non-NA) | 14.4% | 14.7% | +0.2 pp |
| opt_tariff median (finite) | 0.675 | 0.696 | +0.021 |

### Stage 2b `tier` composition

| Metric | v0.3.0 | v0.4.0 | Change |
|---|---|---|---|
| `tier = 0` | 3.3% | 3.3% | -0.0 pp |
| `tier = 1` | 70.1% | 70.1% | +0.0 pp |
| `tier = 2` | 0.2% | 0.2% | -0.0 pp |
| `tier = 3` | 26.4% | 26.4% | +0.0 pp |

### Stage 2b `gamma_se_status` composition

| Metric | v0.3.0 | v0.4.0 | Change |
|---|---|---|---|
| `gamma_se_status = boundary` | 3.5% | 3.5% | -0.0 pp |
| `gamma_se_status = insufficient_df` | 0.5% | 0.5% | +0.0 pp |
| `gamma_se_status = non_converged` | 2.7% | 2.4% | -0.3 pp |
| `gamma_se_status = ok` | 64.9% | 65.1% | +0.2 pp |
| `gamma_se_status = plateau` | 1.0% | 1.0% | +0.0 pp |
| `gamma_se_status = singular` | 0.8% | 0.9% | +0.0 pp |
| `gamma_se_status = tier3_prior` | 25.7% | 25.7% | +0.0 pp |
| `gamma_se_status = NA` | 0.0% | 0.0% | +0.0 pp |



