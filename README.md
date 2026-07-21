# trade-elasticities

Heterogeneous import-demand elasticities (σ) and export-supply
parameters (γ) estimated from CEPII BACI HS92 V202601 trade data
(1995–present),
following Soderbery (2018) with the Grant & Soderbery (2024) HLIML
estimator for Stage 1.

**Status:** Pre-publication. Outputs reproducible from this repo.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey.svg)](#license)
[![Dataset on HuggingFace](https://img.shields.io/badge/HuggingFace-Dataset-yellow)](https://huggingface.co/datasets/impex-machina/trade-elasticities)
[![Build](https://github.com/impex-machina/trade-elasticities/actions/workflows/test.yml/badge.svg)](https://github.com/impex-machina/trade-elasticities/actions)

## Overview

This repository contains the production code that produces a panel of
heterogeneous trade elasticities at the (importer, exporter, HS4) cell
level on 1995–present BACI trade data. It implements a three-stage
pipeline:

- **Stage 1** — Heteroskedastic LIML estimation of σ per (importer, HS4),
  following Grant & Soderbery (2024).
- **Stage 2a** — Regional γ with fixed σ and moderate shrinkage.
- **Stage 2b** — Country-level γ with fixed σ, shrinkage anchored to the
  Stage 2a regional priors, and penalized Gauss-Newton standard errors.

Outputs cover 1,240 HS4 products across 233 importers and 233 exporters,
producing 6,831,402 (importer, exporter, HS4) cell-level γ estimates with
standard errors. Stage 1 attempts σ estimation on 280,649 (importer, HS4)
cells across 234 importers, returning an estimate for
141,824 of them (one importer present at Stage 1 has no country-pair γ at Stage 2b after the minimum-destinations filter).

The accompanying paper is in preparation; this repo will be the reference
replication artifact when it is submitted.

## Citation

If you use these elasticities or this code in your work, please cite:

> [Paper citation placeholder — to be updated upon submission]
> Trade elasticities (BACI HS92 V202601, HS4) [Dataset, 2026].
> https://huggingface.co/datasets/impex-machina/trade-elasticities

and the underlying source data:

> Gaulier, Guillaume and Soledad Zignago (2010), "BACI: International
> Trade Database at the Product-Level. The 1994–2007 Version." CEPII
> Working Paper, N°2010-23.

## What you can do with this repo

| If you want to ... | Do this | Wall time |
|---|---|---|
| Read the methodology and analytic choices | [`docs/methodology/README.md`](docs/methodology/README.md) | — |
| Reproduce paper figures and tables from published outputs | `Rscript scripts/download_outputs.R` → `Rscript analysis/master.R` | ~30 min |
| Re-run the validation pillars (synthetic recovery, SE Monte Carlo) | `Rscript analysis/master.R --rerun-pillars` | ~1 hour |
| Re-run the full estimation pipeline from BACI raw → outputs | Download BACI from CEPII, then `Rscript scripts/run_estimation.R --data <dir>` | r7a.16xlarge, several hours |

## Quick start (figure reproducer)

The fastest path: clone, restore the environment, download published
outputs, make figures. Expect ~30 minutes wall time, most of it the
output download.

```bash
# 1. Clone the repo
git clone https://github.com/impex-machina/trade-elasticities.git
cd trade-elasticities

# 2. Restore the R environment (installs all pinned packages from renv.lock)
R --no-save -e "renv::restore()"

# 3. Download published outputs from HuggingFace into data/derived/
Rscript scripts/download_outputs.R

# 4. Reproduce the paper figures and tables
Rscript analysis/master.R
```

Outputs are written to `analysis/figures/*.pdf` and
`analysis/figures/tables/*.csv`, with a run log at
`analysis/figures/run_log.txt`.

If `renv::restore()` fails (most often on Linux for want of a system
library, or anywhere for want of a C++ toolchain), see
[Replication setup](#replication-setup) below.

## A worked example

The core output is the Stage 2b country-level table. Each row is one
(importer, exporter, HS4-product) cell with its estimated inverse
export-supply elasticity γ (defined below) and the σ that
was fixed in for that product. To load it and
read the first rows:

```r
s2b <- readRDS("data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
nrow(s2b)            # 6831402
head(s2b[, c("exporter", "importer", "good", "sigma",
             "gamma", "gamma_se", "gamma_se_status", "tier")], 5)
```

Columns:

| Column | Meaning |
|---|---|
| `importer`, `exporter` | Numeric country codes (BACI/COMTRADE convention). |
| `good` | **HS4 product code, stored as a character string with leading zeros** (e.g. `"0302"`, not `302`). Read it as character; coercing to integer drops the leading zero and silently mismatches chapters 01–09. |
| `sigma` | Import-demand (substitution) elasticity for the product, fixed from Stage 1 and constant within a product. For 24.8% of rows this is a global-median fallback (σ ≈ 2.878) rather than a cell-specific estimate, and a further 11.1% sit at the cap value of 10 (see Known limitations). |
| `gamma` | **Inverse export-supply elasticity** for the (importer, exporter, product) cell — the headline estimate, Soderbery's γ. Lower-bounded near 0 by the optimizer and **unbounded above** (extreme values are handled by the Stage 2a plateau fallback and the 0.5%-per-tail trim; see Known limitations). γ is the *inverse* of an elasticity: the implied export-supply elasticity is 1 / γ (median ≈ 1.485). Small γ means near-perfectly-elastic supply; large γ means strong importer market power. Most cells are shrunk toward a good-level prior (see Known limitations). |
| `gamma_se` | Penalized Gauss-Newton standard error for `gamma`. |
| `gamma_se_status` | `"ok"` when the SE is usable; other values flag degenerate cases. |
| `gamma_se_total` | Standard error for `gamma` with Stage-1 σ uncertainty propagated in by the delta method: `sqrt(gamma_se² + (∂γ/∂σ · sigma_se)²)`. Populated only where `sigma_robust` is `TRUE`; `NA` otherwise (all Tier-3 cells, and any cell where σ-uncertainty could not be propagated stably). Where present, this is the wider, σ-aware SE; where `NA`, `gamma_se` (conditional on σ) is the only SE available. |
| `sigma_robust` | Cell-level (`importer × good`) flag: `TRUE` when γ's SE is robust to Stage-1 σ uncertainty — σ̂ is unclamped, has a finite SE, sits clear of the σ = 1 identification pole, and the propagated term inflates no γ SE in the cell beyond the screen threshold. `FALSE` when any of those fail; `NA` for Tier-3 imputed cells with no per-cell σ. `TRUE` on 10.8% of rows (14.7% of estimated cells), `FALSE` on 62.6%, `NA` on 26.7%. Filter on this to keep only cells whose γ SE is stable once σ is treated as estimated rather than known (see Known limitations). |
| `sigma_se` | Stage-1 standard error of `sigma` for the product, carried in for the propagation. `NA` where Stage 1 clamped σ or ω (the cap is reported without a usable SE) or returned none. Constant within a product. |
| `dgamma_dsigma` | Local sensitivity ∂γ/∂σ for the cell, from the implicit-function derivative of the γ first-order condition; the input to `gamma_se_total`. Large magnitudes mark cells where γ moves sharply with σ, typically those near the σ = 1 pole. |
| `gamma_exposure` | Number of exporters in the estimating set for the cell. |
| `ref_exporter` | Reference exporter used in the supply system. |
| `tier` | Estimator-provenance tier (1–4) recording how the cell was identified. |
| `convergence`, `obj_value` | Optimizer convergence code and objective value. |
| `opt_tariff`, `opt_tariff_all` | Implied optimal tariff derived from (σ, γ): Soderbery's heterogeneous-exporter optimal-tariff statistic, a trade-weighted aggregate of γ across the cell's exporters (weights ∝ trade / (1 + γσ)), **constant within an (importer, product) cell**. `opt_tariff` aggregates directly estimated exporters (tiers 0-2) only; `opt_tariff_all` includes Tier-3 imputations. Downstream of the estimates — treat as derived, not primary — and collapsing toward zero where supply identification floors ω (see Known limitations). |

A reader reproducing the headline numbers should find σ median ≈ 2.878 on
the canonical 1,240-product universe. `analysis/master.R` prints this as
it runs.

## Repository structure

```
trade-elasticities/
├── R/                 # estimation library (HLIML, Stage 2 solvers, SEs, CLI)
├── scripts/           # entry points: run_estimation.R, download_outputs.R, build_readme.R
├── analysis/          # master.R + 7 numbered pillar scripts (figures/tables)
├── validation/        # synthetic-recovery and SE Monte Carlo harnesses
├── tests/             # testthat suite
├── data/
│   ├── raw/           # BACI input (gitignored; not redistributed)
│   ├── derived/       # published outputs (downloaded from HF; gitignored)
│   └── manifest.csv   # the 12 published files, with SHA-256 checksums
├── docs/methodology/  # methodology write-up + three-pillar evidence base
├── inst/              # Grant & Soderbery (2024) reference PDF
├── results/           # generated summary JSONs feeding the README build
├── renv.lock          # pinned package versions
├── README.template.md # README source; do not edit README.md directly
└── README.md          # GENERATED from README.template.md + results/*.json
```

## Methodology

For the full methodology and the three-pillar evidence base, see
[`docs/methodology/README.md`](docs/methodology/README.md), which indexes:

- **Pillar 1** — BACI HS4 empirical core (Stage 1 / 2a / 2b production).
- **Pillar 2** — Synthetic recovery validation (Tier 1 of `validate_liml.R`).
- **Pillar 3** — SE calibration Monte Carlo.
- **Stage-2 structural-DGP harness** (`validation/stage2_structural_dgp.R`)
  — the moment-identity check that guards the Eq. (10)/(11) coefficients
  against the paper's structural equations: **PASS** at rev `4a947c0`, 2026-07-21 (import + export sides, Eqs. (10) and (11) with the G1 sign correction; seed 20260717). Regenerate with `Rscript validation/stage2_structural_dgp.R`.

The `analysis/` scripts regenerate every paper figure and table from the
published outputs; pass `--rerun-pillars` to regenerate the validation
inputs from the harnesses in `validation/` rather than reading the
published CSVs.

## Replication setup

This section is for readers re-running the **full pipeline from raw BACI
data**. Skip it if you only want to reproduce figures from published
outputs (use the [Quick start](#quick-start-figure-reproducer)).

<details>
<summary><b>System requirements</b></summary>

- **R** 4.5 or newer (tested on R 4.6.0 local, R 4.5.3 on the production
  AMI). Package versions are pinned in `renv.lock`; `renv::restore()`
  reproduces them.
- **A C++ toolchain** is required to build `Rcpp` and a few other packages
  from source if no binary is available: Rtools on Windows, `build-essential`
  on Debian/Ubuntu, Xcode command-line tools on macOS.
- **Linux system libraries.** On a fresh Ubuntu box, `renv::restore()` may
  need development headers for packages that compile from source. If a
  package fails to build, install the matching `-dev` package and retry
  (commonly `libssl-dev`, `libxml2-dev`, `libcurl4-openssl-dev`).
</details>

<details>
<summary><b>Hardware (full pipeline)</b></summary>

Stage 1 is memory-bound. The production run uses an AWS `r7a.16xlarge`
(512 GB RAM): the master process holds a ~30 GB working copy of the trade
data and then forks across worker cores, so a 128 GB instance is not
sufficient. Stages 2a/2b are lighter. The figure-reproducer path
(`download_outputs.R` → `master.R`) runs comfortably on a laptop; only a
from-raw re-estimation needs the large instance.
</details>

<details>
<summary><b>Getting BACI</b></summary>

BACI raw data is **not** redistributed here or on HuggingFace. Download
BACI HS92 V202601 from [CEPII](http://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37)
and point the runner at it:

```bash
Rscript scripts/run_estimation.R --data /path/to/BACI_HS92_V202601 --agg-level hs4
```

> **Source identifier.** Output filenames embed a source tag parsed from
> the *path* of the input directory (e.g. `BACI_HS92_V202601`). If the
> input path does not contain this token, outputs are silently named with
> a generic `baci` prefix. See `docs/parse_baci_source_note.md`.
</details>

## Data sources and provenance

This pipeline consumes CEPII BACI HS92 V202601. The published *outputs*
(elasticity estimates and validation CSVs) are hosted on HuggingFace and
listed, with SHA-256 checksums, in [`data/manifest.csv`](data/manifest.csv);
`scripts/download_outputs.R` fetches and verifies them. BACI raw *inputs*
are not redistributed (see [Getting BACI](#replication-setup)).

## Known limitations

Stated forthrightly:

- **σ small-sample bias and selection under the Stage-1 homogeneity
  assumption.** Synthetic recovery (Pillar 2) shows the estimator *returns
  an estimate* in only 32.5%–52.0% of replications across the σ × ω grid
  (median 35.8%) — a yield rate, not a recovery-within-tolerance rate —
  with the yield declining as sample size grows: a selection signature
  where harder cells converge only with more data. Conditional on
  success, the median σ bias across the grid runs from
  -70.8% to 26.4% and is predominantly *downward*
  across the tested grid, so comparisons to Feenstra-GMM or
  Broda–Weinstein estimates should not assume the upward bias of that
  tradition.
- **Estimator-provenance composition.** On the full universe, 18.2% of
  (importer, HS4) cells are identified at the HLIML interior; the rest fall
  to the Step 2 fallback, of which 8.5% of the full universe (23,943 cells)
  are clamped at the σ/ω caps and report the cap, not an estimate. 82.7% of cells fail the
  Stock-Yogo weak-instrument threshold at the strict 10% maximal-size
  critical value this pipeline screens at. At Grant-Soderbery (2024)'s own
  25% rule of thumb, 58.5% of evaluated cells pass the
  weak-instrument screen, 61.7% pass the Sargan
  overidentification test (conventional p > 0.2), and 28.4% pass both --
  the joint credibility screen of the G&S protocol. Per-cell flags
  (`stockyogo_pass_gs25`, `sargan_pass`, `gs_pass_both`) ship in the Stage 1
  output so either threshold can be applied downstream. Conditional on `status == "ok"`
  the interior rate rises to 36.0%; both framings appear in the methodology
  write-up. Headline σ medians are reported on the canonical 1,240 HS4
  universe.
- **Period extension relative to Soderbery (2018).** This pipeline
  estimates over a longer window than Soderbery's original sample, which
  contributes to estimate differences independently of the estimator
  change from Feenstra GMM to HLIML.
- **Supply-side flooring, and shrinkage that masks it.** The Stage 1
  inversion clamps the supply parameter ω to a lower floor (1e-4); a cell
  pushed there is reported as near-perfectly-elastic supply, not as a
  failure; the `adjust` code does not flag it, though the Stage 1
  `omega_floored` boolean isolates exactly these cells. Stage 2
  ridge shrinkage toward good-level priors then lifts most of that floored
  mass, so the published γ floors in only 0.0% of cells and looks
  better-behaved than the Stage 1 supply identification underneath it (the
  Stage 1 ω-floor share is far larger, at 15.7%
  of cells; see `docs/methodology/stage1_README.md`). Where ω is floored, both γ and the
  derived `opt_tariff` collapse toward zero — toward elastic supply and a
  near-zero optimal tariff — so a γ or tariff sitting at that boundary is an
  identification artifact, not an interior estimate.
- **Standard errors: conditional on σ, with a robustness screen.** `gamma_se`
  is computed with σ held fixed at its Stage 1 value (a global-median fallback
  wherever Stage 1 did not identify σ), so it is conditional on σ. Only
  65.1% of rows carry a clean cell-specific SE: 25.7% are Tier 3 cells
  assigned the regional prior outright (no SE) and the remaining
  9.1% are boundary, plateau, non-converged, or unflagged fits. The pipeline
  additionally propagates the Stage 1 σ uncertainty by the delta method into
  `gamma_se_total` and flags the result with a cell-level `sigma_robust` screen:
  σ̂ unclamped and with a finite SE, clear of the σ = 1 pole, and no γ SE in the
  cell inflated beyond threshold. 10.8% of rows pass (14.7% of estimated cells); 62.6% are flagged `FALSE` and 26.7% are Tier-3 imputed cells (`NA`) with no per-cell σ. The screen is governed almost entirely by σ̂'s distance from the σ = 1 pole, not by the inflation cutoff, and the pass rate is stable across a wide grid of both thresholds (`analysis/sensitivity_sweep.R` reproduces it). Where `sigma_robust` is `FALSE` or `NA`, treat `gamma_se` as a conditional, lower-bound measure of uncertainty; where `TRUE`, `gamma_se_total` is the σ-aware SE — and in either case the SE is frequently as large as the estimate itself.
- **σ is sensitive to the estimator, not only the sample.** On the Tier 4
  comparison against the legacy Feenstra-GMM baseline, the HLIML σ and the
  GMM σ agree poorly in both level and cross-cell rank ordering. Comparisons
  of these σ to GMM- or Broda-Weinstein-style estimates elsewhere should
  account for the estimator difference, not just the sample and period.
- **BACI vs. the COMTRADE data Soderbery (2018) used.** This pipeline uses
  CEPII BACI — mirror-reconciled, FOB-valued, and carrying a share of
  quantities that CEPII imputes from mirror-flow unit-value conversion and
  does not flag in the released data (so the corresponding unit values are
  partly synthetic and cannot be filtered out) — rather than the
  importer-reported COMTRADE of the original. HS4 unit values are weight-based composites
  (value divided by tonnes, summed over the constituent HS6 lines) and so
  move with product mix, not only price. These data-construction choices
  reshape the cross-exporter second moments that identify σ and ω, and
  contribute to differences from Soderbery independently of the estimator
  and period.

## License

- **Code:** [MIT](LICENSE)
- **Data:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

## Acknowledgments

The Stage 1 estimator is a port of the Grant & Soderbery (2024) HLIML
method; we thank the authors for their published replication materials.
Trade data is from the CEPII BACI database. Any errors are our own.

## References

- Feenstra, R.C. (1994). New product varieties and the measurement of
  international prices. *American Economic Review*, 84(1), 157–177.
- Soderbery, A. (2018). Trade elasticities, heterogeneity, and optimal
  tariffs. *Journal of International Economics*, 114, 44–62.
- Grant, M. & Soderbery, A. (2024). Heteroskedastic supply and demand
  estimation: analysis and testing. *Journal of International Economics*,
  150, 103817. (See `inst/grant_soderbery_2024_heteroskedastic_estimation.pdf`.)
- Gaulier, G. & Zignago, S. (2010). BACI: International Trade Database at
  the Product-Level. CEPII Working Paper N°2010-23.
- CEPII BACI World Trade Database, HS92 V202601.
