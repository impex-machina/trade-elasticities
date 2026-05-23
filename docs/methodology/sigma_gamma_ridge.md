# σ-γ ridge analysis: IPW-weighted LIML-only joint

> **Note:** Originally written as `stage2_liml_202605/sigma_gamma_ridge_ipw.md`
> in the pre-refactor working directory. Reflects the May 2026 production
> run. The two figure references (`figures/02_sigma_gamma_joint.png` and
> `figures/09_sigma_gamma_joint_ipw.png`) point at the legacy figures
> directory, which is **not** part of this repository. The plots are
> preserved with the legacy run at the projects-tree `_archive/` and on S3
> (`s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/`,
> under `stage2_liml_202605/figures/`). See the Provenance section of
> `README.md`.

**Run.** 2026-05-14 17:34 EDT

## Motivation

The σ-γ joint plot in the 2026-05-14 heterogeneity report (`figures/02_sigma_gamma_joint.png`, retained in the local archive) shows a bright vertical stripe at σ ≈ 2.91 — cells where Stage 1 LIML failed and Stage 2 used the global median sigma fallback. The stripe contains ~29% of all cells and contaminates any quantitative σ-γ joint analysis.

Filtering to `sigma_provenance == "LIML"` removes the stripe but introduces selection bias: LIML succeeds preferentially on high-σ cells (median σ shifts from 2.91 to ~5 in the LIML-only sample).

Approach: fit a propensity model for LIML success on observable features, then inverse-weight LIML cells to recover the σ distribution we'd see if LIML succeeded equally everywhere.

## Method

Propensity model:

```
logit P(LIML | features) = α + Σ β_hs · 1(hs_section) + Σ γ_reg · 1(region) + δ · log(avg_trade)
```

Fit on 5e+05 SE-strict cells. McFadden R² = 0.247 (modest, as desired — we want calibrated propensities, not a separating model).

Weights `1/p̂` for LIML cells, capped at the 99th percentile to limit extreme values, then normalized to sum to N_LIML.

## Marginal σ distribution

| Sample | N | σ p25 | σ p50 | σ p75 | γ p50 | R1 p50 |
|--------|---|-------|-------|-------|-------|--------|
| Full SE-strict (contains fallback) | 720,982 | 2.91 | 3.21 | 7.42 | 0.225 | 0.184 |
| LIML-only (unweighted) | 500,752 | 2.99 | 5.28 | 10.00 | 0.209 | 0.173 |
| LIML-only (IPW-weighted) | 500,752 | 2.97 | 5.19 | 10.00 | 0.208 | 0.172 |

**Reading the table.** Compare row 2 (LIML unweighted) to row 3 (LIML IPW). If IPW pulls the σ median down toward row 1 (full SE-strict), the propensity model is capturing some of the selection. If it stays stuck near the unweighted LIML median, the observable features don't explain the selection mechanism and the residual bias is on unobservables.

## σ-γ Spearman correlation

Direct test of the σ-γ ridge: under a working two-stage estimator, ρ should be ~0. A strong positive (or negative) ρ in the LIML-only sample would suggest the ridge wasn't fully broken.

| Sample | ρ(σ, γ) |
|--------|---------|
| Full SE-strict (contains fallback) | -0.232 |
| LIML-only unweighted | -0.092 |
| LIML-only IPW-weighted | -0.099 |

## Plot

![IPW joint](figures/09_sigma_gamma_joint_ipw.png)

## Caveats

- IPW assumes the propensity model is correctly specified. The McFadden R² is modest, meaning the features (HS section + region + log trade) capture only part of the selection mechanism. Residual bias on unobservables is possible.
- The fallback-stripe contamination affects σ but not γ point estimates (γ was estimated successfully in all `gamma_se_status=="ok"` rows; only σ was imputed). So `gamma`-only analyses don't need this correction.
- This is a follow-up diagnostic, not a primary deliverable. The headline heterogeneity findings in the 2026-05-14 report (local archive) stand.
