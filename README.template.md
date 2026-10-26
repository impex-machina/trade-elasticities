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
- **Stage 2a** — Regional γ with fixed σ and light shrinkage (λ = 0.05) toward
  good-level priors built from the Stage-1 ω.
- **Stage 2b** — Country-level γ with fixed σ, a log-ridge pull toward
  good-level priors built from the Stage 2a estimates, and sandwich standard
  errors.

Outputs cover {{format_int(req(r$stage1, "n_products"))}} HS4 products across {{req(r$stage2b, "n_importers")}} importers and {{req(r$stage2b, "n_exporters")}} exporters,
producing {{format_int(req(r$stage2b, "n_cells"))}} (importer, exporter, HS4) cell-level γ estimates with
standard errors. Stage 1 attempts σ estimation on {{format_int(req(r$stage1, "n_cells"))}} (importer, HS4)
cells across {{req(r$stage1, "n_importers")}} importers, returning an estimate for
{{format_int(req(r$stage1$status_breakdown, "ok"))}} of them{{asymmetry_phrase(req(r$stage2b, "n_importers_asymmetry_vs_stage1"))}}.{{known_truth_overview(KT, KTS)}}

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
nrow(s2b)            # {{req(r$stage2b, "n_cells") + req(r$stage2b, "n_trim_flagged")}}: published rows + rows the tail trim flagged
s2b <- s2b[is.na(s2b$trim_reason), ]   # keep the published rows (`trim_reason` below)
nrow(s2b)            # {{req(r$stage2b, "n_cells")}}
head(s2b[, c("exporter", "importer", "good", "sigma",
             "gamma", "gamma_se", "gamma_se_status", "tier")], 5)
```

Columns:

| Column | Meaning |
|---|---|
| `importer`, `exporter` | Numeric country codes (BACI/COMTRADE convention). |
| `good` | **HS4 product code, stored as a character string with leading zeros** (e.g. `"0302"`, not `302`). Read it as character; coercing to integer drops the leading zero and silently mismatches chapters 01–09. |
| `sigma` | Import-demand (substitution) elasticity for the (importer, product) cell, fixed from Stage 1 and constant within an `importer × good` cell (the same product carries a different σ for each importer). For {{format_pct(req(r$stage2b$sigma_provenance, "n_fallback"), req(r$stage2b$sigma_provenance, "denominator"))}} of rows this is a global-median fallback (σ ≈ {{format_num(req(r$stage2b$sigma_provenance, "fallback_value"))}}) rather than a cell-specific estimate: the cell has no Stage-1 estimate, or (since v0.9.0) its Stage-1 σ was an edge of the (σ, ω) admissibility box (σ cap 50), or (since v0.10.0) its Stage-1 σ is within one standard error of the pole, σ − 1 < SE — each treated as no estimate (the pole rule is measured in `docs/methodology/stage2_country.md`, "The σ-pole rule, measured"); {{format_pct(req(r$stage2b$sigma_provenance, "n_cap"), req(r$stage2b$sigma_provenance, "denominator"))}} of rows sit at the cap itself (see Known limitations).{{fallback_hierarchy_clause(HIER)}} |
| `gamma` | **Inverse export-supply elasticity** for the (importer, exporter, product) cell — the headline estimate, Soderbery's γ. Lower-bounded near 0 by the optimizer and **unbounded above** (extreme values are handled by the 0.5%-per-tail γ trim; the trimmed tails are overwhelmingly σ-pole cells — on the 2% subsample 88% of them sit in cells with Stage-1 σ < 2 against 37% of published rows, and 65% within one SE of σ = 1, where Eq. (10)'s 1/(σ−1) coefficients send γ to either end — and `sigma_robust` is already FALSE on 90% of them, so a consumer filtering on `sigma_robust` is not relying on the trim (`docs/methodology/stage2_country.md`, "The pre-trim γ blow-up, measured"); measured on the same subsample, estimating such cells at the fallback σ instead — a σ within one SE of the pole treated as no estimate — raises the split-half reproducibility of the within-cell γ from 0.333 to 0.365 and ships as v0.10.0's default (ibid., "The σ-pole rule, measured"); the Stage-2a plateau replacement was retired in v0.9.0; see Known limitations). γ is the *inverse* of an elasticity: the implied export-supply elasticity is 1 / γ (median ≈ {{format_num(req(r$stage2b, "elast_median"))}}). Small γ means near-perfectly-elastic supply; large γ means strong importer market power. Most rows are shrunk toward a good-level prior — median `gamma_shrink_wt` {{format_num(req(SHRINK$data$q1$shrink_wt, "p50"))}}, trade-weighted data share {{format_num(req(SHRINK$data$q1, "implied_data_share_trade_weighted"))}}{{stale_note(SHRINK)}}; see Known limitations. Since v0.7.4 the log-ridge applies to every coordinate, so no directly estimated row sits at the optimizer floor (v0.7.3 had 16.6% there). |
| `gamma_se` | Sampling standard error of the shrinkage estimator for `gamma` (sandwich form `s² A⁻¹ J'WJ A⁻¹`, `A = J'WJ + λ/γ²`; v0.7.4). Read it together with `gamma_shrink_wt`: near 1, the estimate is mostly the good-level prior and a small `gamma_se` reflects that stability, not information about γ. |
| `gamma_se_status` | `"ok"` when the SE is usable. Otherwise `tier3_prior` (the row is the good-level prior; no SE), `non_converged` (the cell's optimizer did not converge; no SE), `boundary` (γ < 0.01) or `plateau` (γ > 5) — no SE is computed at either extreme —, or `insufficient_df`, `singular`, `negative_diag` or `not_computed` (the variance could not be formed). |
| `gamma_se_total` | Standard error for `gamma` with Stage-1 σ uncertainty propagated in by the delta method: `sqrt(gamma_se² + (∂γ/∂σ · sigma_se)²)`. Populated only where `sigma_robust` is `TRUE`; `NA` otherwise (all Tier-3 cells, and any cell where σ-uncertainty could not be propagated stably). Where present, this is the wider, σ-aware SE; where `NA`, `gamma_se` (conditional on σ) is the only SE available. |
| `sigma_robust` | Cell-level (`importer × good`) flag: `TRUE` when γ's SE is robust to Stage-1 σ uncertainty — σ̂ is unclamped, has a finite SE, sits clear of the σ = 1 identification pole, and the propagated term inflates no γ SE in the cell beyond the screen threshold. `FALSE` when any of those fail; `NA` for Tier-3 imputed cells with no per-cell σ. `TRUE` on {{format_pct(req(r$stage2b$sigma_robust, "robust"), req(r$stage2b$sigma_robust, "total"))}} of rows ({{format_pct(req(r$stage2b$sigma_robust, "robust"), req(r$stage2b$sigma_robust, "n_estimated"))}} of the rows outside Tier 3), `FALSE` on {{format_pct(req(r$stage2b$sigma_robust, "not_robust"), req(r$stage2b$sigma_robust, "total"))}}, `NA` on {{format_pct(req(r$stage2b$sigma_robust, "tier3_na"), req(r$stage2b$sigma_robust, "total"))}}. Filter on this to keep only cells whose γ SE is stable once σ is treated as estimated rather than known (see Known limitations). |
| `sigma_se` | Stage-1 standard error of `sigma` for the (importer, product) cell, carried in for the propagation. `NA` where Stage 1 clamped σ or ω (the cap is reported without a usable SE), returned none, or where `sigma` is the fallback — including the cells whose Stage-1 σ was a box edge (since v0.9.1; through v0.9.0 the ω-edge corner cells among them carried the SE of the discarded estimate beside the fallback σ). Constant within an `importer × good` cell. |
| `dgamma_dsigma` | Local sensitivity ∂γ/∂σ for the cell, from the implicit-function derivative of the γ first-order condition; the input to `gamma_se_total`. Large magnitudes mark cells where γ moves sharply with σ, typically those near the σ = 1 pole. |
| `gamma_exposure` | Number of exporters in the estimating set for the cell. |
| `ref_exporter` | Reference exporter used in the supply system. |
| `tier` | Estimator-provenance tier of the row's exporter: `0` the cell's reference exporter, `1` dense (import + export moments; at least 3 differenced years shared with the reference exporter in this market and at least 2 other destinations for the good), `2` moderate (import moments only, shrunk; at least 3 such years), `3` sparse (fewer; assigned the good-level prior; `convergence` = -1). In a cell where every non-reference exporter is Tier 3 the reference row is imputed too and also carries `convergence` = -1. |
| `convergence`, `obj_value` | Optimizer convergence code and objective value. |
| `opt_tariff`, `opt_tariff_all` | Implied optimal tariff derived from (σ, γ): Soderbery's heterogeneous-exporter optimal-tariff statistic, a trade-weighted aggregate of γ across the cell's exporters (weights ∝ trade / (1 + γσ), trade being the pair's mean annual customs value over its years in the estimation panel, so a sporadic exporter weighs as much as a persistent one with the same annual value), **constant within an (importer, product) cell**. `opt_tariff` aggregates directly estimated exporters (tiers 0-2) only; `opt_tariff_all` includes Tier-3 imputations. Since v0.8.3 both are computed over the rows the table publishes (through v0.8.2 they were computed before the 0.5%-per-tail trim, so 12% of Stage-2b cells carried a value that included trimmed rows and 1,571 cells stated a tariff above every γ they publish). Downstream of the estimates — treat as derived, not primary — and collapsing toward zero where supply identification floors ω (see Known limitations). |
| `opt_tariff_total` | Since v0.11.3. The same statistic with each exporter weighted by `total_trade` instead of its mean annual value, so an exporter that traded heavily for a few years weighs less than one that traded steadily for decades -- the average import share over the period, with the years an exporter is absent counted as zero.{{tariff_weight_note(TW)}} The shift has a direction: in v0.11.3 the median cell tariff is 0.772 under total weights against 0.718 under mean annual weights, so long-standing exporters tend to supply less elastically than brief ones. Constant within a cell, over the same directly estimated rows as `opt_tariff`, and `NA` where it is. |
| `avg_trade`, `total_trade` | The pair's mean and total customs value over its observations in the Stage-2 estimation panel (the weights of `opt_tariff` and `opt_tariff_total`); `total_trade` since v0.11.3. That panel is the differenced one: a pair's observation is a year whose previous calendar year it also traded, so the first year of each consecutive run is not counted, and the years the \|Δ ln p\| ≥ 2 unit-value trim removed are not either -- a pair that trades every year of 1995–2024 contributes 29 values, not 30, and `total_trade` is not the pair's total trade over the period. Their ratio is the pair's number of panel observations. |
| `gamma_v_resid` | Since v0.9.1. Change in the row's γ between the last two passes of the exporter-specific γ_V iteration, \|ln γ − ln γ_prev\|; the per-row form of the pass-step census in `docs/methodology/stage2_country.md`. Filled on rows that are directly estimated, converged and published in both passes; `NA` on Tier-3 rows (their γ is the prior), on non-converged rows and where the previous pass has no such row. The iteration is a fixed-point solve whose median contracts and whose tail does not settle in three passes (p99 ≈ 0.4 at v0.9.0): a small value says the row is at the fixed point, a large one says it is not — treat the latter as unsettled, not as wrong. |
| `trim_reason` | Since v0.9.1. `NA` on every row the Stage-2 tail trim kept. Since v0.10.0 the trimmed rows stay in the table with their reason here (`sigma_lo`, `gamma_lo`, `gamma_hi`, `na_sigma_or_gamma`; `--stage2-trim-action flag`, the default) and every statistic in this README, the summary and the γ_V pass lookup read the published rows only — **filter `is.na(trim_reason)` before use**; through v0.9.1 (`drop`) the trimmed rows were not in the table and the column was `NA` throughout, their record being `<prefix>_stage2_trimmed.csv`/`.rds` beside the run. |
| `sigma_source` | Since v0.10.1. Where the row's `sigma` comes from: `estimated` (the cell's own Stage-1 σ), `fallback_no_estimate` (no converged Stage-1 σ > 1 for the cell), `fallback_sigma_edge` (Stage-1 σ on an edge of the (σ, ω) box, since v0.9.0) or `fallback_sigma_pole` (Stage-1 σ within one standard error of 1, since v0.10.0). Every `fallback_*` row carries the same fallback σ (the median of the estimated cells' σ), so `sigma` alone cannot distinguish a fallback from an estimate that happens to equal it; filter `sigma_source == "estimated"` for analyses that need a cell-specific σ. Constant within an `importer × good` cell. |

A reader reproducing the headline numbers should find σ median ≈ {{format_num(req(r$stage2b, "sigma_median"))}} on
the canonical {{format_int(req(r$stage1, "n_products"))}}-product universe{{headline_sigma_note(r$stage2b)}}. `analysis/master.R` prints it
as it runs (`analysis/01_pillar1_empirical_overview.R`).{{product_table_section(PS, req(r$stage2b$sigma_provenance, "fallback_value"), PW)}}

### Parquet copies (since v0.11.2)

Every main table also ships as Parquet beside its `.rds` file -- `stage2b/…_fixed_sigma.parquet`, `stage1/…_feenstra_sigma.parquet`, `stage2a/…_regional_hs4_fixed_sigma.parquet` and `product/…_product_summary.parquet` -- written from the published files by `scripts/export_parquet.R` and checked value for value against them. `good` is a string there (HS4 with its leading zero). In Python:

```python
import pandas as pd
base = "hf://datasets/impex-machina/trade-elasticities@{{release_tag}}/"
products = pd.read_parquet(base + "product/baci_hs92_v202601_elast_hs4_product_summary.parquet")
cars = pd.read_parquet(base + "stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.parquet",
                       filters=[("good", "==", "8703")])
```

The same paths work in DuckDB (`SELECT * FROM 'hf://datasets/impex-machina/trade-elasticities@{{release_tag}}/…'`), Polars and R's arrow or nanoparquet packages. The `.rds` files stay the canonical copies; the Hugging Face dataset viewer opens on the product-level table.

## Repository structure

```
trade-elasticities/
├── R/                 # estimation library (HLIML, Stage 2 solvers, SEs, CLI)
├── scripts/           # entry points: run_estimation.R, download_outputs.R, build_readme.R, refresh_table_censuses.R
├── analysis/          # master.R + 7 numbered pillar scripts (figures/tables)
├── validation/        # synthetic-recovery and SE Monte Carlo harnesses
├── tests/             # testthat suite
├── data/
│   ├── raw/           # BACI input (gitignored; not redistributed)
│   ├── derived/       # published outputs (downloaded from HF; gitignored)
│   └── manifest.csv   # the {{manifest_n_files}} published data files, with SHA-256 checksums
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
  against the paper's reduced-form supply and demand curves, Eqs. (5)–(6)
  and (8)–(9): {{dgp_harness_line(r$stage2_dgp)}}

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
`scripts/download_outputs.R` fetches and verifies them. Each release stays on
the hub at its data revision (the dataset card lists them) under a tag of the
release's name; to fetch an earlier one, pass that release's manifest and tag:
`git show v0.10.2:data/manifest.csv > m.csv`, then
`Rscript scripts/download_outputs.R --manifest m.csv --revision v0.10.2 --force`
(the script's header has the Windows variant). BACI raw *inputs*
are not redistributed (see [Getting BACI](#replication-setup)).

## Known limitations

Stated forthrightly, in short form. The long form — every measurement that bears on each point and the release in which each rule changed — is generated from the same `results/*.json` into [`docs/known_limitations_record.md`](docs/known_limitations_record.md), so its numbers are as current as these; the release-by-release history is the dataset card's changelog ([`docs/hf_dataset_card.md`](docs/hf_dataset_card.md)).

- **What the published numbers support.**{{known_truth_support_sentence(KT, KTS)}} Cell-level σ is weakly reproducible across periods, and one global σ predicts a cell's estimate in the other period better than the cell's own. Read the product-level table and the structural ratios as the result; read the bilateral table's exporter-level γ as a shrinkage-smoothed presentation, not as exporter-level supply information (record §1 and §4, with the known-truth bullet that follows §4).
- **σ at Stage 1: small-sample bias, weak instruments, the σ = 1 pole.** On the Pillar-2 grid{{pillar2_cap_note(r$pillar2, r$stage1)}} the estimator returns an estimate in {{format_prop_pct(req(r$pillar2$tier1a_summary, "min_success_rate"))}}–{{format_prop_pct(req(r$pillar2$tier1a_summary, "max_success_rate"))}} of replications (a yield, not a recovery rate) and, conditional on success, the median σ bias runs from {{format_prop_pct(min(sapply(r$pillar2$tier1a, function(x) x$sigma_bias)))}} to {{format_prop_pct(max(sapply(r$pillar2$tier1a, function(x) x$sigma_bias)))}}, so no upward bias of the Feenstra–Broda–Weinstein kind should be assumed. {{format_pct(req(r$stage1, "sy_fails"), req(r$stage1, "sy_evaluated"))}} of cells fail the Stock–Yogo 10% maximal-size screen and {{format_pct(req(r$stage1, "sy_pass_gs25"), req(r$stage1, "sy_gs25_evaluated"))}} pass Grant–Soderbery's 25% rule; per-cell flags ship in the Stage-1 table. A cell whose σ is a box edge, or within one standard error of the pole, takes the global fallback σ ({{format_num(req(r$stage2b$sigma_provenance, "fallback_value"))}}) like a cell with no estimate: {{format_pct(req(r$stage2b$sigma_provenance, "n_fallback"), req(r$stage2b$sigma_provenance, "denominator"))}} of Stage-2b rows carry it (`sigma_source`). The Step-2 route overstates σ at known truth; it stays because the alternative predicts the other period's σ worse (record §1, §6 and the Step-2 route bullet after §4).
- **Estimator-provenance composition.** {{provenance_lead(r$stage1)}}{{boundary_phrase(r$stage1$routing_summary, req(r$stage1, "n_cells"), r$stage1$edge_se)}} Conditional on `status == "ok"` the interior rate is {{format_pct(req(r$stage1$provenance_rates$interior_conditional_on_ok, "numerator"), req(r$stage1$provenance_rates$interior_conditional_on_ok, "denominator"))}}. Headline σ medians are reported on the canonical {{format_int(req(r$stage1, "n_products"))}}-product universe (record §6).
- **Supply-side boundaries: two ends of the ω axis.** A point whose ρ exceeds (σ−1)/σ has no positive ω (it is the continuation past ω = +∞); since v0.7.0 such points are inadmissible and take the constrained boundary optimum, mostly at the ω cap. The ω floor holds {{format_pct(req(r$stage1$omega_floor, "n_floor"), req(r$stage1$omega_floor, "denominator"))}} of cells ({{format_int(req(r$stage1$omega_floor, "n_floor_boundary_edge"))}} floor-edge optima, `adjust` 6, `omega_floored`); {{format_int(req(r$stage1$negative_omega, "n_sigma_without_omega"))}} cells report a Step-2 σ with ω undetermined and {{format_int(req(r$stage1$negative_omega, "n_boundary_corner"))}} floor-edge optima were reached from a beyond-∞ point (`boundary_corner`; filter them for supply-side uses). Where ω is floored, γ and `opt_tariff` collapse toward zero — an identification artifact, not an interior estimate (record §8).
- **Standard errors are conditional on σ, with a robustness screen.** `gamma_se` holds σ at its Stage-1 (or fallback) value. {{format_pct(req(r$stage2b$se_status, "ok"), req(r$stage2b$se_status, "total"))}} of rows carry a clean cell-specific SE, {{format_pct(req(r$stage2b$se_status, "tier3_prior"), req(r$stage2b$se_status, "total"))}} are the good-level prior with none (Tier 3) and {{format_pct(req(r$stage2b$se_status, "other"), req(r$stage2b$se_status, "total"))}} are extremes or non-converged fits. `gamma_se_total` propagates the Stage-1 σ uncertainty by the delta method and `sigma_robust` is `TRUE` on {{format_pct(req(r$stage2b$sigma_robust, "robust"), req(r$stage2b$sigma_robust, "total"))}} of rows ({{format_pct(req(r$stage2b$sigma_robust, "robust"), req(r$stage2b$sigma_robust, "n_estimated"))}} of the rows outside Tier 3): where it is `FALSE` or `NA`, read `gamma_se` as a conditional lower bound, and in either case the SE is often as large as the estimate. Step-2 `sigma_se` is a composition-conditional lower bound; the exporter-cluster bootstrap is the check (record §9).
- **γ within a cell is a λ-dependent presentation.** The log-ridge (λ = 0.1) keeps the median row at a data share of {{format_num(req(SHRINK$data$q1$implied_data_share, "p50"))}} (trade-weighted {{format_num(req(SHRINK$data$q1, "implied_data_share_trade_weighted"))}}){{stale_note(SHRINK)}}; the within-cell spread of γ scales with λ while its ordering does not, and at known truth that ordering does not follow the true one. Within-cell γ reproduces across odd and even years of a period and drifts across periods; a recent-window estimate was measured and not published (record §3 and §4).
- **Specification choices, each measured and kept.** Eq. (11)'s export side on log export values rather than the printed shares (v0.11.0); the Broda–Weinstein row weights as implemented rather than fn. 14 as printed; the reference-exporter rule; the log prior at λ = 0.1; the σ-pole rule; the Step-2 route over the boundary search; a precision-scaled ridge tested and not adopted. Each has an A/B on record with the rule fixed before the numbers (record §2, §3, §4, §5 and the ridge bullet after §4).
- **Data and sample.** BACI reconciles the importer's and exporter's reports into one FOB flow, so both sets of moments share one unit value and identification rests on the difference between import and export shares alone; a share of BACI quantities is imputed and unflagged; HS4 unit values are weight-based composites of the constituent HS6 lines and move with product mix; the panel is longer than Soderbery's; and on the Tier-4 comparison the HLIML σ agrees poorly with the legacy Feenstra-GMM σ in level and rank, so comparisons with GMM- or Broda–Weinstein-style estimates must account for the estimator, not only the sample and period (record §7, §10 and §11).

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
