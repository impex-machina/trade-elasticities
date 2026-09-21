# The two ends of the supply axis: a geometric correction to the Feenstra feasibility block

*Methodology note and draft paper section (2026-09-21). Numbers are from the
v0.6.1 → v0.7.0 → v0.7.1 releases; every one is reproducible from the shipped
tables with the scripts named in the footnotes. Equation numbering is
provisional. Figure 1 is specified in section 2 and not yet drawn.*

## 1. The problem in one paragraph

Feenstra's (1994) estimator recovers the import-demand elasticity σ and the
inverse export-supply elasticity ω from two regression coefficients through
a map that is not onto. For a subset of cells — 13% of the HS4 universe in
our data — the estimated coefficients lie *past* ω = +∞, in a region the
map cannot reach. The Stata implementation that the literature inherits
(Grant and Soderbery 2024, `GS_Estimation.do`, line 39) resolves this by
clamping ω to a small positive floor and reading the cell as one with
near-perfectly-elastic export supply. Geometrically that is the *opposite*
end of the axis from where the data placed the point. We show why, measure
how often it happens, replace the clamp with the constrained optimum on the
admissible region, and report the consequences for σ, ω, and inference.

## 2. The inversion and its image

The double-differenced Feenstra regression in cell (importer k, product g) is

    Y_vt = θ₀ + θ₁ X₁,vt + θ₂ X₂,vt + u_vt,                              (1)

with Y = (Δᵏ ln p)², X₁ = (Δᵏ ln s)², X₂ = (Δᵏ ln p)(Δᵏ ln s), and the
structural map

    θ₁ = ω / ((1+ω)(σ−1)),   θ₂ = (ω(σ−2) − 1) / ((1+ω)(σ−1)).           (2)

The inversion proceeds through ρ = ω(σ−1)/(1+σω):

    ρ = ½ ± √(¼ − 1/(4 + θ₂²/θ₁)),   σ = 1 + (2ρ−1)/((1−ρ)θ₂),
    ω = ρ / (σ − 1 − σρ).                                                (3)

Admissibility is σ > 1 and ω > 0. The key fact is that ρ is a *bounded,
monotone* function of ω for fixed σ: it rises from 0 at ω = 0 to
(σ−1)/σ as ω → ∞ and never exceeds it. A point with ρ > (σ−1)/σ therefore
has no positive ω; the algebraic ω in (3) is negative because its
denominator has changed sign, which is to say the map has been continued
*past* ω = +∞ (Figure 1).

In (θ₁, θ₂) space the image of the admissible region is bounded by two
curves. Sending ω → 0 in (2) gives θ₁ → 0 and θ₂ → −1/(σ−1): the boundary
is the half-line θ₁ = 0, θ₂ < 0. Sending ω → ∞ gives θ₁ → 1/(σ−1) and
θ₂ → (σ−2)/(σ−1) = 1 − θ₁: the boundary is the line θ₂ = 1 − θ₁ with
θ₁ > 0. A coefficient estimate with θ₁ ≤ 0 is the continuation past the
ω = 0 end (the estimator already reports this as `eta1_nonpositive`); one
with θ₁ > 0 and θ₂ > 1 − θ₁ is the continuation past the ω = ∞ end
(`constraint_violated`). These are the two ends of the supply axis, and
they are not adjacent.

**Figure 1 (to draw).** Left: ρ against ω at σ = 3, showing the asymptote
at (σ−1)/σ = 2/3 and a sample point with ρ̂ = 0.72 that no positive ω
reaches. Right: the (θ₁, θ₂) plane with the admissible image shaded, the
ω = 0 boundary (vertical half-line) and the ω = ∞ boundary (θ₂ = 1 − θ₁),
and the two "beyond" regions labelled by which end they continue.

## 3. What the feasibility block does with such a point

`GS_Estimation.do` handles inadmissible inversions with a sequence of
replacements; the one that matters here is `replace omega = 0.0001 if
omega < 0`. A negative algebraic ω — the ω = ∞ continuation — is set to the
floor, the cell's σ is left at the value the unconstrained inversion
produced, and the cell is reported as an interior estimate with
near-perfectly-elastic supply. The same rule, ported faithfully, governed
our pipeline through v0.6.1.[^1]

Two things are wrong with this at once. The economic reading is inverted:
the data on these cells push ω *up*, past the largest admissible value, and
the clamp reports the smallest. And the pair (σ̂, ω = 10⁻⁴) is not a point
on any optimum: σ̂ is the unconstrained solution at a point outside the
admissible region, paired with an ω chosen by fiat. When an unconstrained
optimum is inadmissible, the estimator's answer should be the constrained
optimum on the admissible region, and that is a different point.

## 4. How often

On the shipped v0.6.1 Stage-1 table (280,649 importer × HS4 cells; 182,385
with an estimate) we classified every cell by the inversion status of its
closed-form HLIML point.[^2]

| population | cells | share |
|---|---|---|
| interior HLIML estimates whose closed form was beyond ω = ∞, shipped with ω = 10⁻⁴ | 36,914 | 13.2% of the universe; 32.0% of all "interior" cells |
| Step-2 (Fuller LIML) estimates in the same state | 13,482 | |
| genuine ω → 0 boundary optima (`eta1_nonpositive`, floor edge) | 11,365 | |

So of the 64,699 cells the release described as sitting at the elastic
floor, roughly four in five were at the wrong end of the axis. The data had
already shown the geometry: the 1,558 beyond-∞ cells whose σ̂ happened to
fall outside (1, 10) — the only ones the feasibility block could not accept
— were routed to a constrained boundary search, and 1,333 of them (86%)
resolved to the ω *cap*, 124 to the σ cap, 101 to the floor.

A synthetic check says the same. On 6,000 cells simulated from the
structural model with σ ∈ {2, 3, 5}, ω ∈ {0.01, …, 1} and panels of
10–25 exporters × 15–30 years, 392 of the 393 cells the shipped rule would
have floored were beyond-∞ points; when the constrained optimum was
computed for them it lay on the ω-cap edge in 96% of cases, and the
Fuller-LIML ω for the same cells was above the true ω in 70–93% of
draws.[^3]

## 5. The correction

From v0.7.0 the inversion returns ω = NA with status `constraint_violated`
for a negative algebraic ω, at every place it is called (the starting-value
step, the Fuller-LIML step, and the closed-form HLIML point). A closed-form
point in that state is inadmissible; a Step-2 point in that state carries no
ω; and the cell takes the constrained optimum of the HLIML objective on the
boundary of the admissible box — a one-dimensional search along each edge
with the intercept profiled out, the edge with the lowest objective
winning.[^4] Precedence is otherwise unchanged: an interior HLIML point
beats everything, a fully admissible Step-2 point beats the boundary, and
the boundary beats a Step-2 σ that arrived without an ω.

Under the old rule (`--stage1-negative-omega floor`) the pipeline
reproduces v0.6.1 bit-for-bit, so the change is auditable cell by cell.

## 6. Consequences

*Point estimates.* 138,542 cells kept their route and are identical to the
last bit. The 36,914 re-routed cells went 18,994 to the ω-cap edge (σ
median 3.86 → 3.16), 14,757 to Step 2 with an interior ω (4.54 → 3.17),
1,830 to the floor edge, 193 to the σ cap, and 1,140 lost their estimate.
The clean-cell σ median moved from 2.727 to 2.462: the constrained optimum
sits 13–16% below the unconstrained closed-form σ on the affected cells,
which is the price of taking the admissible region seriously rather than
an artefact. The floor population fell from 64,699 to 15,582 and is now
the genuine ω → 0 set. Stage-2 γ moved by 3.5% at the median (0.628 →
0.650); tier composition, which depends on the data and not on σ, is
identical.[^5]

*Two populations the correction creates, both flagged.* 13,494 cells have a
Step-2 σ but no admissible ω and no usable edge; they ship with ω missing,
the Stata-style outcome, and enter no supply-side prior. 2,503 cells are
beyond-∞ points whose constrained optimum lies on the ω-*floor* edge, at
σ ≈ 1.1–1.2 — the elastic-supply / unit-demand corner. Their first-stage F
is unremarkable (median 1.46, against 1.61 for interior cells), but the
objective is nearly flat between the beyond-∞ point and that corner (the
constrained value retains 96% of the unconstrained depth), so the data do
not discriminate between "ω → ∞" and "ω → 0, σ → 1" on them. We flag them
(`boundary_corner`) rather than re-route them: any σ threshold would be an
invented number, and 380 cells of the same species already shipped under
the old rule.

*Inference.* A constrained edge optimum pins one coordinate and minimises the
profiled objective along the other with the intercept free — an
unconstrained M-estimator of (θ₀, t) — so the same
Hausman–Newey–Chao–Swanson sandwich that serves interior HLIML applies
through the reparameterisation θ = θ(θ₀, t): Var = (J′H̄J)⁻¹(J′Σ̄J)(J′H̄J)⁻¹
with J = ∂θ/∂(θ₀, t). The free coordinate is the structural parameter, so
σ on the ω edges and ω on the σ-cap edge get sandwich SEs directly; the
pinned coordinate is not estimated and reports none. On synthetic cells the
edge SE covers at 92–95% against a 97% interior benchmark and degrades only
where the interior sandwich also does (truth at a cap). With it, σ-SE
coverage of clean cells is 89.8% (63.6% without it); the σ-robust screen
passes 17.6% of Stage-2b rows rather than 10.7%.[^6]

## 7. Why it matters beyond this dataset

The clamp is not a quirk of one script. Any implementation of the Feenstra
inversion that treats "ω < 0" as "ω small" makes the same error, and the
error is systematic in direction: it converts the most inelastic-supply
cells in a dataset into the most elastic ones. In our data that is one cell
in eight. For any application that uses ω — optimal-tariff calculations,
incidence, the Soderbery (2018) γ that is built on the σ from this stage —
the affected cells carry the wrong sign of the supply response, and the
"share of cells at the elastic floor" statistic that such datasets report
is overstated by a factor of about four. The fix requires no new estimator:
it requires reading the inversion's geometry and finishing the constrained
problem it implies.

---

[^1]: `docs/methodology/stata_port_deviations.md`, entry A8.
[^2]: `analysis/hs4_cf_inversion_census.R`; results in
`docs/results/cf_inversion_census.md`. Every table in this section is
produced from the Stage-1 rds alone.
[^3]: `evidence_exp_floor_routing.R` and `evidence_exp_reject_6000cells.csv`
(`validation/validate_liml.R::simulate_one_cell`, seeds recorded).
[^4]: `R/liml_estimator.R`: `invert_structural(negative_omega = "reject")`,
`hliml_boundary_search()`; the routing order is in `estimate_cell_liml()`.
[^5]: `docs/methodology/v061_v070rc_comparison.md` and the `compare_runs.R`
table `v061_v070rc_compare_runs.md`.
[^6]: `docs/methodology/v071_edge_se.md`; `hncs_edge_se_groups()`.
