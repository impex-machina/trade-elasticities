# Stage 1 — Grant-Soderbery (2024) HLIML estimator

> **Note:** Originally written as `stage1_liml_202605/README.md` in the
> pre-refactor working directory. Reflects the May 2026 production run.
> The `data/legacy/...` paths below are the historical record of the
> legacy run; that tree is **not** part of this repository. It is
> preserved at the projects-tree `_archive/` and on S3
> (`s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/`).
> See the Provenance section of `README.md`.

Stage 1 output: Grant-Soderbery (2024) HLIML estimator applied to BACI
HS92 V202601, aggregated to HS4, years 1995-2024.

Produced: 2026-05-12 by `stage1_liml_wrapper.R` (a legacy one-off Stage 1
driver, not migrated into the refactored `R/` because it's a driver, not a
reusable function; preserved with the archived legacy source, not in this
repo).

## Files

| File | Description |
|------|-------------|
| `data/legacy/stage1_liml_202605/baci_hs92_v202601_elast_country_hs4_feenstra_sigma_liml.rds` | LIML estimator output, country level. 308,045 (importer, good) cells. 30 columns including σ, ω, ρ, γ_common, standard errors, Kleibergen-Paap F, J-stat, Stock-Yogo pass flag, HLIML diagnostics. |
| `data/legacy/stage1_liml_202605/stage1_full.log` | Run log (if present in the snapshot) |

## Summary statistics

- 308,045 cells attempted, 159,794 with `status == "ok"` (51.9%)
- Among ok cells: σ median = 2.912, IQR [1.841, 5.601]; γ_common median = 0.227

## Downstream

This file is consumed by Stage 2 via `translate_liml_to_feenstra_schema.R`
(a legacy script, preserved with the archived legacy source rather than in
this repo), which renames columns and writes
`baci_..._feenstra_sigma.rds` for the Stage 2 runner to ingest. The
translated file is regenerated on each Stage 2 run rather than persisted
in the snapshot.

## Notes

- The 48.1% of cells with `status != "ok"` (mostly `all_inversions_failed`,
  `prep_thin_n0`, `prep_thin_n1`, `thin_panel_*`) fall through to the
  `sigma_fallback` global median in Stage 2. This produces the 29%
  `fallback_median` provenance rate observed in the Stage 2 country
  output. See `stage2_country.md` for the implications.
