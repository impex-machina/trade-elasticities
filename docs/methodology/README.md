# trade-elasticities/docs/methodology/

This directory holds the methodology and parity-verification documentation
for the refactored heterogeneous trade elasticities pipeline. It has two
layers: **methodology** documents describing what each stage of the
pipeline does and why, and **evidence** documents proving the pipeline
behaves as advertised on synthetic and real BACI data.

The combined contents are the paper's evidence base. Three pillars:

1. **BACI HS4 empirical core** — production diagnostics on the 280,649-cell
   HS4 universe (51.9% Stage 1 ok rate, σ median 2.91 matching Soderbery's
   2.88, Stage 2b 8.13M cell-exporter rows with 60.7% finite γ-SE)
2. **Synthetic recovery** — Tier 1+2 of `validate_liml.R` confirming
   HLIML's behavior on known data-generating processes
3. **SE calibration** — Monte Carlo validation of penalized Gauss-Newton
   standard errors across the four (homoskedasticity × shrinkage) regimes

## Methodology layer

These documents describe the pipeline's structure and the choices in it.
They were re-homed from the pre-refactor working directory during the
2026-05 refactor, with path references updated for the new repository
layout.

| File | Coverage |
|------|----------|
| `stage1_liml.md` | Stage 1 (Grant-Soderbery 2024 HLIML): estimator, F-stat diagnostics, Stock-Yogo screening, status flags |
| `stage2_country.md` | Stage 2b (country γ with fixed σ + shrinkage): output schema, σ provenance, SE status breakdown, downstream filtering policy |
| `stage2_derivation.md` | Symbolic derivation of the residual Jacobian and Gauss-Newton variance formula used for γ standard errors |
| `sigma_gamma_ridge.md` | σ–γ identification ridge diagnostic: IPW-weighted analysis on the LIML-only subsample |

## Evidence / parity verification layer

These documents capture the 2026-05-19/20 sprint that established
empirical and synthetic validity of the refactored pipeline against the
legacy run and against ground truth.

| File | Pillar | Coverage |
|------|--------|----------|
| `stage1_README.md` | 1 | Stage 1 production output schema, S3 location, downstream consumption |
| `liml_validation.md` | 2 | Tier 1 (synthetic σ/ω recovery on the parameter grid) and Tier 2 (closed-form sanity checks) results |

## Companion data files

Per-document supporting CSVs and console captures live alongside the
markdown:

- `liml_validation_tier1a.csv`, `liml_validation_tier1b.csv`,
  `liml_validation_console.txt` — Tier 1+2 detail
- `se_calibration_mc_summary.csv`, `se_calibration_mc_per_param.csv`,
  `se_calibration_mc_run.log` — SE Monte Carlo detail (the run log is
  large and lives locally only; CSVs cover all reported numbers)

The non-PDF artifacts mirror to S3 at
`s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/validation/`
(see "Validation harness inventory" below).

## Reading order for a new reader

1. `stage1_liml.md` and `stage2_country.md` for what the pipeline does
2. `stage2_derivation.md` for the SE formula's mathematical basis
3. `stage1_README.md` for the production output schema (pillar 1)
4. `liml_validation.md` for synthetic validation (pillar 2)
5. `sigma_gamma_ridge.md` for the identification-ridge diagnostic
6. "Validation harness inventory" (below) for the scripts that produce
   the evidence docs and the S3 mirror spec

The penalized GN SE calibration (pillar 3) is summarized in the
`se_calibration_mc_summary.csv` companion file and in the "Validation
harness inventory" section below; the underlying script is
`validation/monte_carlo_se.R`.

## Validation harness inventory

The pillar-2 and -3 evidence documents are produced by capture
scripts in `validation/`. Re-running these populates
`data/derived/validation/`, which the analysis layer (see the repo-root
README's analysis section) consumes.

| Evidence document | Produced by | Wall time | Compute |
|---|---|---|---|
| `liml_validation.md` (+ `liml_validation_*.csv`, `liml_validation_console.txt`) | `validation/capture_liml_validation.R` | ~3 min | local |
| `se_calibration_mc_summary.csv` (+ `se_calibration_mc_per_param.csv`) | `validation/monte_carlo_se.R` | ~10 min | local |

Supporting scripts in `validation/`:

- `validate_liml.R` — main validation harness (Tiers 1a/1b/1c/2/3),
  including the 2026-05-20 verdict-logic and BACI column-detection patches.

The historical patch script `patch_tier1_tier2_verdicts.R` (applied the
2026-05-20 verdict edits to `validate_liml.R`) is retained locally for
provenance, not for re-application; the current `validate_liml.R` is the
post-patch version.

### S3 mirror

The non-PDF evidence artifacts and the harness scripts are mirrored for
archival at
`s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/validation/`.
The local canonical copies live in this repository (`docs/methodology/`
for the evidence docs, `validation/` for the scripts). The S3 mirror is
for archival and for external readers who reach the bucket without the
repo. Pillar 1 (BACI HS4 empirical core) is not a standalone file in the
mirror; its production output lives at
`refactored_run_20260519/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`
and is summarized inline in `stage1_README.md`.

### Running the suite

All scripts assume the working directory is the repo root. The harness
requires `R/liml_estimator.R` and `R/feen94_het_baci.R` plus `data.table`.
Typical laptop wall times: Tier 1+2 ~3 min, SE-MC ~10 min.

## Provenance and updates

Methodology-layer documents were re-homed from the pre-refactor working
directory during the 2026-05 refactor sprint (2026-05-14/15).
Evidence/parity-layer documents were authored during the 2026-05-19/20
parity-verification sprint. This index was created during the 2026-05-20
N+3 archival session to make the directory navigable as a unit.

The evidence documents in this directory (`stage1_README.md`,
`liml_validation.md`) are the
canonical record of the validation campaigns that backed the paper's
methodology. Their content is frozen at paper submission; we treat them
as primary evidence, not living documentation.

Post-submission updates (e.g., responses to reviewer comments, additional
robustness checks) are added under `docs/methodology/supplementary/`
rather than by editing the frozen documents.

*Last updated: 2026-05-26: Pillar 4 (HLIML-vs-Feenstra-GMM, Tier 4) cut
from scope per slim-down Decision 1 (research goal is comparison against
Soderbery's published dataset, not estimator self-comparison);
`tier4_hliml_vs_gmm.md`, `tier4_comp.csv`, `tier4_comp_with_adjust.csv`
and the four Tier-4 capture/adjust scripts removed; four-pillar evidence
base reduced to three. Earlier — 2026-05-22 (N+8): evidence docs renamed
to canonical undated names; Grant & Soderbery (2024) PDF moved to
`inst/`; `validation_README.md` absorbed here; frozen-at-submission
stipulation added.*