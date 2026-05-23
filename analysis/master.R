#!/usr/bin/env Rscript
# analysis/master.R
#
# Reproduces all paper figures and tables.
# Reads from data/derived/ (populated by scripts/download_outputs.R).
#
# Default: ~5 min wall time (reads published outputs, makes figures).
# With --rerun-pillars: ~25 min (re-runs validation pillars 2, 3, 4 from
# validation/ scripts instead of reading their published CSVs).
#
# Usage:
#   Rscript analysis/master.R
#   Rscript analysis/master.R --rerun-pillars
#   Rscript analysis/master.R --skip-pillar=3
#   Rscript analysis/master.R --output-dir analysis/figures
#
# NB: this does NOT source R/parse_cli.R. parse_cli() is the estimation
# CLI (optparse-based per E3); it requires --data and rejects unknown
# flags, so it cannot parse master's flags. They are parsed inline below.
#
# Script discovery: master runs analysis/NN_*.R in sorted order. A gap in
# the numbering (01, 02, 04 with no 03) is NOT an error -- master runs
# whatever matches the pattern. Keep the numbering contiguous by convention.
#
# Run log: a single master process appends to run_log.txt. Analysis scripts
# that fork (mclapply) must not write to the log from child processes.

source("R/dependencies.R")
source("R/load_outputs.R")

`%||%` <- function(a, b) if (is.null(a)) b else a

parse_master_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list(rerun_pillars = FALSE, skip_pillar = NULL,
              output_dir = "analysis/figures")
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (a == "--rerun-pillars") {
      out$rerun_pillars <- TRUE
    } else if (a == "--skip-pillar" && i < length(args)) {
      out$skip_pillar <- as.integer(args[i + 1]); i <- i + 1
    } else if (grepl("^--skip-pillar=", a)) {
      out$skip_pillar <- as.integer(sub("^--skip-pillar=", "", a))
    } else if (a == "--output-dir" && i < length(args)) {
      out$output_dir <- args[i + 1]; i <- i + 1
    } else if (grepl("^--output-dir=", a)) {
      out$output_dir <- sub("^--output-dir=", "", a)
    } else {
      stop("Unknown argument: ", a,
           "\nUsage: Rscript analysis/master.R ",
           "[--rerun-pillars] [--skip-pillar=N] [--output-dir DIR]",
           call. = FALSE)
    }
    i <- i + 1
  }
  if (!is.null(out$skip_pillar) && is.na(out$skip_pillar)) {
    stop("--skip-pillar requires an integer pillar number.", call. = FALSE)
  }
  out
}

args <- parse_master_args()

# Configuration (exposed as globals; analysis scripts read these)
RERUN_PILLARS <- isTRUE(args$rerun_pillars)
SKIP_PILLAR   <- args$skip_pillar          # NULL or integer
OUTPUT_DIR    <- args$output_dir %||% "analysis/figures"

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUTPUT_DIR, "tables"), showWarnings = FALSE)

# Fail-fast: verify the published outputs are present before any script runs.
# (Until Section 10 finalizes the manifest, run scripts/download_outputs.R
# --no-verify first, or this will report the derived files missing.)
verify_manifest_complete()

# Run log
log_file <- file.path(OUTPUT_DIR, "run_log.txt")
write_log <- function(...) cat(sprintf("[%s] %s\n", Sys.time(), paste(...)),
                               file = log_file, append = TRUE)
file.create(log_file)
write_log("master.R run started")
write_log(sprintf("R version: %s", R.version.string))
write_log(sprintf("RERUN_PILLARS: %s", RERUN_PILLARS))
write_log(sprintf("SKIP_PILLAR: %s", SKIP_PILLAR %||% "<none>"))
write_log(sprintf("Output dir: %s", OUTPUT_DIR))

# Discover numbered scripts
analysis_scripts <- sort(list.files("analysis", pattern = "^\\d+_.*\\.R$",
                                     full.names = TRUE))
write_log(sprintf("Discovered %d analysis scripts", length(analysis_scripts)))

# 00_setup.R loads the published outputs and sets shared plotting state that
# the pillar scripts rely on. Source it into the GLOBAL environment first, so
# its objects are visible to the pillar scripts; then run the rest with
# local = TRUE so each pillar script gets a clean scope.
setup_script <- grep("/00_setup\\.R$", analysis_scripts, value = TRUE)
pillar_scripts <- setdiff(analysis_scripts, setup_script)
if (length(setup_script) == 1) {
  write_log("Running 00_setup.R (global scope)")
  source(setup_script)            # global env on purpose
} else if (length(setup_script) == 0) {
  write_log("WARNING: no 00_setup.R found; pillar scripts may lack shared state")
}

for (script in pillar_scripts) {
  if (!is.null(SKIP_PILLAR)) {
    pillar_match <- regmatches(basename(script),
                               regexpr("pillar\\d+", basename(script)))
    if (length(pillar_match) > 0) {
      pillar_num <- as.integer(sub("pillar", "", pillar_match))
      if (identical(pillar_num, SKIP_PILLAR)) {
        write_log(sprintf("SKIPPING %s (--skip-pillar=%d)",
                          basename(script), SKIP_PILLAR))
        next
      }
    }
  }
  write_log(sprintf("Running %s", basename(script)))
  withCallingHandlers(
    source(script, local = TRUE),
    warning = function(w) write_log(sprintf("  WARNING: %s",
                                            conditionMessage(w)))
  )
}

write_log("master.R run complete")
message("Done. Figures in ", OUTPUT_DIR, "/, tables in ",
        file.path(OUTPUT_DIR, "tables"), "/")
message("Run log: ", log_file)
