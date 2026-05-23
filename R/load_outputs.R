#' R/load_outputs.R
#'
#' HuggingFace dataset download helpers. Reads data/manifest.csv,
#' verifies SHA-256 checksums, downloads missing files.
#'
#' Exported functions:
#'   load_outputs(force, verify)        -- download/verify all manifested files
#'   verify_checksum(path, expected_sha) -- single-file checksum verify
#'   verify_manifest_complete()          -- fail-fast check used by analysis/master.R
#'
#' Depends on: R/dependencies.R (data.table, openssl)
#'
#' Notes:
#'   - Checksums and hf_url values in data/manifest.csv are placeholders at
#'     commit 1; Section 10 fills them at HF-push time. verify = TRUE will
#'     therefore fail until the manifest carries real SHA-256 values. Call
#'     with verify = FALSE before the manifest is finalized.

load_outputs <- function(force = FALSE, verify = TRUE) {
  manifest <- data.table::fread("data/manifest.csv")
  for (i in seq_len(nrow(manifest))) {
    local <- manifest$local_path[i]
    dir.create(dirname(local), showWarnings = FALSE, recursive = TRUE)
    if (file.exists(local) && !force) {
      if (verify) verify_checksum(local, manifest$sha256[i])
      message(sprintf("[ok] %s already present%s",
                      local, if (verify) " and verified" else ""))
      next
    }
    tmp <- tempfile(fileext = paste0(".", tools::file_ext(local)))
    utils::download.file(manifest$hf_url[i], tmp, mode = "wb", quiet = TRUE)
    if (verify) verify_checksum(tmp, manifest$sha256[i])
    file.rename(tmp, local)
    message(sprintf("[ok] %s downloaded%s",
                    local, if (verify) " and verified" else ""))
  }
  invisible(TRUE)
}

verify_checksum <- function(path, expected_sha) {
  if (is.na(expected_sha) || !nzchar(expected_sha) ||
      identical(expected_sha, "PLACEHOLDER")) {
    stop(sprintf(paste0("No real checksum in manifest for %s ",
                        "(value: '%s'). The manifest still carries commit-1 ",
                        "placeholders; re-run with verify = FALSE or finalize ",
                        "the manifest (Section 10)."),
                 path, expected_sha))
  }
  actual <- as.character(openssl::sha256(file(path)))
  if (!identical(actual, expected_sha)) {
    stop(sprintf("Checksum mismatch for %s\n  expected: %s\n  actual:   %s",
                 path, expected_sha, actual))
  }
  invisible(TRUE)
}

verify_manifest_complete <- function() {
  manifest <- data.table::fread("data/manifest.csv")
  missing <- manifest$local_path[!file.exists(manifest$local_path)]
  if (length(missing) > 0) {
    stop("data/derived/ is missing the following files:\n",
         paste("  ", missing, collapse = "\n"),
         "\nRun: Rscript scripts/download_outputs.R")
  }
  invisible(TRUE)
}
