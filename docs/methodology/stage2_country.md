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
| `gamma_shrink_wt` | numeric | Effective-shrinkage diagnostic: share of curvature at the optimum contributed by the log-ridge prior (0 = pure data, 1 = pure prior). NA for Tier-3, non-converged, and SE-unavailable cells. *Added in v0.4.0; absent in earlier outputs.* |
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

4. **The reference exporter's γ_k is identified only through the export
   side of the other exporters (patch 0062, 2026-09-22 fresh-eyes
   review).** The import side supplies one time-averaged Eq. (10) moment
   per non-reference exporter, each involving only (γ_j, γ_k): J
   equations in J + 1 unknowns. The reference exporter has no Eq. (11)
   row of its own (`build_export_moments()` runs over the Tier-1
   non-reference exporters), so γ_k is pinned by the over-identification
   the Tier-1 export rows add: each such row identifies its own γ_j
   directly, and the corresponding import-side equation then identifies
   γ_k. In a cell with no Tier-1 exporter the system is short by one
   equation and only the log-ridge prior (λ) identifies γ_k; at the
   production tier mix (about 70% of rows Tier 1) this is rare, and
   `gamma_exposure` / `gamma_shrink_wt` on the `tier == 0` row show it
   cell by cell.

The full derivation is at `stage2_derivation.md`. The SE calibration was
verified by Monte Carlo; the original `monte_carlo_se*.R` scripts were lost
during the refactor and are not recoverable. A single reconstructed harness,
`monte_carlo_se.R`, lives in `validation/`, and its summary output is
`se_calibration_mc_summary.csv`.

### Variance formula (patches 0069/0070; v0.7.4 default `sandwich`)

`J'WJ` is the Gauss–Newton Hessian of the *half* objective (SSR/2 + (λ/2)Σ(ln γ − ln g)²), whose ridge curvature at the prior is λ/γ². The formula shipped through v0.7.3, `s²(J'WJ + 2λ/γ²)⁻¹`, added the ridge in full-objective units to a data term in half-objective units. Writing x = J'WJ/P with P = λ/γ², the sampling variance of the penalized estimator is `s² A⁻¹ J'WJ A⁻¹` with A = J'WJ + P (→ 0 as the prior dominates, → `s²(J'WJ)⁻¹` as the data dominate), and the legacy formula's ratio to it is 1 + 1/(x² + 2x): ≈ 1 for x ≥ 3, 1.33 at x = 1, 13 at x = 0.04. The Pillar-3 MC sits at x ≈ 2 (its unpenalized-GN overshoot of 48% and penalized-GN 8% both follow from that x), where legacy is within 6% of the sampling SD; the shipped table's median `gamma_shrink_wt` of 0.98 (v0.7.3) corresponded to x ≈ 0.04.

`--stage2-se {sandwich|posterior|legacy}` (config `stage2_se`, checkpoint-stamped) selects: `sandwich` (v0.7.4 default, and the rule for an absent key) = the sampling variance above; `posterior` = `s²(J'WJ + λ/γ²)⁻¹`, a posterior-style variance under the ridge read as a prior — not shipped, because λ is a tuning constant rather than a calibrated prior precision, so the number has no definition of its own; `legacy` = the v0.7.3 reproducer. The same ridge curvature (λ/γ² except under legacy) enters `compute_dgamma_dsigma()`, so `dgamma_dsigma`, `gamma_se_total` and the `sigma_robust` screen move with the form (at production shrinkage the legacy derivative is ≈ 0.4× the exact implicit-function derivative, the λ/γ² one ≈ 0.8–0.9×; the remainder is the Gauss–Newton approximation). `gamma_shrink_wt` is P/(J'WJ + P) with the P of the chosen form: the implied data share is 1 − s under sandwich/posterior and 2(1−s)/(2−s) under legacy (`analysis/stage2_shrinkage_census.R --shrink-wt-def`).

**v0.7.4-rc A/B (points bit-identical across the three passes, `gate_points.txt`).** Median `gamma_se` legacy 0.547 / posterior 0.736 / sandwich 0.165 on a median γ of 0.658; `gamma_se_total` 0.484 → 0.127 (sandwich); `sigma_robust` TRUE 23.9% → 23.3%. Reading rule for consumers: when `gamma_shrink_wt` is near 1 the estimate is mostly the good-level prior, and a small `gamma_se` reflects the stability of that shrunk estimate, not information about γ — read the two columns together. Calibration: on the structural DGP at production shrinkage the sandwich SE is 1.1–2.5× the empirical sampling SD at T ≤ 50 (conservative) against 5–20× for legacy (`audit_experiments2.R`, Experiment D); Pillar 3 captures the shipped form since patch 0076 (`pen_sandwich` in `se_calibration_mc_summary.csv`, five regimes: the original 2×2 grid, whose λ = 0.1 cells sit at `gamma_shrink_wt` ≈ 0.26, plus a *prod-shrink* regime with the design scaled so that `gamma_shrink_wt` ≈ 0.90, the shipped table's median). The shipped SE's median ratio to the empirical sampling SD is 0.98–1.03 across the five regimes and 1.03 in the production-shrinkage regime, where the legacy formula gives 2.19, the White sandwich 8.0 and the unpenalized GN 9.3 — the legacy factor being √(1 + 1/(x² + 2x)) = 2.24 at x = J'WJ/P = 0.12, as derived above. Numbers in `results/pillar3_summary.json`. Stage 2a's SE columns in v0.7.4 are legacy-form (the regional pass ran before the SE decision; nothing downstream consumes them — priors and lookups use the regional points) and are re-run under the default at the next box session.

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

## Log-ridge domain (patches 0068/0070; v0.7.4 default `all`)

The Stage-2 objective is `sum_rows w_r r_r(gamma)^2 + lambda * sum_i (ln gamma_i - ln g)^2`. Through v0.7.3 the ridge was applied only to coordinates with `gamma_i > 1e-5` while the L-BFGS-B lower bound is `1e-6`, so the band `(1e-6, 1e-5]` was penalty-free and the penalty just above it was `lambda (ln 1e-5 - ln g)^2` — about 11 objective units at `lambda = 0.1` beside a data SSR of order `1e-2 .. 1`. A line search that carried a coordinate below `1e-5` saw the objective fall by that amount and accepted; inside the band the ridge gradient is zero and the data gradient too small to climb out. On the structural DGP the v0.7.3 objective parked 1.5–6% of coordinates there under strong data pull (14–52% of cells with at least one) and an objective penalizing every coordinate never did.

On the shipped v0.7.3 tables (`results/stage2_shrinkage_census.json`, Block A count of 2026-09-25): 828,294 of 4,992,699 directly estimated Stage-2b rows (16.6%) sat at the `1e-6` floor, 13 log units below their prior (tier 0 9.0%, tier 1 16.9%, tier 2 14.3%); 61.7% of cells contained a floor exporter and 8.8% had their *reference* exporter there; those rows were the entire `gamma_se_status = boundary` population (11.3% of all rows); Stage 2a had 14.4% of its estimated rows at the floor and 39 of 1,240 goods a floor prior; the cell-level median `opt_tariff` was 0.526 with floor cells and 0.736 without.

`--stage2-ridge-domain {all|legacy}` (config `stage2_ridge_domain`, checkpoint-stamped): `all` (v0.7.4 default, and the rule for an absent key) penalizes every coordinate with `gamma_i > 0`; `legacy` reproduces every release through v0.7.3. The analytic gradient and the pure-R fallback follow the same switch.

**v0.7.4-rc (S3 `v074rc_run_20260925/`, Stage 1 reused unchanged, sha256-gated).** Under `all`: floor rows 0 in Stage 2a and 2b; priors at the floor 0 of 1,240; the trim's lower gamma band 0.0074 (was 0); rows 6,811,822 (−2,407, all trim membership — tier is identical on every one of the 6,781,459 keys present in both tables); `gamma_se_status` boundary 11.3% → 0.1%, singular 1.5% → 0.0%, ok 54.7% → 63.0%, non_converged 4.4% → 8.9% (the stiff small-gamma region now reaches maxit rather than the hole — a convergence-repair item for v0.8.0); gamma q25 0.384 → 0.458, median 0.650 → 0.665, max 15.98 → 11.59; median 1/gamma 1.538 → 1.503; `opt_tariff` median 0.649 → 0.723 (cells: 0.542 → 0.617); within-pair SD of gamma 0.331 and MAD 0.019 against Soderbery's 0.625 / 0.125; R² of importer×product fixed effects on log gamma 0.400 against his 0.72 (the v0.7.3 value was inflated by the floor mass). `docs/methodology/v073_v074rc_compare_runs.md` is the record.

**What the clean table says about shrinkage (`docs/results/stage2_shrinkage_census_v074rc*.md`).** `var(log gamma)` falls from 25.6 to 0.69 and the nested decomposition is now economics: exporter-within-cell 60% of the variance unweighted, 40% trade-weighted; median within-cell sd of log gamma 0.64 against an across-good sd of the prior of 0.43. The heterogeneity sits where the data curvature is: rank-1 exporters have a median data share of 0.34 (`1 - gamma_shrink_wt` under the sandwich definition), rank > 10 exporters 0.03; the `gamma_shrink_wt >= 0.99` bin (30% of rows) is the prior to within 0.5%. Within-cell heterogeneity is therefore estimated for the large exporters and imputed for the tail — the accurate one-line description of the Stage-2b gamma. The full-universe lambda curve (`docs/results/stage2_lambda_curve_v074rc.md`) shows why lambda stays at 0.1 for now: below 0.01 the median row's distance from the prior barely moves (0.21 → 0.27) while the tails explode (p90 1.8 → 12.5; within-cell sd 1.05 → 5.7), the signature of noise amplification, and a population of ~140k rows heads toward gamma ≈ 0 — exporters whose moments say near-perfectly-elastic supply, which a prior on **log** gamma cannot represent at any lambda. The prior's form, the measurement-error treatment (fn. 14) and the reference-exporter export moment are the v0.8.0 questions, ahead of any lambda change.

## v0.8.0: the prior's form, λ, the two omitted moments, and the reliability of within-cell heterogeneity (patches 0071–0073)

Patch 0071 added the experiment infrastructure behind flags: `--stage2-prior {log|level|share}` (level = λ((γ−g)/g)², share = λ(s(γ)−s(g))² with s = γ/(1+γ); both finite at γ = 0), `--stage2-ref-export-moment` (the reference exporter's own Eq. (11) row, Soderbery's Exports(s_ikg), mapped to γ_k), `--stage2-import-constant` (Soderbery fn. 14's importer–exporter constant, concentrated out of the import block as a weighted within-transformation; one df), `--stage2-maxit`, and `--product-sample` (a deterministic subset of goods applied to the raw cache before `prepare_data()`, exact for Stage 2). Patch 0072 fixed `prepare_data()` applying `--minyear/--maxyear` only on the fresh-load path — on a cached run the window was printed in the header and ignored, which voided the grid's first split-half pass. Patch 0073 sets the v0.8.0 defaults.

**The design grid** (`docs/results/stage2_reliability_{log,level,share}.md`; 2% product subsample, 25 goods, 152k rows / 113k directly estimated rows, one Stage-2a pass per prior form): every prior form × λ ∈ {0.1, 0.01, 0.001} × moments off/on on the full panel, and the halves 1995–2009 / 2010–2024 for the decision configurations. Full-panel results:

| prior, λ | non-converged | γ ≤ 10⁻⁴ | γ ≥ 10 | `shrink_wt` p50 | within-cell sd | \|dev\| p50 / p90 | `opt_tariff` p50 |
|---|---|---|---|---|---|---|---|
| log 0.1, moments on (**shipped**) | 7.6% | 0 | 0 | 0.936 | 0.56 | 0.08 / 1.02 | 0.597 |
| log 0.1, moments off (v0.7.4) | 7.8% | 0 | 0 | 0.941 | 0.60 | 0.08 / 1.10 | 0.571 |
| log 0.01 / 0.001 | 22–23% / 47–48% | 0 | 1–2% | 0.77 / 0.33–0.41 | 1.0 / 1.4 | 0.21 / 1.7–2.2 | 0.57 / 0.51 |
| level 0.1 (base / moments) | 0.5% / 0.7% | 7.4% / 6.2% | 0 | 0.92 | 2.5 / 2.2 | 0.11 / 2.3–1.9 | 0.454 / 0.490 |
| level 0.01 / 0.001 | 1.1–1.4% / 3–4% | 11–12% / 15–16% | 0 / 0.4% | 0.59–0.64 / 0.16–0.20 | 4.0–4.3 / 4.9–5.0 | 0.43 / 12.9 ; 0.82–0.85 / 13 | 0.45–0.49 / 0.47–0.52 |
| share 0.1 / 0.01 / 0.001 | 36% / 48–50% / 48–50% | 5–6% / 6–7% / 7–8% | 3–4% / 5–7% / 7–9% | 0.44–0.49 / 0.02–0.04 / ≤0.005 | 2.8–3.0 / 3.6–4.1 / 4.3–5.0 | 0.22 / 2.9–3.9 ; 0.23–0.24 / 6–9 ; 0.25–0.28 / 9–11 | 0.51–0.56 |

**Split-half reliability** (within-cell-demeaned log γ, keys directly estimated in both halves, cells with ≥ 2 such keys; `analysis/stage2_reliability.R`):

| configuration | keys | cells | Pearson r_within | rank ρ | r (raw log γ) |
|---|---|---|---|---|---|
| log 0.1, moments on | 61,300 | 3,540 | 0.091 | 0.110 | 0.297 |
| level 0.1, base | 61,500 | 3,540 | 0.058 | 0.178 | 0.189 |
| level 0.1, moments on | 61,600 | 3,540 | 0.060 | 0.192 | 0.176 |
| level 0.01, moments on | 61,500 | 3,530 | 0.063 | 0.146 | 0.129 |

**Reading.** The exporter-specific component of γ — an exporter's deviation from its cell mean — is reproduced across the two halves of the panel at r ≈ 0.06–0.09 (rank 0.11–0.19), for every prior form and λ; Spearman–Brown puts full-panel reliability at ~0.2–0.3 at best. The halves confound sampling noise with structural change between 1995–2009 and 2010–2024, so these are lower bounds, but nothing in the grid shows a signal that a looser prior releases: loosening λ raises within-cell dispersion without raising reliability (the noise-amplification signature of the v0.7.4 λ curve), and the `level` form's γ ≈ 0 population is not more reproducible than the log form's tilt. The informative content of the Stage-2b γ is at the good and cell level; the ranking of exporters within a cell is mostly not. That is the statement the paper should make, and the README's Known-limitations bullet makes it.

**Decisions (patch 0073).** The prior stays `log` at λ = 0.1: `level` removes the non-convergence (0.5% vs 7.6%) but does so by sending 6–7% of rows to γ ≈ 0 with no gain in reliability, a 20% lower median `opt_tariff` and an unbounded 1/γ on those rows — assigning perfectly elastic supply to specific exporters that the data do not reproduce; `share` is bounded on both sides, so its upper tail runs away (3–9% of rows at γ ≥ 10) and half its cells hit `maxit`. Both moments go on as defaults: no cost anywhere, slightly less noise, `opt_tariff` +4–5% from the reference-exporter row, and two of Soderbery's specification terms restored. Ridge domain `all` and the sandwich SE stay. The 7–8% `non_converged` share under the log form is a stiffness artefact of the 1/γ ridge gradient and remains open (`--stage2-maxit` untested; a shifted-log prior, ln(γ + ε), is the candidate structural fix). A parity split of the differenced observations (odd/even t, same period, no drift) is the follow-up experiment that separates noise from structural change in the reliability number.

### v0.8.1: same-period reliability, and the convergence cap (patches 0074–0075)

The calendar split above confounds sampling noise with structural change between 1995–2009 and 2010–2024. Patch 0074 added `--t-parity odd|even`, which keeps one parity of the differenced observations after `prepare_data()` — two halves from the same period — and a shifted-log prior (`shiftlog`, λ(ln(γ+ε) − ln(g+ε))²) as a candidate fix for non-convergence. Results on the same 2% subsample (`docs/results/stage2_reliability_parity.md`):

| configuration | keys | Pearson r_within | rank ρ | r (raw log γ) | non-converged (full panel) |
|---|---|---|---|---|---|
| shipped (log 0.1, moments on) | 85,200 | **0.298** | 0.321 | 0.461 | 7.6% (maxit 500) |
| shipped, maxit 2000 / 5000 | — | — | — | — | 2.7% / 1.5% |
| log 0.01 | 85,200 | 0.247 | 0.270 | 0.365 | 22% |
| shiftlog ε 0.01 / 0.05 | 85,900 | 0.250 / 0.236 | 0.337 / 0.346 | 0.409 / 0.366 | 7.8% / 6.4% |
| level 0.1 | 85,700 | 0.209 | 0.352 | 0.310 | 0.7% |

**Reading.** Within a period the exporter-specific component of γ reproduces at r ≈ 0.30 (rank 0.32); Spearman–Brown to the full panel gives ≈ 0.46 / 0.49. So about half of the within-cell heterogeneity is signal, and the calendar split's 0.09 was mostly drift: exporter-specific γ is moderately identified as a period average and moves across periods. Loosening the prior still adds noise rather than signal (log 0.01: 0.25 / 0.27); the level and shifted priors trade Pearson for rank because of their near-zero populations; the shipped configuration stays. The non-convergence was mostly the iteration cap, not the prior's curvature at zero: the shifted prior barely moves it (7.8% / 6.4%), while `maxit` 2000 and 5000 take it to 2.7% and 1.5%, the freed cells moving a little further from the prior (`|dev|` p90 1.02 → 1.19, `opt_tariff` 0.597 → 0.603). The log ridge's curvature, 2λ/γ², spans three orders of magnitude across the coordinates of one cell, so L-BFGS-B is slow rather than stuck; a log-space reparameterisation (θ = ln γ, constant ridge curvature 2λ) is the structural alternative if the remaining 1.5% ever matters.

**Decision (patch 0075).** `--stage2-maxit` default 5000 (500 reproduces v0.8.0 and earlier); prior, λ, moments, ridge domain and SE form unchanged. The README's Known-limitations bullet quotes the same-period numbers as the reliability of the shipped γ and the calendar split as the drift contrast.

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
