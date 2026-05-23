# Pipeline refactor history

This document records the refactor of the trade-elasticities codebase from a
monolithic single-file structure to the current modular layout, and the
subsequent archival of the legacy pipeline. It is a reference for understanding
how the codebase arrived at its current shape; for the canonical layout, see
the top-level `README.md` and the function-level documentation in `R/`.

Pipeline scope: BACI HS92 V202601 HS4 trade-elasticity estimation, LIML era
(Stage 1 = Grant & Soderbery 2024 HLIML; Stage 2 = Soderbery 2018 three-stage
fixed-sigma estimator with shrinkage; gamma standard errors via penalized
Gauss-Newton).

> **Provenance note.** This document supersedes the pre-refactor
> `source/README.md` (also archived as `source_readme_v2.md`). Paths below
> reflect the post-N+3 archival layout, in which the legacy pipeline tree was
> moved out of the active working directory into `_archive/`. Where this
> document references legacy scripts, they are archived artifacts retained for
> traceability — they are not re-run as part of the refactored pipeline, and
> several carry hardcoded paths that point at the pre-archival location and
> would need adjustment to execute.

## Refactored repository structure (May 2026)

The refactor split a monolithic single-file library into a flat `R/` function
layer plus an `src/` C++ layer, driven by a single CLI entry point.

### Core estimation (`R/` and `src/`)

| File | Role |
|------|------|
| `R/feen94_het_baci.R` | Thin wrapper; sources the split files below in dependency order, then loads Rcpp objectives. Preserves the original library's source contract. (Disposition under review at N+6 / E2.) |
| `R/estimate_cell_homogeneous.R`, `R/estimate_cell_fixed_sigma.R` | Cell-level optimization, tier assignment, SE computation |
| `R/estimate_parallel.R` | `estimate_all_parallel` and `estimate_all_fixed_sigma` — the PSOCK-cluster drivers |
| `R/estimate_stage1.R` | Feenstra/Soderbery Stage 1 estimators (used when not using LIML upstream) |
| `R/prepare_data.R`, `R/load_baci.R`, `R/region_map.R`, `R/hs_codes.R` | Data preparation and country/HS mapping |
| `R/summary.R`, `R/output_paths.R`, `R/quality_log.R` | Reporting and output management |
| `R/iteration_helpers.R`, `R/lambda_calibration.R` | Multi-pass and shrinkage-sweep helpers |
| `R/validate_config.R`, `R/helpers.R` | Config validation and small utility functions. (`helpers.R` disposition under review at N+6 / E1.) |
| `R/load_rcpp.R` | Loads the three Rcpp objectives from `src/`, with pure-R fallbacks |
| `R/parse_cli.R`, `R/build_config.R` | CLI argument parsing for `scripts/run_estimation.R`. See "CLI parsing" note below. |
| `src/het_obj.R` | R reference implementation of the joint SUR objective (fallback) |
| `src/het_obj_rcpp.cpp` | Rcpp joint SUR objective (used when sigma and gamma are jointly varied) |
| `src/het_obj_fixed_sigma_rcpp.cpp` | Rcpp fixed-sigma objective (gamma-only; used by Stages 2a/2b) |
| `src/het_obj_fixed_sigma_jacobian_rcpp.cpp` | Rcpp residual + Jacobian function used by `compute_penalized_gn_se` for gamma standard errors |

### CLI driver

| File | Role |
|------|------|
| `scripts/run_estimation.R` | CLI runner for the three-stage pipeline. Replaces the original hardcoded-path `run_est_baci_hs92_v202601_hs4.R`. Accepts `--data`, `--out-dir`, `--ncores`, `--shrinkage-lambda`, `--stage` and other options; see `Rscript scripts/run_estimation.R --help`. |

### CLI parsing (`R/parse_cli.R`)

As of the May 2026 refactor, `R/parse_cli.R` is **optparse-based**: it requires
the `optparse` package and exposes a deliberately small set of run-to-run
options (`--data`, `--out-dir`, `--agg-level`, `--minyear`, `--maxyear`,
`--ncores`, `--shrinkage-lambda`, `--stage`). Methodological knobs (starting
values, exporter weighting, tier thresholds, trimming) are intentionally *not*
CLI-exposed; they stay versioned in source to avoid silent reproducibility loss.

> **Forward note (E3 / D30).** The publication architecture plan's D30 calls for
> evaluating whether to rewrite this parser as hand-rolled (no `optparse`
> dependency) or to keep `optparse` and declare it as an `renv` dependency.
> This is tracked as execution item E3, to be resolved during the N+6 R/
> conventions session. As of this writing the file uses `optparse`; this note
> will be updated to reflect whatever N+6 decides. The `optparse` design is
> well-suited to the "expose only run-to-run knobs, version the rest" intent
> documented in the file header.

## Legacy pipeline (archived; not part of the refactored repo)

The following scripts lived in the pre-refactor `source/` folder. They are
one-off scripts rather than reusable library functions and were **not migrated**
into `R/`. They are retained in the archive for traceability.

**Canonical archive location:**
`_archive/trade_elast_baci_hs92_v202601_hs4_pre_padding_fix/source/`
(at the projects-tree root, one level above this repo).

A partial sibling snapshot also exists at
`_archive/legacy_source_snapshot_20260520/`; it contains a subset of the same
files. The `_pre_padding_fix/source/` tree is the more complete copy and is
treated as canonical here.

### Stage 1 driver (legacy only)

| File | Role |
|------|------|
| `liml_estimator.R` | Stage 1 LIML core: HLIML estimator with Stage 2/Step 2 fallback, F-stat diagnostics, Stock-Yogo screening |
| `stage1_liml_wrapper.R` | Stage 1 driver: applies LIML to the BACI panel, writes `_feenstra_sigma_liml.rds` |
| `translate_liml_to_feenstra_schema.R` | Translates LIML output to the `_feenstra_sigma.rds` schema expected by Stage 2 (renames `gamma_common` → `gamma`, adds `convergence` column) |
| `run_est_baci_hs92_v202601_hs4.R` | Original Stage 2a + 2b runner with hardcoded paths. Replaced by `scripts/run_estimation.R`. |

### Diagnostics & post-processing (legacy only)

These ran against the 2026-05-14 outputs and produced `heterogeneity_report.md`
and the provenance-tagged file in the legacy `stage2_liml_202605/` output set.
They are not re-run as part of the refactored pipeline.

| File | Role |
|------|------|
| `tag_sigma_provenance.R` | Post-run script: joins Stage 2 country output against the LIML file to label each row's sigma source (`LIML` vs `fallback_median`) |
| `inspect_country.R` | Structural inspection: tier breakdown, convergence by tier, sigma/gamma distributions by provenance, fallback concentration |
| `heterogeneity_full.R` | SE-enabled analytical report: 3×3 sensitivity grid (CV × filter mode), matched-HS4 comparison vs Soderbery (2018), R1 by HS section, plots. Produced `heterogeneity_report.md`. |

### Selection-bias diagnostic (completed; written up in methodology layer)

| File | Role |
|------|------|
| `sigma_gamma_ridge_ipw.R` | Inverse-propensity-weighted sigma-gamma analysis on the LIML-only subsample. Fits a logistic propensity model for P(LIML success \| HS section + importer region + log avg trade), reweights LIML cells by 1/p̂, and produces a reweighted sigma-gamma joint plot. A follow-up diagnostic addressing the LIML selection-bias concern (Stage 1 LIML succeeds preferentially on high-sigma cells, shifting the LIML-only median sigma from ~2.9 to ~5.3). |

> **Status: completed and documented.** This diagnostic was run and written up
> at `docs/methodology/sigma_gamma_ridge.md` (run 2026-05-14). Its conclusion:
> the apparent sigma-gamma ridge correlation in the full sample (rho = -0.232)
> is an artifact of the global-median sigma fallback stripe; on the LIML-only
> subsample rho collapses to -0.092, and IPW reweighting on observables barely
> moves it (-0.099), indicating the residual is not a selection artifact but
> likely mild real economic structure. Per that document, this is a **follow-up
> diagnostic, not a primary deliverable** — the headline heterogeneity findings
> stand independently. The script is retained here for provenance; the
> methodology-layer write-up is the canonical record of the result.

### SE methodology verification (legacy only)

These scripts validated the penalized Gauss-Newton SE formula before it was
integrated into the library. They are not part of the production pipeline but
are kept for traceability.

| File | Role |
|------|------|
| `verify_jacobian.R` | Cross-checks the analytic Jacobian against numerical differentiation. Confirms ~1e-11 agreement. |
| `sandwich_se.R` | R helper implementing sandwich SE assembly from sparse Jacobian triplets (used in verification only; production uses Gauss-Newton). |
| `smoke_test_se_integration.R` | End-to-end test that the patched library produces SE columns on synthetic data. The refactored repo's equivalent is `tests/testthat/test-stage2b-e2e.R`. |

> **Note on the Monte Carlo SE scripts.** The original `monte_carlo_se.R`,
> `monte_carlo_se_2.R`, and `monte_carlo_se_3.R` (Monte Carlo calibration of the
> three SE formulas — unpenalized GN, sandwich, penalized GN — against empirical
> SD across replications) were **lost** and are **not present in the archive**.
> A reconstructed `monte_carlo_se.R` lives in the active repo (migrated from
> `tests/` to `validation/` at N+10 per the publication plan) and is
> the live version. Likewise, the pre-LIML `feenstra_core.R` /
> `test_feenstra_core.R` are permanently lost; that methodology was superseded
> by the HLIML approach and the loss is not material to the current pipeline.

## Pipeline order

The refactored pipeline produces the same outputs as the legacy one, but driven
by a single CLI command rather than three separately-invoked scripts.

> **Parity status.** Numerical parity between the refactored CLI and the
> 2026-05 legacy snapshot **was verified during N+3**: Stage 1 and Stage 2a
> parity are confirmed against the legacy pipeline. (N+3 also fixed the HS6
> leading-zero bug, which had inflated the legacy HS4 universe with phantom
> codes; the refactored universe is the corrected one, so Stage 1 figures are
> compared with that correction in mind.) See `docs/methodology/stage2a_parity.md`
> and `docs/methodology/stage2b_parity.md` for the parity evidence.

```
BACI raw CSVs  (--data argument)
    │
    ▼ (scripts/run_estimation.R --stage 1)
    │   legacy equivalent: stage1_liml_wrapper.R, calls liml_estimator.R
    │
{out_dir}/baci_..._feenstra_sigma.rds                (Stage 1 output)
    │   legacy: stage1_liml_YYYYMM/baci_..._feenstra_sigma_liml.rds
    │           + a translate step before Stage 2 ingests it
    │
    ▼ (scripts/run_estimation.R --stage 2a, or --stage all)
{out_dir}/baci_..._regional_hs4_fixed_sigma.rds
    │
    ▼ (scripts/run_estimation.R --stage 2b, or --stage all)
{out_dir}/baci_..._country_hs4_fixed_sigma.rds
    │   (15 columns including gamma_se, gamma_se_status, gamma_exposure)
    │
    ▼ (tag_sigma_provenance.R — legacy only)
{out_dir}/baci_..._country_hs4_fixed_sigma_tagged.rds
    │
    ▼ (inspect_country.R — legacy only)
inspection_country.log
    │
    ▼ (heterogeneity_full.R — legacy only)
heterogeneity_report.md + figures/ + CSVs
```

The "legacy only" steps below Stage 2b are post-hoc analyses that were not
migrated into the refactored repo because they are one-off report-producing
scripts, not reusable pipeline components. They live in the archive
(`_archive/.../source/`) and reference the pre-archival output paths.

## SE methodology

Gamma standard errors use **penalized Gauss-Newton**:

```
V(γ̂) = σ̂² · (J'WJ + 2λ · diag(1/γ̂²))⁻¹
```

where J is the analytic residual Jacobian (from
`src/het_obj_fixed_sigma_jacobian_rcpp.cpp`), W is the diagonal weight matrix,
σ̂² = SSR/df, and λ is the shrinkage parameter from Stage 2b config (0.1 by
default).

This formula was chosen over alternatives based on Monte Carlo verification.
Three methodology notes:

1. `optim()$hessian` is the full Hessian of the SSR, not the Gauss-Newton
   matrix. Using it for NLS variance overestimates by ~50% on nonlinear models.
2. The classical sandwich-robust SE underestimates by ~30% in this NLS setting
   (residual-Jacobian correlation at the optimum).
3. Under shrinkage, the prior's Hessian (2λ·diag(1/γ̂²)) must be added or
   unpenalized GN overstates SE by ~30%.

Penalized GN calibrates within ~5% of empirical sampling variability across all
tested regimes. The symbolic derivation of the residual Jacobian is in
`docs/methodology/stage2_derivation.md` (sympy-verified term-by-term); the
Monte Carlo calibration evidence is in the SE-calibration pillar of the
methodology evidence base (see `docs/methodology/README.md`).

## Archival (N+3, May 2026)

The legacy pipeline directory `trade_elast_baci_hs92_v202601_hs4/` was archived
during the N+3 session to:

- **Locally:** `_archive/trade_elast_baci_hs92_v202601_hs4_pre_padding_fix/`
  (with the legacy `source/` tree under `.../source/`, and a partial snapshot at
  `_archive/legacy_source_snapshot_20260520/`).
- **S3:** `s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/`.

The archive is the pre-HS6-padding-fix state, retained for parity comparison and
traceability. It is read-only history; the canonical pipeline is the refactored
repo.

## Versioning

The refactored repo will be placed under git at the publication session (N+12),
with output data published to HuggingFace and the initial tag `v0.1.0-initial`
(bumping to `v1.0.0` at paper submission). Until then, the 2026-05 legacy
snapshot remains read-only in `_archive/` for parity comparison. Subsequent
changes to the pipeline are tracked through git history rather than in-place
file versioning.

### Dependency management (renv)

Package versions are pinned with `renv` (initialized at N+11). The lockfile
`renv.lock` and `renv/activate.R` are committed; the `renv/library/` tree is
gitignored (it is large and machine-specific). A clone reproduces the
environment with `renv::restore()`. The R version itself is not pinned by the
lockfile; the README declares the tested range (R 4.6.0 local / R 4.5.3
production; works on R 4.5+).

Discipline for changing dependencies:

- **Adding a package:** install it locally, use it in code, run
  `renv::snapshot()`, and commit the updated `renv.lock` in the same commit as
  the code that introduced the dependency. `R/dependencies.R` is the single
  declared inventory (attached packages plus namespace-qualified ones); keep it
  and the lockfile in step.
- **Updating a package:** install the new version, run the test suite and the
  validation harnesses, `renv::snapshot()`, and commit the lockfile only if the
  tests pass.
- **Removing a package:** delete its uses from code first, then snapshot. (The
  optional `arrow` parquet fast-path in `validation/validate_liml.R` was removed
  this way at N+11 rather than carried as a heavyweight lockfile entry for a
  code path the `.rds`/CSV pipeline never exercises.)

Cross-OS validation of `renv::restore()` on EC2 Linux (D37) is performed at the
publication session (N+12), where any Linux system-library prerequisites are
documented in the README's replication-setup section.
