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
m$sha256 <- vapply(m$local_path, function(p) as.character(openssl::sha256(file(p))), character(1))
m$size_bytes <- file.size(m$local_path)
changed <- m$local_path[old != m$sha256]
cat("hashes changed (", length(changed), "):\n", sep = "")
for (p in changed) cat("  ", p, "\n", sep = "")
fwrite(m, "data/manifest.csv", quote = TRUE)
cat("manifest rewritten: data/manifest.csv\n")
