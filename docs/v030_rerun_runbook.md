# v0.3.0 rerun runbook

Full Stage 1 -> 2a -> 2b regeneration after the six-patch series, followed by
local re-derivation of validation pillars, summaries, README, manifest, and
HF publication. Placeholders you must fill are written `<LIKE_THIS>`.

Production invariants carried over from the v0.2.0 arc (do not relitigate):
r7a.16xlarge in us-east-1; AMI `r-estimation-ready` (R 4.5.3); work out of
`/tmp/`, never `~/work/` (stale baked-in state); `aws s3 cp`, never `sync`;
local AWS CLI uses only the `default` profile; canonical v0.2.0 outputs live
under the `refactored_run_20260519` S3 prefix and must not be overwritten.

---

## Phase 0 -- before launching (local)

1. Merge the `fixes-v030` PR into `main`. Confirm the Actions run is green
   (first green since early June -- the stale e2e contract was the blocker).
2. Push the HF dataset-card update (corrected gamma semantics + known-issues
   admonition) so v0.2.0 consumers are warned while the rerun is in flight.
3. Key pair: the old pair was deleted during credential hygiene. Create a
   fresh one and store the .pem OUTSIDE OneDrive:

   ```powershell
   aws ec2 create-key-pair --key-name te-v030 `
     --query 'KeyMaterial' --output text | `
     Out-File -Encoding ascii C:\Users\maxxj\.ssh\te-v030.pem
   ```

4. Decide the new S3 prefix, e.g. `s3://<BUCKET>/v030_run_<YYYYMMDD>/`.
5. Reuse the raw cache. `<prefix>_raw_cache.rds` is a pre-difference artifact
   untouched by all six patches (the gap guard applies at moment construction,
   not caching), so copying it into the run's out-dir skips the multi-hour
   load/clean/aggregate step. Confirm the object exists under the v0.2.0
   prefix before launch.

## Phase 1 -- launch

1. Launch r7a.16xlarge (64 vCPU / 512 GiB), us-east-1, AMI
   `r-estimation-ready`, key pair `te-v030`, EBS sized as per the v0.2.0 run.
2. SSH in; verify the clock is right and disk is where you expect:

   ```bash
   ssh -i ~/.ssh/te-v030.pem ubuntu@<INSTANCE_IP>
   df -h; nproc; free -g
   mkdir -p /tmp/v030/{baci,out} && cd /tmp/v030
   ```

## Phase 2 -- run

1. Clone post-merge main and verify the six commits are present:

   ```bash
   git clone https://github.com/impex-machina/trade-elasticities.git
   cd trade-elasticities && git log --oneline -7
   ```

2. `TRADE_ELAST_SRC` is no longer required (patch 5 added the repo-relative
   fallback). Remove it from any saved launch scripts so nothing points at a
   stale source copy.
3. Stage inputs:

   ```bash
   aws s3 cp s3://<BUCKET>/<BACI_PREFIX>/ /tmp/v030/baci/ --recursive
   aws s3 cp s3://<BUCKET>/refactored_run_20260519/<PREFIX>_raw_cache.rds \
     /tmp/v030/out/<PREFIX>_raw_cache.rds
   ```

   The cache filename must match what `run_estimation.R` derives from
   `--out-dir` + naming, or the cache hit will not fire -- check the
   "Loading cached raw data..." line early in the log.
4. The out-dir must contain ONLY the raw cache. `--stage all` resumes from
   any cached stage outputs it finds; a leftover sigma file would silently
   skip Stage 1.
5. Keep tuning constants fixed to isolate the bug fixes: do NOT pass
   `--shrinkage-lambda` (2b default 0.1; the 2a value stays hardcoded at
   0.05). Any lambda recalibration is a separate, later exercise.
6. Launch under nohup:

   ```bash
   cd /tmp/v030/trade-elasticities
   nohup Rscript scripts/run_estimation.R \
     --data /tmp/v030/baci --out-dir /tmp/v030/out \
     > /tmp/v030/run.log 2>&1 &
   tail -f /tmp/v030/run.log
   ```

7. Early sanity milestones in the log:
   - "Loading cached raw data..." (cache hit fired);
   - the Stage-1 -> Stage-2 translation now prints
     "gamma (omega-scale) median=..." -- expect roughly 0.3, up from ~0.19.
     This is the first live confirmation the scale fix is in effect;
   - the plateau fallback line now reports replaced vs no-prior counts.
8. Budget wall-clock comparable to the v0.2.0 run; none of the patches add
   meaningful compute (the CD eigenvalue is on 2x2 matrices).

## Phase 3 -- upload + terminate

```bash
aws s3 cp /tmp/v030/out/ s3://<BUCKET>/v030_run_<YYYYMMDD>/ --recursive
aws s3 cp /tmp/v030/run.log s3://<BUCKET>/v030_run_<YYYYMMDD>/run.log
aws s3 ls s3://<BUCKET>/v030_run_<YYYYMMDD>/ --recursive --human-readable
```

Verify counts/sizes against the local dir, then terminate the instance.
Do not touch `refactored_run_20260519/`.

## Phase 4 -- local regeneration

1. Download the stage1 / stage2a / stage2b .rds (+ summary .txt/.csv) into
   `data/derived/...` mirroring the `local_path` layout in
   `data/manifest.csv`. Keep the v0.2.0 files in a sibling
   `data/derived_v020/` for the comparison step.
2. Re-run the validation pillars (~1 hour):

   ```powershell
   Rscript analysis\master.R --rerun-pillars
   ```

   This is not optional for v0.3.0: the Tier-1a coverage columns depend on
   the corrected SEs. Expect `sigma_cov` to move from 0.51-0.83 toward 0.95
   -- that movement is itself a direct empirical validation of the Jacobian
   fix, worth a sentence in the comparison note. `fstat` medians will also
   drop (CD min-eig vs trace).
3. Regenerate summaries and README:

   ```powershell
   Rscript analysis\master.R
   Rscript scripts\build_readme.R
   ```

4. Run the comparison (script: `analysis/compare_runs.R`):

   ```powershell
   Rscript analysis\compare_runs.R `
     --old-stage1  data\derived_v020\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
     --new-stage1  data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
     --old-stage2b data\derived_v020\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds `
     --new-stage2b data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds `
     --out docs\methodology\v020_v030_comparison.md
   ```

   Expected signature (deviations are worth investigating before publishing):
   - gamma median UP from 0.238 (prior-scale fix removes the downward pull);
   - Stage-1 sigma median ~unchanged (gap-guard cells only; 2.875 should
     barely move);
   - sigma_se median UP, rho_se median sharply DOWN (Jacobian fix);
   - stockyogo_pass share DOWN, fstat_kp median DOWN (properly conservative
     min-eig statistic);
   - sigma_robust share recomposed -- two opposing forces (larger corrected
     sigma_se fails more pole tests; omega-only-capped cells become eligible),
     net sign ambiguous ex ante;
   - adjust = 4 share up slightly, adjust = 5 down (precedence change);
   - elast median in the new README ~= 1/(new gamma median).

   Add a short prose header to the .md interpreting the table, then commit it
   under docs/methodology/.
5. Manifest: regenerate sha256/size for every changed file, preserving the
   column layout (`local_path, hf_url, sha256, size_bytes, produced_by,
   pillar, description`). PowerShell has native hashing:

   ```powershell
   Import-Csv data\manifest.csv | ForEach-Object {
     if (Test-Path $_.local_path) {
       $_.sha256     = (Get-FileHash $_.local_path -Algorithm SHA256).Hash.ToLower()
       $_.size_bytes = (Get-Item $_.local_path).Length
     }
     $_
   } | Export-Csv data\manifest.csv -NoTypeInformation
   ```

   Then run `Rscript scripts\download_outputs.R --verify-only` style check if
   available, or re-run the checksum block by loading the manifest against
   the local files, to confirm the CSV round-tripped cleanly (Export-Csv
   quotes all fields, matching the current file's style; eyeball the diff).

## Phase 5 -- publish

1. Commit the data + summaries + README + manifest + comparison note as
   `data: v0.3.0 rerun (corrected SEs, omega-scale priors, gap guard, CD
   screen)`. The pre-commit hook enforces README/template/JSON sync.
2. Tag and push:

   ```powershell
   git tag v0.3.0
   git push origin main --tags
   ```

3. HF upload (dataset repo `impex-machina/trade-elasticities`):

   ```powershell
   huggingface-cli upload impex-machina/trade-elasticities `
     data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
     stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds --repo-type dataset
   # repeat for stage2a / stage2b files and the updated card
   ```

   Then spot-check the `hf_url` resolve links in the manifest and note the
   pre-v0.3.0 HF revision hash in the card so v0.2.0 consumers can pin.
4. Downstream hygiene: any Tarifflation analyses that pulled v0.2.0 gammas
   should be flagged for re-pull -- levels shift up, and anything using
   gamma_se_total or sigma_robust screens is affected.

## Checklist

- [ ] PR merged; CI green
- [ ] HF card updated with known-issues note (pre-rerun)
- [ ] Fresh key pair created, stored outside OneDrive
- [ ] Raw cache located and copied; cache hit confirmed in log
- [ ] "gamma (omega-scale) median" sanity line ~0.3
- [ ] Run complete; outputs uploaded to NEW prefix; instance terminated
- [ ] Pillars re-run; sigma_cov moved toward 0.95
- [ ] master.R + build_readme.R; hook invariant holds
- [ ] Comparison note generated and reviewed against expected signature
- [ ] Manifest checksums regenerated and verified
- [ ] Commit + tag v0.3.0 + push
- [ ] HF files + card uploaded; v0.2.0 revision pinned in card
- [ ] Downstream Tarifflation consumers notified
