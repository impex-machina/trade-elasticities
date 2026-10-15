# Stage 2 — Country gamma with fixed σ and shrinkage

> **Note:** Originally written as `stage2_liml_202605/README.md` in the
> pre-refactor working directory. Reflects the May 2026 production run.
> The `data/legacy/...` paths below are the historical record of the
> legacy run; that tree is **not** part of this repository. It is
> preserved at the projects-tree `_archive/` and on S3
> (`s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/`).
>
> **Which numbers are current (patch 0092, 2026-10-10).** The sections
> "Output schema", "SE status table breakdown", "Exposure quantiles",
> "Headline numbers", "Sigma provenance breakdown" and "Reproducibility" below
> describe the May-2026 legacy run (8.13M rows, 20 columns, 60.7% `ok`,
> fallback σ 2.91) and are kept as its record. The shipped table's numbers
> are the README's, regenerated from `results/*.json` at every release; the
> schema is the README's column table (23 columns since v0.10.1). The dated
> sections from "## Log-ridge domain" onward are the methodology record of
> the releases from v0.7.4 on. From patch 0109 a census the README quotes is
> checked against the shipped table's sha256 (`pick_census()` in
> `scripts/build_readme.R`): one computed on an earlier table is printed with
> its vintage rather than as the shipped table's.
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

> *May-2026 legacy run; the current numbers are in the README (see the note at the top of this file).*

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

> *May-2026 legacy run; the current numbers are in the README (see the note at the top of this file).*

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

> *May-2026 legacy run; the current numbers are in the README (see the note at the top of this file).*

- 1,240 HS4 products × 233 importers × 233 exporters covered
- Stage 2b country output: 8,126,398 cell-exporter rows
  - Tier 1 (full identification): 70.6%
  - Tier 3 (prior-assigned): 26.3%
  - Tier 0 (reference exporter): 3.0%
  - Tier 2 (import-side only): 0.2%
- True convergence rate (among Tier 0/1/2 only): 94.63%
- γ SE coverage (status == `ok`): 60.7%

## Sigma provenance breakdown

> *May-2026 legacy run; the current numbers are in the README (see the note at the top of this file).*

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

### Optimizer fallback: which point a non-converged cell publishes (patch 0077)

When L-BFGS-B returns a non-zero convergence code (almost always the
iteration cap), `estimate_importer_product_fixed_sigma()` re-runs the cell
with Nelder–Mead. Through v0.8.2 the NM result then *replaced* the L-BFGS-B
result unconditionally. NM restarts from `d_start` (the prior-scale start,
not the L-BFGS-B point) with `2 × maxit` function evaluations in J + 1
dimensions, so on a cell that exhausted 5,000 L-BFGS-B iterations it returns
a point with a higher objective than the one it discards — on a structural
synthetic cell with J = 80 it has not left the starting point after its
budget — and its own convergence code labels the row: 1 (`non_converged`,
no SE) at its cap, or 0 (`ok`, SE computed at the NM point) when the
simplex collapsed. Nothing in the shipped table records which optimizer
produced a row.

`--stage2-fallback {best|legacy}` (config `stage2_fallback`,
checkpoint-stamped): `best` (default from v0.8.3, patch 0080, and the rule
for an absent key) keeps whichever of the two results has the lower
objective (ties → L-BFGS-B), so a fallback can only improve on the L-BFGS-B
point; `legacy` reproduces every release through v0.8.2. Under either rule
the run writes
`<prefix>_stage2_fallbacks.csv` (beside the checkpoint file) with one row
per fallback cell — `lbfgsb_value`, `lbfgsb_convergence`, `nm_value`,
`nm_convergence`, `chosen`, `rule` — and prints the counts, so a single
Stage-2b pass (a `--product-sample 0.02` pass suffices) is the census of how
many shipped rows carry an NM point and by how much its objective exceeds
the discarded one. `analysis/stage2_fallback_census.R` summarises such a
table (`results/stage2_fallback_census.json`, read by the README's clause,
and `docs/results/stage2_fallback_census.md`).

**Census (2026-09-29, 2% product subsample, `te_grid\fallback_legacy`,
`docs/results/stage2_fallback_subsample_census.md`).** 138 of the fitted
cells reached the 5,000-iteration cap and ran the restart; legacy published
the restart on all 138, and on 123 of them (89%) its objective was higher
than the L-BFGS-B point it replaced — the restart starts from the prior and
its 10,000 evaluations in J + 1 dimensions do not reach the point 5,000
L-BFGS-B iterations reached. Scaled to the universe that is roughly 6,800
cells. The decision (patch 0080) is `best` as the v0.8.3 default: it never
publishes a worse point than legacy, and where the restart had "converged"
(simplex collapse, code 0) while the L-BFGS-B point was better, the row
publishes that point with its own code and reads `non_converged` where
v0.8.2 read `ok` at a stalled point — a truthful relabelling, sized by the
universe census from the v0.8.3 rc pass. `tests/testthat/
test-stage2-fallback.R` locks both rules on the e2e fixture. The
homogeneous (single-γ) estimator in
`estimate_cell_homogeneous.R` has the same fallback shape; it is not on the
production path and is left as is.

### Which Stage-2a rows the Stage-2b priors are medians over (patch 0079)

`country_priors` (the good-level `ln_gamma_prior` that the Stage-2b
log-ridge pulls toward) and `gam_V_regional` (the reference-destination
γ_V lookup of Eq. (11)) are medians over the Stage-2a table. Through v0.8.2
the runner took them over every Stage-2a row with a positive γ — including
the Tier-3 rows Stage 2a itself imputed at the Stage-1 good-level prior and
the all-Tier-3 early-return reference rows (`convergence` −1) — so where
those rows were numerous the country prior was partly the Stage-1 prior
echoed back through Stage 2a, and γ_V likewise. `is_estimated_row()`, the
patch-0066 predicate the trim and `opt_tariff` already apply, was not
applied here.

`--stage2b-prior-source {estimated|all}` (config `stage2b_prior_source`,
checkpoint-stamped): `estimated` (default from v0.8.3, patch 0080, and the
rule for an absent key) restricts both medians to directly estimated
Stage-2a rows (`stage2b_priors_from_regional()` in
`R/iteration_helpers.R`); `all` reproduces the runner through v0.8.2. A
good with no estimated Stage-2a row then has no prior (the cell falls to
the existing no-prior path) instead of silently inheriting the imputed
value. Starting values (`init_from_regional`) are unchanged by the rule.
`analysis/stage2a_prior_rows_census.R` measures the shift on a shipped
Stage-2a table without re-estimating anything.

**Census (2026-09-29, the shipped v0.8.2 Stage-2a table,
`docs/results/stage2a_prior_rows_census.md`).** 422,418 rows with γ > 0, of
which 28,750 (6.8%) are imputed (28,478 Tier 3 plus 272 early-return
reference rows), spread across every good. The good-level prior barely
moves — median γ 0.647 → 0.644, |Δ ln prior| 0.3% at the median and 3% at
p90, 78 goods above 5% and 19 above 20%, signed shift symmetric — but the
γ_V lookup does: |Δ ln γ_V| exceeds 5% on 18.4% of the 25,212 (region, good)
cells and 20% on 7.2%; 280 cells have no estimated row and fall to
`gamma_V_default`. At γ_V ≈ 0.64 a 20% shift moves the Eq. (11)
pass-through γ_V/(1 + γ_V) from about 0.39 to 0.44, roughly 10% on the
export-row coefficients of a Tier-1 exporter whose reference destination
sits in one of those cells. The decision (patch 0080) is `estimated` as the
v0.8.3 default. Because patch 0077's fallback rule applies to Stage 2a
cells as well, v0.8.3 is a Stage 2a + 2b release with Stage 1 reused.

### opt_tariff over the published rows (patch 0081)

The cell estimator computes `opt_tariff` and `opt_tariff_all` from all of
a cell's rows, before `estimate_all_fixed_sigma()`'s 0.5%-per-tail trim
removes rows, and through v0.8.2 only the Stage-2a cells touched by the
plateau replacement were ever recomputed afterwards (over the trimmed
table). A cell statistic therefore depended on rows the table does not
publish, and the v0.8.3-rc gate found it: with every γ bit-identical, 66
Stage-2a cells differed from v0.8.2 in opt_tariff only, because a hair's
shift in the global trim bounds changed which rows the plateau recompute
saw — DEU × 6216 at 86.9 in v0.8.2 with no published γ above 8.78.
Censused on the shipped v0.8.2 tables (`ot_census.txt` in the rc record):
Stage 2b, 27,797 of 231,386 cells (12.0%) carry a value that differs from
the published-row value, median relative difference 19.5%, p90 162%, and
1,571 cells state a tariff above every γ they publish (impossible for a
trade-weighted mean of published γ); Stage 2a, 1,766 cells (7.0%), 126
impossible. `recompute_opt_tariff()` (`R/utils_general.R`) now runs for
every cell after the trim and again after the Stage-2a plateau
replacement, and `scripts/recompute_opt_tariff.R` applies the same
function to an existing table and prints the census, which is how the
v0.8.3 tables were corrected from the rc run without re-estimation. No
estimate is touched; the cell-level opt_tariff median moves 0.649 → 0.638
on the v0.8.3 Stage-2b table. `tests/testthat/test-opt-tariff-published-rows.R`
locks the definition, the idempotence, and the script.

### Trim semantics and the record of removed rows (patch 0083)

`estimate_all_fixed_sigma()` trims 0.5% per tail on σ and on γ before the
table is written. σ is a cell-level quantity, so a σ trim removes whole
cells, but through v0.8.3 its bounds were row quantiles: how many cells
went was set by a row count, and a hair's shift in the bounds (the v0.8.3
rc moved 68 rows relative to v0.8.2) changed membership silently. The
Stage-2a plateau replacement (γ > 20 → the Stage-1 prior; v0.3.0 B6) ran
after the trim and imputed 983 rows that then read as estimated downstream
— they entered the Stage-2b prior medians under either prior-source rule —
while rows above the γ bound were dropped instead: a row at 25 became the
prior, a row at 40 vanished.

`--stage2-trim {legacy|v2}` (config `stage2_trim`, checkpoint-stamped):
`legacy` reproduces every release through v0.8.3; `v2` (default from
v0.9.0) takes the σ bound as a low-tail quantile over cells (one σ per
(importer, good)), so the cell drop is a deliberate 0.5%-of-cells rule,
has no high σ bound (patch 0089: the high tail is the σ-edge rule's job —
a large uncapped σ is an estimate with a large SE that `sigma_robust`
flags; with the cap at 10 the spike sat above the 99.5th cell percentile
and the high bound never bit, while at cap 50 with the edge cells gone it
deleted the top 0.5% of cells, σ > 37, the very cells the cap was raised
for), and retires the plateau replacement (the log ridge bounds γ and the
γ tail trim handles the extremes). The γ trim is a row quantile under
both. Under
**both** modes the rows the trim removes are recorded — `run_meta$trimmed_rows`
and `<prefix>_stage2_trimmed.csv` beside the fallback table, with the
bound each row violated — so the removal is no longer silent and a release
can census it. Membership is the only difference between the modes: rows
present under both carry identical values. The flag-instead-of-delete
design (a `trimmed` column carried through the analysis layer) is the v0.9
schema item. `tests/testthat/test-stage2-trim.R` locks the record, the
legacy arithmetic, and the v2 semantics on the e2e fixture.

### Exporter-specific γ_V for Eq. (11), and the export-side period count (patch 0085)

Eq. (11)'s reference-destination supply parameter is exporter j's own γ at
V; through v0.8.3 the pipeline used the (region(V), good) median from Stage
2a as a proxy (and a single global default at Stage 2a). The structural
DGP harness passes the true γ_V, so it cannot see the proxy.
`--stage2-gamma-v-source table` with `--stage2-gamma-v-table PATH` takes
γ_jV from a previous Stage-2b country table where (V, j, good) is a
directly estimated, converged row, and falls back to the regional median
(then the default) where it is absent; the run meta and the log report how
many export rows resolved each way. `regional` (default) reproduces every
release through v0.8.3. The table is subset to the product and keyed on
(importer, exporter) once per product, so each lookup is a binary search.
Because the exporter-specific value comes from a previous pass, the system
is solved by iteration; `analysis/gamma_v_fixed_point.R` measures the step
between consecutive passes on the Tier-1 rows the iteration touches and,
with three passes, the contraction ratio — a ratio well below 1 says one
exporter-specific pass is enough for the published table, near 1 says the
proxy should stay. Rows outside Tier 1 move only through the joint fit of
their cell.

`--stage2-export-period-count panel` makes the Broda–Weinstein T of an
export-side row the pair's `period_count` (counted before the differencing
filters), the definition the import side already uses; `rows` (default,
through v0.8.3) is the post-filter row count, so the T^{3/2} factor was
computed on two definitions. Both are default-off experiment flags for the
v0.9 session. `tests/testthat/test-stage2-gamma-v.R`: an exporter table
equal to the regional values reproduces the regional run bit for bit; a
different table changes only cells with export rows; the census script
recovers a known contraction ratio.

The same patch hardens the library's reads of `cfg$stage2_prior` to exact
matching (`cfg[["stage2_prior"]]`): R's `$` partial-matches list names, so
on a hand-built config that omits `stage2_prior` but carries
`stage2_prior_eps` (patch 0074) the old read returned the ε value and the
prior-form `switch()` then selected nothing. `build_config()` always sets
both keys, so no CLI run was affected; harnesses and tests that rely on
absent-key defaults were one edit away from it. New config keys should not
extend an existing key's name.

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

### v0.9.0 defaults, the native γ_V iteration, and the σ-edge rule (patch 0086)

From the v0.9 rc attribution ladder (S3 `v090rc_run_20261004/`, runs A–E;
`docs/methodology/v083_v090rcA_compare_runs.md` and the `v090rc*_compare_runs.md`
pairs): the cap is the only change that moves headline numbers (γ median
0.656 → 0.646, opt_tariff 0.751 → 0.736, `non_converged` +0.7 pt, SE
coverage −1.1 pt, SE median 0.198 → 0.230 as larger σ flattens the γ
objective), and every row moves by about 2% at the median through the
priors and σ_V, the cells whose own σ changed barely more; the trim moves
nothing at the headline (−7,705 rows); the exporter-specific γ_V moves the
tail, not the middle (Tier-1 |Δ ln γ| p50 0.2%, p90 9%, p99 92%) and is the
one change that improves the status table; the T rule is small; a third
γ_V pass contracts at 0.13 at the median but about 0.5 at p99, so a
1%-of-rows tail does not settle.

Defaults from v0.9.0: `--stage2-trim v2`, `--stage2-export-period-count
panel`, `--stage2-gamma-v-passes 3`; `legacy`, `rows`, `1` reproduce
v0.8.3 (together with cap 10 and `--stage1-capped-omega keep`). The γ_V
iteration is native: pass 1 uses `--stage2-gamma-v-source` (regional median
by default), each further pass takes γ_jV from the previous pass's own
table under the same flags; the pass tables (`_fixed_sigma_pass<k>.rds`),
every pass's fallback and trimmed tables (`_pass<k>.csv`) and the step log
(`_gamma_v_passes.csv`: Tier-1 |Δ ln γ| p50/p90/p99 per step) are written
beside the final table, so the published table reproduces from one command
and each step is on record. The run with three passes is the shipped one;
the fixed-point residual it leaves in the tail is a stated limitation.

`--stage2-sigma-edge {fallback|publish}` (default `fallback` from v0.9.0,
patch 0087; `publish` reproduces every release through v0.8.3): a Stage-1
cell whose published σ is a box edge (`sigma_capped`) has no σ estimate;
under `fallback` it leaves the clean set, so Stage 2 gives it the fallback
σ like any cell without an estimate, `sigma_robust` is FALSE on it, it
carries no σ_V and its ω is out of the priors (`apply_sigma_edge_rule()` in
`R/iteration_helpers.R`). The rule was decided on principle rather than by
A/B — it is the treatment the pipeline already gives a cell with no Stage-1
estimate, an ω at its cap, and a capped σ's SE — and verified post hoc in
the v0.9.0 run's gate against the rc chain (13,810 cells at cap 50). `tests/testthat/test-v090-defaults.R` locks the
defaults, the reproducers, and both helpers.

### v0.9.1: the edge cells' Stage-1 SE leaked into the σ-propagation (patch 0090)

The σ-edge rule drops a cell from the clean set, so Stage 2b gives it the
fallback σ — but through v0.9.0 `run_estimation.R` built the two lookups the
σ-propagation step reads, `sigma_se_lookup` and `sigma_adjust_lookup`, from
the **full** Stage-1 table rather than from the clean set. On the 13,810
edge cells `estimate_importer_product_fixed_sigma()` therefore ran
`compute_dgamma_dsigma()` and `assess_sigma_robust()` with the fallback σ
(2.306) beside the Stage-1 SE of the discarded σ = 50 point. On the Step-2
clamp cells (adjust 4) and the σ-cap-edge boundary cells that SE is NA and
the screen fails as documented; on the ω-edge corner cells — boundary optima
on the ω floor or cap whose free σ landed within 1e-3 of the cap, flagged
`sigma_capped` by value, adjust 6/8 — the HNCS edge SE for σ is finite, so
`sigma_se` and `dgamma_dsigma` were published for an estimate the row does
not carry, and `sigma_robust` could have passed had that SE been small. The
2026-10-10 fresh-eyes review reproduced the code path on the synthetic
fixture (a dropped cell with a planted SE of 0.3 and adjust 6 published σ
2.306, `sigma_se` 0.3, `sigma_robust` TRUE and a finite `gamma_se_total` on
every estimated row). On the shipped v0.9.0 table the census of the
correction (2026-10-11, `docs/results/sigma_edge_se_correction_v091.txt`) is:
13,804 of the 13,810 edge cells present, 300,515 rows, all at σ = 2.30595;
`sigma_se` finite on 81,401 of them → 0, `dgamma_dsigma` finite on 80,521 →
0, `gamma_se_total` finite on 0, `sigma_robust` TRUE on 0 — the pole test
(σ − 2.5·SE > 1 with σ = 2.306 needs SE < 0.52) rejected every corner cell,
so the v0.9.0 sentence "sigma_robust FALSE on the 13,810 edge cells" held
in fact, by the test's outcome rather than by construction, and the
table-level `sigma_robust` share (24.4%) is unchanged. The published error
was two columns on 1.2% of rows.

Patch 0090 does three things. `stage2b_sigma_lookups()`
(`R/iteration_helpers.R`) builds the σ, σ_se, adjust and σ_V lookups from the
one clean table, so a cell outside it has no row in any of them; the cell
estimator additionally blanks the SE and adjust code whenever the cell's σ
is the fallback, so a hand-built config cannot leak either (a fallback σ has
no Stage-1 SE of its own — the same treatment every other fallback cell
already received). `apply_sigma_edge_se_rule()` and
`scripts/apply_sigma_edge_se_rule.R` apply the rule to an existing table:
for the cells whose Stage-1 row is `status == "ok"` with `sigma_capped`
TRUE, `sigma_se`, `dgamma_dsigma` and `gamma_se_total` are set to NA and
`sigma_robust` to FALSE on the rows that carry a flag (Tier-3 rows keep NA).
γ, `gamma_se` and every other column are untouched because the optimizer
never read the SE, so the corrected table is what a re-run under the patch
publishes — which is how the v0.9.1 table is produced from the shipped
v0.9.0 table without a box session, as the v0.8.3 `opt_tariff` correction
was. Bit-preserving everywhere else: a cell that is not a fallback cell
reads its SE and adjust code exactly as before. `tests/testthat/
test-sigma-edge-se.R` locks the estimator, the lookup builder and the
script (35 assertions). The census of the correction on the shipped table
is the v0.9.1 card entry.

### The fn-14 weights: the lag the first differenced observation never had, and the inert T^{3/2} (patch 0091, experiment flags)

Two findings of the 2026-10-10 fresh-eyes review about `bw_weight()`,
$T^{3/2}(1/x_t + 1/x_{t-1})^{-1/2}$, with the two default-off flags that let
them be measured on the 2% subsample before any default moves.

**The lag.** Under `--bw-lag calendar` (the default since v0.5.0) the lag
$x_{t-1}$ is looked up on the cell panel *after* `prepare_data()` has
dropped each panel's leading observation, so the first differenced
observation of every run (the pair's second year) finds no $t-1$ row and
takes `bw_weight()`'s NA → 1 fallback: on the synthetic fixture a weight of
1 beside 12–95 for its neighbours (a 0.1–1% share of the exporter's mean),
and on BACI values in thousands of dollars the typical neighbour weight is
$T^{3/2}\sqrt{x/2}$, i.e. tens to thousands. The observation is effectively
deleted although $x_{t-1}$ is in the raw data — it is the value the
difference itself was taken against — which contradicts the calendar mode's
own premise that the lag is data rather than a retained-row construct, and
costs one of the (at least) three differenced observations a Tier-1 exporter
needs. `--bw-lag raw` reads a `cusval_lag` column that `prepare_data()` now
attaches from the pre-differencing panel (the previous calendar year's value,
NA across a gap), on both the import and the export side; `legacy` and
`calendar` recompute their own lag on the cell panel and overwrite the
column, so every shipped release is unchanged by its presence
(`tests/testthat/test-bw-lag-raw.R` locks the bit-identity).

**The T^{3/2} factor.** Each exporter's moment row is the within-exporter
`weighted.mean` of its observations, and `period_count` is constant within
an exporter, so the $T^{3/2}$ factor cancels exactly inside the mean. Its
only effect in every release has been through the NA → 1 row: a larger $T$
makes that one row relatively lighter. In particular the v0.9.0 "export-side
Broda–Weinstein $T$ = panel length" rule (patch 0085) could only ever change
the relative weight of that artefact row, which is why the C→D rung of the
attribution ladder was "small". The weight fn. 14 implies *across* exporters
— in Feenstra's 2SLS-with-exporter-dummies ⇔ WLS-on-exporter-averages
equivalence, exporter $j$'s averaged row is weighted by the sum of its row
weights, $T^{3/2}\sum_t(1/x_t + 1/x_{t-1})^{-1/2} \approx T^{5/2}\sqrt{x/2}$
— does not reach the objective at all: the across-exporter weight is
`exporter_weight = "trade_value"` (the exporter's customs value in the focal
market, scaled by $\min(T, 10)/10$, normalized to sum to $J$), a deliberate
and documented departure rather than fn. 14 itself. `--exporter-weight
bw_sum` supplies the fn-14 cross-variety weight (the sum of the exporter's
row weights, normalized to sum to $J$ so that $\lambda$ keeps its meaning
against the data block); `uniform` and `trade_value` are unchanged.

Both flags are experiment flags: the defaults stay `calendar` and
`trade_value`, the checkpoint stamp sees both, and the 2% subsample passes
(`--bw-lag raw`; `--exporter-weight bw_sum`; both) with
`analysis/compare_runs.R` and the parity-reliability script are the
measurement before any default moves. A move of either default is a
methodology release with a Stage-2a + 2b box session. The measurement was
taken on 2026-10-11 and closed both flags; the next section is its record.

### The fn-14 flags, measured: the 2% subsample A/B of 2026-10-11 — closed, no session

Design, fixed before the numbers were seen. D1: four single-pass Stage-2b
runs on the 2% product subsample (`--product-sample 0.02 --product-seed
20260926 --stage2-gamma-v-passes 1`, v0.9.1 Stage-1 and Stage-2a tables) —
`base`, `raw` (`--bw-lag raw`), `bwsum` (`--exporter-weight bw_sum`),
`both` — and the per-row step of each rung against base,
$|\ln\gamma_{\text{rung}} - \ln\gamma_{\text{base}}|$ on shared Tier-1
converged rows (`gamma_v_step()`); a rung with p50 below 1e-3 and p90 below
0.05 would have been inside the γ_V iteration's own residual (p50 4e-4,
p90 0.027) and closed on magnitude alone. D2, for every rung that cleared
D1: odd/even parity passes of base and the rung, and the split-half
reliability of the within-cell-demeaned log γ
(`analysis/stage2_reliability.R`); ship only if $r_{\text{within}}$ improves
on base by at least 0.03 with the rank correlation not lower, reject at
$\Delta r \le 0$. Artefacts: `docs/results/v091_subsample_step_census.txt`,
`docs/methodology/v091_v091_{raw,bwsum,both}_subsample_compare.md`,
`docs/results/stage2_reliability_v091_subsample.md`,
`results/stage2_reliability_v091_subsample.json`; the pass tables are under
`te_grid/v091_*`.

D1 — every rung cleared the magnitude screen by a wide margin (base: 151,779
rows, γ median 0.5437, `opt_tariff` median 0.653; the γ median is pinned by
the Tier-3 mass points and is uninformative here):

| rung | shared Tier-1 rows | step p50 | p90 | p99 | max | below 1e-2 | `opt_tariff` median |
|---|---|---|---|---|---|---|---|
| `raw` | 103,193 | 2.31e-02 | 0.350 | 1.607 | 7.39 | 38.4% | 0.657 |
| `bwsum` | 103,171 | 4.90e-02 | 0.381 | 1.157 | 6.34 | 25.2% | 0.665 |
| `both` | 102,701 | 8.21e-02 | 0.583 | 1.890 | 7.43 | 18.6% | 0.666 |

D2 — all three rungs lower reproducibility; none meets the rule, all three
are rejected:

| config | n_keys | n_cells | $r_{\text{within}}$ | rank ρ | $r_{\text{raw}}$ | sd within (A / B) | non-converged | shrink wt | within-cell sd (full) |
|---|---|---|---|---|---|---|---|---|---|
| `base` | 85,300 | 4,030 | **0.333** | 0.343 | 0.473 | 0.826 / 0.838 | 2.3% | 0.915 | 0.655 |
| `raw` | 85,300 | 4,030 | 0.303 | 0.320 | 0.450 | 0.721 / 0.726 | 1.9% | 0.912 | 0.623 |
| `bwsum` | 85,400 | 4,040 | 0.314 | 0.338 | 0.416 | 1.15 / 1.16 | 2.0% | 0.864 | 0.682 |
| `both` | 85,300 | 4,030 | 0.307 | 0.319 | 0.439 | 0.836 / 0.848 | 2.3% | 0.838 | 0.675 |

Reading. `raw` restores the pair's entry-year observation at full weight;
the result is tighter within-cell dispersion (0.72 vs 0.83) but less of it
reproduces across halves (Δr = −0.030, exactly the resolution of the test,
on the wrong side). The economic reading is that the first year a pair
trades is the noisiest observation in its run — a partial year, small
volumes, a unit value that is not yet the steady-state one — and the
calendar mode's accidental ~zero weight on it has been acting as an
entry-year filter; the accident is kept because it is measured to help, and
it is now documented as a rule of the estimator rather than as fn. 14.
`bwsum` puts the fn-14 cross-variety weight on large, persistent exporters:
within-cell dispersion widens by 40%, the shrinkage weight falls (0.915 →
0.864: the data block gets heavier against the fixed λ), and reproducibility
falls (Δr = −0.019, rank ρ unchanged) — the heavier rows are not the more
reproducible ones. `both` compounds the two (Δr = −0.026). `opt_tariff`
moves by +0.6% / +1.8% / +2.0% at the median under the three rungs; the
direction is not evidence either way. Outcome: the shipped weighting
(`calendar`, `trade_value`) stays, no v0.10.0 session is warranted by these
flags, and both remain available for anyone who wants the fn-14 literal.
`--stage2a-gamma-v-default priors` (patch 0092) is unmeasured by this A/B
and rides whatever Stage-2a session comes next, with an expected effect at
the level of a median over 180k cells.


### Run hygiene, the Stage-2a default γ_V, and the hub upload guard (patch 0092)

Three independent items from the 2026-10-10 review, none of which changes a
published number.

**Empty runs leave no files behind.** Both estimators return early with "No
estimates" when every cell fails; through v0.9.0 that return came before the
end-of-run cleanup, so the `_checkpoint.rds` / `_fs_checkpoint.rds` written
during the run survived and the next run under a different config hit the
resume guard ("written under a different estimation config; refusing to
resume"), and a stale `_stage2_fallbacks.csv` / `_stage2_trimmed.csv` from an
earlier run could pass for the empty run's record. `.remove_stale_run_files()`
runs on both early returns. (Met in the sandbox while testing `--bw-lag raw`
on a panel without the prepared column.)

**`--stage2a-gamma-v-default {clean|priors}`** (default `clean`, every
release). Stage 2a's default γ_V for Eq. (11) reference destinations without
a lookup, and its γ start, are the median ω over the whole clean Stage-1
set — floored (1e-4), capped and, since v0.9.0, σ-edge cells included —
while the good-level priors built two lines earlier exclude exactly those
rows (`feenstra_gamma_clean`). `priors` takes the median over the priors'
rows instead, so the two Stage-2a defaults share one population. The median
is robust and the effect is expected to be small; it is a Stage-2a
methodology change all the same, so it ships default-off for the next
Stage-2a session rather than as a data patch.

**`scripts/hf_upload_release.py` refuses a second upload for a released
entry.** Gate 0 reads the card's topmost changelog entry; if its `Data
revision:` already carries a 40-hex oid, `--execute` aborts unless `--force`
is passed, so an upload cannot run before the next entry has been added to
the card (the v0.9.0 sequencing incident: the release commit landed after
the card commit). A `<fill>` placeholder or a missing line counts as "not
yet released". The dry run prints the top entry and its state either way.

Also: `run_estimation.R`'s end-of-run manifest check reads
`<repo>/data/manifest.csv` rather than a CWD-relative path.


### Two schema columns without a box: `gamma_v_resid` and `trim_reason` (patch 0093)

Both columns are deterministic functions of artefacts every run already
produces, so they are added to an existing table locally and the pipeline
fills them natively from the next run on; the two routes give the same
table (`tests/testthat/test-0093-schema.R`).

**`gamma_v_resid`** is $|\ln \gamma - \ln \gamma_{\text{prev}}|$ between the
final native γ_V pass and the one before it — the per-row form of the
pass-step census above (`gamma_v_step()` reports its quantiles over Tier-1
rows). `attach_gamma_v_resid()` fills it on rows that are directly estimated,
converged and published in both passes and leaves NA on Tier-3 rows (their γ
is the prior and would show a misleading 0), on non-converged rows (a
fallback point) and on rows the previous pass does not carry. The runner
applies it after its last pass and prints the census;
`scripts/add_gamma_v_resid.R` applies it to an existing final table and its
`_fixed_sigma_pass<K−1>.rds`. The v0.9.0 iteration's tail is not at a fixed
point after three passes (p99 of the Tier-1 step 0.40), and this column is
how a consumer sees which rows are settled.

**`trim_reason`** and `--stage2-trim-action {drop|flag}` (default `drop`,
every release through v0.9.1). The trim's record now carries the full row
(`_stage2_trimmed.csv`, and a bit-exact `.rds` twin) rather than the seven
columns of patch 0083, so a drop-mode table and its record reconstruct the
flag-mode table exactly (`add_trim_flags()`, `scripts/add_trim_flags.R`; a
pre-0093 seven-column record is accepted and its rows then carry NA in the
unrecorded columns — the v0.9.0 record is of that kind). Under `flag` the
trimmed rows stay with their reason and every consumer reads the published
rows through `is_published_row()`: the cell statistics (the trim and the
`opt_tariff` recompute run before the rows are re-appended, so a flagged
row's cell-level columns are its pre-trim values), the run summary, the
γ_V pass lookup and `gamma_v_step()`, and `analysis/00_setup.R`, which
keeps the flagged rows aside as `stage2b_flagged`. The checkpoint is
pre-trim, so a resume is valid across the two actions and the stamp does not
include it. v0.9.1 ships the column NA throughout (drop semantics kept, so a
v0.9.0→v0.9.1 diff is the edge-cell correction plus two columns); the
default moves to `flag` with the next full Stage-2b run if the A/B says so.

### The pre-trim γ blow-up diagnostic (patch 0097)

`analysis/trim_diagnostic.R` characterises the rows the tail trim removes,
from a run's trim record (`<prefix>_stage2_trimmed.rds`/`.csv`; full rows
since patch 0093, the seven-column record of earlier runs is accepted with
fewer sections), the published table and the Stage-1 table. Five sections:
composition (reason × tier, reason × convergence, cells, goods); the σ
behind the γ tails — Eq. (10)'s coefficients carry $1/(\sigma-1)$, so a γ
that explodes may be a σ near the pole: level, provenance (HLIML interior /
Step 2 / boundary / fallback) and SE of the trimmed rows' cells against the
published rows'; concentration — whether the tail rows sit in a few cells
whose σ is the problem (half or more of a cell's estimated rows trimmed) or
are single exporters in ordinary cells; distance from the good-level prior
(recovered from the Tier-3 rows, whose γ is exp(prior)) and, on a full-row
record, trade size, shrinkage weight and exposure; and the within-good
alternative — what a 0.5%-per-tail rule taken within each good would remove
on the pre-trim union, against the global rule's removals and their overlap.
Nothing in it changes a published number; it is the evidence for keeping,
tightening or re-scoping the trim (`--stage2-trim-action flag` keeps the
rows either way). Results land in `docs/results/trim_diagnostic_<label>.md`
and `results/trim_diagnostic_<label>.json`; `tests/testthat/
test-trim-diagnostic.R` locks the counts.


### The pre-trim γ blow-up, measured: the 2% subsample (2026-10-11) — the tails are σ-pole cells

`analysis/trim_diagnostic.R` on the D1 base run (`te_grid/v091_base`, full-row
record; `docs/results/trim_diagnostic_v091_subsample_base.md`,
`results/trim_diagnostic_v091_subsample_base.json`): 1,922 trimmed rows from
601 cells and all 25 goods — `sigma_lo` 935 (224 of them Tier 3; the only
reason with non-converged rows, 224), `gamma_hi` 554, `gamma_lo` 433 — against
112,645 published directly estimated rows.

**The σ behind the γ tails** (cell-level, Stage 1 joined):

| rows | n | σ median | σ p10 | σ < 1.5 | σ < 2 | σ SE median | SE > σ − 1 |
|---|---|---|---|---|---|---|---|
| `gamma_hi` | 554 | 1.289 | 1.067 | 66.8% | 81.2% | 0.293 | 48.9% |
| `gamma_lo` | 433 | 1.060 | 1.016 | 93.1% | 97.7% | 0.232 | 86.4% |
| all γ tails | 987 | 1.168 | 1.021 | 78.3% | 88.4% | 0.270 | 65.3% |
| published (directly estimated) | 112,645 | 2.306 | 1.238 | 20.4% | 37.2% | 0.559 | 24.7% |

Provenance: the tail cells are *more* interior-HLIML than the published rows
(`gamma_hi` 60.8%, `gamma_lo` 66.1%, published 42.1%) and no more fallback
(8.5% / 1.4% vs 10.6%) — ordinary ok estimates whose σ is at the pole. Eq.
(10)'s coefficients carry $1/(\sigma-1)$; as σ → 1⁺ the import block's
curvature in γ collapses and the optimizer sends individual exporters' γ to
either end.

**Concentration.** 578 cells; median one tail row per cell (max 18); 41.6% of
tail rows sit in cells with three or more, but only 14 cells (4.6% of tail
rows) lose half or more of their estimated rows. It is single exporters
scattering within pole-σ cells, not cells collapsing whole.

**Distance and trade size.** |ln γ − ln prior| p50 5.23 / p90 6.69 on the
tails (published 0.107 / 1.30): 180× from the prior with `gamma_shrink_wt`
no different from the rest (0.917 vs 0.915 — at the pole the data block
overwhelms λ = 0.1 even where the information is nil). The tails are
*larger* flows (median `avg_trade` 206 vs 54; 2.9% below the published
p10): not a thin-data artefact. `gamma_se_status` on the tails: plateau
52.8%, non_converged 22.9%, boundary 24.0%. `sigma_robust` is FALSE on
89.5% of them — the pole test (σ − 2.5·SE > 1) already rejects almost the
whole population the trim removes.

**The within-good alternative.** On the pre-trim union (113,632 rows) a
0.5%-per-tail rule within each good removes 1,162 rows against the global
rule's 987; 723 by both, 439 only within-good (published today), 264 only
global; 73.3% overlap. The driver is σ, not the good, so a within-good rule
moves 700 rows for no principled gain.

**Reading and outcome.** The 0.5% γ trim is a light-touch σ-pole filter: it
removes the most extreme of the γ's that a σ near 1 produces, and nothing
else of note. It stays as shipped. The consumer guidance is that
`sigma_robust` covers this population more completely than the trim does
(25% of published rows are within one SE of the pole and carry
`sigma_robust` FALSE; the trim touches 0.9%). The methodology question it
opens — a σ-floor edge rule mirroring v0.9.0's cap rule, a σ within $c$·SE
of 1 taking the fallback σ — would move far more rows than the trim and is a
box change, so it is handled like the fn-14 flags: a default-off flag and a
local parity A/B before any session (open; not scheduled). The full-run
record of v0.9.0 is the seven-column kind on S3
(`v090rel_run_20261010`); the subsample finding is large enough (σ median
1.17 vs 2.31) that it is not expected to differ.

### The σ-pole rule: `--stage2-sigma-pole-rule {none|fallback}` (patch 0099, experiment flag)

The other end of the σ axis gets the cap rule's treatment, default-off. A
Stage-1 cell whose σ is within $c$ standard errors of the pole,
$\sigma - 1 < c \cdot \text{SE}(\sigma)$, leaves the clean set under
`fallback` (`--stage2-sigma-pole-se c`, default 1): Stage 2 gives it the
fallback σ, it supplies no σ_V and its ω leaves the priors, exactly as a
cap-edge cell does since v0.9.0. A cell with no finite σ SE cannot be
assessed and is kept. `none` is the identity and every release reproduces.
The motivation is the measurement of patch 0098: the γ tails the trim
removes are σ-pole cells, and Eq. (10)'s $1/(\sigma-1)$ coefficients make
the γ of such a cell uninformative whatever the optimizer returns. The rule
is not a trim: it changes the σ the cell's γ is estimated at, so it moves
every exporter in the cell and, through the σ_V lookup and the priors,
cells elsewhere — on the 2% subsample about a quarter of published rows sit
in cells within one SE of the pole, so at $c = 1$ it is a large change and a
box change.

Measurement before any default moves, as for the fn-14 flags: single-pass
subsample runs at $c = 1$ and $c = 0.5$ against the existing `v091_base`,
the step census (expected large by construction), and the split-half parity
reliability against the existing `v091_base_odd/even`; the rule ships only
if $r_{\text{within}}$ improves on base by at least 0.03 with the rank
correlation not lower. If it ships, the session is Stage 2a + 2b (the
priors and the regional σ medians move too) and can carry
`--stage2a-gamma-v-default priors` and `--stage2-trim-action flag`.
`tests/testthat/test-sigma-pole-rule.R` locks the identity, the drop set
and the plumbing.


### The σ-pole rule, measured: the 2% subsample grid of 2026-10-11 — c = 1 ships as v0.10.0's default

Five single-pass runs (`base` = v0.9.1 defaults; the rule at c = 0.5, 1, 2,
2.5) on the 2% product subsample, each with its odd/even parity halves, the
split-half reliability harness (`docs/results/stage2_reliability_v091_pole.md`,
`results/stage2_reliability_v091_pole.json`) and a decomposition of
$r_{\text{within}}$ by whether the rule moved the cell
(`docs/results/v091_pole_reliability_decomposition.txt`; it replicates the
harness totals). The step census against base
(`docs/results/v091_pole_step_census.txt`) cleared the magnitude screen by
construction (c = 1: p50 1.6e-03, p90 0.39, p99 2.45).

| c | cells moved (of the full clean set) | fallback σ → share of rows at it | $r_{\text{within}}$ (Δ vs base) | rank ρ | $r_{\text{raw}}$ | within-cell sd | non-converged | shrink wt | `opt_tariff` median |
|---|---|---|---|---|---|---|---|---|---|
| base | — | 2.306 → 11.8% | 0.333 | 0.343 | 0.473 | 0.826 | 2.3% | 0.915 | 0.653 |
| 0.5 | 28,737 | 2.405 → 24.9% | 0.355 (+0.022) | 0.355 | 0.497 | 0.672 | 0.8% | 0.926 | 0.654 |
| **1** | **55,396** | **2.473 → 36.8%** | **0.365 (+0.032)** | 0.364 | 0.507 | 0.621 | 0.6% | 0.934 | 0.662 |
| 2 | 94,769 | 2.585 → 56.8% | 0.368 (+0.035) | 0.366 | 0.520 | 0.554 | 0.2% | 0.944 | 0.664 |
| 2.5 | 108,457 | 2.628 → 64.7% | 0.372 (+0.039) | 0.370 | 0.527 | 0.532 | 0.3% | 0.947 | 0.664 |

Decomposition (split-half keys; the rule's own c defines "moved"):

| c | moved: keys / cells / r / sd | unmoved: keys / cells / r / sd |
|---|---|---|
| base (c = 1 classes) | 20,208 / 1,133 / 0.305 / 1.092 | 65,066 / 2,900 / 0.352 / 0.724 |
| 0.5 | 11,359 / 643 / 0.376 / 0.638 | 73,774 / 3,386 / 0.352 / 0.677 |
| 1 | 21,342 / 1,158 / 0.378 / 0.619 | 63,782 / 2,862 / 0.361 / 0.622 |
| 2 | 38,687 / 1,966 / 0.381 / 0.565 | 46,355 / 2,048 / 0.357 / 0.544 |
| 2.5 | 45,673 / 2,254 / 0.384 / 0.546 | 39,489 / 1,761 / 0.357 / 0.515 |

**Reading.** This is the identification signature at every c, not the
shrinkage one: under base the pole cells reproduce worse than the rest
(0.305 vs 0.352) with far wider dispersion (sd 1.09 vs 0.72); once estimated
at a σ away from the pole they reproduce at or above the unmoved cells
(0.376–0.384) at an equal sd. The caveat on record: the unmoved cells also
tighten (sd 0.724 → 0.622 at c = 1, r +0.009) through the priors (the moved
cells' ω leave them), the σ_V lookup and the shifted fallback value; small,
and not where the gain lives. With c the gain flattens while the cost does
not: from c = 1 to c = 2.5 is +0.007 in r for moving another 28 points of
rows onto one global σ (65% of the table), with the within-cell sd still
falling — homogenization rather than identification at that end. The
pre-registered selection rule ("the largest c within 0.005 of the best with
the identification signature") would have picked c = 2.5; it did not weigh
what c does to the σ column, which is a product decision, and it was set
aside for that reason. **Decision (MC, 2026-10-11): c = 1.** It takes 82% of
the available reproducibility gain, the non-converged share to 0.6%, the
γ ≤ 0.01 and γ ≥ 10 populations to zero, keeps a cell σ on 63% of rows, and
has the plain statement that a σ within one standard error of 1 is not an
estimate. c = 2.5 remains the "coincides with the `sigma_robust` pole test"
alternative, available by flag.

**What ships (v0.10.0, one Stage 2a + 2b×3 session, Stage 1 untouched):**
`--stage2-sigma-pole-rule fallback --stage2-sigma-pole-se 1` as the default,
with `--stage2a-gamma-v-default priors` and `--stage2-trim-action flag`
flipped in the same patch (0101), every flag reversible to the v0.9.1
configuration. The subsample grid above is the attribution record; there
is no full-sample ladder.


### v0.10.0, the full run: attribution of the level shift and the shipped configuration's reproducibility (patch 0102)

One box session on 2026-10-12 (`r7a.16xlarge`, S3 `v0100rel_run_20261012/`):
the v0.9.x Stage-1 table loaded (sha256 908c8f53…), Stage 2a re-estimated,
three Stage-2b γ_V passes, all v0.10.0 defaults (`out_H/`, ~1 h 55 of
estimation). The run dropped 13,810 σ-edge and 55,396 σ-pole cells (113,706
clean of 280,649; fallback σ 2.473), published 6,801,807 rows with 90,201
flagged trimmed rows beside them, and filled `gamma_v_resid` on 4,911,380
rows (p50 2.3e-04, p90 0.014, p99 0.245). The γ_V iteration settles faster
with the pole cells out: pass 2→3 Tier-1 step p99 0.23 and 88% of rows below
1e-2, against 0.40 and 83% in v0.9.0 — the pole cells were feeding unstable
γ_V's into Eq. (11).

**The level shift and its attribution.** The headline γ median moved 0.644 →
0.806 and `opt_tariff` 0.733 → 0.869, far more than the subsample grid
suggested, because that grid held Stage 2a at the v0.9.x table. Two
single-pass Stage-2b runs on the box (`out_H1/`, `out_H2/`) split it:

| configuration | γ median | `opt_tariff` median | Nelder–Mead fallback cells |
|---|---|---|---|
| v0.9.1 (no rule, v0.9.x Stage 2a) | 0.644 | 0.733 | — |
| H1: rule in 2b, v0.9.x Stage 2a | 0.662 | 0.766 | 2,940 |
| H2: rule off in 2b, new Stage 2a | 0.777 | 0.828 | 8,056 |
| v0.10.0 (rule in 2b, new Stage 2a; pass 1) | 0.806 | 0.869 | 2,963 |

The rule's own cells account for about a seventh of the shift; the
re-estimated Stage 2a for the rest. Stage 2a moves because its regional σ's
no longer include pole-σ cells (regional 1/(σ−1) 0.766 → 0.679), while the
regional composite γ/((1+γ)(σ−1)) stays put (0.293 → 0.290): the import
moments pin the composite, so a higher σ is carried by a higher γ, and the
regional γ's are both the Stage-2b priors (good-level prior median 0.635 →
0.758, per-good |Δ ln| p50 0.17) and the Eq. (11) γ_V's. Row by row on the
4.74M directly estimated rows shared by both tables (convergence 0):

| Stage-1 class | share | σ moved | γ median | composite median | \|Δ ln γ\| p50 | \|Δ ln composite\| p50 |
|---|---|---|---|---|---|---|
| `no_estimate` | 10% | fallback 2.306 → 2.473 | 0.742 → 0.921 | 0.326 → 0.325 | 0.182 | 0.065 |
| `sigma_edge` | 4% | fallback 2.306 → 2.473 | 0.688 → 0.844 | 0.312 → 0.311 | 0.178 | 0.066 |
| `sigma_pole` | 24% | ~1 → 2.473 | 0.583 → 0.809 | 0.385 → 0.304 | 0.361 | 1.161 |
| `other` | 62% | no | 0.633 → 0.766 | 0.223 → 0.246 | 0.153 | 0.088 |

On the fallback classes the composite is unchanged and γ absorbs the higher
σ — the trade-off exactly. On the pole cells the composite moves because their
old σ was not an estimate (that is the rule). On `other` cells σ is unchanged
and γ rises through the priors and γ_V's of the re-estimated Stage 2a; those
were biased low by pole-σ regional cells (a σ near 1 forces a small γ through
the composite). Optimizer non-convergence among directly estimated rows is
0.42% in both releases; the v0.10.0 gate's first FAIL ("non-converged share
rose", 26.73% → 26.75%) counted the Tier-3 rows, whose convergence is −1 by
construction, and was a defect of the gate, fixed here.

**Reproducibility of the shipped configuration.** The subsample grid was re-run
locally with the new Stage-2a table (`te_grid/v0100_cfg*`;
`docs/results/stage2_reliability_v0100_cfg.md`,
`docs/results/v0100_cfg_reliability_decomposition.txt`): $r_{\text{within}}$
0.369 (base 0.333, rule with the v0.9.x Stage 2a 0.365), rank ρ 0.368,
$r_{\text{raw}}$ 0.543 (0.473 / 0.507); moved cells 0.379 at sd 0.638,
unmoved cells 0.366 at sd 0.639 (base unmoved 0.352). The Stage-2a channel
adds no noise — the levels across halves agree better under the new priors.
The pre-registered ship rule (r ≥ 0.365, rank not lower, unmoved ≥ 0.352) is
met on all three counts. **Decision: v0.10.0 ships as run.**

Also in patch 0102, so the first table with flagged rows is read correctly
everywhere: `recompute_opt_tariff()` recomputes over published rows only and
leaves the flagged rows' cell values untouched; `compare_runs.R`,
`stage2_reliability.R`, `gamma_v_fixed_point.R`, the shrinkage / EB-λ / λ /
prior-rows censuses and the sensitivity sweep read published rows; the run's
console summary counts published rows (it printed 6,892,008 estimates where
6,801,807 were published); `tests/testthat/test-flag-readers-0102.R` locks the
recompute and the gate metric.


### `sigma_source`, and exact reads of prefix config keys (patch 0103)

**`sigma_source`.** Since v0.10.0, 41% of published rows carry the single
fallback σ — cells with no usable Stage-1 estimate, cells on the (σ, ω) box
edge, and cells within one SE of the pole — and a consumer could tell them
from estimates only by matching the value. `stage2_sigma_clean()` is now the
one code path for the clean set (the runner used the same three steps inline:
converged σ > 1, the edge rule, the pole rule) and returns each cell's
provenance; the runner attaches `sigma_source` before saving the Stage-2b
table, and `scripts/add_sigma_source.R` attaches it to an existing table,
verifying that every `estimated` row carries its cell's Stage-1 σ and every
fallback row the fallback σ before writing (a rule set that does not reproduce
the table's σ column is refused). v0.10.1 is the v0.10.0 table plus this
column, produced that way without re-estimation.

**Exact reads of prefix keys.** R's `$` partial-matches list names, so on a
list without `stage2_trim`, `cfg$stage2_trim` returns `cfg$stage2_trim_action`
(patch 0101 found it when the synthetic fixture gained the longer key).
`tests/testthat/test-config-partial-match.R` now fails on any `cfg$` /
`opts$` / `config$` read of a key that is a strict prefix of another config
key; it found four more, all converted to `[[ ]]`: `opts$stage` (prefix of
the `stage1_*` / `stage2_*` options), `opts$stage2_prior` (prefix of
`stage2_prior_*`), a remaining `opts$stage2_trim`, and `cfg$exporter` — the
exporter column name, which on a hand-built config without it would have
returned `exporter_weight` ("trade_value"). Production configs always carry
every key, so no published number was affected. Also: the run log's "Stage
2a starting values / plateau fallback" line drops the retired plateau wording.


### Box tooling and the generic release gate (patch 0104)

`scripts/box/setup.sh` (placement: credentials, packages, the raw cache from
S3 with a size check, the released tables hash-verified, Stage 1 placed so the
run loads it) and `scripts/box/preflight.sh` (the gate in front of every
launch: refuses outside tmux, checks the role, packages, cache and the Stage-1
hash, and prints the expected durations) replace the pasted blocks of earlier
runbooks; `docs/box_session_template.md` is the session shape they fit.
`analysis/gate_release.R` replaces the version-specific `gate_v0100.R` (kept
for the record): beyond schema, row-count and optimizer-convergence checks, it
reconstructs every row's σ from the Stage-1 table through
`stage2_sigma_clean()` and fails if any row carries a σ the rules do not
imply, if a fallback row claims `sigma_robust`, or if `sigma_source` disagrees
with the reconstruction. `tests/testthat/test-gate-release.R` locks the PASS
path and the H3 / H4 / H5 failures.


### Two measurements for the paper: the reference exporter and λ (patch 0105, design fixed before the numbers)

**The reference exporter.** Every cell's moments are differenced against one
reference exporter, chosen as the exporter with the most periods and then the
largest total value (`choose_reference()`). Its noise enters every other
exporter's differenced moments. `--stage2-reference-rule` (default
`periods_value`, every release reproduces bit for bit) adds `periods_stable`
(most periods, then the least variance of Δln p) and `value` (largest total
value, periods ignored). The rule acts in Stage 2a as well as 2b — the
regional cells run the same cell estimator — so the measurement re-estimates
Stage 2a on the subsample for every configuration, including a re-run of the
default; the 2026-10-12 attribution showed what holding Stage 2a fixed misses.

**λ.** The Stage-2b ridge weight is fixed at 0.1 (Stage 2a's at 0.05); the EB
census found its level unidentified by the data. `--shrinkage-lambda` acts in
Stage 2b only, so the λ rungs (0.03, 0.3) reuse the v0.10.0 Stage-2a table and
compare against the existing `v0100_cfg` halves (λ = 0.1, same table).

**Design.** The 2% product subsample (seed 20260926), single γ_V pass, trim
action `drop` for comparability with the earlier grids, odd/even parity
halves, `analysis/stage2_reliability.R` on the within-cell-demeaned log γ.
Ship rule for either flag: $r_{\text{within}}$ at least 0.03 above its base
with the rank correlation not lower; for λ additionally the within-cell sd
may not fall by more than 25% (a gain bought by shrinkage alone is not
identification). If neither alternative λ clears, the paper's stance is that
λ = 0.1 is a regularizer whose level the data do not pin and whose
neighbours do not improve reproducibility; if neither reference rule clears,
the reference note documents the current rule with the measured
alternatives. A rule that clears waits for one batched session (v0.11.0)
with any other cleared item, re-measured as shipped.
`tests/testthat/test-reference-rule.R` locks the rules and the bit-identity
of the default.


### The reference exporter and λ, measured: the 2% subsample of 2026-10-12 — both closed, no session (patch 0106)

Ten half-runs on the design patch 0105 fixed (2% product subsample, seed
20260926, single γ_V pass, trim action `drop`, odd/even halves;
`docs/results/stage2_reliability_m_reference.md`,
`docs/results/stage2_reliability_m_lambda.md` and their JSON). Split-half
reliability of the within-cell-demeaned log γ:

| configuration | keys | cells | $r_{\text{within}}$ | rank ρ | $r_{\text{raw}}$ | within-cell sd (A / B) |
|---|---|---|---|---|---|---|
| reference `periods_value` (base; Stage 2a re-estimated on the subsample) | 85,100 | 4,020 | 0.368 | 0.368 | 0.542 | 0.638 / 0.644 |
| reference `periods_stable` | 85,100 | 4,020 | 0.367 | 0.369 | 0.546 | 0.617 / 0.626 |
| reference `value` | 83,100 | 3,880 | 0.367 | 0.369 | 0.538 | 0.642 / 0.649 |
| λ = 0.1 (base, `v0100_cfg`; v0.10.0 Stage 2a) | 85,100 | 4,020 | 0.369 | 0.368 | 0.543 | 0.639 / 0.644 |
| λ = 0.03 | 85,100 | 4,010 | 0.362 | 0.360 | 0.484 | 0.882 / 0.892 |
| λ = 0.3 | 85,100 | 4,030 | 0.368 | 0.375 | 0.621 | 0.456 / 0.457 |

**Reference exporter.** All three rules reproduce within 0.001 of each other;
none approaches the +0.03 bar. The `value` rule also loses ~140 cells (a
large but short-panelled reference cannot difference the rest of the cell).
The re-run base (0.368, Stage 2a re-estimated on the subsample) reproduces
`v0100_cfg` (0.369, full-sample Stage 2a), which confirms that the λ rungs
could reuse the shipped Stage-2a table. **Stance for the paper:** the
reference exporter is the exporter with the most periods, then the largest
total value; the choice is immaterial for what the estimates reproduce —
the most-stable-price and largest-value alternatives give the same
reliability.

**λ.** The reproducible part of the within-cell heterogeneity is flat across
a tenfold range of λ (0.362 / 0.369 / 0.368; neither alternative within 0.03
of clearing, and λ = 0.3 breaches the 25% sd guard at −29%). What λ governs
is how much dispersion is shown — within-cell sd 0.88 / 0.64 / 0.46 — and
$r_{\text{raw}}$ rises with λ (0.484 / 0.543 / 0.621) because shrinking both
halves toward a common prior makes their levels agree mechanically, not
because the data say more. **Stance for the paper:** λ = 0.1 is a regularizer
whose level the data do not pin (as the EB census found) and whose
neighbours do not improve reproducibility; the within-cell ordering of
exporters is robust to it, the magnitude of within-cell dispersion is
conditional on it. The README states this for consumers.

**Outcome.** Both flags stay default-off; no v0.11.0 session is warranted by
them. The export-share denominator remains the one unmeasured item (it needs
a cache rebuild from the BACI CSVs).


### The export-share denominator: `--stage2-export-total {quantity|all}` (patch 0107, design fixed before the numbers)

**The issue.** BACI carries some flows with a value but no quantity. They
cannot enter a unit value, so dropping them from the price moments is right;
but the raw cache drops them at the HS6 line *before* any total is formed, so
the share denominators exclude them too — and a value-only HS6 line inside
an HS4 flow is dropped from that flow's own value as well. On the import side
(Eq. (10), and all of Stage 1) shares enter only as differences against the
reference exporter in the same importer-year, so the importer total cancels
exactly. On the export side, exporter j's share of its own total exports
$s^J_{ij} = x_{ij}/V_j$ enters Eq. (11) separately for destination $i$ and
for the reference destination $v$, with coefficients built from $\gamma_I$
and $\gamma_V$. With measured $V_j(1 - m_{jt})$, where $m_{jt}$ is the value
share of j's exports lacking a quantity, the mismeasurement contributes a
term proportional to $(\gamma_I - \gamma_V)\,\Delta\ln(1 - m_{jt})$: it
cancels only where $\gamma_I = \gamma_V$, i.e. it sits in exactly the
variation that identifies exporter-specific γ. Expected small on average
(value-only flows are a small share of value, only the *change* in the
excluded share enters, scaled by the γ gap); the risk is concentrated —
reporting changes produce spikes in $\Delta\ln(1-m)$ for particular
exporter-years.

**The fix, default-off.** `scripts/build_export_totals.R` reads the BACI year
files one at a time with the cache's rules except the quantity filter and
writes, per (year, good, exporter), the value of all flows (`value_all`) and
of the flows with a quantity (`value_qobs`), plus the census of value-only
flows (`docs/results/export_totals_census.md`). Under
`--stage2-export-total all`, `prepare_data()` replaces the exporter total with
`value_all` (mapped to regions for Stage 2a) after checking that `value_qobs`
reproduces the panel's own exporter totals to 1e-9 — a table built with other
rules, or missing a panel cell, is refused. Numerators, unit values and the
import side are untouched; `quantity` (default) reproduces every release bit
for bit.

**Measurement and decision rule (fixed now).** Two half-runs on the 2%
product subsample (seed 20260926; `--stage all` with the v0.10.x Stage 1
loaded, so Stage 2a is re-estimated under the option; single γ_V pass; trim
action `drop`) against the existing `m_ref_base` halves — the shipped
configuration estimated the same way — with the split-half harness and the
step census on the odd halves. Decision:
- $\Delta r_{\text{within}} \ge +0.03$ with rank ρ not lower: default flip
  at the next batched session;
- $-0.01 < \Delta r_{\text{within}} < +0.03$: the corrected denominator is
  the model's definition and costs nothing to carry; it becomes the default
  at the next Stage-2 session that happens for another reason, with no
  session for it alone;
- $\Delta r_{\text{within}} \le -0.01$: keep `quantity` and record the census.
The census is recorded whichever way it goes. `tests/testthat/
test-export-totals.R` locks the table, the replacement, the refusals, the
regional mapping and the bit-identity of the default.


### The export-share denominator, measured (patch 0108) — negligible; queued as the next session's default

**The census** (`scripts/build_export_totals.R` over the 30 BACI year files,
2026-10-13; `docs/results/export_totals_census.md`,
`results/export_totals_census.json`; the 4,976,887-row table is on S3 under
`cache/`). Value without a quantity is 1.33% of all value — 5–7% in
1995–1999, then 0.7–1.5% from 2000, when BACI's quantity coverage improves.
28.5% of exporter-good-year cells carry some value-only flow (holding 68.3% of
value); 77,523 cells have no flow with a quantity and are absent from the
panel. Across panel cells $m = 1 - \text{value}_{qobs}/\text{value}_{all}$
has p50 0, p90 0.0031, p99 0.61. Between consecutive years of the same
exporter and good (4,234,489 pairs) $|\Delta\ln(1-m)|$ has p50 0, p90 0.016,
p99 1.31 (max 15.5), exceeding 0.10 in 5.2% of pairs; value-weighted p50
5.7e-06, p90 0.0036, p99 0.24. Small on average, with a real tail and a
1999→2000 break that shifts many exporters' measured totals in the same year.

**The A/B** (patch 0107's design; `m_exptot_odd/even` against
`m_ref_base_odd/even`; `docs/results/stage2_reliability_m_exptot.md`,
`docs/results/export_total_step_census.txt`):

| configuration | keys | cells | $r_{\text{within}}$ | rank ρ | $r_{\text{raw}}$ | within-cell sd (A / B) |
|---|---|---|---|---|---|---|
| `quantity` (base) | 85,100 | 4,020 | 0.368 | 0.368 | 0.542 | 0.638 / 0.644 |
| `all` | 85,100 | 4,020 | 0.367 | 0.368 | 0.542 | 0.638 / 0.643 |

Step on the odd halves, 83,652 shared Tier-1 rows: $|\Delta\ln\gamma|$ p50
2.6e-04, p90 0.0034, p99 0.061 (max 3.0), 95.4% below 1e-2 — the scale of the
γ_V iteration's own pass-to-pass residual; γ and `opt_tariff` medians
unchanged. The census tail does not reach the estimates: the error enters
Eq. (11) scaled by $\gamma_I - \gamma_V$, is averaged within exporter over
periods, and sits mostly in thin cells that carry little trade weight.

**Decision**, by the rule fixed in patch 0107: $\Delta r_{\text{within}} =
-0.001$ falls in $(-0.01, +0.03)$, so the all-value totals — the model's own
definition, costless to carry — become the default at the next Stage-2
session that happens for another reason; there is no session for this
alone. The flip is queued in `docs/next_session_queue.md`.

### The export moment on values: `--stage2-export-moment {share|value}` (patch 0110, design fixed before the numbers)

**The issue.** Soderbery's Eq. (8) writes the export supply curve with prices
on export shares, $D^v\ln p_{ij} = \rho_I\,\Delta\ln s^J_{ij} - \rho_V\,\Delta\ln s^J_{vj} + \delta$.
His own Eq. (7) gives $\ln p_{ij} = \eta_{ij}/(1+\gamma_{ij}) + \rho_{ij}\ln s^J_{ij} + \rho_{ij}\ln V_j$,
so the reference-differenced curve carries $(\rho_I - \rho_V)\,\Delta\ln V_j$, with
$V_j$ the exporter's total sales. Eq. (8) leaves that term in the error, where
it is correlated with the Eq. (9) demand residual through $V_j$ whenever
$\gamma_I \neq \gamma_V$ -- the variation the model exists to estimate. The
import side has no such term: Eq. (6) is written shares-on-prices and the
importer total cancels. Patch 0107's denominator finding was the
measurement-error face of the same term. Tests A-E of the structural-DGP
harness draw data from Eqs. (8)-(9) themselves and could not see it.

**The fix, default-off.** With $R = p\,x$ the supply curve is exact on log
values, $\ln p = \eta/(1+\gamma) + \rho\ln R$, so Eq. (8) holds with
$\Delta\ln R$ in place of $\Delta\ln s^J$; Eq. (9) is a difference across
destinations and is unchanged. The nine-term Eq. (11), its coefficients, the
C++ objective, the Jacobian and the SEs are untouched: under `value`,
`prepare_data()` puts log export value where the export share was. The
exporter total then enters nothing, so `--stage2-export-total` is moot under
`value`. `share` (default) reproduces every release bit for bit.

**Evidence before the flag (sandbox, 2026-10-13).** Harness Test F (the export
side simulated from the primitives): at the truth the share form misses by up
to about a tenth of the outcome when $\gamma_I \neq \gamma_V$, the value form
stays at noise. In a cell simulation from the primitives (one importer, 16
exporters each selling to six destinations, every γ estimated jointly with σ
at the truth; 300 cells at T = 30 with λ = 0.1 and 50 at T = 3,000 without the
ridge), median log bias / median |log error| / median within-cell rank
correlation with the truth:

| export side | baseline, T = 3,000 | baseline, T = 30, λ = 0.1 (rank) | stress, T = 3,000 | stress, T = 30, λ = 0.1 (rank) |
|---|---|---|---|---|
| shares (shipped) | −0.052 / 0.115 / 0.943 | 0.318 | −0.131 / 0.207 / 0.928 | 0.325 |
| values (`value`) | −0.006 / 0.101 / 0.959 | 0.328 | −0.032 / 0.133 / 0.965 | 0.350 |
| total differenced out (not implemented) | −0.009 / 0.114 / 0.941 | 0.285 | −0.037 / 0.157 / 0.951 | 0.244 |

The stress design has concentrated export shares and heterogeneity sd 1.0.
The value form removes the population bias and ranks at least as well at the
pipeline's operating point; differencing the total out instead is unbiased but
discards share variation and ranks worse at T = 30. The simulation omits the
BW weights, unit-value measurement error and the import constant, and gives
γ_V at the truth, so the magnitude on BACI is the A/B's question.

**Measurement and decision rule (fixed now).** As patch 0107: two `--stage all`
half-runs on the 2% product subsample (seed 20260926; the v0.10.x Stage 1
loaded, so Stage 2a is re-estimated under the option; single γ_V pass; trim
action `drop`) as `m_expval_odd/even` against the existing `m_ref_base`
halves, with the split-half harness and the step census on the odd halves.
Decision:
- $\Delta r_{\text{within}} \ge +0.03$ with rank ρ not lower: default flip at
  the next batched session;
- $-0.01 < \Delta r_{\text{within}} < +0.03$: `value` is the model's own form
  and costs nothing to carry; it becomes the default at the next Stage-2
  session held for another reason, and replaces the queued
  `--stage2-export-total all` flip, which is moot under `value`;
- $\Delta r_{\text{within}} \le -0.01$: keep `share`, record the result, and
  state the misspecification in the paper.


### Stage-2a rows handed to Stage 2b: `--stage2a-handoff-rows {all|published}` (patch 0110)

**The bug.** Since v0.10.0 (`--stage2-trim-action flag`) the Stage-2a table
keeps the rows its tail trim flagged. `run_estimation.R` builds Stage 2b's
good-level priors and regional γ_V (`stage2b_priors_from_regional()`) and the
starting values (`init_from_regional()`) from that table, and
`is_estimated_row()` does not read `trim_reason`, so the flagged tails entered
all three; only the γ_V pass lookups and the console summary filtered
(patches 0093/0102). The flag action was meant to change what the table
shows, not what Stage 2b estimates. Medians bound the effect -- each one-sided
flagged row moves a median by one order statistic -- but it also confounds the
v0.10.0 attribution: run H2's "new Stage 2a" changed the pole rule, the γ_V
default and this at once.

**The fix.** `stage2a_handoff_rows()` (`R/iteration_helpers.R`): `published`
hands over the `trim_reason`-NA rows only; `all` (default) reproduces every
release; the two coincide under `drop`. `analysis/handoff_rows_census.R`
recomputes the priors and regional γ_V both ways from the shipped Stage-2a
table (`results/stage2a_handoff_census.json`).

**Decision.** A correctness fix, not a methodology choice: `published` becomes
the default at the next Stage-2 session whatever the census shows; the census
is recorded with it.


### The export moment on values, measured (patch 0112)

Run 2026-10-13 on the local machine with patch 0107's design as fixed in patch
0110: two `--stage all` half-runs on the 2% product subsample (seed 20260926;
the v0.10.x Stage 1 loaded, Stage 2a re-estimated under the option; single γ_V
pass; trim action `drop`) under `--stage2-export-moment value`, scored together
with the existing `m_ref_base` halves in one call of
`analysis/stage2_reliability.R` (priors from the base run's Stage-2a table;
`docs/results/stage2_reliability_m_expval.md`):

| config | keys | cells | r_within | rank ρ | r_raw | sd_within (odd / even) |
|---|---|---|---|---|---|---|
| `m_ref_base` (export shares, shipped) | 8.51e4 | 4.02e3 | 0.368 | 0.368 | 0.542 | 0.638 / 0.644 |
| `m_expval` (export values) | 8.51e4 | 4.02e3 | 0.360 | 0.362 | 0.537 | 0.633 / 0.637 |

Step census, odd halves, shares → values (`gamma_v_step()` over 83,687
published keys): |Δ ln γ| p50 0.0056, p90 0.071, p99 0.64, max 5.68; 61.2% of
keys move by less than 0.01.

**Decision.** $\Delta r_{\text{within}} = -0.008$ -- between −0.009 and −0.007
whatever the rounding -- inside $-0.01 < \Delta < +0.03$: the value form, the
moment the model implies, becomes the default at the next Stage-2 session held
for another reason and replaces the queued `--stage2-export-total all` (the
exporter total enters nothing under `value`). It costs a hair of split-half
reproducibility, as the cell simulation from the primitives suggested at
fifteen periods per half, and it moves γ twenty times more than the
denominator did (step p50 0.0056 against 2.6e-4): the misspecification is real
in the data, small at the median, and up to a factor of $e^{0.64} \approx 1.9$
at the 99th percentile. Both half-runs wrote their records under `--out-dir`
(patch 0111) and none into the working directory.


### The Stage-2a handoff and the v0.10.2 censuses, measured (patch 0112)

**Handoff census** (`analysis/handoff_rows_census.R` on the shipped Stage-2a
table; `results/stage2a_handoff_census.json`): 5,798 flagged rows (γ high
1,834, γ low 1,873, σ low 2,091); 399,154 rows behind the priors under `all`
against 393,486 published. Leaving the flagged rows out moves the good-level
prior of 757 of 1,240 goods (|Δ ln| p50 1.2e-4, p90 0.0093, p99 0.112, max
0.447) and the regional γ_V of 2,499 of 25,064 region × good cells (p99 0.398,
max 5.41); 135 cells have a regional γ_V only because of flagged rows. The
decision stands: `published` at the next Stage-2 session. The README states it
under Known limitations.

**Optimizer fallbacks of the v0.10.0 run** (`out_H`, pass 3;
`docs/results/stage2_fallback_census_v0101.md`): 2,730 cells reached the
L-BFGS-B cap (7,710 at v0.9.0); the Nelder-Mead restart was worse than the
discarded point on 79.4% of them (86% at v0.9.0) and reported convergence on
1,794. The drop is the pole rule's: the σ-near-1 cells, whose objective is
badly scaled, now take the fallback σ.

**Shrinkage of the v0.10.1 table** (`docs/results/stage2_shrinkage_census_v0101.md`):
median data share 0.083 (0.105 at v0.9.0), trade-weighted 0.227 (0.274), a
cell's largest exporter 0.378 against 0.033 below tenth (0.420 / 0.043).
Shrinkage strengthened because the pole rule moved σ away from 1, where the
$1/(\sigma - 1)$ coefficients had inflated the data curvature. The first v0.10.2
README quoted this census under `--shrink-wt-def legacy` -- the script's default
until now, the data share $2(1-s)/(2-s)$ of the pre-v0.7.4 SE form --
(0.153 / 0.304 / 0.548 / 0.064), corrected in `b98134f`. From patch 0112 `half`
is the default and `scripts/build_readme.R` refuses a shrinkage census computed
under any other definition.


### The v0.11.0 run (patch 0114)

**Before the box** (2026-10-13, local; the 2% product subsample, seed 20260926,
single γ_V pass, trim action `flag` so the handoff change is exercised;
`docs/results/stage2_reliability_v0110_cfg.md`):

| config | keys | cells | r_within | rank ρ | r_raw | sd_within (A / B) |
|---|---|---|---|---|---|---|
| `v0100_flag` (v0.10.x defaults) | 8.51e4 | 4.02e3 | 0.368 | 0.368 | 0.542 | 0.639 / 0.644 |
| `v0110_cfg` (v0.11.0 defaults) | 8.51e4 | 4.02e3 | 0.360 | 0.362 | 0.537 | 0.633 / 0.637 |
| `v0110_period` (1995–2009 vs 2010–2024) | 6.11e4 | 3.53e3 | 0.099 | 0.108 | 0.352 | 0.603 / 0.561 |

Rule fixed in patch 0113: $\Delta r_{\text{within}} = -0.0077$, rank $-0.0062$,
both above $-0.02$ -- proceed. The new defaults reproduce the value-only A/B to
the third decimal, so the handoff change adds nothing measurable on the
subsample, where the regional trim flags only a few dozen rows; the
cross-period reliability under the new configuration (0.099) matches the v0.8.0
grid's 0.091.

**The box** (2026-10-14, `r7a.16xlarge`, 62 cores; clone `07681c8`, tree
`38d3fefa`; header `Export moment: value | Stage-2a handoff rows: published`;
S3 `v0110rel_run_20261014/out_I/`). Stage 1 loaded, not re-estimated (113,706
clean cells, σ median 2.473; 13,810 edge and 55,396 pole cells to the
fallback). Stage 2a 3.8 min, 422,212 published rows beside 5,823 flagged, γ
median 0.781; Stage 2b's priors from its 393,461 published directly estimated
rows. Stage 2b's three γ_V passes 39.9, 35.4 and 36.1 min; the step against the
previous pass p50 / p90 / p99 = 0.0015 / 0.065 / 0.63 (pass 2) and
2.1e-4 / 0.0125 / 0.22 (pass 3); `gamma_v_resid` filled on 4,920,407 rows;
2,370 cells reached the Nelder-Mead restart in pass 3. Final table 6,892,008
rows (6,801,742 published, 90,266 flagged); Tier 0 / 1 / 2 / 3 = 3.3 / 70.1 /
0.2 / 26.4%; `sigma_source` on published rows: estimated 4,016,326,
fallback_no_estimate 734,198, fallback_sigma_edge 299,320,
fallback_sigma_pole 1,751,898.

**The release gate** (v0.11.0 against the v0.10.2 table): PASS. Published rows
6,801,807 → 6,801,742; median γ 0.8064 → 0.8044; median `opt_tariff`
0.8687 → 0.8523; σ median 2.4728, fallback share 41.0%, non-converged 0.42%,
Tier 3 26.4% and `sigma_robust` TRUE 24.2% unchanged. |Δ ln γ| on shared
directly estimated rows, by σ source:

| σ source | rows | p50 | p90 | p99 | below 1e-2 |
|---|---|---|---|---|---|
| estimated | 2,943,963 | 6.98e-3 | 0.108 | 0.884 | 56.6% |
| fallback_no_estimate | 484,837 | 1.02e-2 | 0.128 | 0.978 | 49.7% |
| fallback_sigma_edge | 203,190 | 1.03e-2 | 0.134 | 1.059 | 49.4% |
| fallback_sigma_pole | 1,275,909 | 7.89e-3 | 0.106 | 0.843 | 54.6% |

The tail is wider than the subsample's single-pass step for the export moment
alone (p99 0.64): the full run adds the handoff change -- which moved 757 of
1,240 goods' priors, up to 0.447 in logs -- and three γ_V passes.

**Two latent bugs, both met on first real use.**
- `scripts/box/setup.sh` and `preflight.sh` (patch 0104) read the manifest sha
  with `awk -F'","' '{print $3}'`, which never matched `data/manifest.csv`
  (its size column is unquoted, so field 3 ran to the end of the row). The
  session's `setup.sh` failed its Stage-1 check after placing the table; both
  scripts were patched in place on the box (`grep -o '[0-9a-f]\{64\}'`) and the
  table verified before the launch. Patch 0114 makes the same change in the
  repo; `tests/testthat/test-box-scripts.R` checks both scripts and that every
  manifest row carries exactly one 64-hex string, its sha256.
- The runner's `sigma_source` (patch 0103) used `:=` inside
  `attach_sigma_source()` on a table whose over-allocation the γ_V passes had
  lost, so the column landed on a copy local to the function (the run's
  data.table "shallow copy" warning) and the saved table had 22 columns; the
  counts it printed were right. The release train adds the column with
  `scripts/add_sigma_source.R` -- the same code path, which verifies that
  estimated rows carry their cell's Stage-1 σ and fallback rows the fallback --
  gated on the counts above. Patch 0114: the function returns the labelled
  table, the runner `setDT()`s and assigns it back, and a test reproduces the
  lost over-allocation.

**The Eq. (8) correction, for the paper and for the note to Soderbery.** The
printed Eq. (8) (prices on export shares) omits $(\rho_I - \rho_V)\,\Delta\ln V_j$,
which inverting his Eq. (7) leaves. His footnote 8 (p. 48) defers how the
equations are built and the errors defined to an online Appendix A, which is in
neither copy of the article at hand; his §3.3 (p. 52) describes the export-side
error as "structurally the reference difference of first-differenced export
supply shocks for the same exporter" -- a pure supply-shock error, which is what
the value form delivers and the share form does not. His footnote 11 notes that
both sets of shares can be built from one reported flow "using the totality of
world trade", which is BACI's case.

### Audit #7: what the release gates called non-convergence, and three measurements fixed before their numbers (patches 0116, 0117)

**The gates' non-convergence (patch 0116).** The cell estimator writes optim()'s
own code on every row of a fit that did not converge (1 at the 5,000-iteration
cap; 10, 51, 52) and -1 only on imputed rows: Tier-3 rows, and the reference row
of a cell whose other exporters are all Tier 3. `analysis/gate_v0100.R` (patch
0102) and `analysis/gate_release.R` (patch 0104) counted -1 among tier < 3 rows as
optimizer non-convergence, which is the share of those imputed reference rows:
the "0.42% in both releases" of the v0.10.0 record above and of the v0.11.0 run is
that share (with the shipped 1,819,483 `tier3_prior` rows it implies Tier 3 at
26.44%, the card's 26.4%), and the gates' H3 could not fail on a real rise in
non-convergence. `stage2_convergence_census()` (`R/utils_general.R`) is now the
one definition; the gates report the two shares apart, and
`analysis/stage2b_convergence_census.R` records the optimizer's figure for the
shipped table. The v0.11.0 fallback census implies 1,928 cells published a point
that is not a converged optimum (1,868 L-BFGS-B points at the cap, 60 Nelder–Mead
restarts without convergence); the census gives their row share.

**Why the next three measurements are not split-half reliability.** Every
decision since v0.8.0 was taken on the split-half reproducibility of the
within-cell γ on the 2% subsample. The halves share the full-panel σ (Stage 1),
the Stage-2a priors and the γ_V lookups. A rule that replaces a noisy shared σ by
one constant raises the agreement of the halves whether or not it brings σ closer
to the truth: on the σ-pole grid above, r_within rose monotonically with the share
of rows at the fallback (0.333 → 0.355 → 0.365 → 0.368 → 0.372 as that share went
11.8% → 64.7%) while the within-cell sd fell (0.826 → 0.532). The metric measures
stability; questions about σ need truth or out-of-sample prediction. And the
subsample is 25 goods, with no interval on the differences (c = 1 cleared its
+0.03 bar by 0.002). Patch 0117 adds:

1. **The σ-pole rule at known truth** (`validation/pole_rule_accuracy.R`). Pillar
   2's simulator (J = 25, T = 30) at σ ∈ {1.2, 1.5, 2, 3, 5, 8} × ω ∈ {0.3, 1, 3},
   200 cells per point, the shipped Stage-1 estimator at cap 50. The cells of a
   grid point share one σ — they are one good's cells. Policies for the σ Stage 2
   uses: P0 the truth; P1 no pole rule (the estimate if usable, else the global
   fallback 2.4728); P2 the shipped rule; P3 the rule with a good-level fallback
   (the median kept estimate of the point). Consequence: in this homogeneous model
   the optimal tariff is ω; ω*(σ) fits the cell's population moments at the σ used
   (exactly the true ω at the true σ), so a policy's tariff error is the
   compensating ω a wrong σ forces. No Stage-2 shrinkage: in the pipeline the
   prior absorbs part of a cell's response and moves through Stage 2a instead.
   **Reading rules** (fixed in this patch; a 40-replicate debugging trial of the
   harness was seen before they were written):
   - R1, low σ: at σ ∈ {1.2, 1.5}, if P2's median tariff error exceeds P1's by more
     than 0.02 log points at either, the global fallback makes genuinely low-σ
     cells worse than their noisy estimate.
   - R2, collateral drops: if the rule drops more than 10% of usable fits at any
     σ ≥ 3, it acts on large standard errors rather than proximity to the pole,
     and replaces σ's above the fallback by a value below them.
   - R3, net: if the mean over σ values of P2's per-σ median tariff error is not
     at least 0.01 below P1's, the rule has no accuracy case in this model and its
     measured benefit is stability alone.
   - R4, M2 preview: if P3 is at least 0.01 below min(P1, P2) at four or more of
     the six σ values and never more than 0.01 above, a good-level fallback
     dominates in this model; the census below decides whether the data's
     within-good dispersion leaves room for it.
2. **Intervals for the subsample decisions** (`analysis/stage2_reliability.R
   --boot-goods B --base CONFIG`): a bootstrap over the 25 goods, from the
   existing half-run tables, no re-estimation. Reading: a past decision whose
   difference interval covers 0 is recorded as within the subsample's noise; no
   default changes on that alone.
3. **A hierarchical σ fallback, sized** (`analysis/sigma_fallback_hierarchy_census.R`,
   the shipped tables, seconds): the share of the variance of ln(σ − 1) across
   clean cells the good and region × good explain; a leave-one-out prediction of
   each estimated cell's σ from the global median against the ladder region ×
   good → good → global (a level used with ≥ 3 other clean cells); and how far
   the ladder would move the fallback cells. **Reading rule:** if the ladder's
   leave-one-out error is at least 20% below the global median's **and** at least
   25% of fallback rows would move their (σ − 1) by more than 25%, the ladder goes
   to a 2% subsample Stage-2 pass (local) before any session; otherwise the global
   fallback stays and the census is recorded.

### Audit #7 measurements, recorded (patch 0118)

Run on the shipped v0.11.0 tables (Stage 2b sha256 `88bc67f5…`) by patch 0116/0117's
runbook, 2026-10-14/15; readings under the rules fixed in patch 0117.

**Optimizer convergence** (`docs/results/stage2b_convergence_census_v0110.md`). Of
4,982,259 directly estimated rows, 35,825 (0.72%) carry a non-zero optimizer code, in
1,775 of 210,098 fitted cells; `gamma_se_status == "non_converged"` equals the code
count. The codes are 52 on 33,428 rows (93%) and 1 on 2,397 (7%): the restart runs
for every L-BFGS-B fit that did not converge (`result_lb$convergence != 0`), and on
this table the binding cause is a failed L-BFGS-B line search, not the 5,000-iteration
cap. The README since v0.8.3, the fallback census's wording and the card said "reached
the cap"; patch 0118 corrects all three, and `analysis/stage2_fallback_census.R` now
tabulates the codes. The v0.11.0 fallback census implied 1,928 non-converged cells
(1,868 L-BFGS-B points + 60 restarts that did not converge); the census finds 1,775
among published rows, and the 0118 version also counts cells whose non-converged rows
the tail trim flagged. Imputed reference rows: 20,895, 0.42% of tier < 3 rows — the
gates' former figure; Tier 3 26.44%. The 1/γ² stiffness of the log ridge (curvature
spanning orders of magnitude within a cell) is the likely source of the line-search
failures; a log-space parameterisation (θ = ln γ, constant ridge curvature 2λ) is the
structural fix if 0.72% ever matters.

**Clean-set cells the pole rule cannot assess** (A3;
`docs/results/pole_na_se_census_v0110.md`). 413 cells, all constrained boundary optima
(ω cap 270, ω floor 143) whose projected edge SE failed (negative variance 374,
singular curvature 39; 22 `boundary_corner`). Their σ: median 2.36, p10 1.01; 70
below 1.2, 125 below 1.5. With their route's median relative SE the rule would drop
72. They carry 2,855 published rows (0.04%), `sigma_robust` FALSE on all. Recorded;
no rule change on its own.

**The σ-pole rule at known truth** (M1; `docs/results/pole_rule_accuracy.md`;
reproduced on MC's machine to the printed digit). Median tariff error, no rule /
shipped rule / good-level fallback: σ 1.2 0.034 / 0.059 / 0.035; 1.5 0.034 / 0.041 /
0.018; 2 0.038 / 0.030 / 0.009; 3 0.070 / 0.054 / 0.048; 5 0.343 / 0.402 / 0.184;
8 1.916 / 2.284 / 1.067. Rule drops among usable fits: 59.9 / 41.3 / 31.9 / 24.0 /
21.7 / 27.5%. Readings: **R1 triggered** (σ 1.2: +0.025 > 0.02 — the global fallback
makes genuinely low-σ cells worse than their estimate); **R2 triggered** (21.7–27.5%
of usable fits dropped at σ ≥ 3, 53–64% where ω = 3 — the rule acts on large standard
errors, not proximity to 1); **R3: no accuracy case** (mean of the per-σ medians 0.478
with the rule, 0.406 without; also without σ = 8, 0.117 vs 0.104, and without σ ≥ 5,
0.046 vs 0.044); **R4: a good-level fallback dominates in the model** (≥ 0.01 better
at 1.5, 2, 5, 8; never ≥ 0.01 worse). The magnitudes at σ ≥ 5 partly reflect how
weakly ω is identified there (at σ = 8, ω = 0.3, understating σ by 9% moves ω* from
0.30 to 0.05; the floor 1e-4 scales the worst errors). Decision: the rule stays — its
measured benefit is stability, which R3 records as its only benefit — because neither
alternative dominates (no rule is better at σ = 1.2, 5, 8 and worse at 2, 3) and the
good-level fallback fails in the data (below).

**A product-level σ fallback, sized** (M2;
`docs/results/sigma_fallback_hierarchy_census_v0110.md`). Over 113,706 clean cells
the good explains 5.7% of the variance of ln(σ − 1) and region × good 23.3% in
sample; good-level medians run p10 2.01 to p90 3.12 around the global 2.47. Leave one
out, the median error predicting an estimated cell's σ is 0.693 from the global
median, 0.674 from its good's median and 0.699 from the ladder region × good → good →
global: the in-sample region × good share is mostly the fit of small groups (a handful
of cells each) to noise. The ladder would move (σ − 1) by more than 25% on 56% of the
fallback rows (1,551,063 of 2,785,416). **Reading rule: not met** (the ladder's error
is not 20% below the global median's) — **the global fallback stays.** The M1 model's
good-level advantage rests on every cell of a good sharing one σ, which the data do
not show. Consequence, for the README and the paper: on the 41% of rows that take the
fallback, σ carries no cell or product information, so their γ and `opt_tariff` are
conditional on an assumed σ (v0.10.0 showed how far `opt_tariff` moves with it).

**Intervals for the subsample decisions** (`analysis/stage2_reliability.R
--boot-goods`): the half-run manifests are re-scored by patch 0118's runbook into
`docs/results/stage2_reliability_goodsboot_*.md`; read under 0117's rule (an interval
covering 0 records the decision as within the subsample's noise; no default changes
on that alone).

**Hub tags.** 19 releases (v0.3.0–v0.11.0) are tagged on the dataset repository; each
resolves to its card revision (checked with `dataset_info(revision=tag).sha`). The
refs listing reports an annotated tag's own object (v0.11.0: `2dc57000…`), not the
commit, so verify tags by resolution (box template updated).

### Intervals for the subsample decisions, measured; a recent-window estimate (M3), designed (patch 0119)

**The goods bootstrap** (`analysis/stage2_reliability.R --boot-goods 2000`, run by patch
0118's runbook on the existing half-run tables; 2,000 draws over the 25 goods,
differences from each grid's base on the same draws; 95% percentile intervals;
`docs/results/stage2_reliability_goodsboot_*.md`):

| decision | Δ r_within | interval | reading (patch 0117's rule) |
|---|---|---|---|
| σ-pole rule c = 0.5 / 1 / 2 / 2.5 vs v0.9.1 | +0.022 / +0.032 / +0.035 / +0.040 | lower ends +0.003 / +0.009 / +0.011 / +0.015 | the gain is not noise; it rises with c, as the shared-σ smoothing predicts; the +0.03 bar lies inside c = 1's interval (+0.009 to +0.057), so "cleared the bar" was a point-estimate statement |
| v0.10.0 as shipped vs v0.9.1 | +0.036 | +0.014 to +0.062 | real |
| fn-14 `--bw-lag raw` / `--exporter-weight bw_sum` / both | −0.030 / −0.019 / −0.026 | all below 0 | the shipped weighting is well supported |
| λ = 0.03 / 0.3 vs 0.1 | −0.007 / −0.002 | 0.03 below 0; 0.3 covers 0 | λ = 0.1 supported; 0.3 indistinguishable |
| reference rules `periods_stable` / `value` | −0.001 / −0.000 | cover 0 | within noise, as decided |
| export-share denominator `all` | −0.000 | covers 0 | within noise (superseded) |
| export moment on values (v0.11.0) | −0.008 | −0.014 to −0.001 | a small real cost in reproducibility, accepted on correctness (harness Test F); v0.11.0 as shipped vs v0.10.x shows the same −0.008 |
| calendar split 1995–2009 / 2010–2024 | r = 0.099 | 0.081 to 0.115 | the cross-period reproducibility is low and precisely measured |

No default changes. For rules acting through σ the intervals measure goods-sampling
variation only: a real gain in reproducibility is still not evidence of accuracy
(the σ-pole rule's accuracy reading is patch 0118's record).

**A year-window gap (A14).** Patch 0072 made `--minyear` / `--maxyear` apply to the
cached panel inside `prepare_data()`, i.e. for Stage 2; Stage 1 receives the raw
cache directly and honoured `--minyear` (through `run_stage1_liml()`'s `min_year`)
but never `--maxyear`, so a 1995–2009 run estimated σ on data through the cache's
last year. From this patch `year_window()` (`R/utils_general.R`) applies the window
to Stage 1's input too; a no-op for the production window.

**M3, a recent-window estimate: two measurements before any session**, both local,
both read under rules fixed here:

1. **Does γ drift by more than half-panel noise?** (`analysis/window_drift_census.R`,
   seconds.) The v0.11.0 pre-session artifacts hold four 2% subsample Stage-2b runs
   under the shipped configuration with full-panel σ and Stage-2a priors — the hybrid
   design: parity halves (odd / even years, noise only) and period halves (1995–2009
   / 2010–2024, noise plus the true change). With V the robust variance of the
   between-half difference of a quantity, V_parity = 2s² and V_period = D² + 2s²; for
   current use the recent half (error s²) beats the full-panel average (error about
   D²/4 + s²/2) iff D² > 2s², i.e. V_period > 2·V_parity. **Rule**, on the cell's log
   `opt_tariff`: ratio > 2 → a recent-window estimate is better for current use;
   < 1.5 → the full-panel average is as good and M3 stays parked; between → decided
   with step 2. Cell mean log γ and row log γ are reported beside it, with coverage
   and the exporters whose γ moved most.
2. **Is σ stable across periods?** (`analysis/sigma_window_census.R` on two local
   Stage-1 runs of the 2% subsample, 1995–2009 and 2010–2024, `--stage 1
   --product-sample 0.02` with the year window.) On cells clean in both windows
   (independent data), z = (σ_late − σ_early)/√(se_early² + se_late²). **Rule**: the
   share with |z| > 1.96 at standard errors inflated 1.5× (the bootstrap's same-branch
   dispersion ran 0.9–1.7× the analytic SE) ≤ 10% → σ is stable and the hybrid (σ
   from the full panel, γ from the window) is the M3 design; > 25% → σ drifts and a
   full window re-estimation is the coherent design, at the clean-set yield the
   census reports; between → decided with step 1.

**What follows:** step 1 "recent window better" with σ stable → a hybrid session
(Stage 1 loaded; Stage 2a + three 2b passes on 2010–2024; about 2 h on the box,
~$9–10), published as a separate artifact beside the full-panel release; with σ
drifting → a full window re-estimation (Stage 1 + 2a + 2b, about 2¼ h, ~$10) whose
fallback share step 2 sizes; step 1 "full panel as good" → no session, whatever σ
does.
