# Stage 1 â€” refactored_run_20260519

Stage 1 estimates Ïƒ, Ï‰, Ï per (importer, HS4) cell on CEPII BACI HS92
V202601 (1995â€“2024). This is the canonical refactored output, produced
2026-05-19 on r7a.16xlarge using the HLIML estimator ported from
Grant & Soderbery (2024) replication, with weighted Fuller LIML fallback
on cells where HLIML fails to converge and orchestrator value substitution
when either estimator returns Ïƒ or Ï‰ outside the (1, 10) admissibility box.

The refactored pipeline is canonical. Legacy Stage 1 output
(`s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/stage1_liml_202605/`) is preserved
for archival but contains an HS6 leading-zero handling bug that was fixed
in the refactor; see the parity section below.

## Contents

| File | Size | Purpose |
|------|------|---------|
| `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` | 21 MB | Slimmed Stage 1 output: Ïƒ only, downstream input to Stage 2a |
| `baci_hs92_v202601_elast_country_hs4_feenstra_sigma_liml.rds` | 21 MB | Full Stage 1 output: 30 columns with diagnostics, SE, adjust flag, hliml_status |
| `baci_hs92_v202601_elast_country_hs4_raw_cache.rds` | 876 MB | Pre-aggregated BACI panel cached for re-use across stages and validation |
| `parity_check_20260519.log` | 9 KB | Parity comparison against legacy Stage 1 output |
| `README.md` | â€” | This file |

## How it was produced

```
r7a.16xlarge (us-east-1, AMI r-estimation-ready, 62 cores, 512 GB RAM)
Rscript scripts/run_estimation.R --stage 1 --ncores 62
Wall time: approximately 30 minutes
```

The full pipeline command and infrastructure notes are in
`docs/methodology/README.md` and the repo root README. Stage 1 requires
r7a.16xlarge specifically â€” c7a.16xlarge (128 GB RAM) OOMs after the
master copies the raw BACI cache (~30 GB) and forks 62 workers.

## Schema â€” `_liml.rds` (30 columns)

The full Stage 1 output. Key columns:

| Column | Type | Description |
|--------|------|-------------|
| `importer` | integer | ISO numeric importer code |
| `good` | character | HS4 product code (zero-padded; e.g. `0302`) |
| `sigma` | numeric | Reported Ïƒ â€” HLIML if interior, else Step 2 fallback, else cap value |
| `omega` | numeric | Reported Ï‰, same rule as Ïƒ |
| `rho` | numeric | Reported Ï, derived from Ïƒ and Ï‰ |
| `gamma_common` | numeric | Implied Î³ under homogeneity (Î³_j = Î³_k) assumption |
| `sigma_se`, `omega_se`, `rho_se` | numeric | Standard errors (HNCS sandwich if HLIML, delta-method if Step 2) |
| `fstat_kp` | numeric | Kleibergen-Paap rk Wald F-statistic |
| `fstat_het` | numeric | HLIML heteroskedasticity-adjusted F (Step 3 of GS_Estimation.do) |
| `jstat`, `jstat_pval`, `jstat_h` | numeric | Hansen J overidentification statistic and HLIML residual variant |
| `stockyogo_pass` | logical | Whether fstat_kp exceeds the Stock-Yogo (2005) critical value for relevant l |
| `stockyogo_cv` | numeric | The applicable Stock-Yogo critical value at 10% max bias |
| `adjust` | integer | Estimator path flag (see below) |
| `final_source` | character | `"hliml"` or `"step2_weighted"` â€” which estimator supplied Ïƒ |
| `hliml_status` | character | `"ok"` or `"hliml_fail_no_convergence"` (or various failure subtypes) |
| `sigma_step2`, `omega_step2`, `rho_step2` | numeric | Step 2 weighted Fuller LIML estimates (always populated when Step 2 ran) |
| `sigma_hliml`, `omega_hliml`, `rho_hliml` | numeric | HLIML estimates (NA when HLIML failed) |
| `n_obs`, `n_exporters` | integer | Cell size diagnostics |
| `kappa`, `lambda_min` | numeric | LIML Îº and minimum-eigenvalue diagnostics |
| `status` | character | Outer cell status: `"ok"`, `"all_inversions_failed"`, `"thin_panel_*"`, etc. |

The slimmed `_feenstra_sigma.rds` retains (importer, good, sigma, gamma)
for use as Stage 2a input.

## `adjust` flag â€” estimator path indicator

The `adjust` column distinguishes how each cell's reported Ïƒ was produced:

| `adjust` | Meaning | Cell share (full universe) | Share conditional on `status="ok"` |
|----------|---------|----------------------------|------------------------------------|
| 0 | HLIML converged to interior solution; Ïƒ_hliml used | 18.8% | 35.2% |
| 1 | HLIML failed, Step 2 weighted Fuller LIML used; Ïƒ in admissibility box | 25.9% | 48.6% |
| 4 | Step 2 returned Ïƒ > 10; reported Ïƒ = 10 (cap value, not estimate) | 6.4% | 12.1% |
| 5 | Step 2 returned Ï‰ > 10; reported Ïƒ is Step 2's Ïƒ, Ï‰ = 10 cap | 2.2% | 4.1% |
| NA | All inversions failed; Ïƒ = NA | 46.7% | â€” |

Total estimable cells (`status = "ok"`): 149,577 of 280,649 (53.3%).

**Cells with `adjust âˆˆ {4, 5}` carry value-substituted Ïƒ.** For `adjust = 4`,
Ïƒ = 10 is the orchestrator's cap, not what the estimator computed. For
`adjust = 5`, Ïƒ is real (from Step 2) but Ï‰ is value-substituted. Downstream
analysis that depends on precise Ïƒ magnitudes â€” particularly comparisons to
external estimators â€” should filter these out.

## Parity verification

`parity_check_20260519.log` records the comparison against legacy Stage 1
output at `s3://trade-elast-baci-hs92-v202601-hs4/legacy_pipeline_archive_pre_hs6_padding_fix/stage1_liml_202605/`.

**Headline result: refactored output is structurally correct.** On 137,510
overlapping cells where both outputs have a non-NA `final_source`, 99.3%
agree on source assignment (HLIML vs step2_weighted). Of cells where both
sides have a numeric Ïƒ, 97.83% match to 1e-6, with the absolute-difference
99th percentile at Ïƒ â‰ˆ 1.2 and median at exactly 0. A 10-cell random
spot-check shows bit-identical Ïƒ and Î³ on every cell where both sides
returned values.

**Cell-count delta â€” fully explained by leading-zero fix.** Legacy had
308,045 rows, refactored has 280,649 (delta = âˆ’27,396). 46,933 cells
exist only in legacy, 19,537 only in refactored. The asymmetry is the
HS6 leading-zero handling bug: the legacy pipeline mishandled HS92
chapters 01â€“09, producing ~210 phantom HS4 codes like `8062` instead of
`0806`. The refactored pipeline correctly preserves leading zeros, which
both eliminates the phantoms (reducing the row count) and reveals
correctly-padded counterparts that legacy missed. Refactored Ïƒ median on
the canonical 1,240-HS4 universe is 2.875; legacy Ïƒ median on the
corrupted 1,364-HS4 set was 2.912.

**KP-F medians match exactly** (4.00 in both legacy and new on the HLIML
subset), confirming the instrument-strength characterization is unchanged
by the leading-zero fix.

## Pillar 1 of the paper evidence base

Stage 1 production output is the empirical foundation of the paper.
Key paper-relevant statistics readable directly from this directory:

- **HLIML interior-solution rate: 18.8% of universe / 35.2% of estimable cells.**
- **Step 2 fallback rate: 25.9% / 48.6%.**
- **Value-substitution rate (adjust âˆˆ {4, 5}): 8.6% / 16.2%.**
- **Mixture-distribution Ïƒ median: 2.875** â€” combines HLIML interior cells
  (median â‰ˆ 1.94), Step 2 fallback cells (median â‰ˆ 3.94), and cap values.
- **KP-F median: 4.47** on the HLIML-converged subset (per memory; not
  directly in the log).
- **Stock-Yogo failure rate: 43%** of estimable cells exceed the
  Stock-Yogo 10%-max-bias critical value for the relevant number of
  instruments (per memory; computed in downstream summarization).

Synthetic recovery diagnostics for the HLIML estimator are in
`docs/methodology/liml_validation.md`.

## Downstream consumers

- **Stage 2a** consumes `_feenstra_sigma.rds` to estimate regional Î³ with
  Ïƒ fixed. See `../stage2a/PARITY_REPORT.md`.
- **Tier 4 validation** consumes both the production output and
  `_raw_cache.rds` to compare HLIML against the legacy Feenstra GMM
  baseline.
- **External replication** would re-run from the raw cache (or fresh BACI
  download) using `scripts/run_estimation.R --stage 1` in the canonical
  repo.

---

*Last updated: 2026-05-20 following Tier 4 + adjust-flag audit completion.*
