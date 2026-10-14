#!/usr/bin/env bash
# =============================================================================
# scripts/box/preflight.sh   (patch 0104)
#
# The gate in front of every launch on the box. Chain it with && so a failed
# check means the estimation never starts:
#   bash scripts/box/preflight.sh /tmp/w/out_H && Rscript scripts/run_estimation.R ...
# Refuses unless: the shell is inside tmux (a run in the foreground SSH shell
# dies with the connection -- the 2026-10-12 session's runs survived only
# because the window stayed open); the instance role is active; the R
# packages load; the cache and the Stage-1 table are in OUT_DIR with the
# expected size / manifest hash. Prints the expected durations so the cost of
# what follows is on screen before it starts.
# =============================================================================
set -uo pipefail
OUT="${1:-/tmp/w/out_H}"
CACHE_BYTES=917536992
fail() { echo "preflight: FAIL -- $*"; exit 1; }
[ -n "${TMUX:-}" ] || fail "not inside tmux. Run 'tmux new -s rc' (or 'tmux attach -t rc'), wait for the green bar, then launch again. Never launch in the plain SSH shell."
aws sts get-caller-identity --query Arn --output text 2>/dev/null | grep -q "assumed-role" || fail "instance role not active (move ~/.aws/credentials aside)"
RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER="$HOME/R/library" Rscript -e 'm <- c("Rcpp","data.table","optparse","jsonlite"); if (!all(vapply(m, requireNamespace, logical(1), quietly = TRUE))) quit(status = 1)' >/dev/null 2>&1 || fail "R packages missing (run scripts/box/setup.sh)"
[ "$(stat -c %s "$OUT/baci_hs92_v202601_elast_country_hs4_raw_cache.rds" 2>/dev/null || echo 0)" = "$CACHE_BYTES" ] || fail "raw cache missing or wrong size in $OUT"
S1="$OUT/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds"
if [ -f "$S1" ]; then
  WANT=$(grep "stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds" data/manifest.csv | grep -o '[0-9a-f]\{64\}')
  [ "$(sha256sum "$S1" | cut -d' ' -f1)" = "$WANT" ] || fail "Stage-1 table in $OUT does not match the manifest (the run would use a different Stage 1)"
  S1NOTE="Stage 1 will be LOADED (manifest hash verified)"
else
  S1NOTE="no Stage-1 table in $OUT: a --stage all run will RE-ESTIMATE Stage 1 (hours)"
fi
echo "preflight: OK -- inside tmux ($TMUX), role active, packages load, cache OK; $S1NOTE"
echo "preflight: repo HEAD $(git rev-parse --short HEAD) | cores $(nproc) | free disk on /tmp $(df -h /tmp | awk 'NR==2{print $4}')"
echo "preflight: expected durations on r7a.16xlarge at --ncores 62 -- Stage 2a ~3 min; one Stage-2b pass ~37-42 min; --stage all with Stage 1 loaded and 3 passes ~2 h"
echo "preflight: detach with Ctrl-b d once the run is going; check it from outside tmux with grep on the log"
