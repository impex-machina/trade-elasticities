# =============================================================================
# analysis/hs6_survivorship_census.R
#
# HS6 vs HS4 estimability census over the raw BACI CSVs -- the go/no-go
# number for any HS6 estimation project. The pipeline's log-double-difference
# estimator silently drops non-continuous trade; this script quantifies, at
# each HS level, how much of the matrix survives the estimability guards:
#   an exporter QUALIFIES in a cell (importer x good) if it has at least
#   `min_pairs` consecutive-year pairs; a cell is ESTIMABLE if it has at
#   least `min_exporters` qualifying exporters (pipeline default: 4,
#   mirroring run_stage1_liml; reference continuity is approximated by
#   these guards, not modeled exactly).
# Reported per (hs_level x guard combo): cells total/estimable, share of
# routes (importer-exporter-good triples), and share of trade value inside
# estimable cells. HS4 is derived from the same read (substr of the HS6
# code), so both levels come from one pass.
#
# Usage (r7a.16xlarge; ~1h incl. S3 pull; run AFTER Phase 3 upload,
# BEFORE terminate -- outputs go to a census/ prefix, never the release):
#   mkdir -p /tmp/census/baci && cd /tmp/v040/trade-elasticities
#   aws s3 cp s3://trade-elast-baci-hs92-v202601-hs4/<BACI_CSV_PREFIX>/ \
#     /tmp/census/baci/ --recursive --exclude "*" --include "BACI_HS92_Y*_V202601*.csv"
#   Rscript analysis/hs6_survivorship_census.R --data /tmp/census/baci \
#     --out /tmp/census/hs6_survivorship_census.csv
#   aws s3 cp /tmp/census/hs6_survivorship_census.csv \
#     s3://trade-elast-baci-hs92-v202601-hs4/census/
#
# BACI columns: t = year, i = exporter, j = importer, k = HS6 product
# (character; leading zeros matter), v = value. Memory: full HS6 panel is
# ~10 GB in-memory as (j,k,i,t,v) -- fine on the r7a; do not run locally
# unless you have ~64 GB free.
# =============================================================================

suppressMessages(library(data.table))

args <- commandArgs(trailingOnly = TRUE)
getopt <- function(flag, default) {
  w <- which(args == flag)
  if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
data_dir  <- getopt("--data", "data/raw")
out_path  <- getopt("--out", "hs6_survivorship_census.csv")
min_exp_g <- as.integer(strsplit(getopt("--min-exporters", "4"), ",")[[1]])
min_prs_g <- as.integer(strsplit(getopt("--min-pairs", "3,5"), ",")[[1]])

files <- list.files(data_dir, pattern = "BACI_HS.*_Y\\d{4}_V.*\\.csv$",
                    full.names = TRUE)
if (length(files) == 0L) stop("No BACI_HS*_Y*_V*.csv files under: ", data_dir)
cat(sprintf("hs6_survivorship_census | %d year files under %s\n",
            length(files), data_dir))

# One pass: keep (importer j, good k, exporter i, year t, value v),
# pre-summed within tuple to shrink early.
read_one <- function(f) {
  d <- fread(f, select = c("t", "i", "j", "k", "v"),
             colClasses = list(character = "k"))
  d[, .(v = sum(v, na.rm = TRUE)), by = .(j, k, i, t)]
}
dt <- rbindlist(lapply(files, read_one))
setnames(dt, c("importer", "good6", "exporter", "year", "value"))
cat(sprintf("  presence tuples (HS6): %s rows | years %d-%d | value %.3e\n",
            format(nrow(dt), big.mark = ","), min(dt$year), max(dt$year),
            sum(dt$value)))

census_level <- function(dt, good_col, hs_label) {
  g <- dt[, .(value = sum(value)),
          by = .(importer, good = get(good_col), exporter, year)]
  setkey(g, importer, good, exporter, year)
  # consecutive-year pairs per route
  routes <- g[, .(pairs = sum(diff(sort(unique(year))) == 1L),
                  value = sum(value)),
              by = .(importer, good, exporter)]
  total_value  <- routes[, sum(value)]
  total_routes <- nrow(routes)
  total_cells  <- uniqueN(routes[, .(importer, good)])
  out <- list()
  for (me in min_exp_g) for (mp in min_prs_g) {
    cells <- routes[, .(n_qual = sum(pairs >= mp)), by = .(importer, good)]
    est   <- cells[n_qual >= me, .(importer, good)]
    rsub  <- routes[est, on = c("importer", "good")]
    out[[length(out) + 1L]] <- data.table(
      hs_level = hs_label, min_exporters = me, min_pairs = mp,
      cells_total = total_cells, cells_estimable = nrow(est),
      share_cells = nrow(est) / total_cells,
      share_routes = nrow(rsub) / total_routes,
      share_value = rsub[, sum(value)] / total_value)
  }
  rbindlist(out)
}

res6 <- census_level(dt, "good6", "HS6")
dt[, good4 := substr(good6, 1, 4)]
res4 <- census_level(dt, "good4", "HS4")
res <- rbindlist(list(res4, res6))

cat("\n  level min_exp min_pairs   cells_total  estimable  sh_cells sh_routes sh_value\n")
for (r in seq_len(nrow(res))) with(res[r], cat(sprintf(
  "  %-5s %7d %9d  %12s %10s   %6.1f%%   %6.1f%%  %6.1f%%\n",
  hs_level, min_exporters, min_pairs,
  format(cells_total, big.mark = ","), format(cells_estimable, big.mark = ","),
  100 * share_cells, 100 * share_routes, 100 * share_value)))
fwrite(res, out_path)
cat(sprintf("\n  written: %s\n", out_path))
cat("  NOTE: guards approximate estimability (reference continuity not\n")
cat("  modeled); shares are upper bounds on the estimable set.\n")
