#!/usr/bin/env Rscript
# scripts/download_outputs.R
#
# Downloads published outputs from HuggingFace to data/derived/.
# Verifies SHA-256 checksums against data/manifest.csv.
# Wall time: depends on bandwidth; ~5-15 min on residential broadband.
#
# Usage: Rscript scripts/download_outputs.R [--force] [--no-verify] [--revision REV] [--manifest PATH]
#
#   --force       re-download even if the local file already exists
#   --no-verify   skip SHA-256 verification (not recommended: the manifest
#                 has carried real checksums since v0.2.0, and verification
#                 is the point of the manifest)
#   --revision    fetch at a hub revision (tag, 40-hex revision or branch)
#   --manifest    verify against another manifest (an earlier release's)
#
# An earlier release (patch 0116): the manifests of tags through v0.11.0 name
# `main`, so fetch with that release's manifest at its revision. Every release
# whose card entry carries a 40-hex data revision has a hub tag of the same
# name (created by patch 0116's runbook; each release creates its own since):
#   git show v0.10.2:data/manifest.csv > m_v0102.csv
#   Rscript scripts/download_outputs.R --manifest m_v0102.csv --revision v0.10.2 --force
# (Windows PowerShell 5.1: its `>` writes UTF-16, which fread cannot read --
#  use cmd /c "git show v0.10.2:data/manifest.csv > m_v0102.csv" instead.)
#
# This script intentionally does NOT use R/parse_cli.R: that parser is the
# estimation pipeline's CLI (it requires --data to be a valid BACI directory
# and validates --stage/--agg-level), which is the wrong contract for a
# download utility. Its flags and options are parsed inline.

source("R/dependencies.R")
source("R/load_outputs.R")

args <- commandArgs(trailingOnly = TRUE)

# (patch 0116) Two flags and two options. A typo still fails loudly rather
# than being silently ignored.
#   --revision REV   fetch every file at that hub revision: a release tag,
#                    a 40-hex data revision from the dataset card, or main
#   --manifest PATH  verify against another manifest, e.g. an earlier
#                    release's: git show v0.10.2:data/manifest.csv > m.csv
usage <- "Usage: Rscript scripts/download_outputs.R [--force] [--no-verify] [--revision REV] [--manifest PATH]"
flags <- c("--force", "--no-verify"); opts_with_value <- c("--revision", "--manifest")
val <- list(); seen <- character(0); i <- 1L
while (i <= length(args)) {
  a <- args[i]
  if (a %in% flags) { seen <- c(seen, a); i <- i + 1L; next }
  if (a %in% opts_with_value) {
    if (i == length(args) || startsWith(args[i + 1L], "--")) stop(a, " needs a value\n", usage, call. = FALSE)
    val[[a]] <- args[i + 1L]; i <- i + 2L; next
  }
  stop("Unknown argument: ", a, "\n", usage, call. = FALSE)
}

load_outputs(
  force         = "--force" %in% seen,
  verify        = !("--no-verify" %in% seen),
  revision      = val[["--revision"]],
  manifest_path = if (is.null(val[["--manifest"]])) "data/manifest.csv" else val[["--manifest"]]
)
