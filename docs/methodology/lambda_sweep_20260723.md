# Lambda sweep and calibration review (2026-07-23/24)

## Context

The v0.4.1 sign correction (Eq. 11, docs/methodology/eq11_sign_correction.md)
moved Stage 2 moments enough that the report-only lambda drift diagnostic
exceeded the v0.4.0 materiality bar (MAD +6-15% rel across pairings, one
R^2 -0.011 vs the <=3% / <=0.01 bar). Per the freeze policy this fired the
recalibration trigger. Rather than ship with the trigger documented, a
full-scale recalibration sweep was run.

## Design

- Stage 2b re-estimated at lambda in {0.02, 0.05, 0.1, 0.2, 0.5}, full scale,
  on the v0.4.1 (sign-corrected) code at 191fec3.
- Stage 1 and Stage 2a held fixed (2a lambda hardcoded 0.05); inputs were the
  production v041 stage-1 and regional tables.
- Scored on the original four calibration criteria
  (R/lambda_calibration.R::lambda_calibration_diagnostic) plus the committed
  pairing drift diagnostic (analysis/lambda_diagnostic.R).
- Compute: r7a.16xlarge, ~40 min per point. Outputs:
  s3://trade-elast-baci-hs92-v202601-hs4/lambda_sweep_20260723/lambda_<l>/
  (2b table + run.log per point).

## Decision table

| lambda | rows      | WP-MAD | R^2(FE) | plateau | T1/T3 gap | pair-A MAD/R^2 | pair-B MAD/R^2 | est-B R^2 |
|--------|-----------|--------|---------|---------|-----------|----------------|----------------|-----------|
| 0.02   | 6,827,529 | 0.050  | 0.125   | 0.44%   | 0.031     | 0.0960 / 0.088 | 0.0112 / 0.746 | 0.416     |
| 0.05   | 6,829,923 | 0.027  | 0.129   | 0.04%   | 0.042     | 0.0682 / 0.131 | 0.0111 / 0.787 | 0.572     |
| 0.1    | 6,831,219 | 0.015  | 0.136   | 0.00%   | 0.045     | 0.0510 / 0.166 | 0.0115 / 0.795 | 0.628     |
| 0.2    | 6,832,468 | 0.008  | 0.143   | 0.00%   | 0.045     | 0.0437 / 0.195 | 0.0117 / 0.784 | 0.636     |
| 0.5    | 6,833,374 | 0.004  | 0.156   | 0.00%   | 0.041     | 0.0460 / 0.207 | 0.0120 / 0.769 | 0.621     |
| v0.3.0 reference | - | -    | -       | -       | -         | 0.0474 / 0.181 | 0.0103 / 0.805 | 0.641     |

WP-MAD = within-pair gamma MAD (four-criteria diagnostic; original printed
target 0.125). R^2(FE) = importer x good FE variance-decomposition R^2
(printed target 0.720). Pairing stats are the committed drift diagnostic
("all" filter; est-B = est_only pairing-B R^2).

## Findings

1. The printed calibration targets (0.125 / 0.720) are unreachable on this
   data in any direction: WP-MAD moves AWAY from 0.125 as lambda rises and
   would require lambda near 0.005 (deep plateau territory) to reach it.
   They are treated as decorative; the operative criteria are plateau share,
   tier distinctness, and the pairing diagnostics.
2. No lambda restores the v0.3.0 baseline. The corrected moments changed the
   2a/2b relationship itself; the drift is moments-driven and permanent.
   Recalibration therefore means choosing the optimum under current moments
   and resetting the committed baseline.
3. The optimum is a flat ridge over lambda in [0.1, 0.2]: identical plateau
   (0) and tier distinctness (0.045, the maximum). Within the ridge,
   lambda=0.2 restores fine-pairing (A) agreement to the reference level,
   while lambda=0.1 maximizes coarse-pairing (B) R^2 and retains twice the
   within-pair heterogeneity (WP-MAD 0.015 vs 0.008).
4. Anchor validation: the lambda=0.1 sweep table reproduces the production
   v041 table with DATA bit-identical after stripping the run_meta attribute
   and canonically sorting (identical() TRUE). File sha256 values differ only
   through run_meta (per-worker timing_info, t_elapsed, timestamp). The
   estimator is deterministic; the serialized file embeds wall-clock
   metadata. A hygiene change (run_meta to the summary sidecar + canonical
   sort before saveRDS) is slated so future manifests certify content.

## Decision

lambda* = 0.1 (retained). Rationale: the incumbent sits on the optimum
ridge; it maximizes retained cross-exporter heterogeneity, which is the
dataset's purpose, and wins pairing-B R^2 outright. The trigger-metric
gap at 0.1 (pairing-A) reflects the moments change, not calibration decay,
and buying it back at lambda=0.2 costs half the within-pair heterogeneity.
The release ships as v0.4.1 (no lambda change; policy versioning applies
only when the constant changes).

## Baseline reset

results/lambda_diagnostic_v041.json (committed with this release) is the
drift baseline for all future comparisons. The v0.3.0 reference values
remain in results/lambda_diagnostic_v030.json for history but no longer
gate releases.
