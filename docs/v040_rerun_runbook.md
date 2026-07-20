# Estimation rerun runbook -- v0.4.0 (delta over v0.3.0)

Base document: `docs/v030_rerun_runbook.md`. Every instruction there applies
verbatim unless amended here -- especially the [OBSERVED/CORRECTED/DECIDED/
FOUND LIVE] annotations, which encode failure modes actually hit. Read that
file first; this delta covers only what v0.4.0 changes: the code baseline,
the expected output signature (sigma bit-identical, gamma moves), the
rerun-day patch (part 3), and three new local steps (structural-DGP pillar
JSON, lambda diagnostic, v030-vs-v040 comparison).

Production invariants unchanged: r7a.16xlarge in us-east-1; AMI
`r-trade-elast-baci-hs92-v202601-hs4-ready` = ami-03b47f485ae27255e
(R 4.5.3); work out of /tmp (or ~ if the instance might be stopped rather
than terminated); `aws s3 cp`, never `sync`; local AWS CLI uses only the
`default` profile; canonical v0.2.0 outputs under
`s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/` are
read-only; the v0.3.0 run prefix is likewise not to be overwritten.

## What this rerun is

- Code baseline: main after merging `fix/v040-eq10-gs-alignment`
  (part 1 = 4485a84 Eq. 10 fix + G&S screen alignment; part 2 = 635192d
  structural-DGP pillar + gamma_shrink_wt + hardening). Verify both
  hashes in `git log` on the box before launching the run.
- The only estimation-path changes are Stage-2-side (Eq. 10 term-4
  coefficient; omega_capped exclusion from the Stage-2a priors). Stage 1's
  point path is untouched, so under the same stack the sigma table must be
  BIT-IDENTICAL to v0.3.0. That A/B is itself a release artifact: verify
  it first (Phase 4 step 2), cite it in the comparison note and the data
  commit.
- New columns land only via this rerun. Stage 1: `stockyogo_pass_gs25`,
  `stockyogo_cv_gs25`, `sargan_pass`, `gs_pass_both`. Stage 2b:
  `gamma_shrink_wt`.
- F10 (validation-only; part 2.5) must be merged before `--rerun-pillars`:
  the Pillar-2 harness's reduced form carried supply slope 1/omega instead
  of (1+omega)/omega, so its omega truth-labels corresponded to structural
  omega = omega_0/(1-omega_0). The estimator and published estimates were
  never affected (population-moment proof: pre-fix data labeled (3, 0.3)
  returned exactly (3.0000, 0.4286)); the tier1a/1b omega-bias and
  omega-coverage columns were computed against the wrong truth, and the
  old "omega flooring at high true omega" reading is retracted as a
  mislabeling artifact (label grid {0.3, 1.0, 3.0} implied structural
  omega {0.429, +Inf, -1.5}).
- Tuning constants FROZEN to isolate the Eq. 10 fix: do NOT pass
  `--shrinkage-lambda` (2b default 0.1; 2a hardcoded 0.05). The lambda
  calibration targets are recomputed as a DIAGNOSTIC only (Phase 4 step 8);
  any retune is a separate later release.
- Expected wall-clock: comparable to v0.3.0 (the corrected coefficient
  costs the same flops; new columns are O(1) bookkeeping).

## Phase 0 -- before launching (local)

1. Merge the PR into main; CI green on the merge commit.
2. HF card pre-rerun note: pin the current dataset revision hash and
   announce the forthcoming v0.4.0 changelog, leading with "gamma and
   opt_tariff will change (supply-side moment-equation correction); sigma
   will not."
3. Key pair `te-v030`, security group `te-estimation-ssh`, instance
   profile `ec2-s3-access`: all unchanged from v0.3.0. On launch day,
   re-edit the SG inbound source to My IP (v030 section 0.6 -- a stale
   source presents as an SSH timeout).
4. New S3 prefix for this run: 
   `s3://trade-elast-baci-hs92-v202601-hs4/v040_run_<YYYYMMDD>/`
   (stamp with the actual launch date).
5. Do NOT apply `apply_v040_part3_rerunday.ps1` yet. It belongs in
   Phase 4 step 3: the template placeholders it adds fail
   `build_readme.R` (and the pre-commit hook) until 00_setup has been run
   against the NEW Stage-1 output. This ordering is the CI lock working
   as designed, not a defect.

## Phase 1 -- launch + SSH

Launch IN THE CONSOLE as the admin identity (the CLI key/launch routes are
deliberately unavailable to impex-machina-local): EC2 -> us-east-1 ->
Images -> AMIs -> Owned by me -> `r-trade-elast-baci-hs92-v202601-hs4-ready`
(ami-03b47f485ae27255e) -> Launch instance from AMI -> r7a.16xlarge ->
key pair `te-v030` -> security group `te-estimation-ssh` (SELECT EXISTING)
-> Advanced details -> IAM instance profile `ec2-s3-access` -> keep the
100 GB gp3 root. Do NOT launch `r-soderbery-2018-extension-ready`.

```powershell
# PowerShell -- local. Launch happens IN THE CONSOLE (above); nothing here
# starts the instance. After launch, get <PUBLIC_IP> from the console:
# select the instance -> Details -> "Public IPv4 address". The CLI query
# below is an OPTIONAL alternative for retrieving the same IP (handy if
# the console tab is closed, or after a stop/start rotates the IP);
# default profile only:
#   aws ec2 describe-instances --region us-east-1 `
#     --filters "Name=instance-state-name,Values=running" "Name=key-name,Values=te-v030" `
#     --query "Reservations[].Instances[].[InstanceId,PublicIpAddress,InstanceType]" `
#     --output table

# SSH in (imported ed25519 key -- no .pem extension):
ssh -i "$env:USERPROFILE\.ssh\te-v030" ubuntu@<PUBLIC_IP>
# If "UNPROTECTED PRIVATE KEY FILE":
#   icacls "$env:USERPROFILE\.ssh\te-v030" /inheritance:r /grant:r "${env:USERNAME}:R"
```

First-session hygiene on the box (AMI not yet re-baked, so v030 sections
1.2-1.4 still apply in full):

```bash
# bash -- EC2 only
df -h; nproc; free -g
R --version | head -1                  # expect 4.5.3 -- confirms the right AMI
grep te-v030 ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys && cat ~/.ssh/authorized_keys   # exactly one line
ls -la ~/.aws/ 2>/dev/null && mv ~/.aws /tmp/stale_aws_config_$(date +%s)
aws sts get-caller-identity            # expect ...assumed-role/ec2-s3-access/i-...
mkdir -p /tmp/v040/out /tmp/v040/BACI_HS92_V202601 && cd /tmp/v040
```

If the run might be STOPPED rather than terminated at any point, stage
under `~` instead of /tmp (v030 appendix lesson 1: /tmp does not survive a
stop; a stop also rotates the public IP -> refresh the SG source again).

## Phase 2 -- run

```bash
# bash -- EC2 only
cd /tmp/v040
git clone https://github.com/impex-machina/trade-elasticities.git
cd trade-elasticities && git log --oneline -8
# MUST show 635192d and 4485a84 (plus the merge). If not: wrong branch/state -- stop.
```

Stage the canonical raw cache (pre-difference artifact, untouched by every
v0.4.0 patch -- F1/F2 act at estimation, not caching -- so the v0.2.0-era
cache remains valid):

```bash
aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/stage1/baci_hs92_v202601_elast_country_hs4_raw_cache.rds \
  /tmp/v040/out/baci_hs92_v202601_elast_country_hs4_raw_cache.rds
find /tmp/v040/out -type f     # exactly ONE ~918 MB file, FLAT (no stage1/)
```

renv posture and package scan exactly per v030 section 2.6, with appendix
lesson 2: the site library is root-owned, so the scan-and-install runs
under sudo. Fresh instances ALWAYS need the scan (AMI predates optparse,
jsonlite, glue, ggplot2). Numeric stack (data.table/Rcpp) is unchanged
since v0.2.0 -- this is what carries the sigma A/B.

Launch:

```bash
cd /tmp/v040/trade-elasticities
nohup env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript scripts/run_estimation.R \
  --data /tmp/v040/BACI_HS92_V202601 --out-dir /tmp/v040/out \
  > /tmp/v040/run.log 2>&1 &
tail -n 40 -f /tmp/v040/run.log
```

Tripwires, in order:
1. "Country output base: .../baci_hs92_v202601_elast_country_hs4" (tag
   parsed from the --data PATH STRING; if the tag is missing, kill and fix
   the path -- v030 section 2.3a).
2. "Loading cached raw data..." within the first minute (cache hit).
3. Stage-1 -> Stage-2 translation prints "gamma (omega-scale) median"
   ~0.3, SAME as v0.3.0 -- Stage 1 is unchanged; a different value here
   means the wrong code or stack. This is the first live A/B checkpoint.
4. The Stage-2a banner prints lambda = 0.05 (banner fix shipped in the
   v0.3.0 arc).
5. Stage-2a/2b gammas will DIFFER from v0.3.0 -- that is the point.
   Do not "fix" it on the box.

## Phase 3 -- upload + terminate

```bash
aws s3 cp /tmp/v040/out/ s3://trade-elast-baci-hs92-v202601-hs4/v040_run_<YYYYMMDD>/ --recursive
aws s3 cp /tmp/v040/run.log s3://trade-elast-baci-hs92-v202601-hs4/v040_run_<YYYYMMDD>/run.log
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/v040_run_<YYYYMMDD>/ --recursive --human-readable
```

Verify counts/sizes against the local dir; terminate the instance.
OPTIONAL POST-ARC (recommended, carried over from v030 section 1.4): before
terminating, purge `~/.aws`, stale `authorized_keys` entries, `~/work`,
`~/code-fresh`, `~/estimation`, then Console -> create image
(`r-trade-elast-...-ready-v2`) so the hygiene steps retire from future
launches. If re-baking, do it from a CLEAN instance state (no run
artifacts in ~).

## Phase 4 -- local regeneration (ORDER MATTERS)

1. Preserve v0.3.0: rename `data/derived` -> `data/derived_v030`. Download
   the v040 stage1 / stage2a / stage2b .rds (+ summary .txt/.csv) into a
   fresh `data/derived/` mirroring the manifest `local_path` layout.
2. FIRST verification -- the sigma A/B, before anything else:

   ```powershell
   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" -e "suppressMessages(library(data.table)); old <- readRDS('data/derived_v030/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds'); new <- readRDS('data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds'); shared <- intersect(names(old), names(new)); data.table::setcolorder(new); cat('rows:', nrow(old), 'vs', nrow(new), '\n'); cat('bit-identical on shared cols:', identical(old[, shared, with=FALSE], new[, shared, with=FALSE]), '\n'); cat('new cols:', paste(setdiff(names(new), names(old)), collapse=', '), '\n')"
   ```

   Expect: identical TRUE; new cols exactly `stockyogo_pass_gs25,
   stockyogo_cv_gs25, sargan_pass, gs_pass_both`. If NOT identical, STOP
   -- the stack or Stage-1 path differs; diagnose before interpreting any
   Stage-2 delta. (Row order should match since the driver is
   deterministic; if identical() fails, first check with setkey on
   (importer, good) before concluding the values differ.)
   [OBSERVED 2026-07-19] The one-liner requires the data.table namespace
   loaded: `data.table::setcolorder(new)` happens to load it, registering
   `[.data.table`. A variant that drops that call dispatches
   `[.data.frame` and fails with "unused argument (with = FALSE)". The
   command above now loads data.table explicitly rather than by side
   effect.
3. Apply part 3 NOW:

   ```powershell
   powershell -ExecutionPolicy Bypass -File apply_v040_part3_rerunday.ps1 -DryRun
   powershell -ExecutionPolicy Bypass -File apply_v040_part3_rerunday.ps1
   ```

   (3 edits: README.template.md G&S-shares sentence; analysis/00_setup.R
   new JSON fields; plus this runbook and the comparison header draft as
   new files if not already present. Commit comes later with the full data
   series -- the hook requires README/JSON sync, which needs steps 4-6.)
4. Pillars, single pass: `Rscript analysis\master.R --rerun-pillars`
   (~25-60 min). [CORRECTED 2026-07-19] Every tier1a/1b column
   changes relative to the committed v0.3.0 CSVs (last regenerated in the
   v0.3.0 data commit, 4d7565a): F10 corrects the harness's
   data-generating supply slope, so the seeded simulation produces
   different systems and the sigma-side columns move too. Do not expect a
   pillar-level sigma A/B against the committed CSVs. The
   Stage-1-unchanged claim is carried by the production sigma A/B (step
   2) plus a hunk review of the Stage-1 source diff v0.3.0 -> release rev
   (expected content: the four new diagnostic columns, the maximal-size
   rename, and the perfect-fit weight-floor hardening -- all path-inert,
   as the byte identity demonstrates). The omega-bias/coverage columns
   are additionally computed against corrected truth for the first time. Record the new omega ranges in the comparison note; their
   movement is the fix working, not drift.
5. NEW -- structural-DGP pillar, full mode, on the release tree; commit
   its JSON with the data series:

   ```powershell
   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" validation\stage2_structural_dgp.R --seed 20260717 --out results\stage2_dgp_summary.json
   ```

   Expect OVERALL: PASS (reference full-mode signature from the pre-rerun
   verification: max truth residual ratio 0.0028, min perturbation
   separation 34.6x, recovery biases 0.002) with the release git rev in
   `meta`.
6. `Rscript analysis\master.R` then `Rscript scripts\build_readme.R`.
   The README now renders the 10%-vs-25% Stock-Yogo sentence with live
   shares. Sanity: the gs25 pass share should sit WELL above the 17.3%
   strict-threshold share (the post-fix median first-stage statistic 2.08
   lies between cv_0.10 ~3.55-3.6 and cv_0.25 ~1.75-2.1 at common
   exporter counts). If gs25 ~= the 0.10 share, the new columns did not
   populate -- stop and check the RDS.
7. Comparison:

   ```powershell
   Rscript analysis\compare_runs.R `
     --old-stage1  data\derived_v030\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
     --new-stage1  data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
     --old-stage2b data\derived_v030\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds `
     --new-stage2b data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds `
     --out docs\methodology\v030_v040_comparison.md
   ```

   Then merge the prose from
   `docs/methodology/v030_v040_comparison_header_draft.md` above the
   generated table and fill its TODO slots from the table. Expected
   signature: sigma block all-zero deltas (cite as the A/B); gamma level
   and dispersion move -- direction was NOT predicted a priori, record it,
   do not rationalize post hoc; opt_tariff moves with gamma; the
   Soderbery Table-2 ratios re-report (v0.3.0 anchors 0.405/0.532/0.204
   vs paper 0.408/0.532/0.217 -- the third composes gamma and sigma and
   is the one to watch); sigma_robust and gamma_se_total shift through
   dgamma_dsigma; gamma_shrink_wt is NEW -- report quantiles by tier.
8. Lambda diagnostic (report-only; lambda stays frozen this release):

   ```powershell
   Rscript analysis\lambda_diagnostic.R --label v0.4.0 --out results\lambda_diagnostic_v040.json
   ```

   computes regional-vs-country gamma agreement (two pairings x two tier
   filters: pair MAD and R^2) under the fixed definition documented in
   the script header. Compare against the v0.3.0 baseline produced in
   pre-launch prep (results/lambda_diagnostic_v030.json). The original
   calibration session's pairing code was never committed, so THAT
   BASELINE -- not the remembered ~0.125 / ~0.72 -- is the reference.
   The Eq. 10 fix changes gamma dispersion, which is exactly what these
   statistics key on, so drift is EXPECTED; record both JSONs in the
   comparison note, and if drift is material schedule a v0.5.x
   recalibration as its own change with its own A/B.
   Optional: `Rscript analysis\sensitivity_sweep.R` re-checks the
   sigma_robust thresholds on the new 2b.
9. Manifest rehash per v030 section 4.5 -- REMEMBER the buffered-read
   lesson (materialize Import-Csv before Export-Csv to the same file).
   Re-verify checksums against disk after any subsequent copy.

## Phase 5 -- publish

1. Commit data + results JSONs (including stage2_dgp_summary.json) +
   README + manifest + comparison note in one series. Suggested message:
   `data: v0.4.0 rerun (corrected Eq. 10 supply-side moments; G&S screens; DGP pillar)`
   Body must state: sigma bit-identical to v0.3.0 (A/B verified); gamma/
   opt_tariff deltas with the headline numbers; run posture ("AMI library,
   renv autoloader disabled; numeric stack identical to v0.2.0/v0.3.0").
2. Tag and push: `git tag v0.4.0; git push origin main --tags`. CI green.
3. HF upload (changed data files + card), per v030 section 5.3. The card
   changelog leads with: gamma- and opt_tariff-affecting correction of the
   Soderbery (2018) Eq. (10) term-4 coefficient -- a transcription error
   in this repo's implementation from the paper text (no Soderbery 2018
   replication code exists; the port was from the paper alone), caught by
   independent derivation and locked by a new structural-DGP validation
   pillar; sigma unchanged. Pin the pre-v0.4.0 revision hash for
   consumers who need the old gammas.
4. Downstream: Tarifflation analyses consuming gamma, opt_tariff,
   gamma_se_total, sigma_robust, or the SY screens must re-pull.
   Sigma-only consumers are unaffected -- say so explicitly.

## Checklist (v0.4.0)

- [ ] PR merged to main; CI green; hashes 4485a84 + 635192d in history
- [ ] HF card pre-rerun note posted with pinned revision
- [ ] SG inbound source refreshed to current IP; key + instance profile confirmed
- [ ] Instance launched from ami-03b47f485ae27255e; R 4.5.3 confirmed
- [ ] authorized_keys pruned; stale ~/.aws quarantined; caller-identity = ec2-s3-access
- [ ] Clone shows both v0.4.0 commits; raw cache staged FLAT in tagged layout
- [ ] Cache hit + tag-parse tripwires in log; "gamma (omega-scale) median" ~0.3
- [ ] Run complete; outputs on v040_run_<date> prefix; instance terminated
- [ ] (optional) clean AMI re-baked
- [ ] data/derived_v030 preserved; new outputs staged locally
- [ ] SIGMA A/B: bit-identical TRUE; exactly 4 new Stage-1 columns
- [ ] Part 3 applied (template + 00_setup + docs)
- [ ] Pillars single-pass; Tier-1a sigma-side columns bit-identical; omega columns re-based per F10
- [ ] DGP pillar full-mode PASS; results/stage2_dgp_summary.json emitted
- [ ] README regenerated; gs25 share >> 17.3% sanity holds
- [ ] Comparison generated; header merged; TODOs filled; lambda diagnostic recorded
- [ ] Manifest rehashed (buffered read); checksums verified
- [ ] Commit + tag v0.4.0 + push; CI green
- [ ] HF data + card updated; old revision pinned in changelog
- [ ] Downstream consumers notified (sigma-only consumers explicitly cleared)

