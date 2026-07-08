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

# Trade Elasticities — BACI HS92 V202601

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

Outputs are organized by pillar. The authoritative index — including
SHA-256 checksums and provenance — is `data/manifest.csv` in the GitHub
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
