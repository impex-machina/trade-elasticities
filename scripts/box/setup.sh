#!/usr/bin/env bash
# =============================================================================
# scripts/box/setup.sh   (patch 0104)
#
# One-time placement for a box session, idempotent. Run from the repo root on
# the box (ubuntu@ip-...$) after cloning:
#   bash scripts/box/setup.sh [OUT_DIR]        # default /tmp/w/out_H
# It: moves a stale ~/.aws/credentials aside and checks the instance role;
# installs the system libraries and R packages the pipeline needs; pulls the
# HS4 raw cache from S3 (`cache/`, else the newest rc folder) and checks its
# size; downloads the released tables (scripts/download_outputs.R, hash-
# verified against data/manifest.csv) and places the Stage-1 table in
# OUT_DIR so the run LOADS it; creates the empty BACI data stub. Nothing here
# estimates anything: it takes ~5 minutes of box time.
# =============================================================================
set -euo pipefail
OUT="${1:-/tmp/w/out_H}"
BUCKET="s3://trade-elast-baci-hs92-v202601-hs4"
CACHE="baci_hs92_v202601_elast_country_hs4_raw_cache.rds"
CACHE_BYTES=917536992
S1="baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds"
export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE R_LIBS_USER="$HOME/R/library"
[ -f scripts/run_estimation.R ] || { echo "setup.sh: run from the repo root"; exit 1; }

echo "== credentials"
[ -f ~/.aws/credentials ] && mv ~/.aws/credentials ~/.aws/credentials.stale && echo "  moved a stale ~/.aws/credentials aside"
aws sts get-caller-identity --query Arn --output text | tee /dev/stderr | grep -q "assumed-role" || { echo "setup.sh: not running under the instance role"; exit 1; }

echo "== system libraries and R packages"
sudo apt-get install -y libssl-dev libcurl4-openssl-dev >/dev/null 2>&1 || true
( cd /tmp && sudo env RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript -e 'for (p in c("optparse","ggplot2","haven","openssl","jsonlite")) if (!requireNamespace(p, quietly=TRUE)) install.packages(p, repos="https://cloud.r-project.org")' >/dev/null 2>&1 ) || true
Rscript -e 'm <- c("Rcpp","data.table","ggplot2","haven","optparse","openssl","jsonlite"); ok <- vapply(m, requireNamespace, logical(1), quietly = TRUE); print(ok); if (!all(ok)) quit(status = 1)'

echo "== raw cache -> $OUT"
mkdir -p "$OUT" ~/BACI_HS92_V202601
if [ "$(stat -c %s "$OUT/$CACHE" 2>/dev/null || echo 0)" != "$CACHE_BYTES" ]; then
  aws s3 cp "$BUCKET/cache/$CACHE" "$OUT/$CACHE" --only-show-errors 2>/dev/null || {
    SRC=$(aws s3 ls "$BUCKET/" --recursive | grep "$CACHE" | sort | tail -1 | awk '{print $4}')
    echo "  cache/ key missing; pulling $SRC"; aws s3 cp "$BUCKET/$SRC" "$OUT/$CACHE" --only-show-errors; }
fi
[ "$(stat -c %s "$OUT/$CACHE")" = "$CACHE_BYTES" ] || { echo "setup.sh: cache size is not $CACHE_BYTES"; exit 1; }
echo "  cache OK ($CACHE_BYTES bytes)"

echo "== export totals (only read under --stage2-export-total all; patch 0107)"
ET="baci_hs92_v202601_elast_country_hs4_export_totals.rds"
if aws s3 cp "$BUCKET/cache/$ET" "$OUT/$ET" --only-show-errors 2>/dev/null; then echo "  placed $OUT/$ET"; else echo "  not on S3 (fine unless the run uses --stage2-export-total all)"; fi

echo "== released tables (hash-verified) and Stage 1 placement"
Rscript scripts/download_outputs.R
cp "data/derived/stage1/$S1" "$OUT/"
WANT=$(grep "stage1/$S1" data/manifest.csv | grep -o '[0-9a-f]\{64\}')
GOT=$(sha256sum "$OUT/$S1" | cut -d' ' -f1)
[ "$GOT" = "$WANT" ] || { echo "setup.sh: Stage-1 sha $GOT is not the manifest's $WANT"; exit 1; }
echo "  Stage 1 placed and verified (${GOT:0:16})"
echo "setup.sh: done. Next: open tmux (tmux new -s rc), then launch through scripts/box/preflight.sh."
