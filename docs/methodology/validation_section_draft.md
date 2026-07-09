# Estimator validation (draft section for the paper)

Draft prose for the methodology/validation section, written to be lifted
into the paper with light editing. Numbers cite the v0.3.0 release
(GitHub tag v0.3.0; HF dataset impex-machina/trade-elasticities) and
docs/methodology/v020_v030_comparison.md. ASCII notation: sigma = import
demand elasticity, omega/gamma = inverse export supply elasticity,
rho = the derived correlation parameter.

## 1. Validation framework

We validate the estimation pipeline at three levels. First, code-level
verification: the analytic objects that determine inference are checked
against numerical differentiation. The delta-method Jacobian
d(sigma, rho)/d(eta_1, eta_2) used for all Stage 1 standard errors, and
its downstream omega gradient, agree with central finite differences to
machine precision (max abs deviation ~1e-9 across production-typical
parameter points), and the compiled objective's analytic Jacobian agrees
with finite differences to ~2e-9. Second, synthetic recovery (Pillar 2):
the full Stage 1 estimator is run on simulated cells with known
(sigma, omega) across a 4 x 3 grid and a sample-size sweep, recording
estimation yield, conditional bias, and confidence-interval coverage.
Third, standard-error calibration (Pillar 3): a Monte Carlo across four
data regimes compares candidate gamma SE formulas to the true sampling
dispersion; the production formula (penalized Gauss-Newton) attains a
median ratio of estimated-to-true SE between 0.982 and 1.067 across all
regimes, while an unpenalized sandwich understates dispersion by roughly
a third. External anchoring is provided by Soderbery (2018): the
pipeline's aggregate structural ratios -- gamma/(1+gamma) = 0.405,
1/(sigma-1) = 0.532, gamma/((1+gamma)(sigma-1)) = 0.204 -- sit on his
Table 2 values (0.408, 0.532, 0.217) computed from the same BACI-class
input universe.

## 2. What validates the standard errors -- and what does not

A referee may ask why we do not cite confidence-interval coverage from
the synthetic-recovery grid as evidence that the standard errors are
correct. We deliberately do not, because in this design coverage is
bound by conditional point-estimate bias, not by SE calibration. Under
weak identification the HLIML-class estimator exhibits substantial
conditional bias on the harder cells of the grid: median sigma bias
ranges from +21% at the easiest corner (low sigma, moderate omega) to
-75% at the hardest (sigma = 8 with inelastic supply), and estimation
succeeds in only 30 to 58 percent of replications, with success
selecting toward better-behaved samples. An interval centered on a
point estimate that sits 30-75% from the truth cannot cover at the
nominal rate regardless of how correctly its width is computed;
accordingly, observed coverage tracks the bias surface (0.85 where bias
is small, 0.42 where it is largest, median 0.74) and is reported in the
appendix as a bias diagnostic, not an SE test. The standard errors are
instead validated by the two channels that isolate them: the analytic
Jacobian verification above, and the Pillar 3 Monte Carlo, in which the
production SE formula's median calibration ratio lies within -1.8% to
+6.7% of unity in every regime.

A within-release A/B supports this reading. The v0.3.0 release corrected
the Stage 1 SE Jacobian and replaced the weak-instrument diagnostic (see
Section 3) while leaving the point-estimation path untouched; on the
seeded synthetic grid, all point-path statistics (yields, medians,
biases) reproduced bit-identically across releases, while only the
SE- and diagnostic-dependent columns moved. Coverage did not move toward
the nominal rate under the corrected SEs -- exactly as the bias-bound
account predicts and a calibration-bound account would not.

## 3. Weak identification: an honest screen

HS4-by-importer bilateral panels are, for the most part, weakly
identified, and the pipeline now says so. Stage 1 reports a
first-stage weak-instrument statistic per cell and screens it against
Stock-Yogo critical values. Those critical values are tabulated for the
minimum-eigenvalue Cragg-Donald statistic; an earlier implementation
used a trace-form statistic, which averages the two endogenous
directions and therefore masks a weakly identified direction behind a
strong one. On the bit-identical synthetic A/B described above, the
median first-stage statistic falls by a factor of 3.3 when the trace
form is replaced by the minimum eigenvalue, with every point estimate
unchanged -- a direct measurement of the trace form's anti-conservatism.
In production the Stock-Yogo pass share falls from 59.3% to 17.3% of
estimated cells. We regard the latter as the honest number: it changes
no estimate, but it changes what a user should believe about them, and
the per-cell statistic is published so that users can condition on
identification strength (for example, restricting to the
Stock-Yogo-passing subset, or weighting by first-stage strength) rather
than inheriting our threshold.

The screen that flags gamma estimates as robust to sigma uncertainty is
similarly conservative by construction: it fails any cell whose sigma
is boundary-clamped, whose sigma SE is non-finite, whose sigma
confidence band reaches the sigma = 1 pole, or where propagating sigma
uncertainty more than doubles the gamma SE. Under the corrected
(larger) sigma SEs it passes 10.6% of published rows -- down from 16.5%
under the understated SEs -- and we report gamma_se_total (gamma SE
with sigma uncertainty propagated) alongside the conditional gamma_se.

## 4. Known limitation and planned benchmark

The remaining first-order limitation is the one the coverage table
documents: conditional small-sample bias of sigma under weak
identification, predominantly downward and worst where supply is
inelastic. No patch in the current release addresses it, because it is
a property of the estimator class in this data environment rather than
an implementation defect. Two mitigations are in place -- the published
per-cell weak-IV statistic lets users condition on identification
strength, and all headline aggregates are medians, which the bias
surface suggests are less distorted than means -- but the natural next
increment is an exporter-cluster bootstrap benchmark on real data
(implemented in validation/bootstrap_se.R; results to be reported when
the benchmark is run against the production cache):

- Sampling frame: a stratified subsample of 500-1,000 estimated
  (importer, HS4) cells, stratified on the joint distribution of
  n_exporters, the Cragg-Donald statistic, and the adjust code, so the
  weakly and strongly identified regions are both represented.
- Resampling: within each cell, resample exporters with replacement
  (the exporter is the independent sampling unit in the moment
  construction), re-selecting the reference exporter per replicate by
  the production rule; B = 299-499 replicates per cell.
- Comparison: the bootstrap standard deviation of sigma-hat across
  successful replicates against the analytic sigma_se, reported as a
  ratio distribution by stratum, in the spirit of the Pillar 3 design
  but on real rather than synthetic data.
- Caveats to state up front: the bootstrap validates dispersion, not
  bias (a bootstrap distribution centered on a biased point estimate
  inherits the bias), and within-bootstrap selection (replicates that
  fail estimation are dropped) parallels the selection already
  documented in Pillar 2. Compute cost is modest: on the production
  instance class the full design is a matter of hours.

## 5. Release note for replication

Estimates cited in this paper are the v0.3.0 release. Relative to
v0.2.0, v0.3.0 corrected a prior-scale bug that biased gamma downward
(gamma median 0.238 -> 0.680; implied median export-supply elasticity
4.2 -> 1.47), corrected the Stage 1 SE Jacobian (sigma_se +38% at the
median; rho_se -66%), added a consecutive-year guard to Stage 1 moment
construction (-5.2% estimated cells), and replaced the weak-IV
statistic as described above; sigma itself was essentially unchanged
(median 2.878). The full delta accounting is in
docs/methodology/v020_v030_comparison.md; v0.2.0 remains available
pinned at HF revision 7e598f6cb98e and versions should not be mixed
within one analysis.
