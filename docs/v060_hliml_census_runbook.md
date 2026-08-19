# v0.6.0-rc step 1 — HLIML closed-form census run (Stage 1 only, `--stage1-hliml both`)

Purpose: measure, on the full 280,649-cell universe, how the HLIML closed form
(patch 0025: `hliml_closed_form()`, the HLIM eigenvector already implied by the
`alpha` in `hncs_sandwich_se()`) would re-route cells relative to the shipped
wall-BFGS path -- **without changing any shipped number**. `both` mode routes
exactly as v0.5.x and adds the closed form in `*_cf` columns; the census script
tabulates re-routing, agreement, and the projected Stage-1 composition. Those
numbers are the go/no-go for switching the production default to `closed` in
v0.6.0 (plus the O(n) HNCS rewrite and the boundary/hybrid search that follow).

Prediction to test (from the 2026-08-18 audit): a share of the 66,843
`step2_clean` (adjust 1) and some of the 66,429 `all_inversions_failed` cells
have an admissible closed-form HLIML point; where both paths are admissible the
two sigmas agree closely and `Q_cf <= Q_bfgs` essentially always; headline
sigma medians move little; the sigma-bearing cell count (Stage-2 fallback
denominator) rises.

Inputs needed on the box: the Stage-1 raw cache from the v0.5.0-rc run
(`s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_20260818/<out_base>_raw_cache.rds`;
the pipeline's `--stage 1` path reads it when present in the out-dir) OR the raw
BACI CSVs under `BACI_HS92_V202601/` (then Stage 1 rebuilds the cache, +~10 min).
Memory: the master copy of the cache is ~30 GB; keep the r7a.16xlarge recipe
from `docs/v050_rerun_runbook.md` (62 forks) -- the closed form is O(n) and adds
no measurable time over the ~22 min Stage-1 run. A smaller box works with fewer
forks (`--ncores 12` on an r7a.4xlarge, slower).

## Phase 1 — launch + hygiene + preflight
Exactly `docs/v050_rerun_runbook.md` Phase 1 (console launch, r7a.16xlarge,
SG `te-estimation-ssh`, key `te-v030`; AMI hygiene; `R_LIBS_USER`; load-test
gate over Rcpp/data.table/ggplot2/haven/optparse/openssl/jsonlite). Then:

```
ubuntu@ip-...$ mkdir -p /tmp/w && cd /tmp/w
ubuntu@ip-...$ git clone --depth 1 https://github.com/impex-machina/trade-elasticities.git && cd trade-elasticities
ubuntu@ip-...$ git log --oneline -1      # must include patch 0025 (hliml_closed_form)
ubuntu@ip-...$ mkdir -p out && aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_20260818/ out/ --recursive --exclude "*" --include "*_raw_cache.rds"
ubuntu@ip-...$ ls -la out/
```
(`aws s3 cp` with `--recursive --include` is the house pattern; no `--profile`.)

## Phase 2 — Stage 1 in census mode (tmux)
```
ubuntu@ip-...$ tmux new -s s1
ubuntu@ip-...$ env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER=$HOME/R/library \
    Rscript scripts/run_estimation.R --data ~/BACI_HS92_V202601 --out-dir out \
    --stage 1 --stage1-hliml both --bw-lag calendar --ncores 62 2>&1 | tee out/run_s1_both.log
```
Tripwires in the log: cache hit (113.8M obs), sigma median 2.878, omega-scale
median 0.295, 280,649 cells / 141,824 ok -- the shipped numbers must reproduce
exactly because `both` does not change routing. If the sigma median differs,
STOP: something other than the census columns moved.

## Phase 3 — upload + local tabulation
```
ubuntu@ip-...$ aws s3 cp out/ s3://trade-elast-baci-hs92-v202601-hs4/hliml_cf_census_$(date +%Y%m%d)/ --recursive --exclude "*raw_cache*"
```
Terminate from the console. Locally (`PS C:\...>`), pull the LIML intermediate
(`*_feenstra_sigma_liml.rds`, ~25 MB) and run:
```
PS C:\...> aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/hliml_cf_census_<date>/ .\out_cf\ --recursive --exclude "*" --include "*_feenstra_sigma_liml.rds"
PS C:\...> & $Rscript analysis\hs4_hliml_closed_form_census.R --liml .\out_cf\<file>_feenstra_sigma_liml.rds
```
It prints Q1-Q4 and writes `results/hliml_closed_form_census.json` +
`docs/results/hliml_closed_form_census.md` (commit both; neither is
manifested). Paste the printed tables for adjudication.

## Adjudication rule of thumb
- `Q_cf <= Q_bfgs` should be ~100% where both are admissible; if not, inspect
  the exceptions before anything else (eigen edge cases, not a routing
  question).
- Re-routes INTO `hliml_interior` from `step2_clean` are expected and benign
  (same sigma within a few percent, better-classified provenance).
- Re-routes from `all_inversions_failed` are the material gain (new
  sigma-bearing cells): report the count and the median sigma of the rescued
  cells -- if they cluster at the caps, the boundary/hybrid search (next patch)
  is what they need, not the closed form alone.
- Reverse re-routes (BFGS ok, cf inadmissible) should be rare; each one is a
  BFGS local point inside the admissible region while the global min sits
  outside -- under `closed` they fall to Step 2, which is the honest answer.
Then decide: flip `--stage1-hliml` default to `closed` (v0.6.0), with the O(n)
HNCS rewrite and the Stage-2 analytic gradient in the same release.
