# ============================================================================
# helper-paths.R
#
# Locate the directory containing feen94_het_baci.R (the wrapper) and the
# directory containing the .cpp files. After step 3's modularization,
# these may be different directories:
#
#   - feen94_het_baci.R is the thin wrapper in this repo's R/ directory.
#     Pointed at by TRADE_ELAST_SRC.
#   - .cpp files stay in the original project source/ folder. Pointed at
#     by TRADE_ELAST_CPP (defaults to TRADE_ELAST_SRC when unset, which
#     covers the pre-refactor case where R and .cpp lived together).
#
# This mirrors the resolution logic in R/feen94_het_baci.R's wrapper.
# ============================================================================

#' Locate the directory containing the wrapper feen94_het_baci.R.
#'
#' @return Absolute path to the directory containing feen94_het_baci.R.
#' @keywords internal
locate_source_dir <- function() {
  env_dir <- Sys.getenv("TRADE_ELAST_SRC", unset = "")
  if (nzchar(env_dir)) {
    if (!dir.exists(env_dir)) {
      stop("TRADE_ELAST_SRC is set to '", env_dir, "' but that directory ",
           "does not exist.")
    }
    if (!file.exists(file.path(env_dir, "feen94_het_baci.R"))) {
      stop("TRADE_ELAST_SRC='", env_dir, "' does not contain ",
           "feen94_het_baci.R.")
    }
    return(normalizePath(env_dir))
  }

  # Walk up from the test directory looking for feen94_het_baci.R
  # in any direct subdirectory named R or source.
  start <- tryCatch(testthat::test_path(), error = function(e) getwd())
  dir <- normalizePath(start, mustWork = FALSE)
  for (i in seq_len(6L)) {
    for (sub in c(".", "R", "source")) {
      cand <- file.path(dir, sub, "feen94_het_baci.R")
      if (file.exists(cand)) {
        return(normalizePath(file.path(dir, sub)))
      }
    }
    parent <- dirname(dir)
    if (parent == dir) break
    dir <- parent
  }

  stop("Could not locate feen94_het_baci.R. Set TRADE_ELAST_SRC to the ",
       "directory containing it, e.g.:\n  ",
       "Sys.setenv(TRADE_ELAST_SRC = '/path/to/R')")
}


#' Locate the directory containing the .cpp source files.
#'
#' After step 4 (cpp self-containment), the canonical location is
#' <repo>/src/. The env vars and wrapper-dir fallbacks remain as overrides
#' for non-standard layouts. Precedence mirrors R/feen94_het_baci.R.
#'
#' @return Absolute path to the .cpp directory.
#' @keywords internal
locate_cpp_dir <- function() {
  # 1. Repo-local src/ (canonical post-step-4 location)
  src_dir <- locate_source_dir()  # this is <repo>/R/
  repo_src <- normalizePath(file.path(src_dir, "..", "src"),
                             mustWork = FALSE)
  if (dir.exists(repo_src) &&
      file.exists(file.path(repo_src, "het_obj_fixed_sigma_rcpp.cpp"))) {
    return(repo_src)
  }
  # 2-3. Env var overrides
  for (env in c("TRADE_ELAST_CPP", "TRADE_ELAST_SRC")) {
    v <- Sys.getenv(env, unset = "")
    if (nzchar(v) && dir.exists(v)) {
      return(normalizePath(v))
    }
  }
  # 4. Final fallback: wrapper's own dir
  src_dir
}


#' Assert the two .cpp files Stage 2b's SE pipeline depends on are present.
#'
#' Unchanged from step 1 except the search path now uses locate_cpp_dir()
#' rather than the source dir directly.
#'
#' @keywords internal
assert_cpp_files_present <- function(cpp_dir = NULL) {
  if (is.null(cpp_dir)) cpp_dir <- locate_cpp_dir()
  required <- c("het_obj_fixed_sigma_rcpp.cpp",
                "het_obj_fixed_sigma_jacobian_rcpp.cpp")
  present <- file.exists(file.path(cpp_dir, required))
  if (!all(present)) {
    missing <- required[!present]
    stop("Stage 2b end-to-end test requires Rcpp source files. Missing: ",
         paste(missing, collapse = ", "), "\n  searched in: ", cpp_dir,
         "\nSet TRADE_ELAST_CPP to the directory containing the .cpp files.")
  }
  invisible(TRUE)
}


# Compatibility for older R versions; testthat already provides %||%.
`%||%` <- function(a, b) if (is.null(a)) b else a
