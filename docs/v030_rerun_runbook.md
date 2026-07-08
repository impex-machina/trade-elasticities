# Estimation rerun runbook (v0.3.0-hardened)

Full Stage 1 -> 2a -> 2b regeneration, followed by local re-derivation of
validation pillars, summaries, README, manifest, and HF publication.
This is the repo template, hardened by the live v0.3.0 execution
(2026-07-08): every instruction marked [OBSERVED/CORRECTED/DECIDED/FOUND
LIVE 2026-07-08] encodes a failure mode actually hit during that run --
do not remove the annotations; they are the reason the instruction exists.
For the next rerun: replace date stamps (v030_run_<YYYYMMDD>), re-check
IP-bound security-group rules, and read the "lessons" annotations before
improvising. The v0.3.0 execution record (checklist states, exact values)
lives in the git history of this file and in the chat-derived local copy.

Infrastructure names (S3 bucket, AMI) are real and retained deliberately:
they are already public via the v0.3.0 data-commit message, and access
control rests on IAM, not obscurity.

Production invariants carried over from the v0.2.0 arc (do not relitigate):
r7a.16xlarge in us-east-1; AMI `r-trade-elast-baci-hs92-v202601-hs4-ready` = ami-03b47f485ae27255e (R 4.5.3; console shorthand used to be 'r-estimation-ready'); work out of
`/tmp/`, never `~/work/` (stale baked-in state); `aws s3 cp`, never `sync`;
local AWS CLI uses only the `default` profile; canonical v0.2.0 outputs live
under `s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/` and
must not be overwritten.

---

## Phase 0 -- before launching (local)

1. Merge the fix series into main; confirm CI green on both the PR run and
   the main push before anything else. (v0.3.0: merged as `4d40514`; first
   green since early June -- the stale e2e contract had been the blocker.)
2. Post the HF card pre-rerun note (known issues + forthcoming changelog) so
   current-data consumers are warned while the rerun is in flight, and pin
   the current revision hash in it. (v0.3.0: `c840a751`, then `f8d81700`
   citing pin `7e598f6cb98e`.)
3. Key pair (console route -- the CLI route is DEAD on this machine:
   impex-machina-local lacks ec2:CreateKeyPair, by design; do not widen it):

   a. Generate locally, outside OneDrive:

      ```powershell
      # PowerShell -- local
      ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\te-v030" -C "te-v030"
      Get-Content "$env:USERPROFILE\.ssh\te-v030.pub" | Set-Clipboard
      ```

      (v0.3.0 key: te-v030, ed25519,
      fingerprint SHA256:M8npZV8W74yuTTilHMRs2R2ul8kpOVyeRMP3hP/IQRE)

   b. Import in the AWS Console AS THE ADMIN IDENTITY:
      EC2 -> region us-east-1 -> Key Pairs -> Actions -> Import key pair ->
      name `te-v030` -> paste .pub -> Import. Verify the fingerprint matches
      the one above.

   c. If Windows ssh complains "UNPROTECTED PRIVATE KEY FILE" on first use:

      ```powershell
      # PowerShell -- local
      icacls "$env:USERPROFILE\.ssh\te-v030" /inheritance:r /grant:r "${env:USERNAME}:R"
      ```

4. New S3 prefix: `s3://trade-elast-baci-hs92-v202601-hs4/v030_run_<YYYYMMDD>/`
   -- stamp with the ACTUAL launch date on the day.
5. Confirm the raw cache exists under the canonical prefix (v0.3.0 observed
   917,536,992 bytes):
   `s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/stage1/baci_hs92_v202601_elast_country_hs4_raw_cache.rds`
   It is a pre-difference artifact untouched by all six patches (the gap
   guard applies at moment construction, not caching), so copying it into
   the run's out-dir skips the multi-hour load/clean/aggregate step.
6. Launch-day console prerequisites (admin identity):
   - Security group: `te-estimation-ssh` (create once: inbound SSH from
     My IP, outbound default allow-all; VPC vpc-0cea54ba04e8aa7c3). On
     launch day, re-edit inbound source -> My IP -- residential IPs drift,
     and a stale source presents as an SSH timeout. Do NOT let the wizard
     create another launch-wizard-N group (26 exist already; select
     existing instead). Post-arc cleanup snippet lives in the chat log.
   - IAM instance profile: `ec2-s3-access` [IDENTIFIED 2026-07-08 --
     trusted by ec2.amazonaws.com, last active early June = the v0.2.0
     sessions]. The instance's S3 access comes from this profile, never
     from local keys copied onto the box. Wizard location: Advanced
     details -> IAM instance profile.

## Phase 1 -- launch

1. Launch IN THE CONSOLE (admin identity). Easiest path that avoids the
   wizard's AMI picker entirely: EC2 -> Images -> AMIs -> Owned by me ->
   select `r-trade-elast-baci-hs92-v202601-hs4-ready`
   (ami-03b47f485ae27255e) -> "Launch instance from AMI". Then in the
   wizard: r7a.16xlarge (64 vCPU / 512 GiB), us-east-1, key pair
   `te-v030`, security group `te-estimation-ssh` (SELECT EXISTING -- do
   not create new), IAM instance profile `ec2-s3-access` (Advanced
   details), EBS: keep the AMI default 100 GB gp3 root (ample: cache
   ~1 GB, outputs a few GB). The /dev/sdb, /dev/sdc ephemeral mappings
   are inert on r7a (no instance store) -- ignore them.
   NOTE: do NOT launch `r-soderbery-2018-extension-ready` -- that is the
   retired soderbery-extension project's image.
2. SSH in; verify the clock is right and disk is where you expect:

   ```bash
   # bash -- EC2 only
   ssh -i ~/.ssh/te-v030 ubuntu@<INSTANCE_IP>    # no .pem -- imported ed25519 key
   df -h; nproc; free -g
   R --version | head -1        # expect 4.5.3 -- confirms the right AMI
   ls ~/work 2>/dev/null        # stale v0.2.0 state expected; do NOT use it
   mkdir -p /tmp/v030/{baci,out} && cd /tmp/v030
   ```

3. Prune stale authorized keys. The AMI was baked from a v0.2.0-era
   instance, so ~/.ssh/authorized_keys may still contain the OLD public key
   (whose private half was OneDrive-exposed and deleted). Keep only te-v030:

   ```bash
   # bash -- EC2 only
   cat ~/.ssh/authorized_keys        # inspect: cloud-init appends te-v030 at launch
   grep te-v030 ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   cat ~/.ssh/authorized_keys        # expect exactly one line, comment te-v030
   ```

   Do this in your FIRST session, before starting the run -- if the grep
   somehow empties the file, you still have the live session to fix it.

4. Purge stale baked AWS credentials [FOUND LIVE 2026-07-08: caused 403 on
   the first s3 cp]. The AMI carries a pre-hygiene ~/.aws/credentials with
   the OLD (rotated, dead) impex-machina-local key; the credential chain
   consults it BEFORE the instance profile, shadowing ec2-s3-access:

   ```bash
   # bash -- EC2 only
   ls -la ~/.aws/ 2>/dev/null && mv ~/.aws /tmp/stale_aws_config_$(date +%s)
   aws sts get-caller-identity
   # expect Arn ...assumed-role/ec2-s3-access/i-... ; if instead
   # "Unable to locate credentials", attach the role via Console ->
   # Instances -> Actions -> Security -> Modify IAM role -> ec2-s3-access
   ```

   POST-ARC: re-bake a clean AMI (purge ~/.aws, stray authorized_keys,
   ~/work) so steps 3-4 stop being necessary on every launch.

## Phase 2 -- run

1. Clone post-merge main and verify the six commits are present:

   ```bash
   git clone https://github.com/impex-machina/trade-elasticities.git
   cd trade-elasticities && git log --oneline -7
   ```

2. `TRADE_ELAST_SRC` is no longer required (patch 5 added the repo-relative
   fallback). Remove it from any saved launch scripts so nothing points at a
   stale source copy.
3. Stage inputs -- CACHE FIRST, BACI CSVs ONLY IF THE CACHE MISSES.
   [CORRECTED LIVE 2026-07-08 after two wrong inferences:]
   (a) The dataset tag `baci_hs92_v202601` is regex-parsed from the
       --data PATH STRING (parse_baci_source, R/output_paths.R:
       `BACI_HS\d{2}_V\d{6}` anywhere in the path) -- NOT from the
       directory contents. The data dir must therefore be NAMED to
       match, e.g. /tmp/v030/BACI_HS92_V202601. An untagged path falls
       back to `baci` and every output/cache name is wrong.
   (b) The runner's on-disk layout is FLAT under --out-dir
       (raw_cache_file = <out_base>_raw_cache.rds). The stage1/
       subfolders on S3 are the PUBLICATION layout only.
   `--data` validation only checks the directory exists
   (parse_cli.R:140); with a cache hit the CSVs are never read.

   ```bash
   # bash -- EC2 only
   mkdir -p /tmp/v030/BACI_HS92_V202601     # empty; the NAME carries the tag
   aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/stage1/baci_hs92_v202601_elast_country_hs4_raw_cache.rds \
     /tmp/v030/out/baci_hs92_v202601_elast_country_hs4_raw_cache.rds
   ls -la /tmp/v030/out/    # expect the one ~918 MB file, FLAT (no stage1/)
   ```

   Launch with `--data /tmp/v030/BACI_HS92_V202601`. TRIPWIRES, in
   order: the banner's "Country output base:" must read
   .../baci_hs92_v202601_elast_country_hs4 (tag parsed), then
   "Loading cached raw data..." within the first minute. If the base
   reads .../baci_elast_country_hs4 the tag failed -- kill and fix the
   --data path. Only if the cache cannot be made to hit, pull the CSVs
   as fallback INTO THE TAGGED DIR:

   ```bash
   # bash -- EC2 only (FALLBACK ONLY)
   aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/<BACI_PREFIX>/ /tmp/v030/BACI_HS92_V202601/ --recursive
   ```

4. The out-dir must contain ONLY the raw cache (flat, no subfolder).
   `--stage all` resumes from any cached stage outputs it finds; a leftover
   sigma file would silently skip Stage 1. Verify:
   `find /tmp/v030/out -type f` returns exactly the one cache file.
5. Keep tuning constants fixed to isolate the bug fixes: do NOT pass
   `--shrinkage-lambda` (2b default 0.1; the 2a value stays hardcoded at
   0.05). Any lambda recalibration is a separate, later exercise.
6. renv posture [DECIDED LIVE 2026-07-08]: the fresh clone activates renv
   with an EMPTY project library ("no package called data.table"). Run
   with RENV_CONFIG_AUTOLOADER_ENABLED=FALSE to use the AMI system
   library instead -- deliberately: those are the EXACT package versions
   that produced v0.2.0, so version drift is removed as a confounder in
   the v0.2.0-vs-v0.3.0 comparison. Pre-flight:

   ```bash
   # bash -- EC2 only
   export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE
   Rscript -e 'for (p in c("data.table","Rcpp","optparse","jsonlite","glue")) cat(sprintf("%-12s %s\n", p, requireNamespace(p, quietly=TRUE)))'
   ```

   [OBSERVED 2026-07-08] AMI library has the computational stack
   (data.table, Rcpp -- the packages that determine numerics) but lacks
   utility packages added during the repo re-architecture (optparse,
   jsonlite, glue, ggplot2 + deps, ...). Do NOT install piecemeal: scan
   the sourced tree for every library()/require() target and install all
   missing at once (Ncpus=32; a few minutes). All additions are
   reporting/plotting plumbing downstream of the estimates, so v0.2.0
   numeric comparability holds:

   ```bash
   # bash -- EC2 only
   cd /tmp/v030/trade-elasticities
   Rscript - <<'EOF'
   files <- unlist(lapply(c("R","scripts","src"), list.files,
                          pattern = "[.]R$", full.names = TRUE))
   hits <- unlist(lapply(files, function(f) {
     x <- readLines(f, warn = FALSE)
     m <- regmatches(x, gregexpr('(library|require|requireNamespace)\\(["\']?[A-Za-z0-9.]+', x))
     sub('.*\\(["\']?', '', unlist(m))
   }))
   pkgs <- setdiff(unique(hits), c("", rownames(installed.packages())))
   cat("missing:", if (length(pkgs)) paste(pkgs, collapse = ", ") else "none", "\n")
   if (length(pkgs)) {
     lib <- Sys.getenv("R_LIBS_USER")
     dir.create(lib, recursive = TRUE, showWarnings = FALSE)
     options(Ncpus = 32)
     install.packages(pkgs, lib = lib, repos = "https://cloud.r-project.org")
   }
   EOF
   ```

   Re-run the scan until it reports "missing: none", then launch as
   below. If a package fails to compile on a missing system header,
   apt-get the header or use the full fallback.
   Full fallback if anything fails to compile:
   `Rscript -e 'options(Ncpus=32); renv::restore(prompt=FALSE)'` and
   launch WITHOUT the env var.

7. Launch under nohup (note the TAGGED --data path):

   ```bash
   cd /tmp/v030/trade-elasticities
   nohup env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript scripts/run_estimation.R \
     --data /tmp/v030/BACI_HS92_V202601 --out-dir /tmp/v030/out \
     > /tmp/v030/run.log 2>&1 &
   tail -n 40 -f /tmp/v030/run.log
   ```

   Record the posture in the v0.3.0 data-commit message ("AMI library,
   renv autoloader disabled; package versions identical to v0.2.0").

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
2. Re-run the validation pillars (~25-60 min depending on hardware):

   ```powershell
   Rscript analysis\master.R --rerun-pillars
   ```

   As of the post-v0.3.0 fix, this is SINGLE-PASS: master.R runs the
   harnesses before 00_setup, refreshes docs/methodology CSVs, syncs them
   to data/derived/validation/, and emits consistent JSONs -- no second
   pass, no manual copy. What to check afterwards: the Tier-1a
   point-path columns (success_rate, sigma_med, biases) should be
   BIT-IDENTICAL to the previous release when only diagnostics changed
   (seeded harness, unchanged estimator path) -- that A/B is itself
   evidence; only SE-dependent columns (sigma_cov, omega_cov, med_fstat)
   move. NOTE [CORRECTED 2026-07-08]: do NOT expect coverage to approach
   0.95 after an SE fix -- Tier-1a coverage is bound by conditional
   small-sample bias under weak identification, not by SE calibration
   (an interval centered 30-75% from truth cannot cover at 95% however
   correct its width). SE calibration is validated by Pillar 3 and the
   analytic Jacobian check, not by this table.

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

   Reference signature -- the v0.3.0 observed deltas (a future rerun on
   unchanged code should show ~none of these; deviations mean something
   changed):
   - gamma median 0.238 -> 0.680; implied export-supply elasticity
     4.2 -> 1.47 (prior-scale fix); structural ratios on Soderbery
     Table 2 (0.405 / 0.532 / 0.204 vs 0.408 / 0.532 / 0.217);
   - sigma median ~unchanged (2.875 -> 2.878); ok cells -5.2% (gap guard);
   - sigma_se +38% median, rho_se -66% (corrected Jacobian);
   - stockyogo_pass 59.3% -> 17.3%, fstat_kp median 4.50 -> 2.08
     (min-eig CD); sigma_robust 16.5% -> 10.6% (corrected sigma_se
     dominated the newly-eligible omega-capped cells);
   - clean-SE share 58.7% -> 64.9% (scale-consistent priors improved
     optimizer health);
   - adjust semantics: code 4 = sigma capped (now equals the sigma==10
     share exactly), code 5 = omega-only; use sigma_capped/omega_capped
     for cross-version comparisons.

   Add a short prose header to the .md interpreting the table, then commit it
   under docs/methodology/.
5. Manifest: regenerate sha256/size for every changed file, preserving the
   column layout (`local_path, hf_url, sha256, size_bytes, produced_by,
   pillar, description`). PowerShell has native hashing:

   ```powershell
   # CORRECTED 2026-07-08: materialize the read BEFORE writing. The
   # streaming form (Import-Csv file | ... | Export-Csv samefile)
   # truncates the file mid-read and empties it -- recover with
   # `git restore data\manifest.csv` if it ever happens again.
   $rows = Import-Csv data\manifest.csv
   foreach ($r in $rows) {
     if (Test-Path $r.local_path) {
       $r.sha256     = (Get-FileHash $r.local_path -Algorithm SHA256).Hash.ToLower()
       $r.size_bytes = (Get-Item $r.local_path).Length
     }
   }
   $rows | Export-Csv data\manifest.csv -NoTypeInformation
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

## Checklist (template -- v0.3.0 execution record is in this file's git history)

- [ ] Fix series merged; CI green
- [ ] HF card known-issues/changelog note posted (pre-rerun)
- [ ] Key pair present in console (us-east-1) with local private key outside OneDrive
- [ ] Security group inbound source refreshed to current IP
- [ ] IAM instance profile ec2-s3-access confirmed
- [ ] Raw cache located on S3; copied on-instance (FLAT path, tagged --data dir); cache hit in log
- [ ] "gamma (omega-scale) median" sanity line plausible at translation
- [ ] Run complete; outputs uploaded to NEW dated prefix; instance terminated
- [ ] authorized_keys pruned + stale ~/.aws quarantined on first login
- [ ] Pillars re-run (single pass); comparison note generated and reviewed
- [ ] Manifest: files current on disk BEFORE the buffered checksum pass; re-run pass after any copy
- [ ] Commit + tag + push; CI green
- [ ] HF: data files uploaded atomically; LFS sha256 verified against manifest; card updated
- [ ] Downstream consumers notified of level changes
