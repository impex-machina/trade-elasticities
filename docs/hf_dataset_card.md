---
license: cc-by-4.0
language:
  - en
tags:
  - economics
  - international-trade
  - trade-elasticities
  - tariffs
  - baci
pretty_name: "Trade Elasticities (BACI HS92 V202601)"
---

<!--
  AUTHORITATIVE SOURCE (post-v0.4.1 audit): this repo copy is the source
  of truth for the HuggingFace dataset card. Edit it in the release
  commit, then paste it wholesale to the hub at the release runbook's
  card step. Do not draft changelog entries hub-side: hub-only edits are
  what let this file fall four releases behind the live card
  (v0.2.0 -> v0.4.1 changelogs existed only on the hub until this note).
-->

> **v0.6.1 (2026-09-01).** Corrects the HLIML boundary search (the routing
> introduced in v0.6.0 for cells where neither the closed-form interior
> estimator nor the Step-2 fallback yields an admissible point). The v0.6.0
> search minimised the profiled objective along each edge of the admissible
> box with a single `optimize()` call, which assumes a unimodal objective;
> the edge profiles are multimodal, so on the two omega-edges (where sigma
> is free) the search could terminate at the sigma -> 1 Cobb-Douglas pole,
> and a value of 1 + 1e-6 then passed the `sigma > 1` cleanliness filter
> into the shipped table (patches 0038-0041). **3,286 of 30,056 v0.6.0
> boundary-routed cells (10.9%) shipped at the sigma-pole** (sigma <=
> 1.001), concentrated on the omega-floor edge. Under the corrected search
> **3,285 of those 3,286 are now correctly `all_inversions_failed`** -- they
> have no admissible optimum anywhere in the box -- exactly one re-routed to
> a legitimate edge, and the boundary sigma-pole count is now **0** (minimum
> boundary sigma 1.0012). Clean Stage 1 cells move 185,144 -> **182,385**
> (66.0% -> 65.0%) and boundary-routed cells 30,056 -> **27,297** (equal
> drops of 2,759: every cell that left the clean set failed honestly). The
> Stage 1 **sigma median moves 2.7045 -> 2.7272**, the net of two effects on
> distinct populations -- removing the pole cells raises it +0.058 (they sat
> at sigma ~ 1 in the left tail), while the honest re-estimation of the
> remaining non-pole cells lowers it -0.035. **Stage 2b gamma is
> superseded**: gamma median 0.657 -> **0.628**, opt_tariff median 0.674 ->
> **0.657**, rows 6,860,437 -> 6,829,023, convergence 68.9% -> 69.2%, tier
> composition unchanged (3.3/70.1/0.2/26.4). Country structural ratios
> (v0.6.1): gamma/(1+gamma) 0.386, 1/(sigma-1) 0.579,
> gamma/((1+gamma)(sigma-1)) 0.204 (Soderbery 2018: 0.408 / 0.532 / 0.217).
> Pillar-2 synthetic-recovery validation was re-run under the closed-form
> default for the first time (its capture could not run under that default
> until patch 0042, so v0.6.0's Pillar-2 numbers predated the closed form):
> the median recovery yield rises to 98% (from 71.8%), reflecting the closed
> form's higher success rate, with Tier 1b consistency and Tier 2 sanity
> checks still passing.
> Of the v0.6.0 sigma-median movement attributed to the closed form (2.878
> -> 2.705), roughly a third was this pole artifact; the artifact-free level
> is ~2.76, and v0.6.1's 2.727 reflects that net of the honest
> re-estimation. Re-pull anything consuming sigma OR gamma. Data revision:
> `96e1589e4b5bd0bde0b3f2643b673ee09ff9f680`. **v0.6.0 remains available pinned at revision
> `4d0987e22977a6482eeefd8d9a3d5452d907e505`** -- do not mix versions within
> one analysis.

> **v0.6.0 (2026-08-19).** Stage 1 moves from the BFGS search to the
> closed-form HLIML estimator with hybrid boundary-search routing
> (patches 0025-0037): usable Stage 1 cells rise **50.5% -> 66.0%**
> (141,824 -> 185,144 of 280,649; HLIML interior 62.4% of ok, Step 2
> fallback 21.4%, boundary optima 16.2% with structurally unavailable
> SEs, adjust codes 6/7/8), and **sigma moves for the first time across
> releases**: median 2.878 -> 2.705 (IQR 1.63-5.71). Standard errors on
> closed-form cells use an O(n) group-sum HNCS sandwich (100% finite).
> **Stage 2b gamma is superseded**: gamma median 0.657, opt_tariff
> median 0.674, rows 6,860,437, tier composition unchanged
> (3.3/70.1/0.2/26.4). A Stage 2 analytic gradient was evaluated against
> the numeric default and REJECTED 22:1 under the current optimizer
> cascade (docs/methodology/v060_stage2_gradient_ab.md); numeric remains
> the default. Shipped Stage 1 cap flags corrected post-hoc for boundary
> corner cells (sigma_capped +1,934, omega_capped +3,328;
> scripts/patch_stage1_boundary_flags.R). Disclosure: saved Stage 2b row
> membership depends on global 0.5% tail-trim quantile bands; 2.2-2.9%
> of cells lack their own reference-exporter row in every release to
> date (ibid., Section 5). Re-pull anything consuming sigma OR gamma.
> Data revision: `4d0987e22977a6482eeefd8d9a3d5452d907e505`. **v0.5.1
> remains available pinned at revision
> `3b796a6db8a6fa1caabb37acb1e51480a3cbcaf4`** -- do not mix versions
> within one analysis.

> **v0.5.1 (VALIDATION-ONLY, 2026-08-18).** Corrects the Pillar-2 synthetic-recovery
> harness: `simulate_one_cell()` built the y/x1/x2 moment columns time-major while
> its exporter/t labels were exporter-major, so every labeled exporter was a
> mixture of all true exporters and the estimator was benchmarked on a no-signal
> design. **Stage 1 sigma and Stage 2b gamma are bit-identical to v0.5.0**
> (production moment construction is row-wise and was never affected); only the
> two validation CSVs change. Corrected Tier 1a (J=25, T=30, 200 reps): yield
> 41-96% (median 72%); sigma median bias within +/-3% for sigma <= 3, largest at the
> (8, 3) corner (-46%); median coverage 91%. Tier 1b (3, 1): yield RISES with n
> (72% at n=150 to 99% at n=3000), sigma bias -8.8% -> -2.3%. The earlier
> "yield falls with n / fragility of the LIML class" reading is withdrawn.
> Data revision: `3b796a6db8a6fa1caabb37acb1e51480a3cbcaf4`. v0.5.0 remains pinned at
> `ea1c3ea464ca1ac114bf9b6c518325e8135bdc41`.
>
> **v0.5.0 (2026-08-18).** Broda-Weinstein fn-14 weight lag corrected to the
> previous **calendar** year of the cell panel: v0.4.x took the previous
> *retained* row via a positional shift, which silently substituted a stale
> x_{t-2+} whenever the t-1 row had been filtered out. CLI default is now
> `--bw-lag calendar`; `--bw-lag legacy` reproduces v0.4.1 bit-for-bit.
> **Stage 1 sigma is bit-identical to v0.4.1** (280,649 cells; Stage 1
> carries no BW weights) -- sigma-only consumers are unaffected. **Stage 2b
> gamma is superseded**: gamma median 0.679 -> 0.678, p95 1.949 -> 1.940,
> share gamma > 1 23.6% -> 23.4%, opt_tariff median 0.713 -> 0.709, tier
> composition unchanged (3.3/70.1/0.2/26.4); 95.2% of matched estimates
> moved but the median |dgamma| is 0.0024 (p90 0.16, p99 1.46) -- broad,
> small reweighting; membership churn 8,586 out / 8,085 in (0.12%), rows
> 6,831,219 -> 6,830,718. Prepared-panel gap census (HS4, country scope):
> 52.8% of bilateral series carry internal holes and 7.15M rows (9.1%)
> received a stale lag under v0.4.x, touching 91.0% of cells; those rows now
> take the weight-1 fallback (the same path as series-first rows), and
> movement is monotone in per-cell stale-row count (Spearman 0.45 on
> cell-max |dgamma|). Full read with the recorded prediction:
> `docs/methodology/v041_v050_comparison.md` at GitHub tag `v0.5.0`.
> **Manifest note:** sha256 values for the binary `.rds` files are now
> computed in binary mode; the v0.4.0/v0.4.1 manifests recorded text-mode
> hashes for those four files that do not match standard sha256 tools (the
> files themselves were always correct; hub-side checksums unaffected).
> Saved outputs are now canonically sorted with run metadata moved to the
> summary sidecar, so from this release the manifest hashes certify content.
> Data revision: `ea1c3ea464ca1ac114bf9b6c518325e8135bdc41`. **v0.4.1
> remains available pinned at revision `5493c51f`** -- do not mix versions
> within one analysis.
>
> **v0.4.1 (2026-07-25).** Sign correction on Soderbery (2018) Eq. (11):
> the export-supply moment used x5/x6 sign conventions inconsistent with
> the paper (derivation and fix: `docs/methodology/eq11_sign_correction.md`
> at GitHub tag `v0.4.1`; a `paper_exact_eq11` flag preserves the old
> behavior for replication). Full test suite 120/120; estimator harness
> (T = 1e6) OVERALL PASS with printed-sign separation 260.9x. **Sigma is
> unchanged from v0.4.0** (bit-identical, 280,649 cells) -- sigma-only
> consumers are unaffected. **Stage 2b gamma is superseded**: rows
> 6,831,402 -> 6,831,219; gamma median 0.674 -> 0.679; optimal-tariff
> median 0.713; tier shares and convergence stable (3.3/70.1/0.2/26.4;
> 70.7%). **Stage-1 identification diagnostics are re-based**: earlier
> releases overstated strength via a Sargan dof error and a
> non-partialled Cragg-Donald F. Corrected: strict Stock-Yogo pass 6.1%
> (was 17.3), G&S-25 pass 41.2% (was 58.5), Sargan pass 56.3% (was
> 61.7), joint 22.4% (was 28.4); G&S-protocol Sargan 74.9%. Comparison
> to Grant & Soderbery's 44% joint rate carries a robust-KP caveat
> (`docs/methodology/stata_port_deviations.md`). Pervasive weak
> identification is the empirical case for the shrinkage design (median
> prior weight 0.98). **Lambda reviewed and retained at 0.1** after the
> corrected moments fired the drift trigger: a full-scale five-point
> sweep (`docs/methodology/lambda_sweep_20260723.md`) shows a flat
> optimum over [0.1, 0.2]; 0.1 maximizes retained heterogeneity; drift
> baseline reset to `results/lambda_diagnostic_v041.json`.
> **Reproducibility**: an independent re-estimation reproduced this
> release's Stage-2b table data-bit-identically after stripping the
> `run_meta` attribute; file hashes differ across runs only through
> embedded run metadata (a sidecar fix is slated). Full comparison:
> `docs/methodology/v040_v041_comparison.md` at GitHub tag `v0.4.1`.
> Data revision: `5493c51f`. **v0.4.0 remains available pinned at
> revision `a76f2d7`** -- do not mix versions within one analysis.

> **v0.4.0 (2026-07-19).** Full regeneration on the corrected Soderbery
> (2018) Eq. (10): the coefficient on the fourth import-side moment was
> mistranscribed in every prior release (found in a fresh-eyes audit
> 2026-07-17; confirmed by hand derivation, the footnote-12 homogeneity
> limit, and an independent structural-DGP simulation). **Sigma is
> bit-identical to v0.3.0** on all shared columns (verified A/B, 280,649
> cells) -- sigma-only consumers are unaffected. **Gamma, opt_tariff,
> and the SE columns are superseded**: the marginals move little (gamma
> median 0.680 -> 0.674) but 44% of cells move by more than 0.01 and
> 11.5% by more than 10% of their v0.3.0 value -- re-pull anything
> consuming gamma, opt_tariff, gamma_se_total, sigma_robust, or the
> weak-identification screens, and do not mix versions within one
> analysis. New columns: Stage 1 `stockyogo_pass_gs25`,
> `stockyogo_cv_gs25`, `sargan_pass`, `gs_pass_both` (the Grant &
> Soderbery 2024 screening protocol at their 25% rule of thumb alongside
> the strict 10% screen, which is unchanged at 17.3% pass; the 25%
> screen passes 58.5%), and Stage 2b `gamma_shrink_wt` (per-row share of
> curvature contributed by the shrinkage prior; overall median 0.98).
> The validation stack gains a structural-DGP pillar that simulates
> Eqs (5)-(6) independently of all pipeline code, and the Pillar-2 omega
> columns are re-based per the F10 harness correction. Full comparison:
> `docs/methodology/v030_v040_comparison.md` at GitHub tag `v0.4.0`.
> Data revision: `a76f2d7`. **v0.3.0 remains available pinned at
> revision `ec59b57894cab18b2d0295c96334a96b7dd8a2cd`:**
>
> ```python
> from huggingface_hub import hf_hub_download
> hf_hub_download("impex-machina/trade-elasticities",
>                 "stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds",
>                 repo_type="dataset", revision="ec59b57894cab18b2d0295c96334a96b7dd8a2cd")
> ```

> **v0.3.0 (2026-07-08).** Full regeneration on the six-patch fix series
> (GitHub tag `v0.3.0`). Gamma re-levels onto Soderbery (2018) Table 2
> benchmarks (gamma/(1+gamma) = 0.405 vs his 0.408): gamma median rises
> 0.238 -> 0.680 and the implied median export-supply elasticity is now
> 1.47 (the prior-scale bug in v0.2.0 biased gamma down and inflated the
> implied elasticity). Sigma is essentially unchanged (median 2.878).
> Standard errors are corrected (sigma_se was understated, rho_se
> overstated); the weak-IV screen now uses the minimum-eigenvalue
> Cragg-Donald statistic (Stock-Yogo pass 59% -> 17% -- the honest
> number); `sigma_robust` passes on 10.6% of rows. Details:
> `docs/methodology/v020_v030_comparison.md` in the GitHub repo.
> **v0.2.0 remains available pinned at revision `7e598f6cb98e`** -- do
> not mix versions within one analysis.
>
> **2026-07-10.** Added exporter-cluster bootstrap SE benchmark outputs
> under `validation/` (`bootstrap_se_summary.csv`, per-cell
> `bootstrap_se_cells.csv`, 736 cells): real-data calibration of the
> analytic sigma_se by identification stratum and estimator branch. See
> `docs/methodology/validation_section_draft.md` (Section 4) in the
> GitHub repo for results and interpretation.

# Trade Elasticities -- BACI HS92 V202601

Importer-product-exporter trade elasticity estimates: heterogeneous
import-demand elasticities (sigma) and inverse export-supply
elasticities (gamma) estimated
from CEPII BACI bilateral trade data, following Soderbery (2018) and
Grant & Soderbery (2024).

This dataset holds the **published outputs** of the estimation pipeline.
The code that produces them, full methodology, and replication
instructions live in the GitHub repository:

**https://github.com/impex-machina/trade-elasticities**

## License

Data in this dataset: **CC BY 4.0**. The pipeline code (in the GitHub
repo) is licensed separately under **MIT**.

## What's here

Outputs are organized by pillar. The authoritative index -- including
SHA-256 checksums and provenance -- is `data/manifest.csv` in the GitHub
repo; the table below mirrors its human-readable view.

| Path | Pillar | Description |
|---|---|---|
| `stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` | 1 | Stage 1 sigma estimates (HLIML primary, Step 2 fallback) |
| `stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds` | 1 | Stage 2a regional gamma with fixed sigma |
| `stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` | 1 | Stage 2b country-level gamma with shrinkage + SE |
| `stage2b/..._summary.rds` / `.txt` | 1 | Country-pair summary table (binary + human-readable) |
| `validation/liml_validation_tier1a.csv` | 2 | Synthetic recovery: Tier 1a sigma grid |
| `validation/liml_validation_tier1b.csv` | 2 | Synthetic recovery: Tier 1b sample-size convergence |
| `validation/se_calibration_mc_summary.csv` | 3 | SE calibration Monte Carlo (4 regimes x 3 formulas) |
| `validation/se_calibration_mc_per_param.csv` | 3 | Per-parameter calibration detail |
| `validation/bootstrap_se_summary.csv` | 3 | Exporter-cluster bootstrap SE benchmark: ratio-by-stratum summary (2026-07-10 run) |
| `validation/bootstrap_se_cells.csv` | 3 | Bootstrap SE benchmark: per-cell detail (736 reporting cells) |

The three pillars: (1) the BACI HS4 empirical core, (2) synthetic
recovery of the estimator, (3) standard-error calibration. See the
repo's `docs/methodology/` for details.

## Raw BACI data is NOT here

The raw CEPII BACI HS92 V202601 trade data is **not** redistributed in
this dataset (it is CEPII's to distribute, and it is large). Download it
directly from CEPII:

**https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37**

Place it under `data/raw/` in your clone of the repo. The pipeline reads
it from there.

## Loading the outputs in R

The recommended path is to clone the GitHub repo and use the bundled
loader, which reads the manifest and verifies checksums:

```r
# from the repo root, after renv::restore()
source("R/load_outputs.R")
load_outputs()                       # downloads all manifested files to data/derived/
x <- readRDS("data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
head(x)
```

To pull a single file directly from this dataset without the repo:

```r
url <- paste0("https://huggingface.co/datasets/impex-machina/",
              "trade-elasticities/resolve/main/",
              "stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
tmp <- tempfile(fileext = ".rds")
download.file(url, tmp, mode = "wb")
x <- readRDS(tmp)
head(x)
```

## Citation

If you use these data, please cite the paper (DOI to be added on
publication) and the underlying sources:

- Soderbery, A. (2018). Trade elasticities, heterogeneity, and optimal
  tariffs. *Journal of International Economics*, 114, 44-62.
- Grant, M. & Soderbery, A. (2024). Heteroskedastic supply and demand
  estimation: Analysis and testing. *Journal of International
  Economics*, 150, 1-23. https://doi.org/10.1016/j.jinteco.2023.103817
- CEPII BACI World Trade Database, HS92 V202601.
