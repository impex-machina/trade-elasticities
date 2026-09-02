# Standard errors for constrained boundary optima (patch 0049, v0.7.1 candidate)

## Why

v0.7.0 routes every closed-form point that is inadmissible (beyond ω = +∞,
beyond ω = 0, or outside the σ box) to the constrained optimum on an edge of
the admissible box — 55,240 cells, 30.5% of clean cells — and those cells
shipped without standard errors. Consequently σ-SE coverage fell from 77.9%
to 63.6% of clean cells, `gamma_se_status = boundary` tripled, and the
σ-robust screen (which needs a finite σ SE) passed 10.7% of rows instead of
14.6% (`docs/methodology/v061_v070rc_comparison.md`, section 4). None of
that is a point-estimate problem; it is missing inference.

## What

An edge optimum pins one structural coordinate (ω on the `omega_floor` /
`omega_cap` edges, σ on `sigma_cap`) and minimises the profiled HLIM
objective Q along the other, with the intercept θ₀ free. That is an
*unconstrained* M-estimator of φ = (θ₀, t) for the objective Q(θ(φ)), so the
HNCS sandwich that already serves the interior estimator applies through
the reparameterisation θ = θ(φ):

    Var(φ̂) = (J′H̄J)⁻¹ (J′Σ̄J) (J′H̄J)⁻¹,   J = ∂θ/∂φ  (3 × 2)

with H̄ = X′(P − D − α_c I)X and Σ̄ the same two-piece HNCS meat as the
interior estimator, evaluated at the constrained point and its objective
value α_c = Q_bd. The constrained first-order condition is J′(B − α_c A)b = 0,
and the projected curvature J′H̄J is the edge profile's second derivative at
an edge minimum up to the positive factor b′Ab — exactly the interior
argument, restricted to the tangent. In the full 3-space H̄ has a negative
direction at a constrained point (the unconstrained descent direction);
its projection onto the tangent is positive definite at a genuine edge
minimum, and when it is not the point is a degenerate corner and the SE is
reported NA with status `edge_se_curvature_not_pd`.

The free coordinate is the structural parameter, so no further delta step
is needed: on the ω edges `sigma_se = √Var[2,2]` and `omega_se` is NA (the
pinned coordinate is not estimated); on `sigma_cap` the reverse. `rho_se`
follows from ρ = ω(σ−1)/(1+σω) by the one-dimensional delta rule
(|∂ρ/∂σ| = ω(1+ω)/(1+σω)², |∂ρ/∂ω| = (σ−1)/(1+σω)²).

Implementation: `hncs_parts_groups()` factors H̄ and Σ̄ out of
`hncs_sandwich_se_groups()` verbatim (interior SEs bit-identical, locked by
test); `hncs_edge_se_groups()` projects them; `estimate_cell_liml(edge_se =
"hncs")` — CLI `--stage1-edge-se hncs` — fills the SE fields on boundary
routes and stamps `edge_se_method` / `edge_se_status` on every row. Point
estimates, routing and every non-SE field are untouched (locked by test);
the default `none` reproduces v0.7.0 bit-for-bit.

## Calibration (synthetic cells, `evidence_exp_edge_se_4800cells.csv`)

`validation/validate_liml.R::simulate_one_cell`, 200 replicates per
configuration, (J, T) ∈ {10, 25} × {15, 30}, truth placed so that roughly
half the draws route to the edge under test. Nominal 95%.

| truth | route | n | σ-SE coverage | median bias |
|---|---|---|---|---|
| ω = 0.01, σ = 2 / 4 | ω-floor edge | 330 / 351 | **92.7% / 95.4%** | 0.00 |
| ω = 0.01, σ = 2 / 4 — draws that landed beyond ω = +∞ | ω-cap edge | 89 / 205 | **92.1% / 94.6%** | +0.14 / +0.06 |
| ω = 0.01, σ = 2 / 4 | interior HNCS (benchmark) | 322 / 222 | 96.9% / 96.8% | 0.02 / 0.01 |
| ω = 10 (truth at the ω cap), σ = 2 / 4 | ω-cap edge | 200 / 234 | 100% / 78% | +8 / +6 (σ at its own cap) |
| ω = 10, σ = 2 / 4 | interior HNCS | 75 / 121 | 97% / **41%** | −0.4 / −2.6 |
| σ = 10 (truth at the σ cap), ω = 1 | σ-cap edge, ω SE | 38 | 47% | — |
| σ = 10, ω = 1 | interior HNCS, ω SE | 234 | 55% | — |

Reading: the edge SE is calibrated wherever the estimator itself is. On the
two populations that matter in production — beyond-∞ closed forms resolved
to the ω-cap edge, and genuine ω → 0 cells on the floor edge — coverage is
92–95% against a 97% interior benchmark, with no bias. Where the truth sits
*at* a cap, coverage collapses for the edge SE **and** for the interior
HNCS (41% at ω = 10; 55% for ω at σ = 10): that is the estimator's
identification failing near the caps, not the projection, and the
`sigma_robust` screen already excludes those cells. Failure statuses
occurred on 9 of 2,030 edge cells, all on the σ-cap edge (8 non-PD
curvature, 1 negative variance).

## Release shape (v0.7.1, validation-only)

Full rerun with `--stage1-edge-se hncs` on the v0.7.0 command line. Stage 1
σ / ω / ρ / γ_common and every routing field must be **identical** to
v0.7.0 (bit-for-bit — the tripwire); only `sigma_se`, `omega_se`, `rho_se`
and the two provenance columns move. Stage 2a/2b re-run so
`gamma_se_total` and `sigma_robust` pick up the new σ SEs through
`sigma_se_lookup`; γ, tiers, opt_tariff must be identical. Expected: σ-SE
coverage back toward ~90% of clean cells, `sigma_robust` pass rate up from
10.7%. Followed by a card entry in the v0.5.1 (validation-only) pattern.
