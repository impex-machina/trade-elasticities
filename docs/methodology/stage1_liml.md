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

## Sample construction: Stage 1 and Stage 2 estimate on different rows (v0.7.2 note)

Stage 1 (`run_stage1_liml` → `prepare_cell_moments`) works directly from
the raw cache: within each (importer, exporter, product) it keeps rows with
finite positive value and quantity, differences log unit value and log
share against the previous **calendar** year, and double-differences against
the reference exporter. Stage 2 (`prepare_data`) applies one further filter
before the γ estimation: rows with |Δ ln p| ≥ `uv_outlier_threshold` = 2.0
(a factor of ~7.4 in the unit value from one year to the next) are dropped.
Stage 1 applies no such trim. σ and γ for the same cell are therefore
identified on different observation sets — the σ sample includes the
unit-value jumps that the γ sample excludes — and the Feenstra second
moments Stage 1 uses are exactly the statistics such jumps dominate.

Two smaller asymmetries live in the same place: `run_stage1_liml` is called
with `min_exporters = 2` from the config (its own default is 4; the
estimator then requires ≥ 3 exporters and ≥ 5 observations per cell), and
Stage 1 has no `min_year` filter beyond the cache's own year range.

**Decision (2026-09-22): the Stage-1 sample stays untrimmed.** The
asymmetry was tested rather than assumed away. `--stage1-uv-trim THRESH`
(patch 0057) applies Stage 2's rule inside Stage 1, at the same point and on
the differenced observation; a full-universe rc at 2.0 and a threshold curve
on a fixed 2% cell subsample are recorded in `sample_rule_decision.md` and
`docs/results/sigma_uv_trim_sensitivity*.md`. σ rises monotonically with
every tightening of the rule (untrimmed 2.47 → 3.00 at 3.0 → 3.64 at 2.0 →
4.54 at 1.5 on the subsample; 2.46 → 3.73 on the universe at 2.0) with no
plateau, and the share of cells pinned at the σ cap rises with it (13.7% →
19.0%). That is not a distinct population of bad observations being removed;
it is the estimator losing the price variance it identifies σ from. No
threshold can be defended as "the clean σ", so none is shipped. The Stage-2
trim is retained because the γ moment equations do not lean on unit-value
variance the way Feenstra's second moments do and because it is the
inherited Soderbery-era rule; the difference is now a stated design choice.
The trimmed σ is a robustness result, available to anyone with the flag.

## Step-2 standard errors: the k-class sandwich (patch 0061, 2026-09-22)

The Step-2 point estimate is a weighted Fuller(1) LIML, i.e. a k-class
estimator: it solves $X_k'(y - X\eta) = 0$ with
$X_k = ((1-\kappa)I + \kappa P_Z)X$, so $\hat\eta - \eta = K^{-1}X_k'u$ with
$K = X_k'X$ and the heteroskedasticity-consistent sandwich is
$K^{-1}(X_k'\,\mathrm{diag}(u^2)\,X_k)K^{-1}$ (at $\kappa = 1$ the 2SLS HC0
form). Through v0.7.2 `fuller_liml_core()` filled `V_eta_robust` with the
**OLS** meat $X'\mathrm{diag}(u^2)X$ instead. Because $X$ carries
within-exporter variation that the projected $X_k$ does not, that meat
overstates the variance, and the delta method amplifies it into the
structural SEs. This is the SE that ships as `sigma_se` / `omega_se` /
`rho_se` on every `step2_weighted` cell (47,479 in v0.7.2) and that feeds
their `gamma_se_total` and `sigma_robust` screen; interior HLIML and
boundary cells use the HNCS sandwich and are unaffected.

Measured on the Pillar-2 DGP (`validate_liml.R::simulate_one_cell`, the
Tier-1a 4×3 grid, 150 replications per point, both rules on the same cells
so points and routing are identical):

| route | cells | σ 95% coverage, legacy | k-class | median σ SE / σ, legacy | k-class |
|---|---|---|---|---|---|
| `hliml` (interior) | 1,042 | 0.872 | 0.872 | 0.236 | 0.236 |
| `hliml_boundary` | 486 | 0.836 | 0.836 | 0.273 | 0.273 |
| `step2_weighted` | 195 | **1.000** | **0.940** | **6.03** | **0.51** |

The legacy Step-2 σ SE is ~12× the k-class one and covers 100% of the
time — an uninformative interval. Pooled across routes (what Tier 1a
reports) coverage barely moves (0.876 → 0.870), which is why the defect
never surfaced there. The real-data exporter-cluster bootstrap of
2026-07-10 showed the same sign on Step-2 strata (bootstrap SD / analytic
SE 0.24–0.73). A direct Monte Carlo on a group-instrument IV design
(`tests/testthat/test-step2-kclass-vce.R`) puts the legacy η SEs at
1.8–2.1× the sampling SD and the k-class SEs within 5%.

`fuller_liml_core(vce = "kclass")` / `estimate_cell_liml(step2_vce =
"kclass")` / `run_stage1_liml(step2_vce = "kclass")` /
`--stage1-step2-vce kclass` implement the k-class sandwich; the row stamp
`step2_vce_method` records the rule. **`kclass` is the default from v0.7.3
(patch 0064)**; `legacy` reproduces every table shipped through v0.7.2
bit-for-bit, as `--stage1-edge-se none` reproduces v0.7.0.

### v0.7.3 rc, 2026-09-24: the real-data footprint

Stage 1 rerun on the v0.7.2 command line plus `--stage1-step2-vce kclass`
(S3 `v073rc_run_20260924/`; on-box bit-identity gate): every non-SE
column identical to v0.7.2 on every row; `sigma_se`, `omega_se` and
`rho_se` identical on every non-Step-2 row and moving on 36,670 / 43,431 /
33,307 of the 47,479 Step-2 rows (the 10,809 untouched `sigma_se` rows are
the adjust-4 σ-capped cells whose SE is pinned NA; the 33,307 `rho_se` rows
are adjust 1 exactly). Step-2 `sigma_se` ratio k-class / legacy: p10 0.104,
p25 0.141, **median 0.195**, p75 0.282, p90 0.411 — the OLS meat overstated
the Step-2 σ SE about fivefold at the median on real cells (the Pillar-2
DGP said ~12×; real cells are smaller and weaker). Median relative SE
(`sigma_se`/`sigma`): Step 2 **1.18 → 0.239**, now on the same footing as
interior HLIML (0.252) and boundary (0.298); σ-SE availability unchanged at
89.8% of ok cells. Stage 2a bit-identical; Stage 2b identical except
`sigma_se`, `sigma_robust` and `gamma_se_total` on the 1,018,474 rows
(14.9%) whose σ is a Step-2 cell: `sigma_robust` TRUE 17.6% → 23.9% of rows
(on those Step-2 rows 15.4% → 57.9%), `gamma_se_total` populated 13.9% →
19.2% (median 0.562 → 0.575). γ, `opt_tariff`, tiers and row counts are
unchanged.

The branch-tagged exporter-cluster bootstrap (patch 0063; 750 cells × 399
replicates on the rc Stage-1 table, `--step2-vce kclass`; eligible 156,090
cells; baseline refits 750/750 with 100% σ and route match) gives the
like-for-like calibration by branch. Medians are over the 653 cells with
at least four exporters and a defined weak-instrument F: the 83
three-exporter cells resample to a handful of distinct panels (their
within-branch MAD collapses toward zero) and the 14 F-undefined cells
barely bootstrap, so both are reported in the per-cell file but excluded
here (`results/bootstrap_se_summary.json` is the same computation):

| branch | cells | replicates on the published branch | within-branch MAD / SE | within-branch SD / SE | all-replicate MAD / SE | all-replicate SD / SE |
|---|---|---|---|---|---|---|
| interior HLIML | 243 | 63% | **1.03** | 1.88 | 1.55 | 4.51 |
| boundary | 205 | 55% | **1.44** | 2.73 | 1.75 | 3.25 |
| Step 2 | 205 | 32% | **1.51** | 3.95 | 1.93 | 3.97 |

The interior HNCS sandwich is calibrated against the robust within-branch
dispersion (1.03 at the median; 0.89–1.06 across the exporter-count bins);
the unconditional 4.5× of the July benchmark is branch switching plus heavy
tails, not miscalibration. The boundary SE understates by ~40% (larger
cells more: 0.96 at 10–19 exporters, 1.72 at 50+), consistent with its
edge-conditional derivation. Step 2 is the knife-edge branch: two-thirds
of its replicates leave it, and within the branch the ratio splits by
instrument strength — MAD 0.68 at F < 2, 2.61 at F 2–7, **6.36 at F ≥ 7**
(SD 28.8). That is not the σ cap (published σ ≥ 9 in 3 of the 40 such
cells, same-route replicate medians ≥ 9 in 2): those cells have the
*smallest* analytic SEs (0.3–1% of σ) beside replicate distributions that
are wider and shifted (e.g. σ 3.59, SE 0.012, same-route replicate median
5.19). The k-class SE is the variance conditional on the cell's exporter
set, which the Monte Carlo covers at 94% because every simulated exporter
obeys one σ; the exporter bootstrap adds the variance over *which*
exporters the cell contains, and Step-2 cells — the cells whose HLIML point
was inadmissible — are exactly the population where exporters disagree
about σ. Read Step-2 `sigma_se` as a composition-conditional lower bound
and `sigma_robust` as the analytic pole test it is; the per-cell bootstrap
file publishes the resampling dispersion. Two follow-ups sharpen: routing
inadmissible closed-form cells to the constrained HLIML optimum instead of
Step 2 (a branch two-thirds of resamples leave is not a stable estimator
for those cells), and a universal exporter-bootstrap dispersion column (750
cells took 7.4 minutes on 62 cores; every Step-2 cell at B = 399 is ~8 box
hours, every clean cell at B = 99 ~7).

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
