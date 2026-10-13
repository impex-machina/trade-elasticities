# Box session template (patch 0104)

The standard shape of an estimation session on EC2, written after the 2026-10-12
v0.10.0 session. Copy it into a release-specific runbook and fill the run-specific
lines. **Costs and durations are stated before every step that uses the box.**

## Before launching (local, $0)

- The code for the release is on `main` and the suite is green.
- Every methodology change in the session has been measured on the 2% subsample
  locally, with a ship rule written down before the numbers, including the
  configuration *as it will ship* (the 2026-10-12 lesson: the subsample grid held
  Stage 2a fixed, the full run did not, and a 25% level shift had to be attributed
  on the box).
- The release gate's expectations are known: `analysis/gate_release.R` with the
  rules the run will use.

## Durations on `r7a.16xlarge`, `--ncores 62`

| step | duration |
|---|---|
| `scripts/box/setup.sh` (placement, packages, hash checks) | ~5 min |
| Stage 2a | ~3 min |
| one Stage-2b pass | ~37–42 min |
| `--stage all`, Stage 1 loaded, three γ_V passes | ~2 h |
| Stage 1 re-estimated | several hours — only when Stage 1 changes |
| upload of an output folder (no cache) | 1–2 min |

The instance bills from launch to termination, idle or not. One run that answers
the question beats two that cross-check it; say which before launching.

## On the box (`ubuntu@ip-…$`)

1. Clone `main`; `bash scripts/box/setup.sh /tmp/w/out_H` (~5 min).
2. `tmux new -s rc` as its own command; wait for the green bar.
3. Launch through the gate, on one line:
   `bash scripts/box/preflight.sh /tmp/w/out_H && env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER=$HOME/R/library Rscript scripts/run_estimation.R --data ~/BACI_HS92_V202601 --out-dir /tmp/w/out_H --stage all --ncores 62 2>&1 | tee /tmp/w/out_H/run.log`
   `preflight.sh` refuses outside tmux, so the run cannot end up in the foreground
   SSH shell. Then `Ctrl-b d`.
4. Everything else — checks, quick reads, uploads — from **a second SSH
   connection** (same key, same IP), never by typing into the running window.
   In a `;`-chained launch, Ctrl-C kills the current run and starts the next.
5. The run's records (optimizer-fallback and tail-trim tables, per pass) are written into
   `--out-dir` beside the outputs since patch 0111. On a checkout older than 0111 they land
   in the working directory; move them into the output folder first:
   `mv baci_hs92_v202601_elast_*_stage2_*.csv baci_hs92_v202601_elast_*_stage2_*.rds /tmp/w/out_H/ 2>/dev/null`
6. The gate: `Rscript analysis/gate_release.R --old <released 2b> --new /tmp/w/out_H/<2b table> --stage1 /tmp/w/out_H/<stage1> --pass-log /tmp/w/out_H/<passes csv> --out /tmp/w/out_H/gate.md --label <release>` — must PASS.
7. Upload: `aws s3 cp --recursive /tmp/w/out_H s3://trade-elast-baci-hs92-v202601-hs4/<run folder>/out_H/ --exclude "*raw_cache*" --only-show-errors`.
8. Terminate from the console, then confirm locally:
   `aws ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name]" --output table` — empty.

## After (local, $0)

The release train: place the tables, re-run the gate locally, `compare_runs.R`,
`analysis/master.R`, README build and CR-normalized lock check, `rehash_manifest.R`,
suite, commit, tag **before** the upload, `hf_upload_release.py` (Gate 0 refuses a
second upload for a released card entry), then the card's revision and hub sync.
Every PowerShell block wrapped in `& { … }` so a `throw` ends it.
