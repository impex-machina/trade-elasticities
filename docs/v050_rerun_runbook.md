# v0.5.0 rerun runbook — Step 6 release train (bw_lag calendar)

Base documents: `docs/v030_rerun_runbook.md` and `docs/v040_rerun_runbook.md`;
their [OBSERVED/CORRECTED/HARDENED] annotations still apply. This runbook was
drafted 2026-07-26 and executed 2026-08-18; the [OBSERVED 2026-08-18] blocks
below record what actually happened where it deviated from the plan, so the
next release does not rediscover it. Executed outcome: SHIPPED — GitHub tag
`v0.5.0` = a0b7b4f (+ card commit d4830c6), HF data revision
`ea1c3ea464ca1ac114bf9b6c518325e8135bdc41`, card commit 872ca2c5.

Session prep date: 2026-07-26. Base: `origin/main = c8e9eb5` (patches
0009–0015 live, suite 325). Companion patches delivered with this
runbook, both certified by `git am` + tree-hash onto `c8e9eb5`:

- `0016-analysis-HS4-per-cell-BW-fn-14-gap-census-for-the-v0.patch`
  — apply in **Phase 0**, BEFORE the EC2 run (the box clones it).
- `0017-fix-flip-bw_lag-CLI-default-to-calendar-v0.5.0.patch`
  — apply in **Phase 6**, ONLY after the A/B adjudicates. Do not apply
  early: until then repo HEAD must keep reproducing published v0.4.1
  under the default.

SHELL DISCIPLINE: every block below is labeled. `PS C:\...>` blocks run
in local PowerShell ONLY; `ubuntu@ip-...:$` blocks run on the EC2 box
ONLY. Pasting a bash block into PowerShell is the wrong-shell tell
(`mkdir -p` errors, `aws s3 cp` pulling to `C:\tmp`).

Design facts this runbook leans on:

- Production Stage 1 (HLIML wrapper) contains no BW weights, so σ is
  predicted **bit-identical** to v0.4.1 — that identity is the run's
  first gate. Stages 2a/2b reweight and move; the census bounds where.
- Patch 0013 means every new RDS is saved canonically sorted with
  `run_meta` stripped: file hashes change even where data is identical
  (the Stage-1 file will hash-differ while being data-identical). All
  A/B comparisons below sort both sides before `identical()`.
- The raw cache (pre-difference artifact) is untouched by every patch
  since v0.2.0 — reuse it; no BACI CSV pull needed.
- Absent-key rule: hand-built cfg lists run legacy, so validation
  captures and simulation pillars are bit-identical by design — no
  `--rerun-pillars`, no capture refresh this release.

---

## Phase 0 — local prep (PowerShell)

```powershell
# PS C:\...> — local only. Pause OneDrive sync first.
cd "C:\Users\maxxj\OneDrive\Desktop\Projects\trade-elasticities\trade-elasticities"
git log --oneline -1             # expect c8e9eb5
git am "$env:USERPROFILE\Downloads\0016-analysis-HS4-per-cell-BW-fn-14-gap-census-for-the-v0.patch"
git push origin main
git log --oneline -2             # census commit atop c8e9eb5, pushed
# Resume OneDrive. 0017 STAYS in Downloads until Phase 6.
```

Baseline safety check — confirm where v0.4.1 lives before anything gets
renamed (git + HF pin `5493c51f` are canonical; an S3 run prefix may or
may not exist):

```powershell
# PS C:\...> — local only
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/ | Select-String v04
```

---

## Phase 1 — launch + SSH (console checklist, then PowerShell)

Console (us-east-1): AMIs → `r-estimation-ready`
(`ami-03b47f485ae27255e`) → Launch instance from AMI →
**r7a.16xlarge** → key pair `te-v030` → SG `te-estimation-ssh`
(refresh the My-IP inbound source) → IAM instance profile
`ec2-s3-access` → **100 GB gp3** root. Do NOT launch
`r-soderbery-2018-extension-ready`. Copy `<PUBLIC_IP>` from
Details → Public IPv4 address.

```powershell
# PS C:\...> — local only (imported ed25519 key, no .pem extension)
ssh -i "$env:USERPROFILE\.ssh\te-v030" ubuntu@<PUBLIC_IP>
# If "UNPROTECTED PRIVATE KEY FILE":
#   icacls "$env:USERPROFILE\.ssh\te-v030" /inheritance:r /grant:r "${env:USERNAME}:R"
```

[OBSERVED 2026-08-18] The first launch came up as a 4-vCPU / 30 GB box
(instance-type field defaulted in the console), which would have run the
pipeline in hours on 2 workers. `nproc; free -g` at the top of Phase 2 is a
GATE, not a courtesy: expect 64 / ~493. If not, terminate and relaunch (or
stop -> change type -> start; a stop rotates the public IP and wipes /tmp).
Also: a `Connection timed out` on the first SSH is the security group's
My-IP rule being stale, not the instance — refresh the /32 and retry.

---

## Phase 2 — box hygiene + stage (bash, EC2 only)

```bash
# ubuntu@ip-...:$ — EC2 only
df -h; nproc; free -g
R --version | head -1                  # expect 4.5.3 — confirms the right AMI
grep te-v030 ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys && cat ~/.ssh/authorized_keys   # exactly one line
ls -la ~/.aws/ 2>/dev/null && mv ~/.aws /tmp/stale_aws_config_$(date +%s)
aws sts get-caller-identity            # expect ...assumed-role/ec2-s3-access/i-...
mkdir -p /tmp/v050/out /tmp/v050/BACI_HS92_V202601 && cd /tmp/v050
# (If a STOP rather than terminate is possible, stage under ~ instead —
#  /tmp does not survive a stop, and a stop rotates the public IP.)
```

```bash
# ubuntu@ip-...:$ — EC2 only
cd /tmp/v050
git clone https://github.com/impex-machina/trade-elasticities.git
cd trade-elasticities && git log --oneline -3
# MUST show "analysis: HS4 per-cell BW fn-14 gap census..." atop c8e9eb5.
# If not: Phase 0 push didn't land — stop.
```

Stage the canonical raw cache (FLAT in out/, exact filename — the tag
is parsed from the `--data` path string, and the cache path derives
from it):

```bash
# ubuntu@ip-...:$ — EC2 only
aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/refactored_run_20260519/stage1/baci_hs92_v202601_elast_country_hs4_raw_cache.rds \
  /tmp/v050/out/baci_hs92_v202601_elast_country_hs4_raw_cache.rds
find /tmp/v050/out -type f     # exactly ONE ~918 MB file, FLAT (no stage1/)
```

Package preflight — sudo, from OUTSIDE the repo, renv autoloader off
(the 2026-07-23 hijack lesson). Fresh instances always need the scan:

```bash
# ubuntu@ip-...:$ — EC2 only
cd /tmp/v050
sudo env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript -e 'need <- c("optparse","jsonlite","glue","ggplot2","haven","openssl"); miss <- need[!need %in% rownames(installed.packages())]; if (length(miss)) install.packages(miss, repos = "https://cloud.r-project.org")'
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript -e 'for (p in c("Rcpp","data.table","ggplot2","haven","optparse","openssl","jsonlite")) { library(p, character.only = TRUE); cat("OK:", p, "\n") }'
```

---

## Phase 3 — run + census (bash, EC2 only, inside tmux)

`--bw-lag calendar` is EXPLICIT and REQUIRED here: 0017 is not applied
yet, so the tree's default is still legacy. λ stays 0.1 (retained).

```bash
# ubuntu@ip-...:$ — EC2 only
tmux new -s v050
cd /tmp/v050/trade-elasticities
nohup env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript scripts/run_estimation.R \
  --data /tmp/v050/BACI_HS92_V202601 --out-dir /tmp/v050/out \
  --bw-lag calendar \
  > /tmp/v050/run.log 2>&1 &
tail -n 40 -f /tmp/v050/run.log
```

[OBSERVED 2026-08-18] Pasting this block as one unit does NOT work: `tmux new`
takes over the terminal before the remaining lines are consumed, so the
`cd`/`nohup`/`tail` never run and the tmux window sits at an idle prompt.
Run `tmux new -s v050` alone, THEN paste the rest inside the window. Inside
tmux, `Ctrl-C` on the tail is safe (the job is nohup-backgrounded), but a
`Ctrl-C` while a FOREGROUND Rscript (e.g. the census) is running kills it —
wait for the "Written:" lines. Scrollback lives in the log file: `grep` /
`less` / `scp` it rather than scrolling tmux.

Tripwires, in order:

1. `Shrinkage lambda: 0.1` and the config echo shows the bw-lag flag
   took (no "--bw-lag" rejection at parse).
2. `Country output base: .../baci_hs92_v202601_elast_country_hs4` — tag
   parsed from the --data path string; if missing, kill and fix.
3. "Loading cached raw data..." within the first minute (cache hit).
4. Stage-1 → Stage-2 translation prints "gamma (omega-scale) median"
   ~0.295, SAME as v0.4.1 — Stage 1 has no BW weights; a different
   value means wrong code or stack. First live A/B checkpoint.
5. Stage-2a λ banner matches the v0.4.x run logs (0.05 — the banner-fix
   value from the v0.3.0 arc).
6. Stage-2a/2b gammas will DIFFER from v0.4.1 — that is the point. Do
   not "fix" it on the box. Expect ~53 min total (v0.4.1 precedent;
   `mc.preschedule=TRUE` chunking unchanged in `stage1_liml_wrapper.R`).

Census fold-in — same box, same cache, after the run completes (it
re-prepares from cache; minutes):

```bash
# ubuntu@ip-...:$ — EC2 only
cd /tmp/v050/trade-elasticities
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript analysis/hs4_bw_gap_census.R \
  --data /tmp/v050/BACI_HS92_V202601 --out-dir /tmp/v050/out \
  > /tmp/v050/census.log 2>&1
grep -A 12 "HS4 BW fn-14 gap census" /tmp/v050/census.log
```

[OBSERVED 2026-08-18] The census script as first committed (7522966) assumed
`prepare_data()` returns the bare panel; it returns `list(dt, qlog)` (see
run_estimation.R's `prep_country$dt`), so `:=` failed on a list. Fixed on the
box by hand (`prep <- prepare_data(...)$dt; setDT(prep)`) and carried into
the repo copy in the post-release hygiene patch — the committed script now
matches what produced the shipped census. Result on the real panel: 52.8% of
series holed, 7.15M rows (9.1%) legacy-stale, 91.0% of cells affected.

Paste that printed block into the session notes — it is the headline
incidence read (rows with legacy-STALE lags = the lower bound on
weights that changed, and the cells CSV keys where).

---

## Phase 4 — upload + terminate (bash, EC2 only)

```bash
# ubuntu@ip-...:$ — EC2 only
aws s3 cp /tmp/v050/out/ s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_$(date +%Y%m%d)/ --recursive
aws s3 cp /tmp/v050/run.log    s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_$(date +%Y%m%d)/run.log
aws s3 cp /tmp/v050/census.log s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_$(date +%Y%m%d)/census.log
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_$(date +%Y%m%d)/ --recursive --human-readable
```

Verify counts/sizes against `/tmp/v050/out`, then terminate from the
console. (Optional post-arc AMI re-bake per the v0.4.0 runbook note —
only from a clean instance state.)

---

## Phase 5 — local A/B (PowerShell; ORDER MATTERS)

**5.1 Preserve v0.4.1.** Pause OneDrive. The v0.4.0 arc's rename was
silently defeated by a OneDrive lock — verify with Test-Path:

```powershell
# PS C:\...> — local only. OneDrive PAUSED.
cd "C:\Users\maxxj\OneDrive\Desktop\Projects\trade-elasticities\trade-elasticities"
Move-Item data\derived data\derived_v041
Test-Path data\derived_v041   # must be True
Test-Path data\derived        # must be False — if True, the move silently failed
```

[OBSERVED 2026-08-18] `Rename-Item` rejects a PATH as the new name ("Cannot
rename the specified target, because it represents a path or device name");
`Move-Item` is the correct verb. Also: `Move-Item` carries `.gitkeep` along, so
`git status` later shows `D data/derived/.gitkeep` — restore it with
`git checkout -- data/derived/.gitkeep` before the release commit.

**5.2 Download** into a fresh `data\derived` mirroring the manifest
layout — INCLUDING the summary .rds/.txt (the v0.4.0 rds-only pull left
a stale HF-bound summary that only the rehash caught). Substitute the
actual `v050rc_run_<YYYYMMDD>` prefix:

```powershell
# PS C:\...> — local only
$pre = "s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_<YYYYMMDD>"
mkdir data\derived\stage1, data\derived\stage2a, data\derived\stage2b | Out-Null
aws s3 cp "$pre/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds"  data\derived\stage1\
aws s3 cp "$pre/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds"    data\derived\stage2a\
aws s3 cp "$pre/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"     data\derived\stage2b\
aws s3 cp "$pre/baci_hs92_v202601_elast_country_hs4_summary.rds"         data\derived\stage2b\
aws s3 cp "$pre/baci_hs92_v202601_elast_country_hs4_summary.txt"         data\derived\stage2b\
# validation/ files are untouched this release (absent-key rule) — copy them across.
# [OBSERVED 2026-08-18] The manifest carries 5 stage files + 6 validation CSVs = 11;
# the regional summary pair is NOT manifested (skip it). Check with
# `git show HEAD:data/manifest.csv | Select-Object -First 15` before downloading.
Copy-Item data\derived_v041\validation data\derived\validation -Recurse
# census outputs: evidence artifacts, never the manifest
aws s3 cp "$pre/baci_hs92_v202601_elast_country_hs4_bw_gap_census_cells.csv"  results\
aws s3 cp "$pre/baci_hs92_v202601_elast_country_hs4_bw_gap_census_series.csv" results\
```

**5.3 FIRST verification — the σ A/B** (sort both sides: the new file
is canonically sorted by patch 0013; the old one predates it):

```powershell
# PS C:\...> — local only
@'
suppressMessages(library(data.table))
old <- readRDS("data/derived_v041/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds")
new <- readRDS("data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds")
setDT(old); setDT(new)
setorderv(old, c("good", "importer")); setorderv(new, c("good", "importer"))
shared <- intersect(names(old), names(new))
cat("rows:", nrow(old), "vs", nrow(new), "\n")
cat("bit-identical on shared cols:", identical(old[, shared, with = FALSE], new[, shared, with = FALSE]), "\n")
cat("new cols:", paste(setdiff(names(new), names(old)), collapse = ", "), "\n")
cat("run_meta on new (expect NULL):", is.null(attr(new, "run_meta")), "\n")
'@ | Set-Content -Encoding ASCII sigma_ab.R
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" sigma_ab.R
```

Expect: identical **TRUE**, new cols **none**, run_meta stripped TRUE.
If not identical, STOP — the stack or Stage-1 path differs; diagnose
before reading any Stage-2 delta.

**5.4 The comparison:**

```powershell
# PS C:\...> — local only
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" analysis\compare_runs.R `
  --old-stage1  data\derived_v041\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
  --new-stage1  data\derived\stage1\baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds `
  --old-stage2b data\derived_v041\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds `
  --new-stage2b data\derived\stage2b\baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds `
  --old-label v0.4.1 --new-label v0.5.0-rc `
  --out docs\methodology\v041_v050_comparison.md
```

**5.5 Census–delta join** (does the movement sit where the census says
the stale lags were?):

[OBSERVED 2026-08-18] With 91% of cells carrying stale rows, the stale-vs-
clean split below is degenerate. Read it as a DOSE-RESPONSE instead:
quintiles of `n_stale_rows` against cell-median and cell-max |Δγ|, plus
Spearman, plus |Δγ| by tier. Observed: monotone across all five quintiles
(cell-median 0.00064→0.00353, cell-max 0.014→0.68, share moved 89.8%→100%),
Spearman 0.22 (median) / 0.45 (max); by tier p50/p99: T0 0.047/4.94, T1
0.0055/1.60, T2 0.002/0.86, T3 0.0004/0.034 — T3 moves only via the 2a
prior, T0 (reference exporter) takes the export-side reweight. NOTE: R code
lines belong INSIDE the here-string, never at the PS prompt (`cat(...)`
resolves to Get-Content there).

```powershell
# PS C:\...> — local only
@'
suppressMessages(library(data.table))
old <- setDT(readRDS("data/derived_v041/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"))
new <- setDT(readRDS("data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"))
m <- merge(old[, .(importer, exporter, good, g_old = gamma)],
           new[, .(importer, exporter, good, g_new = gamma)],
           by = c("importer", "exporter", "good"))
m[, adg := abs(g_new - g_old)]
cell <- m[, .(max_adg = max(adg, na.rm = TRUE), med_adg = median(adg, na.rm = TRUE)), by = .(importer, good)]
cen <- fread("results/baci_hs92_v202601_elast_country_hs4_bw_gap_census_cells.csv")
j <- merge(cell, cen[, .(importer = as.character(importer), good = as.character(good), n_stale_rows)],
           by = c("importer", "good"), all.x = TRUE)
j[is.na(n_stale_rows), n_stale_rows := 0L]
cat("matched-pair rows:", nrow(m), "  cells:", nrow(j), "\n")
cat("share of cells with any gamma movement (>1e-12):", j[, mean(max_adg > 1e-12)], "\n")
print(j[, .(cells = .N, share_moved = mean(max_adg > 1e-12), med_max_adg = median(max_adg)), by = .(stale = n_stale_rows > 0)])
cat("NOTE: stale=FALSE cells can still move via cell-level filtering\n")
cat("(reference joins, moment-NA drops) — the census is a lower bound.\n")
'@ | Set-Content -Encoding ASCII census_join.R
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" census_join.R
```

**5.6 Adjudicate.** Ship gates: σ bit-identical (5.3); movement
concentrated in and around census-flagged cells with the stale=TRUE
group moving more (5.5); marginals in the comparison md shift modestly
and explicably (γ median/IQR, opt_tariff, tier shares); membership
churn small. Record the read in the comparison header prose BEFORE
looking further (prediction-record discipline). Anomaly → stop, keep
`derived_v041` in place, investigate. Ship → Phase 6.

---

## Phase 6 — release (PowerShell)

**6.1 The flip.** Pause OneDrive.

```powershell
# PS C:\...> — local only
git am "$env:USERPROFILE\Downloads\0017-fix-flip-bw_lag-CLI-default-to-calendar-v0.5.0.patch"
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" -e "testthat::test_dir('tests/testthat')"
# expect 325 pass, 0 fail/warn/skip
```

**6.2 Regenerate** (empirical layers only — pillars and validation
captures are bit-identical by the absent-key rule; skip
`--rerun-pillars`):

```powershell
# PS C:\...> — local only
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" analysis\master.R
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" scripts\build_readme.R
# optional, report-only (lambda unchanged at 0.1):
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" analysis\lambda_diagnostic.R --label v0.5.0 --out results\lambda_diagnostic_v050.json
```

**6.3 Comparison prose.** Write the header above the generated table in
`docs\methodology\v041_v050_comparison.md`: the prediction (σ zero-delta
by construction; 2a/2b reweighting only), the census incidence block
pasted from Phase 3, the join read from 5.5, and the observed
signature. Note explicitly that the Stage-1 FILE hash changes while its
data is bit-identical (patch 0013 canonicalization) — the manifest diff
in 6.4 is expected to show it.

**6.4 Rehash + commit + tag:**

[OBSERVED 2026-08-18 — three incidents, all recovered; read before running]

(a) GITHUB SIZE. The per-series census CSV (183 MB, 7.3M lines) cannot be
committed: the push fails with HTTP 408 and GitHub refuses >100 MB files.
Commit ONLY the per-cell CSV (~9 MB, the join key); the series file's durable
home is the S3 rc prefix. `.gitignore` now carries
`results/*_bw_gap_census_series.csv` (comment on its OWN line — git treats
`#` as a comment only at line start; a trailing comment breaks the pattern).
Do NOT `git add -A` for the release commit; name the files.

(b) MANIFEST HASH ROOT CAUSE. `scripts/hf_upload_release.py` aborted on hash
drift for all four `.rds` rows while `.txt`/CSV rows passed, and a re-rehash
reported 0 changes. Not settling: `rehash_manifest.R` hashed with
`openssl::sha256(file(p))` — no `"rb"` — a TEXT-MODE read on Windows that
mangles binary bytes. PS `Get-FileHash`, Python `hashlib`, and R
`sha256(file(p, "rb"))` all agree on the true hash. Fixed in a0b7b4f
(binary mode; tidied with an explicit connection in the hygiene patch).
CONSEQUENCE: the v0.4.0 and v0.4.1 manifests recorded text-mode hashes for
their four `.rds` rows — files always correct, hub LFS checksums correct,
but a consumer verifying against the git manifest with a standard tool
would see a mismatch. Disclosed in the v0.5.0 card entry. From v0.5.0 the
manifest certifies bytes.

(c) PS 5.1 BOM. `Set-Content -Encoding UTF8` writes a byte-order mark; R's
parser rejects it (`unexpected input in "﻿"`). Rewrite any R script from PS
with `[System.IO.File]::WriteAllText(path, text, (New-Object
System.Text.UTF8Encoding($false)))` and confirm the first bytes are not
239,187,191. (The comparison-md header write is fine: markdown tolerates a
BOM.)

Amend chain for the record: facecfc (series CSV in) → 3f05569 (dropped it)
→ 176fccd (no-op re-rehash) → a0b7b4f (rb fix + true hashes = tag v0.5.0).
Nothing downstream had consumed the earlier hashes, so `--force-with-lease`
on main and `--force` on the tag were safe.

```powershell
# PS C:\...> — local only
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" scripts\rehash_manifest.R
# expect changed hashes: stage1 rds (data-identical, canonicalized bytes),
# stage2a rds, stage2b rds + summary.rds + summary.txt; validation rows unchanged
git add data\derived data\manifest.csv README.md docs\methodology\v041_v050_comparison.md results\baci_hs92_v202601_elast_country_hs4_bw_gap_census_cells.csv results\baci_hs92_v202601_elast_country_hs4_bw_gap_census_series.csv
git add -A   # picks up master.R/build_readme regenerations; review git status first
git commit -m "data: v0.5.0 rerun (bw_lag calendar default; fn-14 calendar lag)"
git tag v0.5.0
git push origin main
git push origin v0.5.0
```

**6.5 HF data — gated atomic upload (Step 8):**

```powershell
# PS C:\...> — local only, from the repo root
py scripts\hf_upload_release.py
# read the verified plan; then:
py scripts\hf_upload_release.py --execute --message "data: v0.5.0 rerun (bw_lag calendar)"
# record the printed hub commit oid — it is the v0.5.0 data revision pin
```

[OBSERVED 2026-08-18] Dry run passed on the corrected manifest: `verified 11
files, 244.2 MB`; execute landed all 11 in ONE hub commit
`ea1c3ea464ca1ac114bf9b6c518325e8135bdc41` (3 RDS transferred, rest deduped).
The gate catching (b) above on its first outing is exactly what patch 0015
was for.

**6.6 Card changelog (Step 9).** Edit `docs\hf_dataset_card.md` in the
house blockquote style — fill the TODO slots from the comparison md and
the upload output:

```
> **v0.5.0 — 2026-MM-DD.** Broda–Weinstein fn-14 lag corrected to the
> previous CALENDAR year (was: previous retained row, which went stale
> across filtered years). CLI default now `calendar`; `legacy`
> reproduces v0.4.x bit-for-bit. σ (Stage 1) bit-identical to v0.4.1.
> γ: <TODO median old→new, IQR, share of cells |Δγ|>0.01 from the
> comparison>; opt_tariff <TODO>. Gap incidence (prepared panel):
> <TODO stale-row and affected-cell counts from the census block>.
> Data revision: <TODO hub oid from 6.5>. Supersedes v0.4.1
> (pin 5493c51f).
```

[OBSERVED 2026-08-18] The card has NO standing supersession warning — each
entry carries its own in-line ("**Stage 2b gamma is superseded**", "**vPREV
remains available pinned at revision `xxx`** -- do not mix versions within
one analysis."), entries are consecutive `>` blocks separated by a bare `>`
line, and the version tag reads `**v0.5.0 (2026-08-18).**` (parenthesized
date). Insert the new entry immediately above the previous release's entry
(line-index insert, guarded by a regex on the v0.4.1 opener) and close it
with the pin formula. Live at card commit 872ca2c5; five-pattern verify all
True. Ignore the next sentence's "standing warning" phrasing —
move the supersession pointer to v0.5.0,
keep the v0.4.1 pin row (5493c51f) and all earlier pins (a76f2d7,
ec59b57..., 7e598f6cb98e). Then push the card and verify:

```powershell
# PS C:\...> — local only
@'
from huggingface_hub import HfApi, hf_hub_download
api = HfApi()
info = api.upload_file(
    path_or_fileobj="docs/hf_dataset_card.md",
    path_in_repo="README.md",
    repo_id="impex-machina/trade-elasticities",
    repo_type="dataset",
    commit_message="docs: v0.5.0 card changelog + supersession",
)
print("pushed:", getattr(info, "commit_url", info))
p = hf_hub_download("impex-machina/trade-elasticities", "README.md",
                    repo_type="dataset", force_download=True)
txt = open(p, encoding="utf-8").read()
for pat in ["AUTHORITATIVE SOURCE", "v0.5.0", "5493c51f",
            "ec59b57894cab18b2d0295c96334a96b7dd8a2cd"]:
    print("verify", pat, ":", pat in txt)
'@ | Set-Content -Encoding ASCII $env:TEMP\card_v050.py
py $env:TEMP\card_v050.py
```

**6.7 Baseline retirement.** Only after 6.5 + 6.6 verify clean:

```powershell
# PS C:\...> — local only
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/ | Select-String v041
# if no shipped-v0.4.1 archive exists, create one before deleting:
aws s3 cp data\derived_v041\ s3://trade-elast-baci-hs92-v202601-hs4/v041_shipped_20260725/ --recursive
Remove-Item data\derived_v041 -Recurse
```

v0.4.1 then lives in its canonical homes only: git history (tag
`v0.4.1` = 5b2c691), HF pin 5493c51f, and the S3 archive.

[OBSERVED 2026-08-18] Archived as `v041_shipped_20260725/` (12 objects,
232.9 MB — the shipped set incl. the audit-refreshed tier1a; distinct from
`v041_run_20260721/`, the pre-refresh box output). Local copy retired after
the listing verified. Final repo state: main = 5d2a232, tree clean. Resume
OneDrive. Release complete across all layers — commit the runbook's
observed notes as dated annotations if anything deviated.

---

## Checklist

- [ ] Phase 0: 0016 applied + pushed; 0017 parked in Downloads
- [ ] Phase 1: r7a.16xlarge, te-v030, ec2-s3-access, 100 GB gp3
- [ ] Phase 2: sts shows assumed role; census commit on the box clone; cache staged flat (~918 MB); package gate green
- [ ] Phase 3: `--bw-lag calendar` explicit; σ tripwire ~0.295; run ~53 min; census block captured
- [ ] Phase 4: out + run.log + census.log at `v050rc_run_<date>/`; sizes verified; instance terminated
- [ ] Phase 5: rename verified with Test-Path; summaries downloaded; σ A/B TRUE with no new cols; comparison md generated; census join read; adjudicated in writing
- [ ] Phase 6: 0017 applied, 325 green; master + README regenerated; rehash shows the expected file set; commit + tag v0.5.0 + push; gated upload dry→execute, oid recorded; card changelog live + 4-pattern verify; v0.4.1 archived then retired locally
