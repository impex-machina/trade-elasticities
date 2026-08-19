#!/usr/bin/env Rscript
# scripts/rehash_manifest.R -- hardened manifest rehash (release step).
suppressMessages(library(data.table))
m <- fread("data/manifest.csv")
missing <- m$local_path[!file.exists(m$local_path)]
if (length(missing)) stop("manifest paths missing on disk: ", paste(missing, collapse = ", "))
disk <- list.files("data/derived", recursive = TRUE, full.names = TRUE,
                   all.files = TRUE)
disk <- disk[basename(disk) != ".gitkeep"]  # tracked empty-dir placeholder, never shipped or manifested
extra <- setdiff(disk, m$local_path)
if (length(extra)) stop("untracked files under data/derived: ", paste(extra, collapse = ", "))
old <- m$sha256
# Binary-mode read is REQUIRED: file(p) without "rb" is a text-mode read on
# Windows and mangles .rds bytes, so the recorded hash does not match standard
# sha256 tools (the v0.4.0/v0.4.1 manifests carried such hashes for their four
# .rds rows; caught by scripts/hf_upload_release.py at the v0.5.0 gate). The
# explicit connection + on.exit(close) keeps the run free of "closing unused
# connection" warnings.
sha_file <- function(p) {
  con <- file(p, "rb")
  on.exit(close(con))
  as.character(openssl::sha256(con))
}
m$sha256 <- vapply(m$local_path, sha_file, character(1))
m$size_bytes <- file.size(m$local_path)
changed <- m$local_path[old != m$sha256]
cat("hashes changed (", length(changed), "):\n", sep = "")
for (p in changed) cat("  ", p, "\n", sep = "")
fwrite(m, "data/manifest.csv", quote = TRUE)
cat("manifest rewritten: data/manifest.csv\n")
