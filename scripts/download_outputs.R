#!/usr/bin/env Rscript
# scripts/download_outputs.R
#
# Downloads published outputs from HuggingFace to data/derived/.
# Verifies SHA-256 checksums against data/manifest.csv.
# Wall time: depends on bandwidth; ~5-15 min on residential broadband.
#
# Usage: Rscript scripts/download_outputs.R [--force] [--no-verify]
#
#   --force       re-download even if the local file already exists
#   --no-verify   skip SHA-256 verification (required until the manifest
#                 carries real checksums; see Section 10)
#
# NB: at commit 1 the manifest's sha256 and hf_url columns are placeholders.
# Until Section 10 finalizes them, run with --no-verify; the download URLs
# will not resolve until the HF dataset is live.
#
# This script intentionally does NOT use R/parse_cli.R: that parser is the
# estimation pipeline's CLI (it requires --data to be a valid BACI directory
# and validates --stage/--agg-level), which is the wrong contract for a
# download utility. The two boolean flags here are parsed inline.

source("R/dependencies.R")
source("R/load_outputs.R")

args <- commandArgs(trailingOnly = TRUE)

# Reject anything that isn't one of the two known flags, so a typo
# (e.g. --no-verfy) fails loudly instead of silently verifying.
known <- c("--force", "--no-verify")
unknown <- setdiff(args, known)
if (length(unknown) > 0) {
  stop("Unknown argument(s): ", paste(unknown, collapse = ", "),
       "\nUsage: Rscript scripts/download_outputs.R [--force] [--no-verify]",
       call. = FALSE)
}

load_outputs(
  force  = "--force" %in% args,
  verify = !("--no-verify" %in% args)
)
