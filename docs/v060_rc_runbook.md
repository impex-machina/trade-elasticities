# v0.6.0-rc rerun runbook — closed-form HLIML default (leg 2)

Scope: full Stage 1 -> 2a -> 2b rerun with the v0.6.0 Stage-1 default
(`--stage1-hliml closed`, boundary routing for cells failing both HLIML and
Step 2), a Stage-2b A/B of the analytic gradient, `compare_runs.R` against
v0.5.1, and release if adjudicated. Infra and hygiene exactly as
`docs/v050_rerun_runbook.md` Phase 1 (r7a.16xlarge, SG `te-estimation-ssh`
with the inbound source refreshed to My IP, key `~/.ssh/te-v030` (no .pem),
`R_LIBS_USER=$HOME/R/library`, load-test gate). Raw cache: archived at
`s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_20260818/` (the pipeline
reads `<out>/<base>_raw_cache.rds` when present; the 0.6.0 change is estimator-
side only, so the cache is reusable).

**Decision already taken** (census 2026-08-19, `docs/results/hliml_closed_form_census.md`):
Stage-1 default is `closed` (patch 0031). **Decision NOT yet taken**: Stage-2b
gradient (`--stage2-gradient analytic`) -- the rc run measures it.

**Lessons carried in from leg 1 (OBSERVED 2026-08-19):** never edit a function
signature with a regex (patch 0025 stranded a formal inside a default; caught
only at the first real call); every CLI-reachable entry point needs one
end-to-end smoke test (`test-stage1-wrapper-smoke.R`); a *stopped* instance
loses `/tmp` and its public IP -- re-clone, re-pull the cache, refresh the SG.

## Phase 1 — launch, clone, cache (`ubuntu@ip-…$`)
```
export R_LIBS_USER=$HOME/R/library
mkdir -p /tmp/w && cd /tmp/w && git clone --depth 1 https://github.com/impex-machina/trade-elasticities.git && cd trade-elasticities
git log --oneline -1                    # must include patch 0031 (closed default)
mkdir -p out && aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_20260818/ out/ --recursive --exclude "*" --include "*_raw_cache.rds"
```

## Phase 2 — Stage 1 + 2a + 2b with the new default (tmux, ~1 h)
```
tmux new -s rc
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER=$HOME/R/library \
  Rscript scripts/run_estimation.R --data ~/BACI_HS92_V202601 --out-dir out \
  --bw-lag calendar --ncores 62 2>&1 | tee out/run_v060rc.log
```
(`--stage1-hliml closed` and `--stage2-gradient numeric` are the defaults; say
them explicitly in the log message if you prefer.) Tripwires: cache hit
(113.8M obs); 280,649 cells; **ok count and sigma median will MOVE** -- the
census projects ~185k sigma-bearing cells (from 141,824; interior ~116k, plus
~30k boundary) -- record them; Stage 2a/2b run as before (~35 min).

## Phase 3 — Stage 2b gradient A/B (same Stage 1, second 2b pass)
```
mkdir -p out_grad && cp out/*_feenstra_sigma*.rds out/*_raw_cache.rds out/*regional*.rds out_grad/ 2>/dev/null
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER=$HOME/R/library \
  Rscript scripts/run_estimation.R --data ~/BACI_HS92_V202601 --out-dir out_grad \
  --stage 2b --stage2-gradient analytic --bw-lag calendar --ncores 62 2>&1 | tee out_grad/run_2b_analytic.log
```
(`--stage 2b` reuses the Stage-1/2a artefacts present in the out-dir; confirm
the log says so and does not re-run Stage 1.) Compare per cell on `convergence`
and `obj_value` (merge on importer x good x exporter): share converged, share
with lower objective, median |delta gamma|, tier composition. Rule: adopt
`analytic` as the v0.6.0 default only if convergence rises materially AND the
objective is <= numeric in the large majority of cells; otherwise ship
`numeric` and keep the flag.

## Phase 4 — upload, terminate
```
aws s3 cp out/ s3://trade-elast-baci-hs92-v202601-hs4/v060rc_run_$(date +%Y%m%d)/ --recursive
aws s3 cp out_grad/ s3://trade-elast-baci-hs92-v202601-hs4/v060rc_run_$(date +%Y%m%d)/stage2b_analytic/ --recursive --exclude "*raw_cache*"
```
Terminate from the console (not stop).

## Phase 5 — local adjudication (`PS C:\…>`)
Pull the rc stage1 / stage2a / stage2b / summary artefacts into
`data\derived_v060rc\` (keep `data\derived` = v0.5.1) and run
`compare_runs.R` v0.5.1 vs rc exactly as the v0.5.0 cycle did. Expected
signature of a correct rc: sigma composition per census Q4 (+ boundary tail);
sigma medians move only where cells changed estimator (census Q3 says agreeing
cells agree to 1e-4); gamma moves through (a) the enlarged sigma lookup
(fewer fallback rows) and (b) any Stage-2b gradient change; tier composition
unchanged (tiers depend on data, not on sigma). Anything outside that shape:
stop and diagnose before regenerating.

## Phase 6 — regenerate + release (as v0.5.0)
`data\derived` <- rc artefacts; `master.R` (no `--rerun-pillars`);
`build_readme.R` (the README bullet 1 / provenance bullet pick up the new
routing fields, including the boundary sentence); `rehash_manifest.R`;
card entry (v0.6.0: closed-form HLIML default; boundary routing; sigma-bearing
cells N -> M; sigma median X -> Y; gamma median; gradient decision);
tag v0.6.0; `hf_upload_release.py` dry -> execute; card sync with the new oid
in the verify list. Keep `--stage1-hliml bfgs` documented as the v0.5.x
reproducer.
