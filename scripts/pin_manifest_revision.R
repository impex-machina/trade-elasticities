#!/usr/bin/env Rscript
# ============================================================================
# scripts/pin_manifest_revision.R  (patch 0116, fresh-eyes audit #7, item A9)
#
# Points every hf_url in data/manifest.csv at one hub revision -- the release
# tag the data is uploaded under -- so a checkout of the release's git tag
# downloads the files its own hashes describe. Through v0.11.0 every URL named
# `main`: the manifest of an older tag then checked main's files against its
# hashes and scripts/download_outputs.R stopped on every file changed since,
# although the card states that each earlier release "remains available
# pinned at revision ...". Hub revisions can be tags, so the URL can name the
# release before the upload exists; the release train creates the hub tag on
# the uploaded commit (HfApi().create_tag(..., revision=<oid>)) before
# pushing. Only the hf_url column changes; the file is rewritten exactly as
# scripts/rehash_manifest.R writes it (fwrite, quote = TRUE).
#
# Usage (repo root):
#   Rscript scripts/pin_manifest_revision.R --revision v0.11.0     # rewrite
#   Rscript scripts/pin_manifest_revision.R --check                # print the revision(s) named
#   [--manifest PATH]  (default data/manifest.csv)
# ============================================================================

suppressPackageStartupMessages(library(data.table))

manifest_revisions <- function(urls) {
  rev <- sub("^.*/resolve/([^/]+)/.*$", "\\1", urls)
  rev[!grepl("/resolve/[^/]+/", urls)] <- NA_character_
  rev
}

pin_manifest_revision <- function(manifest_path, revision) {
  if (!grepl("^[A-Za-z0-9._-]+$", revision)) stop("pin_manifest_revision(): not a revision name: ", revision)
  m <- fread(manifest_path)
  if (!"hf_url" %in% names(m)) stop("pin_manifest_revision(): no hf_url column in ", manifest_path)
  before <- manifest_revisions(m$hf_url)
  if (anyNA(before)) stop("pin_manifest_revision(): not a hub resolve URL: ", paste(m$hf_url[is.na(before)], collapse = ", "))
  m$hf_url <- sub("/resolve/[^/]+/", paste0("/resolve/", revision, "/"), m$hf_url)
  fwrite(m, manifest_path, quote = TRUE)
  invisible(list(before = unique(before), after = revision, n = nrow(m)))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default = NULL) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
  mp <- get_arg("--manifest", "data/manifest.csv")
  if (!file.exists(mp)) stop("manifest not found: ", mp)
  if ("--check" %in% args) {
    rv <- manifest_revisions(fread(mp)$hf_url)
    cat(sprintf("pin_manifest_revision: %s names %s\n", mp, paste(sprintf("%s (%d)", names(table(rv, useNA = "ifany")), as.integer(table(rv, useNA = "ifany"))), collapse = ", ")))
    quit(status = if (length(unique(rv)) == 1L && !anyNA(rv)) 0L else 1L)
  }
  rev <- get_arg("--revision")
  if (is.null(rev)) stop("usage: Rscript scripts/pin_manifest_revision.R --revision REV | --check [--manifest PATH]")
  res <- pin_manifest_revision(mp, rev)
  cat(sprintf("pin_manifest_revision: %d URLs in %s now name %s (were: %s)\n", res$n, mp, res$after, paste(res$before, collapse = ", ")))
}
