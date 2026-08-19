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

## v0.6.0 addendum: closed-form HLIML, O(n) algebra, boundary routing

*Added 2026-08-19 (patches 0025-0031). The sections above describe the v0.5.x
BFGS path, which remains available bit-for-bit via `--stage1-hliml bfgs`.*

**Point estimate.** The HLIML objective $Q(\theta) = A'(P-D)A / A'A$ with
$A = Y - X\theta$ is a Rayleigh quotient in $b = (1, -\theta)$, so its
unconstrained minimiser is the generalized eigenvector for the smallest
eigenvalue of $(X_c'X_c)^{-1} X_c'(P-D)X_c$, $X_c = [Y, X]$ -- the same
$\alpha$ the HNCS sandwich already uses. `hliml_closed_form()` computes it
deterministically and inverts to $(\sigma, \omega)$; the admissibility caps
then apply exactly as before. No optimizer, so a cell's HLIML status is a
property of the data, not of a search path.

**O(n) algebra.** With exporter dummies as instruments, $P$ is block-diagonal
with entries $1/n_g$, so every $P$-weighted quadratic form in the objective and
in the HNCS sandwich collapses to within-exporter sums (`hliml_group_moments()`,
`hncs_sandwich_se_groups()`). The `closed` path never builds an $n \times n$
matrix. Summation order differs from the dense path, so the dense `bfgs` path
is kept as the v0.5.x reproducer rather than rewritten.

**Routing (precedence unchanged, one new tail).** Interior closed-form HLIML
(adjust 0) > Step-2 cascade (adjust 1/4/5, `omega_floored`) > **boundary
optimum** (new): when both are inadmissible, `hliml_boundary_search()`
minimises $Q$ along the edges of the admissible box with $\theta_0$ profiled
out; a usable edge (`omega_floor` -> adjust 6, `sigma_cap` -> 7, `omega_cap`
-> 8; `sigma_floor` stays a failure) is routed with
`final_source == "hliml_boundary"`, the matching cap/floor flags, and no SE.
This is Soderbery (2015)'s hybrid behaviour made explicit and flagged.

**Census on the full universe (2026-08-19, `--stage1-hliml both`, bit-identical
routing to v0.5.1; `docs/results/hliml_closed_form_census.md`).** Of 150,429
cells where v0.5.x BFGS did not converge, 63,040 have an admissible closed-form
HLIML point. Where both paths are admissible (52,293 cells), median
$|\Delta\sigma| = 0.0001$, 95.1% within 1%, and $Q_{cf} \le Q_{bfgs}$ in
99.99%. Projected composition under `closed`: `hliml_interior` 51,038 ->
115,999; `step2_clean` 66,843 -> 24,776; `capped` 23,943 -> 14,598;
`all_inversions_failed` 66,429 -> 52,880 before the boundary tail, of which
29,909 carry a usable boundary optimum (median $\sigma$ 3.31; 46% on the
$\omega$ floor, 37% at the $\sigma$ cap, 17% at the $\omega$ cap). 5,424
shipped interior cells have an inadmissible global optimum (BFGS had stopped
at a non-minimising interior point); under `closed` they fall to the Step-2
cascade. The realised v0.6.0 tables come from the rc run
(`docs/v060_rc_runbook.md`), not from this projection.
