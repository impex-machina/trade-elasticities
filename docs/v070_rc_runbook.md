# v0.7.0-rc rerun runbook — negative-ω inversions routed as the ω = +∞ continuation

Scope: full Stage 1 → 2a → 2b rerun with `--stage1-negative-omega reject`
(patch 0046), on-box tripwires and census after Stage 1, upload, then the
local A/B against v0.6.1. Everything else on the command line is the
v0.6.1 configuration (`--stage1-hliml closed`, `--bw-lag calendar`,
`--stage2-gradient numeric`, λ 0.1). The raw cache is estimator-independent
and is reused from `v050rc_run_20260818/` exactly as the v0.6.0 rc did.

**Decision NOT yet taken:** whether `reject` becomes the v0.7.0 default. The
rc measures it. Do not touch README/docs until Phase 6.

**Why this run exists** (`docs/results/cf_inversion_census.md`, 2026-09-01):
36,914 shipped interior-HLIML cells (13.2% of the universe) are closed-form
points whose inversion clamped a *negative* ω up to the 1e-4 floor. A
negative ω is ρ beyond (σ−1)/σ — the continuation past ω = +∞ — so the
floor is the wrong end of the supply-elasticity axis; the 1,558 such cells
that did reach the boundary search in v0.6.1 resolved 86% to the ω-**cap**
edge. `reject` makes the point inadmissible at every inversion and lets the
boundary search take the cell.

**Lessons carried in:** stop OneDrive (not pause) before any `git am` on the
Windows side; on the box never `exit` a tmux window (Ctrl-b d); capture long
output to files and read with `sed`/`less`; a stopped instance loses `/tmp`.

Wrong-shell tell: every block below is `ubuntu@ip-…$` unless marked
`PS C:\…>`. If `mkdir -p` errors, you are in PowerShell.

---

## Phase 0a — SSH in (`PS C:\…>`, ~2 min)

Read the instance's **Public IPv4 address** from the console (Instances →
select → Details). Then, from PowerShell (this is the one block that runs
locally; every later block runs on the box):

```powershell
# 1. the SG must allow port 22 from wherever you are NOW; residential IPs rotate
#    console: EC2 -> Security Groups -> te-estimation-ssh -> Edit inbound rules -> SSH source "My IP" -> Save
# 2. connect (key has NO .pem extension; user is ubuntu; region us-east-1)
ssh -i "$env:USERPROFILE\.ssh\te-v030" ubuntu@<PUBLIC_IPV4>
```

First connection prints the host-key prompt — answer `yes`. The prompt
becomes `ubuntu@ip-…$`; everything from Phase 0 on is typed there.

| Symptom | Cause | Fix |
|---|---|---|
| `Connection timed out` | SG inbound rule still holds an old residential IP | refresh the source to My IP (step 1), retry |
| `Permission denied (publickey)` | wrong key path, or `.pem` appended, or a different key pair on this instance | `Test-Path "$env:USERPROFILE\.ssh\te-v030"`; check the instance's Key pair name in the console |
| `WARNING: UNPROTECTED PRIVATE KEY FILE` | key ACL too open (rare on Windows) | `icacls "$env:USERPROFILE\.ssh\te-v030" /inheritance:r /grant:r "$env:USERNAME:R"` |
| `Host key verification failed` after a re-launch | same IP reused by a new instance | `ssh-keygen -R <PUBLIC_IPV4>` then reconnect |

Keep this PowerShell window: it is your SSH session. Open a *second*
PowerShell window for Phase 6 later; never paste box commands into it.

## Phase 0 — preflight on the running box (`ubuntu@ip-…$`, ~3 min)

```bash
# 0.1 the AMI's stale static credentials shadow the instance role: move them aside
mv ~/.aws/credentials ~/.aws/credentials.stale 2>/dev/null
aws sts get-caller-identity          # ARN must contain assumed-role/ec2-s3-access
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/ | tail -5

# 0.2 library path + load gate (the legacy ~/R/library sits outside .libPaths)
export R_LIBS_USER=$HOME/R/library
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript -e 'for (p in c("Rcpp","data.table","ggplot2","haven","optparse","openssl","jsonlite")) cat(sprintf("%-11s %s\n", p, tryCatch(as.character(packageVersion(p)), error=function(e) "MISSING")))'
# any MISSING -> install from OUTSIDE the repo (never inside it; renv would hijack the install):
#   cd /tmp && sudo env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript -e 'install.packages("<pkg>", repos="https://cloud.r-project.org")'

# 0.3 the --data path only has to EXIST and carry the BACI_HS92_V202601 token (the run reads the cache)
ls -d ~/BACI_HS92_V202601 && df -h /tmp | tail -1 && nproc && free -g | head -2
```

Stop if the ARN is not the role, if any package is MISSING after the
install, or if `/tmp` has < 20 GB free.

## Phase 1 — clone at main = 554236d, pull the cache (~5 min)

```bash
mkdir -p /tmp/w && cd /tmp/w
git clone --depth 1 https://github.com/impex-machina/trade-elasticities.git && cd trade-elasticities
git log --oneline -1                 # must read: 554236d patch 0046: negative-omega inversions ...
git rev-parse 'HEAD^{tree}'          # 6f05d1302fde4ef2797c2b9998b9f08db704870f
grep -c negative_omega R/liml_estimator.R    # 18

mkdir -p out_rc
aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_20260818/ out_rc/ --recursive --exclude "*" --include "*_raw_cache.rds"
ls -la out_rc/                        # exactly one file: baci_hs92_v202601_elast_country_hs4_raw_cache.rds
```

The cache filename must be exactly `<out-dir>/baci_hs92_v202601_elast_country_hs4_raw_cache.rds`
— that is what the runner tests with `file.exists()`; a misnamed copy
silently triggers a 30-minute raw-BACI rebuild that then fails on the
AMI's Readme-only data directory.

## Phase 2 — Stage 1 only, in tmux (~25 min)

Run Stage 1 alone first so the tripwires and the census gate 2a/2b.

```bash
tmux new -s rc
cd /tmp/w/trade-elasticities && export R_LIBS_USER=$HOME/R/library
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER=$HOME/R/library \
  Rscript scripts/run_estimation.R --data ~/BACI_HS92_V202601 --out-dir out_rc \
  --stage 1 --stage1-negative-omega reject --stage1-hliml closed --bw-lag calendar \
  --stage2-gradient numeric --ncores 62 2>&1 | tee out_rc/run_v070rc_stage1.log
```

Detach with **Ctrl-b d** (never `exit`). Re-attach: `tmux attach -t rc`.

Header must show, in this order:

```
  BW lag mode:      calendar
  Stage-1 HLIML:    closed
  Stage-1 CF rule:  legacy
  Stage-1 neg-omega: reject
  Stage-2 gradient: numeric
```

(`CF rule: legacy` is correct — 0043's `strict` is a census mode and stays off.)
Then `Loading cached raw data... 113.8M obs` and `Cells to process: 280649`.

When the `--- Stage 1 LIML summary ---` block prints, read it from the file:

```bash
grep -A 12 "Stage 1 LIML summary" out_rc/run_v070rc_stage1.log
```

## Phase 3 — tripwires + on-box census (seconds; still Phase-2 window or a second one)

```bash
cd /tmp/w/trade-elasticities
cat > /tmp/w/tripwire.R <<'EOF'
suppressPackageStartupMessages(library(data.table))
d <- as.data.table(readRDS("out_rc/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds"))
ref <- c(ok = 182385, hliml = 115440, step2 = 39648, boundary = 27297, floored = 64699,
         bd_floor = 11470, bd_scap = 6438, bd_ocap = 9389)
ok <- d[status == "ok"]
now <- c(ok = nrow(ok), hliml = ok[final_source == "hliml", .N],
         step2 = ok[final_source == "step2_weighted", .N],
         boundary = ok[final_source == "hliml_boundary", .N],
         floored = d[omega_floored %in% TRUE, .N],
         bd_floor = ok[adjust == 6L, .N], bd_scap = ok[adjust == 7L, .N], bd_ocap = ok[adjust == 8L, .N])
cat(sprintf("%-9s %8s %8s %8s\n", "", "v0.6.1", "rc", "delta"))
for (k in names(ref)) cat(sprintf("%-9s %8d %8d %+8d\n", k, ref[k], now[k], now[k] - ref[k]))
cat(sprintf("\nneg-omega rule on Step-3 rows: %s\n", paste(unique(na.omit(d$hliml_negative_omega)), collapse = ",")))
cat("Step-2 inversion status x omega_floored (Step-2-routed ok cells):\n")
print(ok[final_source == "step2_weighted", .N, by = .(step2_inversion_status, floored = omega_floored %in% TRUE)][order(-N)])
cat("closed-form inversion status among ok cells by route:\n")
print(dcast(ok[, .N, by = .(final_source, hliml_cf_inversion)], final_source ~ hliml_cf_inversion, value.var = "N", fill = 0))
cat(sprintf("\nsigma: clean median %.3f (v0.6.1: 2.727); quartiles %s\n",
    median(ok[sigma > 1, sigma]), paste(sprintf("%.3f", quantile(ok[sigma > 1, sigma], c(.25,.5,.75))), collapse = " / ")))
cat(sprintf("sigma-without-omega cells (adjust 1, omega NA): %d\n", ok[adjust == 1L & is.na(omega), .N]))
EOF
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript /tmp/w/tripwire.R 2>&1 | tee out_rc/tripwire_stage1.txt

env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript analysis/hs4_cf_inversion_census.R \
  --stage1 out_rc/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds \
  --out out_rc/cf_inversion_census_rc.json --md out_rc/cf_inversion_census_rc.md 2>&1 | tail -3
sed -n '/## Q6/,$p' out_rc/cf_inversion_census_rc.md
```

**Gate (go / no-go for 2a/2b):**

| Tripwire | Expect | If not |
|---|---|---|
| `neg-omega rule` line | `reject` only | wrong clone or flag — stop |
| `hliml` (interior) | **78,526 exactly** (78,523 ok-inversion + 3 genuine sub-floor) | wrong code — stop |
| `boundary` | 51k – 68k, `bd_ocap` carrying most of the increase | outside → read the Q6 table before proceeding |
| `ok` delta | small negative (a cell loses σ only if Step 2 fails *and* its best edge is `sigma_floor`) | drop > ~4,000 → stop; report the `sigma_floor` share with `d[hliml_bd_edge=="sigma_floor", .N]` |
| `floored` | falls toward the genuine ω→0 population (~11.4k boundary floor-edge + whatever Step 2 floors from the `eta1_nonpositive` side) | if still > ~35k, the rule did not reach an inversion — stop |
| σ clean median | moves little; the 36.9k cells have σ median 4.2, so watch it *together with* the `ok` delta | |

Paste `out_rc/tripwire_stage1.txt` and the Q6 section. Then proceed.

## Phase 4 — Stage 2a + 2b (~35 min, same tmux window)

`--stage all` loads the Stage-1 file already in `out_rc/` (log says
`STAGE 1: LOADING SIGMA ESTIMATES`) and runs 2a then 2b. Same flags, verbatim:

```bash
env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER=$HOME/R/library \
  Rscript scripts/run_estimation.R --data ~/BACI_HS92_V202601 --out-dir out_rc \
  --stage all --stage1-negative-omega reject --stage1-hliml closed --bw-lag calendar \
  --stage2-gradient numeric --ncores 62 2>&1 | tee out_rc/run_v070rc_stage2.log
```

Tripwires in the log: `Stage 2a starting values ... N products, median gamma=…`
(N and the median WILL move — the ~8.5k Step-2 re-routes carry large interior
ω into `feenstra_priors`, which excluded every floored cell before; record
both), `Shrinkage lambda=0.100`, the 2b trim line with its bands, final
report rows ~6.83M and tiers 3.3 / 70.1 / 0.2 / 26.4 (tiers depend on data,
not σ — any tier movement is a bug).

If the tmux server dies mid-2b: `tmux new -s rc2`, relaunch the same
command with `--stage 2b`. The Stage-2 checkpoint guard (0044) resumes from
`baci_hs92_v202601_elast_country_hs4_fs_checkpoint.rds` in the repo root
and refuses if any estimation flag differs — so re-type the flags exactly.

## Phase 5 — upload, verify, terminate (~10 min)

```bash
cd /tmp/w/trade-elasticities
ls -la out_rc/ | wc -l && du -sh out_rc/
aws s3 cp out_rc/ s3://trade-elast-baci-hs92-v202601-hs4/v070rc_run_$(date +%Y%m%d)/ --recursive
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/v070rc_run_$(date +%Y%m%d)/ --recursive | wc -l   # == local count
aws s3 ls s3://trade-elast-baci-hs92-v202601-hs4/v070rc_run_$(date +%Y%m%d)/ --recursive --summarize | tail -2
```

Expected contents: 3 stage rds + the rich `_liml.rds` + raw cache + 2 csv
mirrors + regional/country summary rds+txt + 2 logs + tripwire txt + census
json/md. The raw cache rides along (dual-homed, as before). Terminate from
the console — **terminate, not stop**.

## Phase 6 — local A/B (`PS C:\…>`, OneDrive paused)

```powershell
Move-Item data\derived data\derived_v061            # Move-Item, not Rename-Item; restore .gitkeep afterwards
# pull the rc into the manifest layout (stage1/, stage2a/, stage2b/, validation/ untouched); csv mirrors stay on S3
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" analysis\compare_runs.R --old-label v0.6.1 --new-label v0.7.0-rc --out docs\methodology\v061_v070rc_comparison.md   # explicit old/new paths as in the v0.6.0 cycle
```

Read, in this order: (1) Stage-1 composition — interior 78,526, the boundary
edge split, `ok` delta, σ median; (2) the σ side of the 36.9k re-routed
cells (median |Δσ|/σ; the DGP said ~4.5% median, >10% on a third); (3)
priors: `feenstra_priors` product count and median; (4) 2b γ median,
opt_tariff, tier composition (must be unchanged), the fingerprint-first
row-membership reconciliation before any per-cell join. Anything outside
that shape: stop and diagnose before regenerating.

Adjudicate. If ship: patch 0047 (default flip to `reject`; README
"Supply-side flooring" rewritten with the two-ends split emitted by
`00_setup.R`; ledger entry for the deliberate deviation from
`GS_Estimation.do`'s `omega = 0.0001 if omega < 0`; this comparison doc),
then the standard train — `master.R` (no `--rerun-pillars`), `build_readme`,
`rehash_manifest`, tag v0.7.0, `hf_upload_release.py` dry → execute, card
with the new oid. If not ship: the docs-only part of 0047 still goes in.

## OBSERVED — v0.7.0 rc (2026-09-02)

- Box: r7a.16xlarge, fresh AMI arrived with Rcpp 1.1.1 / data.table 1.18.2.1 and
  WITHOUT ggplot2, haven, openssl (optparse only after install); installed
  from `/tmp` after `apt-get install libssl-dev libcurl4-openssl-dev`. The
  different numeric stack changed nothing: 138,542 unchanged-route cells
  agree with v0.6.1 to zero.
- Windows side: a paused OneDrive is not enough for `git am` — the 0046 apply
  died on a `.git/rebase-apply` handle and had to be cleared with OneDrive
  *stopped* (`Stop-Process -Name OneDrive`; `Remove-Item .git\rebase-apply`).
- tmux: `tmux attach` from inside the session prints "sessions should be
  nested with care" and the following lines run in the current window (which
  was the right place). Ctrl-c inside the job window killed Stage 1 once; it
  has no checkpoint and restarted clean in 10 min.
- Stage 1 wall time: 10 min (4 min split + 5.8 min estimation, 62 forks).
  Header echo confirmed: `Stage-1 neg-omega: reject`.
- Tripwires (`tripwire_stage1.txt`): ok 182,385 -> 181,245 (-1,140); interior
  115,440 -> **78,526** (exact); Step 2 39,648 -> 47,479; boundary 27,297 ->
  55,240 (floor 15,578 / sigma-cap 7,259 / omega-cap 32,403); floored 64,699
  -> 15,582; sigma-without-omega 13,482 (7,304 adjust 1, rest adjust 4).
- Q6 exact: Step-2-routed ok cells by their own inversion: ok 33,984,
  constraint_violated 13,482 (all omega NA), omega_div_zero 12, floored 1.
- Per-cell (`percell_v061_vs_rc.txt`): floored-interior 36,917 -> omega-cap
  edge 18,994 (sigma 3.86 -> 3.16), Step 2 14,757 (4.54 -> 3.17), floor edge
  1,830 (5.28 -> 1.15), sigma-cap edge 193, interior 3, lost 1,140; Step 2
  39,648 -> unchanged 32,722, omega-cap 4,020 (10 -> 7.21), floor 2,278
  (6.11 -> 1.29), sigma-cap 628.
- Floor-edge corner (`bd6_check*.txt`): the 4,108 new floor-edge cells have
  sigma p10/med/p90 1.03/1.21/2.59 (pre-existing 11,470: 1.14/1.72/6.03),
  F_kp 1.46 (interior 1.61), Q_bd/Q_cf 0.958 (flat objective; values are
  negative so the ratio < 1 is the correct ordering). Decision: flag as
  `boundary_corner` (provenance-defined), not re-route (patch 0047).
- 2a: 424,008 estimates, priors 1,240 products median 0.642 (2b priors
  0.643), gamma 0.649, tariff 0.727. 2b: 30.5 min, 6,814,229 rows (v0.6.1
  6,829,023), sigma 2.462 (2.727), gamma 0.650 (0.628), tariff 0.649,
  convergence 68.9%, tiers 3.3 / 70.0 / 0.2 / 26.4 (unchanged), trim 77,779
  rows, gamma band [0, 15.98].
- S3: `v070rc_run_20260902/`, 19 objects, 2.3 GiB (raw cache dual-homed);
  instance terminated after the count matched.
