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
correct. We report it, with one caveat about where it is informative. On the
4x3 (sigma, omega) grid at J = 25 exporters and T = 30 periods (200
replications per point), the estimator returns an admissible estimate
in 80 to 100 percent of replications (median 98 percent). Conditional
on success, the median sigma is within about 3 percent of truth for
omega <= 1 across the grid, the one exception being (8, 1) at 9
percent; bias becomes material only along the high-omega edge
(omega = 3), where the median sigma runs from +30 percent at low sigma
to -37 percent at (8, 3) and omega is pulled toward its floor at the
high-sigma corners (-53 and -93 percent at (5, 3) and (8, 3)). That
edge is also where the yield is lowest, 80 percent at (2, 3). Coverage
tracks the same surface: 0.85 to 0.97 for sigma and 0.89 to 0.97 for
omega on the sigma <= 3 rows, falling to 0.55 and 0.68 at (8, 3),
median 0.91 across the grid. Tier 1b at (3, 1) shows the consistency
signature directly: the yield rises from 93 percent at n = 150 to 100
percent at n >= 600, and the median sigma bias shrinks from -12 to -2
percent (omega: -51 to -0.3 percent). We therefore read coverage
as informative about the standard errors on the well-identified region
and as a bias diagnostic only at the corner. The standard errors are further validated by the two channels that isolate them: the analytic
Jacobian verification above, and the Pillar 3 Monte Carlo, in which the
production SE formula's median calibration ratio lies within -1.8% to
+6.7% of unity in every regime. Both channels validate the formula
conditional on the selected estimator branch; Section 4 reports a
real-data bootstrap that quantifies how far these conditional SEs sit
from unconditional resampling dispersion, and in which direction, by
branch.

A within-release A/B isolates the two paths. The v0.3.0 release corrected
the Stage 1 SE Jacobian and replaced the weak-instrument diagnostic (see
Section 3) while leaving the point-estimation path untouched; on the
seeded synthetic grid, all point-path statistics (yields, medians,
biases) reproduced bit-identically across releases, while only the
SE- and diagnostic-dependent columns moved.

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
surface suggests are less distorted than means. To quantify how far the
analytic standard errors sit from real-data resampling dispersion, we
ran the exporter-cluster bootstrap benchmark specified above
(validation/bootstrap_se.R; executed 2026-07-10 on the production
cache): 750 estimated cells drawn from the 122,720 eligible
(status ok, finite sigma_se, uncapped), stratified on n_exporters x
Cragg-Donald F x estimator source with per-stratum floors; within each
cell, exporters resampled with replacement (draws relabeled so
duplicates enter as distinct panels; the reference exporter re-selected
per replicate by the production rule); B = 399 replicates per cell.
Internal validity is exact: all 750 baseline refits reproduce the
published sigma bit-for-bit. Median bootstrap yield is 74.8%, falling
from 92-98% in the largest-exporter strata to 21-53% in the smallest --
the within-bootstrap selection caveat, quantified.

The results (docs/methodology/bootstrap_se_summary.csv; per-cell detail
in bootstrap_se_cells_20260710.csv, 736 cells reporting) do not deliver
the ratio-near-one verdict a well-calibrated conditional SE would hope
for; they deliver something more specific. The dominant axis is not
instrument strength but estimator branch. On HLIML-interior cells the
bootstrap SD of sigma-hat runs 4-9x the analytic sigma_se at stratum
medians (2-17x across strata), and even a median-absolute-deviation
dispersion measure -- robust to wild replicates -- sits at 1.2-2.5x.
On Step-2 fallback cells the pattern inverts: bootstrap dispersion is
BELOW the analytic SE in the weak- and mid-identification strata
(SD ratios 0.24-0.73, MAD ratios 0.1-0.4), exceeding one only in the
small strong-F strata. The corrected analytic SEs are therefore
anti-conservative for the interior estimator and conservative for the
fallback -- opposite-signed, branch-conditional miscalibration that no
single scalar verdict captures.

Two features of the replicate distributions discipline the
interpretation. First, SD- and MAD-based ratios diverge by up to an
order of magnitude in the explosive strata, the signature of
heavy-tailed, plausibly bimodal resampling distributions: most
replicates land near the estimate while a minority flip discretely --
across the HLIML/Step-2 branch boundary, or to the sigma cap or the
sigma = 1 pole. Second, and consequently, the bootstrap measures
UNCONDITIONAL pipeline dispersion, including the variance contributed
by the estimator-selection step itself, while the analytic sigma_se is
conditional on the selected branch. Branch-switching variance is
genuine sampling uncertainty that no within-branch formula credits;
the synthetic calibration of Section 1 (Pillar 3) validates the
formula within-branch and is not contradicted by these results. A
branch-tagged rerun (recording each replicate's final_source) would
decompose the two components and is the natural follow-up.

Practical guidance for users of the published estimates follows
directly. Treat sigma_se as a branch-conditional, frequently
lower-bound dispersion measure: for sigma-critical inference on
HLIML-interior cells, robust bootstrap factors of roughly 1.5-2.5x
(MAD-based) to several-fold (SD-based, tail-sensitive) apply, while
for Step-2 cells in the weak-identification mass the analytic SE is if
anything conservative. The per-cell bootstrap file is published
precisely so users can calibrate to their own cell mix rather than
inherit a global factor. The pre-stated caveats stand: this
benchmarks dispersion, not bias, and replicate selection is of the same kind as the yield selection in Pillar 2 -- mild in the well-identified region, material only along the high-omega edge.

## 5. Release note for replication

Estimates cited in this paper are the v0.6.0 release (GitHub tag v0.6.0; HF data revision 4d0987e22977a6482eeefd8d9a3d5452d907e505). v0.6.0 replaces the Stage 1 BFGS search with the closed-form HLIML estimator with boundary-search routing: usable Stage 1 cells rise from 50.5% to 66.0% of the 280,649 attempted, and sigma moves for the first time across releases (median 2.878 -> 2.705); gamma median 0.678 -> 0.657, optimal-tariff median 0.709 -> 0.674, rows 6,860,437, tier composition unchanged. A Stage 2 analytic gradient was evaluated and rejected 22:1 under the current optimizer cascade (docs/methodology/v060_stage2_gradient_ab.md), and shipped Stage 1 cap flags were corrected post-hoc for boundary corner cells (sigma_capped +1,934, omega_capped +3,328). Full delta accounting: docs/methodology/v051_v060rc_comparison.md. Relative to v0.5.0, v0.5.1 is validation-only: Stage 1 sigma and Stage 2b gamma are bit-identical to v0.5.0 (HF revision ea1c3ea464ca1ac114bf9b6c518325e8135bdc41); it corrects the Pillar-2 synthetic-recovery harness described in Section 2 and re-captures its tables. Relative to v0.4.1, v0.5.0 corrected the Broda-Weinstein weight
lag to the previous calendar year of the cell panel (v0.4.x used the
previous retained row, a stale x_{t-2+} after any filtered-out year);
sigma is unchanged and gamma moves broadly but slightly (median 0.679
-> 0.678, median |delta gamma| 0.0024, tier composition unchanged).
Earlier deltas: v0.4.1 corrected the Eq. (11) x5/x6 signs and re-based
the Stage 1 identification diagnostics (partialled Cragg-Donald F,
Sargan dof); v0.4.0 corrected a mistranscribed Eq. (10) fourth-moment
coefficient; v0.3.0 corrected a prior-scale bug that biased gamma
downward (gamma median 0.238 -> 0.680; implied median export-supply
elasticity 4.2 -> 1.47), corrected the Stage 1 SE Jacobian (sigma_se
+38% at the median; rho_se -66%), added a consecutive-year guard to
Stage 1 moment construction (-5.2% estimated cells), and replaced the
weak-IV statistic as described above; sigma itself was essentially unchanged from v0.2.0 through v0.5.1 (median 2.878), until the v0.6.0 estimator change. The full delta accounting is in
docs/methodology/v0*_comparison.md; every earlier release remains
available pinned at its HF revision (v0.5.1 3b796a6db8a6fa1caabb37acb1e51480a3cbcaf4, v0.5.0 ea1c3ea4..., v0.4.1
5493c51f, v0.4.0 a76f2d7, v0.3.0
ec59b57894cab18b2d0295c96334a96b7dd8a2cd, v0.2.0 7e598f6cb98e) and
versions should not be mixed within one analysis.
