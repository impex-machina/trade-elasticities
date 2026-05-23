# Tier 4 Validation: HLIML vs Feenstra GMM (2026-05-20)

## Context

Tier 4 of the LIML validation harness (`validation/validate_liml.R`) compares the
refactored HLIML estimator's Stage 1 σ estimates against the pre-HLIML Feenstra
GMM Stage 1 σ estimates on overlapping (importer, HS4) cells. The GMM baseline
is the legacy Stage 2b production output archived at
`s3://trade-elast-baci-hs92-v202601-hs4/archive_feenstra_gmm_202604/`,
dedup'd to the cell level via median within (importer, good). This is the
in-house complement to the cross-paper benchmarks against Soderbery (2015) and
Grant & Soderbery (2024), and is the only head-to-head HLIML-vs-GMM comparison
available on our own BACI HS4 panel.

A post-hoc audit (2026-05-20) joined the harness's cell-level output to the
production Stage 1 output (`refactored_stage1_liml.rds`) on (importer, hs4) to
surface the production `adjust` flag for each cell. The flag distinguishes
HLIML interior solutions (`adjust = 0`), Step 2 weighted Fuller LIML fallback
(`adjust = 1`), and orchestrator value substitution where the underlying
estimator returned σ or ω outside the admissibility box (`adjust = 4` for σ
clamped to cap = 10, `adjust = 5` for ω clamped to cap = 10). The audit-based
analysis below supersedes earlier σ ≈ 10 heuristic identification of "boundary"
cells.

## Run parameters

| Parameter           | Value                                                          |
|---------------------|----------------------------------------------------------------|
| Date                | 2026-05-20                                                     |
| BACI input          | `baci_hs92_v202601_elast_country_hs4_raw_cache.rds` (113.8M rows) |
| GMM input           | `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (8.08M rows → 233,561 cells after dedup) |
| Cells sampled       | 200                                                            |
| HLIML success rate  | 140 / 200 (70%)                                                |
| Pre-filter          | ≥3 exporters, ≥5 periods                                       |
| Wall time           | 7.0 min                                                        |

A two-line schema patch was applied to `validate_liml.R` (lines 686, 689) to
accept the BACI raw cache's `good` and `cusval` column names; the symmetric
edit was made at lines 498, 501 for the alternate loader path.

## Sample composition by `adjust` code

The 140-cell Tier 4 sample composition compared to the full production
universe:

| `adjust`           | Tier 4 sample | Production universe (280,649) |
|--------------------|---------------|-------------------------------|
| 0 (HLIML interior) | 35.7% (n=50)  | 18.8%                         |
| 1 (Step 2 fallback)| 45.0% (n=63)  | 25.9%                         |
| 4 (σ clamped)      | 15.7% (n=22)  | 6.4%                          |
| 5 (ω clamped)      | 3.6% (n=5)    | 2.2%                          |
| NA (all failed)    | 0% (excluded) | 46.7%                         |

The Tier 4 universe is the intersection of (estimable, overlapping with GMM,
passes `min_exporters≥3` and `min_periods≥5`), so production NA cells are
excluded by construction. Within the estimable subset (`status = "ok"`,
149,577 cells in production), the population shares are roughly 35/49/12/4
across {0, 1, 4, 5}. The Tier 4 sample is reasonably representative of the
estimable universe but skews slightly toward censored cells (19.3% vs ~16% in
production), likely due to the additional pre-filter requirements.

## Headline results

### Full sample (n = 140)

| Statistic                | Value   |
|--------------------------|---------|
| Median ratio (HLIML/GMM) | 0.724   |
| Mean ratio (HLIML/GMM)   | 1.068   |
| Ratio of medians         | 0.755   |
| Spearman ρ               | 0.190   |
| Pearson r                | −0.062  |
| Median σ (HLIML)         | 3.04    |
| Median σ (GMM)           | 4.02    |

The full sample headline includes value-substituted cells (`adjust ∈ {4, 5}`)
on the HLIML side and one extreme outlier (σ_GMM ≈ 11,000) on the GMM side.
The mean ratio (1.068) substantially exceeds the median ratio (0.724) because
of the 27 value-substituted cells where the harness reports σ = 10 against
GMM values often well below 10, inflating cell-level ratios. The disaggregation
in the next section gives the honest reading.

### Clean comparison subset (n = 112)

Excluding 27 value-substituted cells (`adjust ∈ {4, 5}`) and 1 GMM extreme
outlier (`sigma_stage1 ≥ 50`):

| Statistic                | Value   |
|--------------------------|---------|
| Median ratio (HLIML/GMM) | 0.675   |
| Mean ratio (HLIML/GMM)   | 0.851   |
| Spearman ρ               | 0.200   |
| Pearson r                | 0.104   |
| Median σ (HLIML)         | 2.75    |
| Median σ (GMM)           | 3.92    |

On the clean subset, HLIML produces a **32.5% reduction in median σ** relative
to GMM, in the same direction and approximate magnitude as the Soderbery
(2015) LIML bias correction (~35% on SITC3). Mean and median of ratios both
fall on the same side of the PASS threshold.

### Stratification by estimator path

The clean subset combines cells where HLIML actually converged (`adjust = 0`)
with cells where the Step 2 weighted Fuller LIML fallback supplied the
estimate (`adjust = 1`). These are different estimators, and the bias
correction differs materially across them:

| Subset                       | n  | Median ratio | Median σ (HLIML) | Median σ (GMM) | Spearman ρ |
|------------------------------|----|--------------|------------------|----------------|------------|
| HLIML interior (adjust = 0)  | 49 | **0.564**    | 2.20             | 3.85           | 0.203      |
| Step 2 fallback (adjust = 1) | 63 | 0.730        | 3.12             | 4.03           | 0.264      |

**The 32.5% combined-headline correction is a weighted average of two
qualitatively different stories.** When HLIML converges to an interior solution
and is used directly (n = 49), the bias correction is 43.6% — substantially
larger than the combined headline and slightly exceeding the Soderbery (2015)
benchmark. When Step 2 weighted Fuller LIML supplies the estimate after HLIML
fails to converge (n = 63), the correction is 27.0% — meaningful but smaller.

This stratification is the more publishable finding from Tier 4. The
heterogeneous bias correction across estimator paths suggests that
characterizing "the σ produced by the pipeline" without disaggregating by
`adjust` understates the magnitude of HLIML's correction on cells where HLIML
actually runs.

## Diagnostic findings

### 1. Value substitution affects 19.3% of the Tier 4 sample

27 of 140 cells have `adjust ∈ {4, 5}`. For these cells, the reported σ is
**the orchestrator's cap value (10.0), not the estimator's output**:

- 22 cells with `adjust = 4`: HLIML returned `hliml_fail_no_convergence`; the
  Step 2 fallback then produced σ > 10, which the orchestrator clamped to
  σ = 10. The cells' "true" Step 2 σ values range from ~10 to plausibly much
  higher and are not preserved in production output.
- 5 cells with `adjust = 5`: same path, but Step 2 produced ω > 10. The
  reported σ in these cells comes from Step 2 and is itself interior; only ω
  is clamped. For these 5 cells, σ_new lies in (1.76, 3.44).

This is **deliberate orchestrator-level censoring**, not estimator failure.
The `final_source` column ("hliml" vs "step2_weighted") and `adjust` code
together disambiguate. In population terms, `adjust ∈ {4, 5}` accounts for
8.6% of all 280,649 production cells and ~12% of the estimable subset.

### 2. Rank disagreement is structural

Spearman ρ between HLIML and GMM σ estimates:

- Full sample (n=140): 0.190
- Clean subset (n=112): 0.200
- HLIML interior only (n=49): 0.203
- Step 2 fallback only (n=63): 0.264

Rank correlation hovers near 0.20 across every reasonable subsetting,
including the strictest (HLIML-success-only). Pearson correlation is similarly
flat near 0.10. **The two estimators recover σ via structurally different
mechanisms; they do not just produce shifted versions of the same ranking.**
This is the most distinctive empirical finding from Tier 4 and persists after
every plausible cleaning of the sample.

Combined with the population-level convergence rates (HLIML interior on 21%
of all production cells, conditional on estimability 35%), this supports
framing the paper around estimator-disagreement accounting rather than a
single-headline bias correction. Two estimators trained to recover the same
structural parameter on the same data produce per-cell estimates with
ρ ≈ 0.20 — that's the empirical phenomenon worth explaining.

### 3. GMM right tail is a single-cell numerical failure

Only one cell has σ_GMM > 50: cell `398_4301` (importer 398 = Kazakhstan,
HS4 = 4301 raw furskins) with σ_GMM = 11,023.6. This single cell drives the
21× gap between mean σ_GMM (84.6) and median σ_GMM (4.02) across the 140-cell
sample. Most likely cause is a thin (importer, HS4) panel where the GMM
objective had a near-flat ridge or near-singular Hessian; it escaped legacy
pipeline QA filters and was carried into the archived output. Excluding it
has minimal effect on the headline ratios.

## Methodological notes and limitations

- **Tier 4 estimator vs production estimator: near-perfect reproduction.**
  138 of 140 cells have |σ_Tier4 − σ_production| < 0.01 (median diff = 0.000).
  Two cells show larger differences: `178_8422` (Δ = −0.022, both interior)
  and `376_8305` (Δ = +8.41, where Tier 4 landed at σ = 10 and production
  landed at σ = 1.59, both flagged `adjust = 0`). The latter cell suggests
  occasional BFGS path-dependence around degenerate optima; 1 cell of 140
  (0.7%) is below the threshold where this would materially affect headline
  ratios but is worth flagging.

- **Cell identifiers in the comparison frame are reduced to bare `cell_id`
  strings** (`{importer}_{hs4}`, e.g. `100_7204`) during the harness's dedup
  step. The original (importer, hs4) keys are recoverable via `tstrsplit`
  but were not preserved natively in the harness output; this audit
  reconstructed them via the post-hoc join script
  `validation/tier4_adjust_join.R`. A future harness modification could surface
  `adjust`, `final_source`, and `hliml_status` directly in `result$comp`.

- **The (10, 10) σ/ω cap is set as a default argument to the orchestrator**
  (`sigma_start_cap = 10`, `omega_start_cap = 10` in `liml_estimator.R` lines
  857–858). Widening these caps would convert some `adjust ∈ {4, 5}` cells
  into interior solutions, but only for the underlying estimator's true
  optimum; cells where the optimizer is genuinely unbounded would simply
  re-clamp at a higher cap. Whether the current caps are correctly calibrated
  for HS4 BACI is an open methodological question.

- **n = 140 is adequate for headline-magnitude inference but thin for
  stratified analysis.** The HLIML-interior-only subset (n = 49) and Step 2
  fallback subset (n = 63) are particularly susceptible to sampling noise on
  the rank correlation. A 1,000-cell follow-up would tighten all confidence
  intervals.

## Artifacts

- `docs/methodology/tier4_comp.csv` — original cell-level comparison (140
  rows; columns: `cell_id, sigma_new, omega_new, sigma_stage1`)
- `docs/methodology/tier4_comp_with_adjust.csv` — augmented comparison with
  production `adjust`, `hliml_status`, `final_source`, and per-step σ/ω
  estimates joined back from `refactored_stage1_liml.rds`
- `docs/methodology/tier4_hliml_vs_gmm.md` — this document
- Scripts: `validation/capture_tier4_validation.R`,
  `validation/sanity_check_tier4.R`, `validation/tier4_adjust_join.R`,
  `validation/tier4_recompute_with_adjust.R`
- Mirrored on S3 at
  `s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/validation/`
