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

Outputs cover 1,240 HS4 products across 233 importers and 233 exporters,
producing 6,801,742 (importer, exporter, HS4) cell-level γ estimates with
standard errors. Stage 1 attempts σ estimation on 280,649 (importer, HS4)
cells across 234 importers, returning an estimate for
182,912 of them (one importer present at Stage 1 has no country-pair γ at Stage 2b after the minimum-destinations filter).

Checked against known truth (`validation/known_truth_stage2.R`): on synthetic panels built to the estimator's own assumptions, the published γ and `opt_tariff` track true differences between products (correlation 0.88 and 0.91 for the products' median γ and 0.89 for their `opt_tariff`, at baseline and triple shock volatility), track differences between importers within a product only weakly (0.16 and 0.23, keeping 2% and 21% of the true spread), and do not recover differences between exporters within a cell (0.05 and 0.09). See Known limitations.

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
nrow(s2b)            # 6892008: published rows + rows the tail trim flagged
s2b <- s2b[is.na(s2b$trim_reason), ]   # keep the published rows (`trim_reason` below)
nrow(s2b)            # 6801742
head(s2b[, c("exporter", "importer", "good", "sigma",
             "gamma", "gamma_se", "gamma_se_status", "tier")], 5)
```

Columns:

| Column | Meaning |
|---|---|
| `importer`, `exporter` | Numeric country codes (BACI/COMTRADE convention). |
| `good` | **HS4 product code, stored as a character string with leading zeros** (e.g. `"0302"`, not `302`). Read it as character; coercing to integer drops the leading zero and silently mismatches chapters 01–09. |
| `sigma` | Import-demand (substitution) elasticity for the (importer, product) cell, fixed from Stage 1 and constant within an `importer × good` cell (the same product carries a different σ for each importer). For 41.0% of rows this is a global-median fallback (σ ≈ 2.473) rather than a cell-specific estimate: the cell has no Stage-1 estimate, or (since v0.9.0) its Stage-1 σ was an edge of the (σ, ω) admissibility box (σ cap 50), or (since v0.10.0) its Stage-1 σ is within one standard error of the pole, σ − 1 < SE — each treated as no estimate (the pole rule is measured in `docs/methodology/stage2_country.md`, "The σ-pole rule, measured"); 0.0% of rows sit at the cap itself (see Known limitations). One global value is kept because the product does not predict σ: across the cells with an estimate the good explains 5.7% of the variance of ln(σ − 1), and a fallback built from good and region × good medians predicts held-out estimates no better than the global median (median error 0.699 against 0.693; `docs/results/sigma_fallback_hierarchy_census_v0110.md`). |
| `gamma` | **Inverse export-supply elasticity** for the (importer, exporter, product) cell — the headline estimate, Soderbery's γ. Lower-bounded near 0 by the optimizer and **unbounded above** (extreme values are handled by the 0.5%-per-tail γ trim; the trimmed tails are overwhelmingly σ-pole cells — on the 2% subsample 88% of them sit in cells with Stage-1 σ < 2 against 37% of published rows, and 65% within one SE of σ = 1, where Eq. (10)'s 1/(σ−1) coefficients send γ to either end — and `sigma_robust` is already FALSE on 90% of them, so a consumer filtering on `sigma_robust` is not relying on the trim (`docs/methodology/stage2_country.md`, "The pre-trim γ blow-up, measured"); measured on the same subsample, estimating such cells at the fallback σ instead — a σ within one SE of the pole treated as no estimate — raises the split-half reproducibility of the within-cell γ from 0.333 to 0.365 and ships as v0.10.0's default (ibid., "The σ-pole rule, measured"); the Stage-2a plateau replacement was retired in v0.9.0; see Known limitations). γ is the *inverse* of an elasticity: the implied export-supply elasticity is 1 / γ (median ≈ 1.243). Small γ means near-perfectly-elastic supply; large γ means strong importer market power. Most rows are shrunk toward a good-level prior — median `gamma_shrink_wt` 0.924, trade-weighted data share 0.236; see Known limitations. Since v0.7.4 the log-ridge applies to every coordinate, so no directly estimated row sits at the optimizer floor (v0.7.3 had 16.6% there). |
| `gamma_se` | Sampling standard error of the shrinkage estimator for `gamma` (sandwich form `s² A⁻¹ J'WJ A⁻¹`, `A = J'WJ + λ/γ²`; v0.7.4). Read it together with `gamma_shrink_wt`: near 1, the estimate is mostly the good-level prior and a small `gamma_se` reflects that stability, not information about γ. |
| `gamma_se_status` | `"ok"` when the SE is usable. Otherwise `tier3_prior` (the row is the good-level prior; no SE), `non_converged` (the cell's optimizer did not converge; no SE), `boundary` (γ < 0.01) or `plateau` (γ > 5) — no SE is computed at either extreme —, or `insufficient_df`, `singular`, `negative_diag` or `not_computed` (the variance could not be formed). |
| `gamma_se_total` | Standard error for `gamma` with Stage-1 σ uncertainty propagated in by the delta method: `sqrt(gamma_se² + (∂γ/∂σ · sigma_se)²)`. Populated only where `sigma_robust` is `TRUE`; `NA` otherwise (all Tier-3 cells, and any cell where σ-uncertainty could not be propagated stably). Where present, this is the wider, σ-aware SE; where `NA`, `gamma_se` (conditional on σ) is the only SE available. |
| `sigma_robust` | Cell-level (`importer × good`) flag: `TRUE` when γ's SE is robust to Stage-1 σ uncertainty — σ̂ is unclamped, has a finite SE, sits clear of the σ = 1 identification pole, and the propagated term inflates no γ SE in the cell beyond the screen threshold. `FALSE` when any of those fail; `NA` for Tier-3 imputed cells with no per-cell σ. `TRUE` on 24.2% of rows (33.1% of the rows outside Tier 3), `FALSE` on 49.0%, `NA` on 26.8%. Filter on this to keep only cells whose γ SE is stable once σ is treated as estimated rather than known (see Known limitations). |
| `sigma_se` | Stage-1 standard error of `sigma` for the (importer, product) cell, carried in for the propagation. `NA` where Stage 1 clamped σ or ω (the cap is reported without a usable SE), returned none, or where `sigma` is the fallback — including the cells whose Stage-1 σ was a box edge (since v0.9.1; through v0.9.0 the ω-edge corner cells among them carried the SE of the discarded estimate beside the fallback σ). Constant within an `importer × good` cell. |
| `dgamma_dsigma` | Local sensitivity ∂γ/∂σ for the cell, from the implicit-function derivative of the γ first-order condition; the input to `gamma_se_total`. Large magnitudes mark cells where γ moves sharply with σ, typically those near the σ = 1 pole. |
| `gamma_exposure` | Number of exporters in the estimating set for the cell. |
| `ref_exporter` | Reference exporter used in the supply system. |
| `tier` | Estimator-provenance tier of the row's exporter: `0` the cell's reference exporter, `1` dense (import + export moments; at least 3 differenced years shared with the reference exporter in this market and at least 2 other destinations for the good), `2` moderate (import moments only, shrunk; at least 3 such years), `3` sparse (fewer; assigned the good-level prior; `convergence` = -1). In a cell where every non-reference exporter is Tier 3 the reference row is imputed too and also carries `convergence` = -1. |
| `convergence`, `obj_value` | Optimizer convergence code and objective value. |
| `opt_tariff`, `opt_tariff_all` | Implied optimal tariff derived from (σ, γ): Soderbery's heterogeneous-exporter optimal-tariff statistic, a trade-weighted aggregate of γ across the cell's exporters (weights ∝ trade / (1 + γσ), trade being the pair's mean annual customs value over its years in the estimation panel, so a sporadic exporter weighs as much as a persistent one with the same annual value), **constant within an (importer, product) cell**. `opt_tariff` aggregates directly estimated exporters (tiers 0-2) only; `opt_tariff_all` includes Tier-3 imputations. Since v0.8.3 both are computed over the rows the table publishes (through v0.8.2 they were computed before the 0.5%-per-tail trim, so 12% of Stage-2b cells carried a value that included trimmed rows and 1,571 cells stated a tariff above every γ they publish). Downstream of the estimates — treat as derived, not primary — and collapsing toward zero where supply identification floors ω (see Known limitations). |
| `gamma_v_resid` | Since v0.9.1. Change in the row's γ between the last two passes of the exporter-specific γ_V iteration, \|ln γ − ln γ_prev\|; the per-row form of the pass-step census in `docs/methodology/stage2_country.md`. Filled on rows that are directly estimated, converged and published in both passes; `NA` on Tier-3 rows (their γ is the prior), on non-converged rows and where the previous pass has no such row. The iteration is a fixed-point solve whose median contracts and whose tail does not settle in three passes (p99 ≈ 0.4 at v0.9.0): a small value says the row is at the fixed point, a large one says it is not — treat the latter as unsettled, not as wrong. |
| `trim_reason` | Since v0.9.1. `NA` on every row the Stage-2 tail trim kept. Since v0.10.0 the trimmed rows stay in the table with their reason here (`sigma_lo`, `gamma_lo`, `gamma_hi`, `na_sigma_or_gamma`; `--stage2-trim-action flag`, the default) and every statistic in this README, the summary and the γ_V pass lookup read the published rows only — **filter `is.na(trim_reason)` before use**; through v0.9.1 (`drop`) the trimmed rows were not in the table and the column was `NA` throughout, their record being `<prefix>_stage2_trimmed.csv`/`.rds` beside the run. |
| `sigma_source` | Since v0.10.1. Where the row's `sigma` comes from: `estimated` (the cell's own Stage-1 σ), `fallback_no_estimate` (no converged Stage-1 σ > 1 for the cell), `fallback_sigma_edge` (Stage-1 σ on an edge of the (σ, ω) box, since v0.9.0) or `fallback_sigma_pole` (Stage-1 σ within one standard error of 1, since v0.10.0). Every `fallback_*` row carries the same fallback σ (the median of the estimated cells' σ), so `sigma` alone cannot distinguish a fallback from an estimate that happens to equal it; filter `sigma_source == "estimated"` for analyses that need a cell-specific σ. Constant within an `importer × good` cell. |

A reader reproducing the headline numbers should find σ median ≈ 2.473 on
the canonical 1,240-product universe — the fallback σ itself: 41.0% of rows carry it, so the row-level median falls on that mass. The fallback is the median of the cell-specific estimates (one per importer × HS4 cell in the clean set); filter `sigma_source == "estimated"` for the estimates' own distribution. `analysis/master.R` prints it
as it runs (`analysis/01_pillar1_empirical_overview.R`).

### The product-level table (since v0.11.1)

`data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv` has one row per HS4 product (1,240), built from the table above by `analysis/product_summary.R`: `gamma_median` (the median γ over directly estimated rows), `opt_tariff_median` (the median over the product's (importer, product) cells), `sigma_median`, `share_cells_own_sigma`, and the counts `n_cells`, `n_rows`, `n_rows_estimated` and `trade` (the sum of `avg_trade`). It is the level the estimates support: at known truth the pipeline recovers differences between products, weakly those between importers within a product, and not those between exporters within a cell (Known limitations). On a 2% product subsample (25 products) the product medians hardly depend on which half of the Stage-2b data is used -- Spearman 0.99 for γ and 0.97 for `opt_tariff` between odd and even years (0.99 and 0.98 between 1995–2009 and 2010–2024) -- but those halves share the full-panel Stage 1 (the odd/even halves also its Stage-2a priors), from which a product's median is mostly built, so they do not show that product differences reproduce in independent data (`docs/results/product_summary_census.md`; a hash check in `docs/results/product_window_census.md`). Estimated independently on 1995–2009 and on 2010–2024 -- each period's own Stage 1, Stage 2a and Stage 2b, on the same 25 products -- product medians correlate at 0.64 for γ and 0.76 for `opt_tariff`; by the rule fixed in patch 0130 that is "reproduces" (`docs/results/product_window_census.md`). Between those periods a product's median γ differs by a median of 25.5% (94.9% at the 90th percentile) and its median `opt_tariff` by 16.0% (56.4%). Part of that is change over time, but it is the scale of uncertainty to read the table's values with: its ranking of products is better supported than its levels. σ is the global value (2.473) for nearly every product. Read `good` as character; the table carries no interval columns, because resampling importers leaves the product prior -- a product's main source of uncertainty -- untouched.

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
│   └── manifest.csv   # the 12 published data files, with SHA-256 checksums
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
  and (8)–(9): **PASS** at rev `1e5d5ac`, 2026-10-13 (import + export sides, Eqs. (10) and (11) with the G1 sign correction; Test F, the export side against the primitives: exact on export values, the form shipped since v0.11.0 (residual at the truth at most 0.4% of the outcome), while the share form of the printed Eq. (8) misses by up to 10.0% when γ_I ≠ γ_V; seed 20260717). Regenerate with `Rscript validation/stage2_structural_dgp.R`.

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

Stated forthrightly:

- **σ small-sample bias and selection under the Stage-1 homogeneity
  assumption.** Synthetic recovery (Pillar 2) shows the estimator *returns
  an estimate* in 80.0%–100.0% of replications across the σ × ω grid
  (median 99.2%) — a yield rate, not a recovery-within-tolerance rate —
  and the yield rises as the
  sample grows from 150 to 3,000 observations. Conditional on
  success, the median σ bias across the grid runs from
  -38.0% to 30.4% (negative at 8 of 12 grid points),
  so comparisons to Feenstra-GMM or Broda–Weinstein estimates should not
  assume the upward bias of that tradition. The nominal 95% interval for σ covers the truth in a median 91.6% of replications across the grid, but below 80% at 2 of 12 points, both at the grid's largest ω (3): 60.6% at σ = 8 (46.6% on interior-HLIML fits) and 73.6% at σ = 5. The grid's smallest σ is 2, so these figures do not describe cells near the σ = 1 pole, where the σ-pole rule acts. Cell-level σ is weakly reproducible across periods: on the 2% subsample, σ estimated on 1995–2009 and on 2010–2024 ranks the 1,282 cells clean in both almost independently (rank ρ 0.05 on ln(σ − 1)); σ − 1 differs by more than a factor of 2 in 62.6% of them, with no shift in level, while only 16.7% of the changes exceed 1.96 combined standard errors inflated 1.5× — the standard errors are as wide as the disagreement. A 15-year panel does not pin down how σ varies across importers within a product, and the full panel only doubles it: read cell-level σ, and the γ and `opt_tariff` built on it, as weakly identified in that dimension (`docs/results/sigma_window_census_v0110.md`). Out of sample the global value does better still (patch 0122): one global σ (each period's fallback) predicts a cell's estimate in the other period with a median absolute error in ln(σ − 1) of 0.87 (1995–2009 → 2010–2024) and 0.83 (the reverse), against 1.00 and 0.98 for the cell's own published σ and 0.95 and 0.94 for its empirical-Bayes posterior — cell-level differences in σ do not carry from one period to the other (`docs/results/sigma_eb_period_census_v0110.md`). Empirical-Bayes shrinkage of σ is not adopted: at known truth it lowered the σ error by 10% or more in 2 of 6 worlds (`docs/results/known_truth_stage2.md`), and on this split it is beaten by the constant it shrinks toward.
- **Since v0.11.0 Eq. (11)'s export side is built on log export values, not on the export shares of the printed Eq. (8).** From Soderbery's Eq. (7), prices on export shares carry (ρ_I − ρ_V)·Δln V_j, V_j the exporter's total sales, which the printed Eq. (8) leaves in the error, where it moves with the Eq. (9) demand residual; his own account of that error (§3.3: the reference difference of the exporter's supply shocks) is what the value form delivers. On log export values the supply curve is exact and the nine-term Eq. (11) holds unchanged (harness Test F). Before the switch the value form moved within-cell γ on the 2% subsample by a median 0.0056 in log points (p99 0.64) and left split-half reliability at 0.360 against 0.368; in the v0.11.0 run, together with the corrected Stage-2a handoff (v0.10.x built Stage 2b's priors partly from Stage-2a rows its tail trim had flagged) and three γ_V passes, directly estimated γ moved by a median 0.007–0.010 in log points (p99 0.84–1.06; `docs/methodology/stage2_country.md`, "The v0.11.0 run"). `--stage2-export-moment share` reproduces v0.10.x; the exporter totals, whose value-only flows patch 0108 measured, no longer enter.
- **Within-cell dispersion of γ is a λ-dependent presentation; the within-cell ranking is not.** Measured on the 2% subsample (2026-10-12; `docs/methodology/stage2_country.md`, "The reference exporter and λ, measured"): across λ = 0.03 / 0.1 / 0.3 the split-half reproducibility of the within-cell-demeaned log γ is flat (r = 0.362 / 0.369 / 0.368) while the within-cell standard deviation scales with λ (0.88 / 0.64 / 0.46). The ordering is stable across λ, but at known truth it does not follow the true ordering (within-cell rank correlation 0.08 at baseline shock volatility and 0.17 at three times it, shipped configuration; next bullet): read neither the ordering nor the spread of exporters' γ's within a cell as exporter-level information. The spread is in addition conditional on the shipped λ = 0.1, which sits in the middle of that plateau. The choice of reference exporter, by contrast, does not matter: three rules give r = 0.367–0.368.
- **γ heterogeneity within a cell reproduces within a period and drifts across periods, and it is not recovered at known truth.** The Stage-2 log-ridge (λ = 0.1) is strong relative to the data curvature of a time-averaged moment row: the median row keeps a data share of 0.076, the trade-weighted share is 0.236, and a cell's largest exporter keeps 0.364 against 0.030 for exporters ranked below tenth. On a 2% product subsample, an exporter's deviation from its cell mean reproduces across odd- and even-year observations of the same period, under the shipped configuration, at r = 0.360 (rank ρ 0.362; ≈ 0.53 at full panel length by Spearman–Brown), but only at r = 0.099 between 1995–2009 and 2010–2024, also under the shipped configuration — reproducible within a period and period-specific. Whether that drift calls for a recent-window estimate was measured as well (patch 0119): on the same subsample the cell's log `opt_tariff` differs between 1995–2009 and 2010–2024 by 1.42 times the variance of its odd/even-year difference, below 1.5, so the full-panel average describes current conditions as well as a 2010–2024 estimate would, and none is published (`docs/results/window_drift_census_v0110.md`). Reproducible is not the same as recovered (patch 0122): on synthetic panels built to the estimator's own assumptions — Soderbery's model with known σ and γ, 30 years, no unit-value measurement error, 3 seeds (`validation/known_truth_stage2.R`) — the shipped pipeline's within-cell deviations correlate with the true ones at r = 0.05 at baseline shock volatility and 0.09 at three times it, and only at 0.21 and 0.18 with the true σ and no shrinkage, while the ridge holds the published γ near the good-level prior (median shrink weight 0.999 and 0.968). The within-cell spread of the published γ is not exporter-level supply information even when every assumption holds (`docs/results/known_truth_stage2.md`). Loosening λ or changing the prior's form adds noise rather than signal, so λ stays at 0.1 with the log prior. Since v0.8.0 the reference exporter's own export-side moment and Soderbery's importer–exporter constant (fn. 14, concentrated out) are included; since v0.8.1 the cell optimizer runs to 5,000 iterations (non-converged cells 9% → ~2%); since v0.8.3 a cell whose L-BFGS-B fit does not converge — far more often a failed line search than the iteration cap — publishes the better of its L-BFGS-B point and the Nelder–Mead restart (through v0.8.2 the restart was published unconditionally, and on a 2% product subsample it was the worse point on 123 of the 138 such cells), and the good-level prior and γ_V are medians over directly estimated Stage-2a rows only (through v0.8.2 they included Stage 2a's own Tier-3 imputations). On the shipped table the L-BFGS-B fit did not converge on 2,370 cells (code 52, a failed line search, on 2,363; code 1, the iteration cap, on 7) and the restart ran; its objective was higher than the discarded point on 1,868 of them (79%), and it had reported convergence on 1,561, rows that v0.8.2 labelled `ok` at a stalled point (`docs/results/stage2_fallback_census_v0110.md`). Since v0.9.0 the Stage-1 σ cap is 50 (10 through v0.8.3, which censored a continuous right tail), the tail trim takes a low-tail σ bound over cells (no high bound: a σ on a box edge is handled by the edge rule, and a large estimated σ is flagged by `sigma_robust`) and the Stage-2a plateau replacement is retired, Eq. (11)'s γ_V is the exporter's own γ at the reference destination from the previous Stage-2b pass (three passes; the residual in the tail is a stated limitation), the export-side Broda–Weinstein T is the pair's panel length, and a Stage-1 cell whose σ is a box edge takes the fallback σ like a cell with no estimate — as does, since v0.10.0, a cell whose σ is within one standard error of the pole (σ − 1 < SE; Eq. (10)'s 1/(σ−1) coefficients make such a cell's γ uninformative, and estimating it at the fallback σ raised the split-half reproducibility of the within-cell γ from 0.333 to 0.365 on the 2% subsample grid, 0.369 with Stage 2a re-estimated under the rule as shipped). At known truth the rule does not make the tariff its σ implies more accurate (patch 0117: Pillar 2's simulator at σ = 1.2, 1.5, 2, 3, 5, 8): the median tariff error is higher with the rule at σ = 1.2, 1.5, 5, 8 and lower at σ = 2, 3, and at σ ≥ 3 the rule drops 21.7%–27.5% of usable fits — cells far from the pole whose standard errors are large. Its measured benefit is the stability above (`docs/results/pole_rule_accuracy.md`). **The γ level rose with v0.10.0** (median 0.644 → 0.806, `opt_tariff` 0.733 → 0.869): about a seventh of it from the rule's own cells, the rest through Stage 2a, whose regional σ's no longer include pole cells; the import moments pin the composite γ/((1+γ)(σ−1)), which is unchanged on cells whose σ moved only through the fallback (0.326 → 0.325), so the shift is the σ–γ trade-off of a less pole-biased σ rather than new information about γ — compare levels across releases with that in mind (`docs/methodology/stage2_country.md`, "v0.10.0, the full run"). Since v0.9.1 its Stage-1 SE and adjust code leave the clean set with it: through v0.9.0 the σ-propagation step still read them, so the ω-edge corner cells among the 13,810 edge cells published the discarded σ = 50 point's `sigma_se` on 81,401 rows and its `dgamma_dsigma` on 80,521, beside the fallback σ; the pole test rejected every one of those rows, so `sigma_robust` and `gamma_se_total` were unaffected (the v0.9.0 statement that `sigma_robust` is FALSE on the edge cells held in fact — by the test's outcome, not by construction). `scripts/apply_sigma_edge_se_rule.R` is the correction, applied to the shipped v0.9.0 table without re-estimation. Details and the grids: `docs/methodology/stage2_country.md` ("v0.8.0", "v0.8.1"), `docs/results/stage2_reliability_*.md`, `docs/results/stage2_lambda_curve_v074rc.md`.
- **What the published γ and `opt_tariff` track at known truth.** On synthetic panels whose ln γ differs by product (s.d. 0.7 between 12 products, 0.35 within; `validation/known_truth_stage2.R --structures good,good_importer`, 3 seeds), the products' median published γ correlates with the true one at 0.88 and 0.91 and their mean ln `opt_tariff` at 0.89 (baseline and triple shock volatility): product differences pass from the Stage-1 ω through the Stage-2a priors into Stage 2b. With an importer effect added (s.d. 0.5), the cell mean ln γ tracks the importer differences within a product at r = 0.16 and 0.23, keeping 2% and 21% of their true spread, and the cell's `opt_tariff` at r = 0.10 and 0.14: the Stage-2b prior is one value per product, so with shrink weights near 1 importer differences survive only where the data outweigh it. Across all cells the `opt_tariff` correlates with the truth at 0.67 and 0.73 and the composite γ/((1+γ)(σ−1)) at 0.55 and 0.64. By reading R4 (fixed in patch 0123) that is "recovered" between products and "partial" within them (`docs/results/known_truth_structured.md`).
- **Stage 1's Step-2 route overstates σ at known truth.** On the known-truth worlds (`validation/known_truth_routing.R`, 18 worlds), cells whose closed form is inadmissible and that Stage 1 routes through the Step-2 cascade carry σ − 1 overstated by a median factor of 1.47 and 1.38 at baseline and triple shock volatility, against 1.08 and 1.06 on the closed form's cells; after the edge and pole rules the published factor is 1.20 (`docs/results/known_truth_routing.md`). In the shipped Stage 1 the Step-2 route carries 45,305 cells (24.8% of the cells with an estimate), 30,657 of them in the set whose median is the fallback σ. By the rule fixed in patch 0127 that is "biased". The alternative, the boundary search, is usable on 23,592 of those cells (patch 0129): at known truth it is less biased (+0.12 against +0.31) but noisier (median error 0.37 against 0.31), and on the real 1995–2009 / 2010–2024 split it predicts the other period's σ worse (median error 1.33 and 1.42 against 1.20 and 1.23). By the rule fixed in patch 0129 that is "keep Step 2"; switching would move the fallback σ only from 2.473 to 2.486 (`docs/results/routing_ab.md`).
- **A ridge that does not scale with price volatility is being tested (patches 0132–0135; not in the published data).** Under `--stage2-ridge-scale cell` each cell's Stage-2b data term is divided by its own noise variance and λ becomes the prior precision 1/τ² of ln γ around the product prior. At known truth it recovers importer differences within a product at r 0.49 / 0.43 (τ² = 0.1) against 0.16 / 0.23 under the shipped ridge, keeping the product-level signal (reading R5: "calibrate on real data"; `docs/results/known_truth_ridge.md`); exporter differences within a cell stay unrecovered. τ² is set by empirical Bayes from two halves of the years (alternate four-year blocks, so that no year's level enters both): at known truth the estimate lands in the useful range in 100% of the six worlds (reading R6: "EB validated"), overstating the true variance by a median 19%. On the 2% product subsample it gives τ² = 0.89; there, importer differences within a product reproduce across the halves at 0.292 against 0.266 under the shipped ridge, and product medians move by a median 4% (adoption reading: "adopt-candidate"; `docs/results/ridge_tau2_check.md`). Cell-level `opt_tariff` reproduces across the halves at 0.344 against 0.391 under the shipped ridge (rule fixed in patch 0135: no more than 0.02 below; "do not release"; `docs/results/ridge_tariff_check.md`).
- **The Broda–Weinstein row weights are not fn. 14 as printed, and the measured alternative is worse.** Each exporter's moment row is a within-exporter weighted mean, so the T^{3/2} factor of Soderbery's fn. 14 cancels; the only trace of it is that the first differenced observation of every trading run — the pair's entry year — takes `bw_weight()`'s NA → 1 fallback (~1 beside 10–3,000 for its neighbours) because the calendar lag is looked up on the differenced table. The across-exporter weight is trade value scaled by min(T, 10)/10, a documented departure. Both were measured on a 2% product subsample on 2026-10-11 (`docs/methodology/stage2_country.md`, "The fn-14 flags, measured"): restoring the entry-year observation (`--bw-lag raw`) moves the median Tier-1 γ by 2.3% and the p90 row by 35% and lowers split-half reliability of the within-cell heterogeneity from r = 0.333 to 0.303; the fn-14 cross-variety weight (`--exporter-weight bw_sum`) lowers it to 0.314 and widens within-cell dispersion by 40%; both together 0.307. The shipped weighting stays; the two flags remain available and default-off.
- **Estimator-provenance composition.** On the full universe, 28.9% of
  (importer, HS4) cells are identified at the HLIML interior and 16.1% (45,305 cells) by the
  Step 2 (Fuller LIML) fallback, of which 2.1% of the full universe (5,802 cells)
  are clamped at the σ/ω caps and report the cap, not an estimate; a further 20.1% (56,461 cells) are constrained boundary HLIML optima -- 15,490 on the ω floor, 6,399 at the σ cap, 34,572 at the ω cap -- routed where the closed-form HLIML point was inadmissible and Step 2 supplied no admissible ω (`final_source == "hliml_boundary"`; SEs from the HNCS sandwich projected onto the edge on 55,947 of them (σ on the ω edges, ω on the σ-cap edge); `edge_se_status` names the 514 where the projected curvature was not usable); the remaining 34.8% (97,737 cells) return no estimate (thin or short panels, too few exporters, a singular first step, or no admissible point on any route). 93.7% of cells fail the
  Stock-Yogo weak-instrument threshold at the strict 10% maximal-size
  critical value this pipeline screens at. At Grant-Soderbery (2024)'s own
  25% rule of thumb, 38.5% of the 182,891 evaluated cells pass the
  weak-instrument screen, and 58.3% of the 178,732 cells with an
  overidentified Step-2 fit pass its Sargan test (conventional p > 0.2). The
  joint credibility screen of the G&S protocol pairs the 25% weak-instrument
  rule with the HLIML-residual overidentification statistic J_h, which exists
  only on the interior-HLIML cells: of the 81,142 cells where both are
  defined, 23.6% pass both. Per-cell flags
  (`stockyogo_pass_gs25`, `sargan_pass`, `sargan_pass_gs`, `gs_pass_both`) ship
  in the Stage 1 output so either threshold can be applied downstream. Conditional on `status == "ok"`
  the interior rate rises to 44.4%; both framings appear in the methodology
  write-up. Headline σ medians are reported on the canonical 1,240 HS4
  universe.
- **Period extension relative to Soderbery (2018).** This pipeline
  estimates over a longer window than Soderbery's original sample, which
  contributes to estimate differences independently of the estimator
  change from Feenstra GMM to HLIML.
- **Supply-side boundaries: two ends of the ω axis.** The Feenstra
  inversion has no positive ω for a point whose ρ exceeds (σ−1)/σ: the
  algebraic ω is negative, and geometrically the point is the continuation
  of the admissible interval *past ω = +∞*. Grant & Soderbery's Stata code
  clamps such points to the 1e-4 floor — the opposite end of the axis —
  and reports them as near-perfectly-elastic supply; this pipeline did the
  same through v0.6.1. From v0.7.0
  (`--stage1-negative-omega reject`; `floor` reproduces v0.6.1) such points are
  inadmissible at every inversion and take the constrained boundary optimum,
  which lands at the ω *cap* in most cases (`omega_capped`, `adjust` 8).
  The ω floor now holds 5.5% of cells,
  15,490 of them constrained floor-edge optima (`adjust` 6) — the genuine
  perfectly-elastic-supply end, which the `omega_floored` boolean isolates.
  Two populations need care: 13,069 cells report a Step-2 σ with ω
  undetermined (no admissible ω, no usable edge; `omega` is NA), and
  2,462 floor-edge optima were reached from a beyond-∞ point
  (`boundary_corner`): they sit near σ = 1 with a flat objective and should be
  filtered for supply-side uses. Stage 2 ridge shrinkage toward good-level
  priors lifts floored mass, so the published γ floors in only 0.0% of cells and looks
  better-behaved than the Stage 1 supply identification underneath it
  (see `docs/methodology/stage1_README.md`). Where ω is floored, both γ and the
  derived `opt_tariff` collapse toward zero — toward elastic supply and a
  near-zero optimal tariff — so a γ or tariff sitting at that boundary is an
  identification artifact, not an interior estimate.
- **Standard errors: conditional on σ, with a robustness screen.** `gamma_se`
  is computed with σ held fixed at its Stage 1 value (a global-median fallback
  wherever Stage 1 did not identify σ), so it is conditional on σ. Only
  71.7% of rows carry a clean cell-specific SE: 26.8% are rows
  assigned the good-level prior outright, with no SE (Tier 3, and the reference row of a cell
  whose other exporters are all Tier 3) and the remaining
  1.6% are rows at an extreme where no SE is computed (`boundary`, γ < 0.01;
  `plateau`, γ > 5), non-converged fits, or variances that could not be formed. The cell optimizer did not converge on 0.7% of directly estimated rows (1,775 of 210,098 fitted cells; a failed L-BFGS-B line search on 93.3% of those rows and an iteration cap on 6.7% — L-BFGS-B's, or the Nelder–Mead restart's where its point was published): those cells publish the better of the L-BFGS-B point and the Nelder–Mead restart, with `gamma_se_status` `non_converged` and no SE (`docs/results/stage2b_convergence_census_v0110.md`). The pipeline
  additionally propagates the Stage 1 σ uncertainty by the delta method into
  `gamma_se_total` and flags the result with a cell-level `sigma_robust` screen:
  σ̂ unclamped and with a finite SE, clear of the σ = 1 pole, and no γ SE in the
  cell inflated beyond threshold. 24.2% of rows pass (33.1% of the rows outside Tier 3); 49.0% are flagged `FALSE` and 26.8% are Tier-3 imputed cells (`NA`) with no per-cell σ. The screen is governed almost entirely by σ̂'s distance from the σ = 1 pole, not by the inflation cutoff, and the pass rate is stable across a wide grid of both thresholds (`analysis/sensitivity_sweep.R` reproduces it). Where `sigma_robust` is `FALSE` or `NA`, treat `gamma_se` as a conditional, lower-bound measure of uncertainty; where `TRUE`, `gamma_se_total` is the σ-aware SE — and in either case the SE is frequently as large as the estimate itself. Stage-1 `sigma_se` on the 45,305 Step-2 (Fuller LIML fallback) cells uses the k-class sandwich from v0.7.3; through v0.7.2 an OLS meat overstated it several-fold. Median relative SE (`sigma_se`/`sigma`): 0.30 on Step-2 cells, 0.26 on interior HLIML cells, 0.32 on boundary cells. An exporter-cluster bootstrap (750 cells × 399 replicates, branch-tagged; `validation/bootstrap_se_cells.csv`; medians over the 654 cells with at least four exporters and a defined weak-instrument F) puts the robust (MAD) dispersion of the replicates that stay on a cell's own branch at 0.89× the analytic SE for interior HLIML cells, 1.54× for boundary cells and 1.69× for Step-2 cells, with 60%, 55% and 36% of replicates staying on the published branch; the unconditional SD-based ratios are 10.15×, 11.95× and 11.56×, the difference being branch switching and heavy tails. Step-2 cells with strong instruments (Kleibergen-Paap F ≥ 7) sit at 6.33× within their own branch: their σ depends on which exporters the cell contains, so read Step-2 `sigma_se` as a composition-conditional lower bound and consult the per-cell bootstrap dispersion alongside it. In the Pillar-3 Monte Carlo — a regression-level harness on the shipped variance formula (sandwich with the ridge in λ/γ² units) with the import-side constant concentrated out as the shipped estimator does — the SE has a median ratio to the empirical sampling SD of 1.059 in a regime whose median `gamma_shrink_wt` is 0.897 (the shipped table's is 0.924) and 0.978–1.059 across all 5 regimes (`docs/methodology/se_calibration_mc_summary.csv`).
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
  COMTRADE of the original, which uses the importer's and the exporter's
  reports separately: Soderbery's import moments use the importer-reported
  (delivered) flows, his export moments the exporter-reported (shipped)
  ones, and he names the gap between shipped and delivered unit values as a
  source of the variation that keeps the import and export hyperbolae
  distinct (his §3.1 and fn. 11). BACI reconciles the two reports into one
  flow, so here both sets of moments share one unit value and identification
  rests on the difference between import shares and export shares alone,
  which Soderbery's fn. 11 argues is enough in principle. HS4 unit values are weight-based composites
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
