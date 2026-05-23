#' R/dependencies.R
#'
#' Consolidated CRAN package dependencies for the trade-elasticities pipeline.
#' All unconditional library() calls live here; R/ files do not call library()
#' at top level. (Exception: worker-scoped library() inside clusterEvalQ blocks
#' in estimate_parallel.R and stage1_liml_wrapper.R load packages into PSOCK
#' worker sessions and are intentionally not consolidated here.)
#'
#' Sourced by: scripts/*.R, analysis/*.R, validation/*.R.
#' Required packages are pinned in renv.lock (see Section 5 of the plan).
#'
#' Namespace-qualified dependencies, used via :: and NOT force-loaded here.
#' renv still pins each in the lockfile.
#'   Required (the calling code always needs them when its path runs):
#'     openssl — SHA-256 checksums in R/load_outputs.R (openssl::sha256),
#'              called namespace-qualified. Needed whenever outputs are
#'              downloaded/verified (scripts/download_outputs.R).
#'   Optional (Suggests-style; only some input paths need them):
#'     haven   — only when reading Stata .dta input (R/load_baci.R). The .rds
#'              and .csv input paths need no haven.
#'
#' parallel ships with R but is NOT attached by default; the pipeline calls
#' detectCores(), makeCluster(), parLapply(), mclapply() etc. UNqualified,
#' so it must be attached here (library below), not merely installed.
#'
#' ggplot2 is attached here because the analysis layer (analysis/00_setup.R
#' and the numbered pillar scripts) builds figures with unqualified ggplot()
#' calls and theme functions.
#'
#' Other base/recommended packages used via :: (stats, utils, methods, tools)
#' are attached by default or namespace-qualified, and are NOT declared here.
#'
#' NOTE (D89): this is a living artifact, not a write-once N+6 output. Packages
#' introduced after N+6 — openssl (N+9, Section 3), ggplot2 (N+11, Section 4
#' analysis layer) — are appended here and verified against the renv snapshot
#' at N+11 before the lockfile is locked. The N+10 validation/ migration was
#' re-inventoried at N+11 (D91): no new attached deps beyond ggplot2; the
#' optional arrow fast-path in validate_liml.R was removed rather than locked.
#'
#' Depends on: none
suppressPackageStartupMessages({
  library(data.table)
  library(parallel)
  library(Rcpp)
  library(optparse)
  library(ggplot2)
})
