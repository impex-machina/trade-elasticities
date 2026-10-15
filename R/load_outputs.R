#' R/load_outputs.R
#'
#' HuggingFace dataset download helpers. Reads data/manifest.csv,
#' verifies SHA-256 checksums, downloads missing files.
#'
#' Exported functions:
#'   load_outputs(force, verify, revision, manifest_path)
#'                                       -- download/verify all manifested files
#'   hf_url_at_revision(url, revision)   -- point a hub resolve URL at a revision (patch 0116)
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

#' Point a hub `.../resolve/<revision>/<path>` URL at another revision
#' (patch 0116): a release tag (`v0.11.0`), a 40-hex data revision or a
#' branch. NULL or "" returns the URL unchanged. Hub revisions name no paths,
#' so a revision with a slash, a space or a quote is refused.
hf_url_at_revision <- function(url, revision = NULL) {
  if (is.null(revision) || !nzchar(revision)) return(url)
  if (!grepl("^[A-Za-z0-9._-]+$", revision)) stop("hf_url_at_revision(): not a revision name: ", revision)
  if (!all(grepl("/resolve/[^/]+/", url))) stop("hf_url_at_revision(): not a hub resolve URL: ",
                                                 paste(url[!grepl("/resolve/[^/]+/", url)], collapse = ", "))
  sub("/resolve/[^/]+/", paste0("/resolve/", revision, "/"), url)
}

#' (patch 0116) `revision` fetches every file at that hub revision instead of
#' the one each manifest URL names (through v0.11.0 the URLs named `main`, so
#' an older tag's manifest checked main's files against its own hashes and
#' failed on every file changed since). `manifest_path` reads another
#' manifest -- e.g. an earlier release's, `git show v0.10.2:data/manifest.csv`
#' -- whose hashes then verify the download.
load_outputs <- function(force = FALSE, verify = TRUE, revision = NULL,
                         manifest_path = "data/manifest.csv") {
  manifest <- data.table::fread(manifest_path)
  manifest$hf_url <- hf_url_at_revision(manifest$hf_url, revision)
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
  # Binary-mode read is REQUIRED: file(path) without "rb" is a text-mode
  # read on Windows and mangles .rds bytes, so the computed hash does not
  # match the (binary-mode) manifest values -- the Quick Start would fail
  # on Windows against the v0.5.0 manifest. Same fix as
  # scripts/rehash_manifest.R (patch 0018).
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  # openssl::sha256() returns a raw vector classed c("hash", "sha256") and
  # its as.character() method KEEPS that class, so identical() against
  # the plain manifest string is FALSE even when the hex digests are
  # equal (verified with openssl 2.1.1 and the 2.4.0-era source). Strip
  # the class and compare plain, case-normalized hex strings.
  actual <- tolower(unclass(as.character(openssl::sha256(con))))
  expected_sha <- tolower(trimws(expected_sha))
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
