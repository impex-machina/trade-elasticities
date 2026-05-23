# Stage 2 — Country gamma with fixed σ and shrinkage

> **Note:** Originally written as `stage2_liml_202605/README.md` in the
> pre-refactor working directory. Reflects the May 2026 production run.
> The `data/legacy/...` paths below are the historical record of the
> legacy run; that tree is **not** part of this repository. It is
> preserved at the projects-tree `_archive/` and on S3
> (`s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/`).
> The reproducibility section at the end documents the *legacy* workflow
> as a historical record; the equivalent CLI-driven workflow will be
> documented once parity is verified. See the Provenance section of
> `README.md`.

Stage 2 output: Soderbery (2018) three-stage fixed-sigma + shrinkage
estimator. Sigma input from Stage 1 LIML (see `stage1_liml.md`).

Produced: 2026-05-12 (initial Stage 2a + 2b run), 2026-05-13 (provenance
tagging + inspection), 2026-05-14 (Stage 2b re-run with γ standard errors
via penalized Gauss-Newton; SE-enabled heterogeneity report). See
`refactor_history.md` for the code inventory.

## Files

All filenames below are relative to `data/legacy/stage2_liml_202605/`
in the archived legacy tree (see top note).

### Country-level (Stage 2b — the main deliverable)

| File | Description |
|------|-------------|
| `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` | Translated LIML output (LIML rows + `gamma_common` renamed to `gamma`, `status == "ok"` mapped to `convergence == 0L`). This is the actual file Stage 2 consumed. |
| `baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` | **Primary analytical output.** 8.13M cell-exporter rows with γ point estimates, standard errors, status flags, and identification exposure. 15-column schema (see below). |
| `baci_hs92_v202601_elast_country_hs4_fixed_sigma.csv` | CSV mirror of the above |
| `baci_hs92_v202601_elast_country_hs4_fixed_sigma_tagged.rds` | Superset with `sigma_provenance` column (`LIML` vs `fallback_median`). Use this for analyses combining γ-SE-based filtering with σ-source filtering. |
| `baci_hs92_v202601_elast_country_hs4_fixed_sigma_tagged.csv` | CSV mirror |
| `baci_hs92_v202601_elast_country_hs4_summary.rds` | Per-product summary table |
| `baci_hs92_v202601_elast_country_hs4_summary.txt` | Human-readable summary report |

### Regional (Stage 2a)

| File | Description |
|------|-------------|
| `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds` | Stage 2a regional gamma estimates. 442,525 rows. Sigma column = regional median of country-level LIML sigma (not directly comparable to country file's sigma). |
| `baci_hs92_v202601_elast_regional_hs4_fixed_sigma.csv` | CSV mirror |
| `baci_hs92_v202601_elast_regional_hs4_summary.rds` | Per-product summary |
| `baci_hs92_v202601_elast_regional_hs4_summary.txt` | Human-readable summary |

### Analysis outputs (2026-05-14 SE-enabled heterogeneity report)

The full heterogeneity report and its supporting CSVs/figures (the
2026-05-14 legacy run) are retained in the project's local archive and are
not part of the published repository. The headline findings are summarized
below.

| File | Description |
|------|-------------|
| `heterogeneity_sensitivity_grid.csv` | 18-row table: ratios under each (CV, mode) combination, both sides |
| `heterogeneity_hs_section_se_strict.csv` | R1 by HS section in the SE-strict CV<0.5 sample |
| `matched_hs4_cv_{strict,medium,loose}.csv` | Per-HS4 matched comparison vs Soderbery at each CV |
| `figures/` | Three plots referenced by the report (γ density, σ-γ joint, R1 by HS section). Not migrated into the new repo; available in the legacy snapshot. |

The σ-γ ridge follow-up analysis is at
`docs/methodology/sigma_gamma_ridge.md`.

### Logs (in `data/legacy/stage2_liml_202605/` if present in the snapshot)

| File | Description |
|------|-------------|
| `stage2_full.log` | Original Stage 2a + 2b runner log (2026-05-12) |
| `stage2b_full.log` | Re-run log with SE methodology (2026-05-14) |
| `inspection_country.log` | Output of `inspect_country.R` against the tagged file |

## Output schema (country-level, 15 columns)

| Column | Type | Description |
|--------|------|-------------|
| `importer` | character | ISO numeric importer code |
| `exporter` | character | ISO numeric exporter code |
| `good` | character | HS4 product code |
| `sigma` | numeric | Elasticity of substitution. From Stage 1 LIML or global median fallback |
| `gamma` | numeric | Inverse export supply elasticity |
| `gamma_se` | numeric | Penalized Gauss-Newton standard error on γ. NA if not estimable (see status column) |
| `gamma_se_status` | character | SE quality flag: `ok`, `boundary`, `plateau`, `non_converged`, `singular`, `tier3_prior`, `insufficient_df`, or NA for legacy all-tier3 cells |
| `gamma_exposure` | integer | Count of residual rows contributing to γ identification. Low values (≤2) indicate weak identification |
| `ref_exporter` | character | Reference exporter chosen for this (importer, good) cell |
| `convergence` | integer | optim() convergence code. 0 = converged, -1 = prior-assigned (Tier 3), other = non-convergence |
| `obj_value` | numeric | Final SSR at optimizer convergence |
| `tier` | integer | 0 = reference, 1 = full identification, 2 = import-side only, 3 = prior-assigned |
| `avg_trade` | numeric | Average bilateral trade value at the cell (for trade-weighted aggregations) |
| `opt_tariff` | numeric | Optimal-tariff at the cell, computed from Tier 0/1/2 exporters only |
| `opt_tariff_all` | numeric | Optimal-tariff at the cell, computed from all exporters including Tier 3 imputations |

## Standard errors methodology

γ standard errors use **penalized Gauss-Newton**:

```
V(γ̂) = σ̂² · (J'WJ + 2λ · diag(1/γ̂²))⁻¹
```

where J is the residual Jacobian at the optimum (analytic, computed by
`src/het_obj_fixed_sigma_jacobian_rcpp.cpp`), W is the diagonal weight
matrix, σ̂² = SSR/df, and λ is the shrinkage parameter from Stage 2b
config (0.1 by default).

Three methodology notes worth flagging:

1. **Don't use `optim()$hessian` directly for NLS SE.** It returns the full
   Hessian of the SSR, which includes residual×second-derivative terms.
   For strongly nonlinear models like Soderbery's, this overestimates the
   variance by ~50%. We use the Gauss-Newton matrix J'WJ instead, computed
   from the analytic Jacobian.

2. **Sandwich-robust SE is wrong for this NLS structure.** Despite being
   the "robust" textbook choice, Monte Carlo testing shows the sandwich
   formula systematically underestimates true variance by ~30% in this
   setting (residual-Jacobian correlation at the NLS optimum violates
   the i.i.d. assumption behind sandwich derivation). Gauss-Newton is the
   correct formula here.

3. **Under shrinkage, the prior Hessian must be included.** Standard
   Gauss-Newton overstates SE by ~30% in shrinkage regime; adding
   `2λ · diag(1/γ̂²)` to J'WJ brings calibration within 5% of empirical
   variability.

The full derivation is at `stage2_derivation.md`. The SE calibration was
verified by Monte Carlo; the original `monte_carlo_se*.R` scripts were lost
during the refactor and are not recoverable. A single reconstructed harness,
`monte_carlo_se.R`, lives in `validation/`, and its summary output is
`se_calibration_mc_summary.csv`.

## SE status table breakdown

| Status | Count | Share | Interpretation |
|--------|-------|-------|-----------------|
| `ok` | 4,932,371 | 60.70% | Finite SE, calibrated. Safe for inference |
| `tier3_prior` | 2,088,554 | 25.70% | Tier 3 row; γ assigned from prior, no SE |
| `boundary` | 561,812 | 6.91% | γ < 0.01 (at lower bound); SE undefined |
| `non_converged` | 300,914 | 3.70% | optim convergence != 0 |
| `plateau` | 93,485 | 1.15% | γ > 5; SE undefined |
| NA | 67,826 | 0.83% | Legacy all-tier3 early-return cells (tier 0 ref + tier 3 prior-assigned) |
| `singular` | 51,600 | 0.63% | J'WJ + λH_prior numerically singular |
| `insufficient_df` | 29,836 | 0.37% | Fewer observations than parameters |

The 60.7% with `ok` SE is the strongest subset for SE-based downstream
filtering (CV cuts, confidence intervals).

## Exposure quantiles

| 0% | 25% | 50% | 75% | 100% |
|----|-----|-----|-----|------|
|  1 |  2  |  2  |  2  | 211  |

Median exposure of 2 reflects HS4 thinness: most (importer, exporter, HS4)
cells have only a few residual rows after period_count filtering. Cells with
exposure ≤2 have SEs that correctly reflect weak identification.

## Headline numbers

- 1,240 HS4 products × 233 importers × 233 exporters covered
- Stage 2b country output: 8,126,398 cell-exporter rows
  - Tier 1 (full identification): 70.6%
  - Tier 3 (prior-assigned): 26.3%
  - Tier 0 (reference exporter): 3.0%
  - Tier 2 (import-side only): 0.2%
- True convergence rate (among Tier 0/1/2 only): 94.63%
- γ SE coverage (status == `ok`): 60.7%

## Sigma provenance breakdown

| Provenance | Rows | Share |
|------------|------|-------|
| `LIML` (cell-specific from Stage 1) | 5,775,087 | 71.07% |
| `fallback_median` (global median 2.911845) | 2,351,311 | 28.93% |

Cross-checked: 0 mismatches in 1,000-row spot-check between Stage 2 sigma
and Stage 1 LIML sigma for `LIML`-tagged rows. All `fallback_median` rows
have sigma exactly 2.911845.

Fallback is concentrated in:
- Tier 1 rows: 27% of Tier 1 rows have fallback sigma. **These rows had
  gamma genuinely optimized against the wrong sigma.** Their gamma
  estimates are biased to the extent the true cell sigma deviates from
  the global median 2.911845.
- Tier 3 rows: 33% of Tier 3 rows have fallback. Less consequential
  since Tier 3 gamma is prior-assigned, not optimized.
- Concentrated in agricultural HS4 codes (0901 coffee, 0402 milk/cream,
  0804 dates/figs, 0902 tea, etc.) — products with seasonality and
  unit-value heterogeneity that defeat LIML identification.

## σ-γ ridge diagnostic

A standard concern with Feenstra-style estimators is the σ-γ identification ridge: when σ and γ are estimated jointly, the objective surface has a near-flat ridge along which different (σ, γ) combinations fit the data nearly equally well. Soderbery's three-stage approach is designed to break this by estimating σ first via LIML, then conditioning on σ to estimate γ.

Empirical check: Spearman ρ between σ and γ in the SE-strict (CV<0.5) sample, under three filtering regimes:

| Sample | ρ(σ, γ) | Interpretation |
|--------|---------|-----------------|
| Full SE-strict (incl. fallback) | −0.232 | Apparent correlation driven by σ-fallback stripe |
| LIML-only, unweighted | −0.092 | Ridge effectively broken |
| LIML-only, IPW-weighted | −0.099 | Same conclusion after correcting for LIML selection bias |

The full-sample ρ = −0.23 is an artifact: the global-median sigma fallback (2.911845) creates a vertical stripe in the joint distribution, and cells in that stripe have slightly elevated γ on average, manufacturing a spurious negative correlation when σ varies.

On the LIML-only subsample (where σ is genuinely cell-specific), ρ collapses to −0.09. Inverse-propensity weighting on (HS section, importer region, log avg_trade) — the observable predictors of LIML success — barely moves the correlation, so the residual −0.10 is not a selection artifact either. It is probably real, mild economic structure (products with higher σ also tending to have slightly lower γ).

See `sigma_gamma_ridge.md` for the full diagnostic.

## Headline findings vs Soderbery (2018)

From the 2026-05-14 SE-enabled heterogeneity report (retained in the local
archive):

**Distribution.** σ medians match closely (2.91 ours vs 2.87 Soderbery;
R2 = 1/(σ-1) = 0.523 vs Soderbery's published 0.532). γ medians differ:
0.22–0.28 ours under SE-strict filtering, vs 0.42 Soderbery — a stable
~0.10 R1 gap that does not close under stricter filtering.

**Matched-cell rank correlation** (Spearman ρ at HS4 level, symmetric
SE filtering on both sides):

| CV | Matched HS4 | ρ(γ) | ρ(σ) | ρ(R1) |
|----|-------------|------|------|-------|
| 0.25 | 1,076 | 0.307 | 0.180 | 0.307 |
| 0.50 | 1,119 | 0.400 | 0.126 | 0.401 |
| 1.00 | 1,129 | 0.394 | 0.042 | 0.394 |

Pre-SE versions showed ρ(γ) around 0.16–0.21 — the SE-based filtering
roughly doubles the agreement once weakly-identified cells are excluded
on both sides. ρ(σ) remains weak: σ-level matches Soderbery but the
**ranking** of HS4 codes by σ doesn't, possibly due to the period
extension (1995–2024 vs 1994–2008).

**HS section structure.** R1 ranges from 0.13 (Plastics & rubber) to
0.43 (Works of art) across HS sections, with most sections at 0.15–0.20.
Economic ordering is sensible (differentiated manufactures lower γ;
homogeneous agriculture/raw materials higher) — but uniformly shifted
~0.10 below Soderbery's section-level estimates.

The R1 gap is most plausibly explained by sample-period differences
(post-2008 trade reshufflings absent from Soderbery's sample) and/or
methodological differences (LIML-σ + shrinkage-γ pipeline vs Soderbery's
joint estimator).

## Downstream filtering policy

With `gamma_se` and `gamma_se_status` available, four filtering tiers
work well:

1. **Raw.** No filters. All 8.13M rows. Use for descriptive scope.
2. **SE-strict.** `gamma_se_status == "ok"` AND `gamma_se/gamma < 0.5`.
   ~721K rows. Cleanest subset for confidence intervals and CV-based
   downstream comparisons.
3. **LIML-only.** Add `sigma_provenance == "LIML"`. ~501K rows. Cleanest
   subset for σ-γ joint analysis, but **note selection bias**: LIML
   succeeds preferentially on high-σ cells (median σ shifts from 2.9 to 5.3).
4. **Identification-strict.** Add `gamma_exposure >= 5`. Drops cells where
   prior carries identification rather than data.

## Reproducibility (legacy workflow, 2026-05)

> **Local replication is possible without AWS.** The commands below
> describe the EC2/S3 workflow as it was actually run in May 2026; the
> refactored pipeline runs on any local machine via
> `scripts/run_estimation.R`. See the "Replication setup" section in
> the root `README.md` for the local workflow.
>
> **Note:** This section documents the workflow as it was actually run
> in May 2026 — EC2 + S3 + a handful of separate scripts. The refactored
> CLI in `scripts/run_estimation.R` consolidates Stages 1, 2a, and 2b
> into a single command, but numerical parity between the new CLI and
> the legacy outputs in `data/legacy/` has not been verified. The legacy
> workflow below is the authoritative reproducibility recipe until
> parity is established.

To recreate from scratch:

1. Set up EC2 (c7a.16xlarge, 62 cores).
2. `aws s3 cp s3://.../source/ . --recursive`
3. `aws s3 cp s3://.../stage1_liml_202605/baci_..._feenstra_sigma_liml.rds .`
4. `aws s3 cp s3://.../BACI_HS92_V202601/ BACI_HS92_V202601/ --recursive`
5. `Rscript translate_liml_to_feenstra_schema.R <liml.rds> baci_..._feenstra_sigma.rds`
6. `Rscript run_est_baci_hs92_v202601_hs4.R` (~60 min)
7. `Rscript tag_sigma_provenance.R <liml.rds> <fixed_sigma.rds> <tagged.rds>`
8. `Rscript inspect_country.R 2>&1 | tee inspection_country.log`
9. `Rscript heterogeneity_full.R` (analysis only; uses tagged file as input)
10. Upload all outputs to this prefix.

Stage 1 wall-clock not included (skipped because Stage 1 output already
exists).
