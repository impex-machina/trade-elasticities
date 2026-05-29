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

Outputs cover {{format_int(req(r$stage1, "n_products"))}} HS4 products across {{req(r$stage2b, "n_importers")}} importers and {{req(r$stage2b, "n_exporters")}} exporters,
producing {{format_int(req(r$stage2b, "n_cells"))}} (importer, exporter, HS4) cell-level γ estimates with
standard errors. Stage 1 estimates σ for {{format_int(req(r$stage1, "n_cells"))}} (importer, HS4) cells
across {{req(r$stage1, "n_importers")}} importers{{asymmetry_phrase(req(r$stage2b, "n_importers_asymmetry_vs_stage1"))}}.

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
| Re-run the validation pillars (synthetic recovery, SE Monte Carlo, Tier 4) | `Rscript analysis/master.R --rerun-pillars` | ~1 hour (Tier 4 needs the BACI cache + GMM archive) |
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
(importer, exporter, HS4-product) cell with its estimated export-supply
parameter γ (defined below — γ is not itself an elasticity) and the σ that
was fixed in for that product. To load it and
read the first rows:

```r
s2b <- readRDS("data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
nrow(s2b)            # {{req(r$stage2b, "n_cells")}}
head(s2b[, c("exporter", "importer", "good", "sigma",
             "gamma", "gamma_se", "gamma_se_status", "tier")], 5)
```

Columns:

| Column | Meaning |
|---|---|
| `importer`, `exporter` | Numeric country codes (BACI/COMTRADE convention). |
| `good` | **HS4 product code, stored as a character string with leading zeros** (e.g. `"0302"`, not `302`). Read it as character; coercing to integer drops the leading zero and silently mismatches chapters 01–09. |
| `sigma` | Import-demand (substitution) elasticity for the product, fixed from Stage 1 and constant within a product. For roughly a quarter of country-pairs this is a global-median fallback rather than a cell-specific estimate, and its upper tail is the cap value (see Known limitations). |
| `gamma` | Export-supply **parameter** for the (importer, exporter, product) cell — the headline estimate. This is γ = ω / (1 + ω), bounded in (0, 1), where ω is the inverse export-supply elasticity; **γ is not itself an elasticity.** The implied export-supply elasticity is (1 - γ) / γ (median ≈ 3.3). Most cells are shrunk toward a good-level prior (see Known limitations). |
| `gamma_se` | Penalized Gauss-Newton standard error for `gamma`. |
| `gamma_se_status` | `"ok"` when the SE is usable; other values flag degenerate cases. |
| `gamma_exposure` | Number of exporters in the estimating set for the cell. |
| `ref_exporter` | Reference exporter used in the supply system. |
| `tier` | Estimator-provenance tier (1–4) recording how the cell was identified. |
| `convergence`, `obj_value` | Optimizer convergence code and objective value. |
| `opt_tariff`, `opt_tariff_all` | Implied optimal tariff derived from (σ, γ): the per-cell value and the all-exporter variant. This equals the inverse export-supply elasticity ω = γ / (1 - γ) (Soderbery's optimal-tariff result). Downstream of the estimates — treat as derived, not primary — and biased downward for inelastic-supply products (see Known limitations). |

A reader reproducing the headline numbers should find σ median ≈ {{format_num(req(r$stage2b, "sigma_median"))}} on
the canonical {{format_int(req(r$stage1, "n_products"))}}-product universe. `analysis/master.R` prints this as
it runs.

## Repository structure

```
trade-elasticities/
├── R/                 # estimation library (HLIML, Stage 2 solvers, SEs, CLI)
├── scripts/           # entry points: run_estimation.R, download_outputs.R, build_readme.R
├── analysis/          # master.R + 7 numbered pillar scripts (figures/tables)
├── validation/        # synthetic-recovery, SE Monte Carlo, Tier 4 harnesses
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

- **σ upward bias from the Feenstra homogeneity assumption.** The Stage 1
  σ estimates inherit the known small-sample upward bias of the LIML-class
  estimator; synthetic recovery (Pillar 2) shows the estimator recovers
  true σ in {{format_prop_pct(req(r$pillar2$tier1a_summary, "min_success_rate"))}}–{{format_prop_pct(req(r$pillar2$tier1a_summary, "max_success_rate"))}} of cells across the σ × ω grid
  (median {{format_prop_pct(req(r$pillar2$tier1a_summary, "median_success_rate"))}}), with recovery declining as sample size grows — a
  selection-bias signature where harder cells converge only with more data.
- **Estimator-provenance composition.** On the full universe, {{format_pct(req(r$stage1$provenance_rates$interior_full_universe, "numerator"), req(r$stage1$provenance_rates$interior_full_universe, "denominator"))}} of
  (importer, HS4) cells are identified at the HLIML interior; the rest fall
  to the Step 2 fallback, of which {{format_pct(req(r$stage1$routing_summary, "clamped_total"), req(r$stage1, "n_cells"))}} of the full universe ({{format_int(req(r$stage1$routing_summary, "clamped_total"))}} cells)
  are clamped at the σ/ω caps and report the cap, not an estimate. {{format_pct(req(r$stage1, "sy_fails"), req(r$stage1, "sy_evaluated"))}} of cells fail the
  Stock-Yogo weak-instrument threshold. Conditional on `status == "ok"`
  the interior rate rises to {{format_pct(req(r$stage1$provenance_rates$interior_conditional_on_ok, "numerator"), req(r$stage1$provenance_rates$interior_conditional_on_ok, "denominator"))}}; both framings appear in the methodology
  write-up. Headline σ medians are reported on the canonical {{format_int(req(r$stage1, "n_products"))}} HS4
  universe.
- **Period extension relative to Soderbery (2018).** This pipeline
  estimates over a longer window than Soderbery's original sample, which
  contributes to estimate differences independently of the estimator
  change from Feenstra GMM to HLIML.
- **Supply-side flooring, and shrinkage that masks it.** A large share of
  Stage 1 cells produce an inadmissible supply estimate — the implied export
  supply is non-positive (the Feenstra-infeasible region) or driven to the
  boundary — and these are clamped to the admissibility floor rather than
  reported as failures. Stage 2 shrinkage toward good-level priors then
  compresses the floored mass in the published γ, so the headline γ looks
  better-behaved than the underlying supply identification. Both γ and the
  derived `opt_tariff` are biased toward elastic supply and low tariffs
  precisely for inelastic-supply (high-tariff) products. See the methodology
  write-ups in `docs/methodology/`.
- **Standard errors are conditional on σ.** `gamma_se` is computed with σ
  held fixed at its Stage 1 value (a global-median fallback wherever Stage 1
  did not identify σ); it does not propagate Stage 1 σ uncertainty. A large
  share of rows carry no usable cell-specific SE — flagged degenerate, or
  assigned outright from the regional prior (Tier 3) — and where an SE exists
  it is frequently as large as the estimate itself. Treat `gamma_se` as a
  conditional, lower-bound measure of uncertainty.
- **σ is sensitive to the estimator, not only the sample.** On the Tier 4
  comparison against the legacy Feenstra-GMM baseline, the HLIML σ and the
  GMM σ agree poorly in both level and cross-cell rank ordering. Comparisons
  of these σ to GMM- or Broda-Weinstein-style estimates elsewhere should
  account for the estimator difference, not just the sample and period.
- **BACI vs. the COMTRADE data Soderbery (2018) used.** This pipeline uses
  CEPII BACI — mirror-reconciled, FOB-valued, and carrying a substantial
  share of CEPII-imputed quantities — rather than the importer-reported
  COMTRADE of the original. HS4 unit values are weight-based composites
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
