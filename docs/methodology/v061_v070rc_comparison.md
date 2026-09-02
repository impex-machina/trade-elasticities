# Run comparison: v0.6.1 vs v0.7.0-rc — negative-ω inversions as the ω = +∞ continuation

Box-side A/B, 2026-09-02, on `s3://…/v070rc_run_20260902/` against
`v061_run_20260901/`. Evidence files: `tripwire_stage1.txt`,
`percell_v061_vs_rc.txt`, `bd6_check.txt`, `bd6_check2.txt`,
`cf_inversion_census_rc.md` (all in the S3 prefix). The local
`compare_runs.R` table (Phase 6 of `docs/v070_rc_runbook.md`) is the
release-side counterpart and supersedes any number here if they differ.

**One flag changed:** `--stage1-negative-omega reject` (patch 0046).
Everything else is the v0.6.1 command line. Decision (patch 0047):
`reject` becomes the default; `floor` stays as the v0.6.1 reproducer.

## 1. Why

`invert_structural()` maps the Feenstra regression coefficients to (σ, ω)
through ρ = ω(σ−1)/(1+σω). ρ rises monotonically to (σ−1)/σ as ω → ∞, so a
point with ρ beyond that limit has *no* positive ω: the algebraic
ω = ρ/(σ−1−σρ) is negative because the map has been continued past
ω = +∞. `GS_Estimation.do:39` clamps such points to the 1e-4 floor —
perfectly elastic supply, the opposite end of the axis — and the port
reproduced that through v0.6.1. In (θ₁, θ₂) space the admissible image is
bounded by θ₁ = 0 (the ω → 0 continuation, reported as `eta1_nonpositive`)
and θ₂ = 1 − θ₁ (the ω → ∞ end); `constraint_violated` is the region beyond
the second line.

Census on the shipped v0.6.1 table (`docs/results/cf_inversion_census.md`):
36,914 interior-HLIML cells (13.2% of the universe, 32.0% of the "hliml"
bucket) were such points shipped with ω = 1e-4; 13,482 Step-2 cells were the
same at Step 2. The geometry was already visible in production: of the
1,558 beyond-∞ cells that *did* reach the boundary search in v0.6.1 (their
σ_cf was outside (1, 10)), 1,333 resolved to the ω-cap edge, 124 to the σ
cap, 101 to the floor.

## 2. Stage 1

| | v0.6.1 | v0.7.0-rc | Δ |
|---|---|---|---|
| ok cells | 182,385 | 181,245 | −1,140 |
| HLIML interior | 115,440 | **78,526** | −36,914 (exactly the census set) |
| Step 2 | 39,648 | 47,479 | +7,831 |
| Boundary optima | 27,297 | 55,240 | +27,943 |
| — ω-floor edge (adjust 6) | 11,470 | 15,578 | +4,108 |
| — σ-cap edge (7) | 6,438 | 7,259 | +821 |
| — ω-cap edge (8) | 9,389 | 32,403 | +23,014 |
| ω floored (≤ 1e-4) | 64,699 | 15,582 | −49,117 |
| σ with ω undetermined (Step 2, ω NA) | 0 | 13,482 | new population |
| σ median (ok, > 1) | 2.727 | 2.462 | −0.27 |
| σ quartiles | 1.72 / 5.23 | 1.58 / 4.90 | |

**Per-cell.** 138,542 cells kept their route and agree with v0.6.1 to
**zero** (max |Δσ| = 0), on a different Rcpp/data.table stack. Every cell
that moved is one the census named:

| v0.6.1 route | rc route | n | σ v0.6.1 → rc (medians) | share |Δσ| > 10% |
|---|---|---|---|---|
| floored interior | ω-cap edge | 18,994 | 3.86 → 3.16 | 70% |
| floored interior | Step 2 | 14,757 | 4.54 → 3.17 | 81% |
| floored interior | ω-floor edge | 1,830 | 5.28 → 1.15 | 99% |
| floored interior | σ-cap edge | 193 | 3.94 → 10 | 92% |
| floored interior | interior (genuine sub-floor ω) | 3 | unchanged | 0% |
| floored interior | all_inversions_failed | 1,140 | lost | — |
| Step 2 (σ at cap, ω floored) | ω-cap edge | 4,020 | 10 → 7.21 | 61% |
| Step 2 (ω floored) | ω-floor edge | 2,278 | 6.11 → 1.29 | 95% |
| Step 2 (ω floored) | σ-cap edge | 628 | 10 → 10 | 47% |

Reading: the −0.27 in the σ median is the constrained optimum disagreeing
with the unconstrained closed-form σ by a steady 13–16% on ~34k cells, plus
~4k cells whose optimum is the elastic-supply / unit-demand corner. On the
synthetic DGP (6,000 cells, `evidence_exp_reject_6000cells.csv`) the same
routing left whole-grid σ yield and recovery unchanged to ±0.1 pp and put ω
above the truth in 86% of the re-routed cells (floor: below in 100%).

## 3. The floor-edge corner

The 4,108 cells that went from a beyond-∞ closed form to the ω-*floor* edge
are not the same species as the pre-existing floor-edge cells:

| | pre-existing floor-edge (11,470) | new floor-edge (4,108) | interior (78,526) |
|---|---|---|---|
| σ p10 / median / p90 | 1.14 / 1.72 / 6.03 | 1.03 / **1.21** / 2.59 | — |
| share σ ≤ 1.05 | 3.3% | 16.0% | — |
| share σ ≤ 1.5 | 38% | 73% | — |
| F_kp median | 1.22 | 1.46 | 1.61 |
| Q_bd / Q_cf median | 0.79 | **0.96** | — |
| n_obs / n_exporters median | 84 / 15 | 383 / 35 | 273 / 30 |

Q is negative at the minimum (B = Xc′(P−D)Xc is indefinite), so the ratio
below 1 is the correct ordering (Q_bd ≥ Q_cf holds); a ratio near 1 means
the objective is nearly flat between the beyond-∞ point and the corner. On
these cells the data barely distinguish "ω → ∞" from "ω → 0, σ ≈ 1.2": they
are weakly identified in the structural sense although their first-stage F
is ordinary, so the σ-robust screen does not catch them. Decision: flag
(`boundary_corner`, provenance-defined: floor-edge optimum reached from a
`constraint_violated` closed form), do not re-route — a σ threshold would be
an invented number, and 380 cells of the same species already ship in
v0.6.1. Users doing supply-side work should filter on it.

## 4. Stage 2

| | v0.6.1 | v0.7.0-rc |
|---|---|---|
| 2a priors (products / median γ) | 1,240 / — | 1,240 / 0.642 |
| 2a estimates / γ / tariff | 424,0xx / — / — | 424,008 / 0.649 / 0.727 |
| 2b rows | 6,829,023 | 6,814,229 (−14,794 = the 1,140 lost cells' rows) |
| 2b σ median | 2.727 | 2.462 |
| 2b γ median (q25–q75) | 0.628 (0.43–0.91) | 0.650 |
| 2b opt_tariff median | — | 0.649 |
| convergence (code 0) | — | 68.9% |
| tiers 0 / 1 / 2 / 3 | 3.3 / 70.1 / 0.2 / 26.4 | 3.3 / 70.0 / 0.2 / 26.4 |
| trim | — | 77,779 rows, γ band [0, 15.98] |

The 28k cells now at ω = 10 do **not** enter the 2a priors —
`feenstra_gamma_clean` excludes `omega_capped` as well as `omega_floored`
(F2, v0.4.0). The prior median rose because ~8.5k Step-2 re-routes with
large *interior* ω now qualify. γ moved +3.5%; tiers are identical, as they
must be (tiers depend on data, not σ). Fill the v0.6.1 dashes from
`compare_runs.R` at release.

## 5. Adjudication

Adopt `reject` as the v0.7.0 default. The patch is surgical (zero movement
off the named set), the ω side is labelled at the end of the axis the data
point to, γ and tiers barely notice, and the σ shift is the price of the
constrained optimum rather than an artefact. Residuals carried into the
release notes: 13,482 σ-without-ω cells (Stata-style adjust 1/4 with ω
missing; γ NA, excluded from priors), 4,108 `boundary_corner` cells, 1,140
cells that lose their σ. `--stage1-negative-omega floor` reproduces v0.6.1
bit-for-bit.
