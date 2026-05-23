#' ===========================================================================
#' R/feen94_het_baci.R
#'
#' Thin wrapper for the Soderbery (2018) heterogeneous elasticity estimation
#' library. Sources the 15 split files in `R/` in dependency-safe order,
#' then loads the Rcpp objective implementations from a configurable cpp_dir.
#'
#' This file replaces the original 3,436-line monolithic feen94_het_baci.R
#' but preserves its source contract: callers can still do
#'   source("R/feen94_het_baci.R")
#' and get a fully-loaded library. No changes are required in run_estimation.R
#' or the test suite.
#'
#' CITATION:
#'   Soderbery, Anson, "Trade Elasticities, Heterogeneity, and Optimal
#'   Tariffs," JIE, 114, 2018, pp. 44-62.
#'
#' Refactored: 2026-05-15 (step 3 of repo refactor)
#' Original last updated: 2026-04-16
#' ===========================================================================

# ---------------------------------------------------------------------------
# Resolve the directory containing this wrapper. All splits live alongside it.
# Robust to being sourced both via Rscript and interactively.
# ---------------------------------------------------------------------------
.this_file_dir <- function() {
  # When sourced via source("path/to/feen94_het_baci.R") — covers both
  # interactive sourcing AND being source()d from an outer Rscript-driven
  # script. The outer script's --file= would point to the wrong location,
  # so check ofile first.
  if (!is.null(sys.frames())) {
    for (frm in rev(sys.frames())) {
      ofile <- frm$ofile
      if (!is.null(ofile)) {
        return(normalizePath(dirname(ofile), mustWork = FALSE))
      }
    }
  }
  # When feen94_het_baci.R is itself the top-level Rscript target
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    return(normalizePath(dirname(sub("^--file=", "", file_arg)),
                         mustWork = FALSE))
  }
  # Last resort
  normalizePath(getwd(), mustWork = FALSE)
}

.R_dir <- .this_file_dir()

# ---------------------------------------------------------------------------
# Attach package dependencies (C3, D14). Sourcing this file alone must still
# yield a fully-loaded library (the wrapper's source contract), so we pull in
# dependencies.R here rather than relying on the caller to have done so.
# ---------------------------------------------------------------------------
source(file.path(.R_dir, "dependencies.R"))


# ---------------------------------------------------------------------------
# Source the split files in dependency-safe order.
#
# The order respects calls between files (e.g. estimate_cell_fixed_sigma.R
# calls helpers.R functions). It's not strictly necessary to source in this
# order because R looks up function names at call time, not at definition
# time — but doing so makes the dependency graph explicit and easier to
# audit. See the topological sort that produced this order in step 3.
# ---------------------------------------------------------------------------
.split_files <- c(
  # Leaves (no inter-file dependencies)
  "utils_general.R",
  "hs_codes.R",
  "load_baci.R",
  "output_paths.R",
  "quality_log.R",
  "region_map.R",
  "validate_config.R",
  "liml_estimator.R",              # NEW: HLIML/Fuller LIML per-cell library (G&S 2024 port)
  # Depends on the above
  "estimate_cell_homogeneous.R",   # helpers, region_map
  "prepare_data.R",                # hs_codes, load_baci, quality_log, region_map, validate_config
  "summary.R",                     # output_paths
  # Depends on cell-level homogeneous + leaves
  "estimate_cell_fixed_sigma.R",   # estimate_cell_homogeneous, helpers, prepare_data, region_map
  "estimate_stage1_feenstra.R",             # estimate_cell_homogeneous, helpers, output_paths, prepare_data
  # The Rcpp loader. Defines flags and the pure-R fallback for het_obj_fixed_sigma.
  # Must be sourced before the parallel drivers, which reference these globals.
  "load_rcpp.R",
  # Drivers
  "estimate_parallel.R",           # the cell-level + fixed_sigma estimators, load_rcpp, output_paths
  "stage1_liml_wrapper.R",         # NEW: HLIML driver, depends on liml_estimator.R
  "lambda_calibration.R",          # estimate_parallel, prepare_data, summary
  "iteration_helpers.R"            # estimate_parallel, lambda_calibration, region_map
)

for (f in .split_files) {
  p <- file.path(.R_dir, f)
  if (!file.exists(p)) {
    stop("Refactored split file not found: ", p,
         "\nExpected all 15 R/*.R files to be in the same directory as ",
         "feen94_het_baci.R itself.")
  }
  source(p)
}


# ---------------------------------------------------------------------------
# Load Rcpp objectives from the configured .cpp source directory.
#
# Resolution order for the cpp_dir:
#   1. <repo>/src/  — the canonical location, populated by hard links to the
#      original .cpp files (see step 4 of the refactor). Self-contained.
#   2. Env var TRADE_ELAST_CPP, if set (override for non-standard layouts)
#   3. Env var TRADE_ELAST_SRC, if set (covers cases where R + .cpp are
#      colocated, e.g. the pre-refactor monolith)
#   4. The wrapper's own directory (.R_dir) as a final fallback
# If none contains the .cpp files, load_rcpp_objectives() leaves the flags
# FALSE and downstream code uses pure-R fallbacks.
# ---------------------------------------------------------------------------
.resolve_cpp_dir <- function() {
  # 1. <repo>/src/ — wrapper is in R/, so repo root is one level up
  repo_src <- normalizePath(file.path(.R_dir, "..", "src"), mustWork = FALSE)
  if (dir.exists(repo_src) &&
      file.exists(file.path(repo_src, "het_obj_fixed_sigma_rcpp.cpp"))) {
    return(repo_src)
  }
  # 2-3. Env var overrides
  for (env in c("TRADE_ELAST_CPP", "TRADE_ELAST_SRC")) {
    v <- Sys.getenv(env, unset = "")
    if (nzchar(v) && dir.exists(v)) return(normalizePath(v))
  }
  # 4. Same directory as the wrapper itself
  .R_dir
}

load_rcpp_objectives(cpp_dir = .resolve_cpp_dir())


# ---------------------------------------------------------------------------
# Citation banner (preserves the original library's behaviour).
# ---------------------------------------------------------------------------
cat("HETEROGENEOUS IMPORT DEMAND AND EXPORT SUPPLY ELASTICITIES\n")
cat("  Soderbery (2018), JIE 114, pp. 44-62.\n")
cat("  Applied to CEPII BACI data.\n")
cat("  PLEASE CITE ACCORDINGLY.\n\n")

cat("Core library loaded (v2: two-stage + tiered estimator).\n")
cat("  Use run_estimation.R for the three-stage pipeline.\n")
