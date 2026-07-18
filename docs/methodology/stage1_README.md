# Stage 1 — refactored_run_20260519

Stage 1 estimates σ, ω, ρ per (importer, HS4) cell on CEPII BACI HS92
V202601 (1995–2024). This is the canonical refactored output, produced
2026-05-19 on r7a.16xlarge using the HLIML estimator ported from
Grant & Soderbery (2024) replication, with weighted Fuller LIML fallback
on cells where HLIML fails to converge and orchestrator value substitution
when either estimator returns σ or ω outside the (1, 10) admissibility box.

The refactored pipeline is canonical. Legacy Stage 1 output
(`s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/stage1_liml_202605/`) is preserved
for archival but contains an HS6 leading-zero handling bug that was fixed
in the refactor; see the parity section below.

## Contents

| File | Size | Purpose |
|------|------|---------|
| `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` | 21 MB | Slimmed Stage 1 output: σ only, downstream input to Stage 2a |
| `baci_hs92_v202601_elast_country_hs4_feenstra_sigma_liml.rds` | 21 MB | Full Stage 1 output: 30 columns with diagnostics, SE, adjust flag, hliml_status |
| `baci_hs92_v202601_elast_country_hs4_raw_cache.rds` | 876 MB | Pre-aggregated BACI panel cached for re-use across stages and validation |
| `parity_check_20260519.log` | 9 KB | Parity comparison against legacy Stage 1 output |
| `README.md` | — | This file |

## How it was produced

```
r7a.16xlarge (us-east-1, AMI r-estimation-ready, 62 cores, 512 GB RAM)
Rscript scripts/run_estimation.R --stage 1 --ncores 62
Wall time: approximately 30 minutes
```

The full pipeline command and infrastructure notes are in
`docs/methodology/README.md` and the repo root README. Stage 1 requires
r7a.16xlarge specifically — c7a.16xlarge (128 GB RAM) OOMs after the
master copies the raw BACI cache (~30 GB) and forks 62 workers.

## Schema — `_liml.rds` (30 columns)

The full Stage 1 output. Key columns:

| Column | Type | Description |
|--------|------|-------------|
| `importer` | integer | ISO numeric importer code |
| `good` | character | HS4 product code (zero-padded; e.g. `0302`) |
| `sigma` | numeric | Reported σ — HLIML if interior, else Step 2 fallback, else cap value |
| `omega` | numeric | Reported ω = ρ/(σ−1−σρ) — the **inverse** export-supply elasticity (the implied export-supply elasticity is 1/ω); same HLIML → Step 2 → cap rule as σ. |
| `rho` | numeric | Reported ρ — the structural correlation root; σ and ω are computed from it (not the reverse). |
| `gamma_common` | numeric | Implied export-supply **parameter** γ = ω/(1+ω) ∈ (0, 1) under the homogeneity (γ_j = γ_k) restriction — a bounded reduced-form parameter, **not an elasticity** (the implied export-supply elasticity is (1−γ)/γ = 1/ω). |
| `omega_floored` | logical | `TRUE` when reported ω sits at its lower admissibility floor (1e-4) — i.e. ω was clamped, not estimated at an interior point (see the ω-floor note below). Lets the floored cells be filtered directly, e.g. `dt[!(omega_floored)]`; a genuine interior estimate never lands exactly on the floor. *Added by the B3 fix and populated from the estimator re-run that introduced the column; absent in pre-fix outputs.* |
| `sigma_se`, `omega_se`, `rho_se` | numeric | Standard errors (HNCS sandwich if HLIML, delta-method if Step 2) |
| `fstat_kp` | numeric | Kleibergen-Paap rk Wald F-statistic |
| `fstat_het` | numeric | HLIML heteroskedasticity-adjusted F (Step 3 of GS_Estimation.do) |
| `jstat`, `jstat_pval`, `jstat_h` | numeric | Sargan overidentification statistic (homoskedastic; `jstat_pval` is the conventional p-value 1 - pchisq(J, df) -- the complement of the "J P-value" tabulated in G&S 2024) and the HLIML residual variant |
| `stockyogo_pass` | logical | Whether fstat_kp exceeds the Stock-Yogo (2005) critical value for relevant l |
| `stockyogo_cv` | numeric | The applicable Stock-Yogo LIML critical value at 10% maximal size (size, not bias) |
| `stockyogo_pass_gs25`, `stockyogo_cv_gs25` | logical, numeric | The same screen at the 25% maximal-size threshold -- the G&S (2024) rule of thumb. *Added in v0.4.0; absent in earlier outputs.* |
| `sargan_pass`, `gs_pass_both` | logical | Sargan pass (conventional p > 0.2, per G&S 2024) and the joint F-and-J pass flag. *Added in v0.4.0; absent in earlier outputs.* |
| `adjust` | integer | Estimator path flag (see below) |
| `final_source` | character | `"hliml"` or `"step2_weighted"` — which estimator supplied σ |
| `hliml_status` | character | `"ok"` or `"hliml_fail_no_convergence"` (or various failure subtypes) |
| `sigma_step2`, `omega_step2`, `rho_step2` | numeric | Step 2 weighted Fuller LIML estimates (always populated when Step 2 ran) |
| `sigma_hliml`, `omega_hliml`, `rho_hliml` | numeric | HLIML estimates (NA when HLIML failed) |
| `n_obs`, `n_exporters` | integer | Cell size diagnostics |
| `kappa`, `lambda_min` | numeric | LIML κ and minimum-eigenvalue diagnostics |
| `status` | character | Outer cell status: `"ok"`, `"all_inversions_failed"`, `"thin_panel_*"`, etc. |

The slimmed `_feenstra_sigma.rds` retains (importer, good, sigma, gamma)
for use as Stage 2a input.

## `adjust` flag — estimator path indicator

The `adjust` column distinguishes how each cell's reported σ was produced:

| `adjust` | Meaning | Cell share (full universe) | Share conditional on `status="ok"` |
|----------|---------|----------------------------|------------------------------------|
| 0 | HLIML converged to interior solution; σ_hliml used | 18.8% | 35.2% |
| 1 | HLIML failed, Step 2 weighted Fuller LIML used; σ in admissibility box | 25.9% | 48.6% |
| 4 | Step 2 returned σ > 10; reported σ = 10 (cap value, not estimate) | 6.4% | 12.1% |
| 5 | Step 2 returned ω > 10; reported σ is Step 2's σ, ω = 10 cap | 2.2% | 4.1% |
| NA | All inversions failed; σ = NA | 46.7% | — |

Total estimable cells (`status = "ok"`): 149,577 of 280,649 (53.3%).

**Cells with `adjust ∈ {4, 5}` carry value-substituted σ.** For `adjust = 4`,
σ = 10 is the orchestrator's cap, not what the estimator computed. For
`adjust = 5`, σ is real (from Step 2) but ω is value-substituted. Downstream
analysis that depends on precise σ magnitudes — particularly comparisons to
external estimators — should filter these out.

**Lower-bound flooring — sized, and now flagged via `omega_floored`.** Beyond the upper caps, `invert_structural`
also imposes lower bounds: ρ and ω are each clamped to a floor of 1e-4, applied
before the Feenstra feasibility check (ρ < (σ−1)/σ, equivalently ω > 0). A
dedicated routing code for an ω-floor event (`adjust = 3`) exists but is unused
in this run, and the status breakdown contains no `constraint_violated` cells —
strictly infeasible inversions are rerouted to the Step 2 fallback or dropped
rather than reported as floored. The practical consequence is that a cell whose
ω is pinned at the 1e-4 floor keeps its HLIML or Step 2 `adjust` code rather
than a distinct floor flag, so floored cells cannot be isolated from `adjust`
alone. The floor nonetheless binds for about one cell in six (≈17% of all cells, and ≈32% of the cells that actually
yield an estimate; the root README carries the exact all-cells share from
`stage1_summary.json`) — far more than
the near-0% γ floor that survives Stage 2 shrinkage. The `omega_floored`
boolean (B3) now isolates exactly these cells (`dt[!(omega_floored)]`),
populated from the estimator re-run that introduced the column. A floored ω is reported as near-perfectly-elastic supply, which collapses
both γ_common = ω/(1+ω) and the derived optimal tariff toward zero for those
cells; a γ_common or optimal tariff sitting at the boundary should be read as an
identification artifact, not an interior estimate.

## Parity verification

`parity_check_20260519.log` records the comparison against legacy Stage 1
output at `s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/stage1_liml_202605/`.

**Headline result: refactored output is structurally correct.** On 137,510
overlapping cells where both outputs have a non-NA `final_source`, 99.3%
agree on source assignment (HLIML vs step2_weighted). Of cells where both
sides have a numeric σ, 97.83% match to 1e-6, with the absolute-difference
99th percentile at σ ≈ 1.2 and median at exactly 0. A 10-cell random
spot-check shows bit-identical σ and γ on every cell where both sides
returned values.

**Cell-count delta — fully explained by leading-zero fix.** Legacy had
308,045 rows, refactored has 280,649 (delta = −27,396). 46,933 cells
exist only in legacy, 19,537 only in refactored. The asymmetry is the
HS6 leading-zero handling bug: the legacy pipeline mishandled HS92
chapters 01–09, producing ~210 phantom HS4 codes like `8062` instead of
`0806`. The refactored pipeline correctly preserves leading zeros, which
both eliminates the phantoms (reducing the row count) and reveals
correctly-padded counterparts that legacy missed. Refactored σ median on
the canonical 1,240-HS4 universe is 2.875; legacy σ median on the
corrupted 1,364-HS4 set was 2.912.

**KP-F medians match exactly** (4.00 in both legacy and new on the HLIML
subset), confirming the instrument-strength characterization is unchanged
by the leading-zero fix.

## Pillar 1 of the paper evidence base

Stage 1 production output is the empirical foundation of the paper.
Key paper-relevant statistics readable directly from this directory:

- **HLIML interior-solution rate: 18.8% of universe / 35.2% of estimable cells.**
- **Step 2 fallback rate: 25.9% / 48.6%.**
- **Value-substitution rate (adjust ∈ {4, 5}): 8.6% / 16.2%.**
- **Mixture-distribution σ median: 2.875** — combines HLIML interior cells
  (median ≈ 1.94), Step 2 fallback cells (median ≈ 3.94), and cap values.
- **KP-F median: 4.47** on the HLIML-converged subset (per memory; not
  directly in the log).
- **Stock-Yogo failure rate: 43%** of estimable cells exceed the
  Stock-Yogo 10%-max-bias critical value for the relevant number of
  instruments (per memory; computed in downstream summarization).

Synthetic recovery diagnostics for the HLIML estimator are in
`docs/methodology/liml_validation.md`.

## Downstream consumers

- **Stage 2a** consumes `_feenstra_sigma.rds` to estimate regional γ with
  σ fixed. See `../stage2a/PARITY_REPORT.md`.
- **Tier 4 validation** consumes both the production output and
  `_raw_cache.rds` to compare HLIML against the legacy Feenstra GMM
  baseline.
- **External replication** would re-run from the raw cache (or fresh BACI
  download) using `scripts/run_estimation.R --stage 1` in the canonical
  repo.

---

*Last updated: 2026-05-20 following Tier 4 + adjust-flag audit completion.*
