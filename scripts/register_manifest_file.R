#!/usr/bin/env Rscript
# ============================================================================
# scripts/register_manifest_file.R  (patch 0128)
#
# Adds a file under data/derived to data/manifest.csv, or updates its row:
# sha256 (binary read, as scripts/rehash_manifest.R does), size, the hub URL
# at a revision (the path with data/derived/ stripped, the layout
# scripts/hf_upload_release.py uploads to), produced_by, pillar, description.
# Through v0.11.0 the manifest only ever held the pipeline's own files and
# rows were added by hand; v0.11.1 adds the product-level companion table.
# The file is rewritten exactly as rehash_manifest.R writes it
# (fwrite, quote = TRUE); other rows are untouched.
#
# Usage (repo root):
#   Rscript scripts/register_manifest_file.R --local data/derived/product/x.csv
#       --revision v0.11.1 --produced-by "analysis/product_summary.R" --pillar 1
#       --description "..." [--manifest data/manifest.csv]
# ============================================================================

suppressPackageStartupMessages(library(data.table))

HUB_BASE <- "https://huggingface.co/datasets/impex-machina/trade-elasticities/resolve"

#' Register (add or update) one file in a manifest table; returns the new table.
register_manifest_file <- function(m, local, revision, produced_by, pillar, description) {
  if (!grepl("^data/derived/", local)) stop("register_manifest_file(): the file must sit under data/derived/: ", local)
  if (!file.exists(local)) stop("register_manifest_file(): no such file: ", local)
  if (!grepl("^[A-Za-z0-9._-]+$", revision)) stop("register_manifest_file(): not a revision name: ", revision)
  con <- file(local, "rb"); on.exit(close(con))
  sha <- as.vector(unclass(as.character(openssl::sha256(con))))   # a plain string: openssl's class would block rbindlist()
  row <- data.table::data.table(local_path = local, hf_url = paste(HUB_BASE, revision, sub("^data/derived/", "", local), sep = "/"),
                                sha256 = sha, size_bytes = as.numeric(file.size(local)), produced_by = produced_by,
                                pillar = as.integer(pillar), description = description)
  m <- data.table::copy(data.table::as.data.table(m))
  if (local %in% m$local_path) {
    i <- match(local, m$local_path)
    for (k in names(row)) data.table::set(m, i, k, row[[k]])
  } else {
    m <- data.table::rbindlist(list(m, row), use.names = TRUE)
  }
  m
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  local <- get_arg("--local", NA_character_); rev <- get_arg("--revision", NA_character_)
  pb <- get_arg("--produced-by", NA_character_); pil <- get_arg("--pillar", NA_character_); desc <- get_arg("--description", NA_character_)
  mp <- get_arg("--manifest", "data/manifest.csv")
  if (any(is.na(c(local, rev, pb, pil, desc)))) stop("usage: Rscript scripts/register_manifest_file.R --local F --revision R --produced-by P --pillar N --description D")
  local <- gsub("\\\\", "/", local)
  m <- data.table::fread(mp)
  had <- local %in% m$local_path
  m2 <- register_manifest_file(m, local, rev, pb, pil, desc)
  data.table::fwrite(m2, mp, quote = TRUE)
  cat(sprintf("%s %s in %s (%d rows); sha256 %s\n", if (had) "updated" else "added", local, mp, nrow(m2),
              substr(m2$sha256[match(local, m2$local_path)], 1, 12)))
}
