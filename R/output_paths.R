#' R/output_paths.R
#'
#' Output path construction: parse the BACI source identifier from a filepath
#' and build scoped output prefixes.
#' Extracted from feen94_het_baci.R (lines 2291-2330) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   parse_baci_source(filepath)      — parse BACI source id from a path
#'   build_output_prefix(cfg, scope)  — build a scoped output prefix
#'
#' Depends on: none

# ===========================================================================

#' Parse BACI source identifier from the filepath.
#'
#' Extracts the HS revision and version from the BACI directory or file name.
#' Falls back to "baci" if the pattern is not recognized.
#'
#' Examples:
#'   "BACI_HS92_V202601/"       -> "baci_hs92_v202601"
#'   "BACI_HS07_V202601/"       -> "baci_hs07_v202601"
#'   "data/BACI_HS17_V202501/"  -> "baci_hs17_v202501"
#'   "my_trade_data.csv"        -> "baci"
#'
#' @param filepath The BACI data path from config.
#' @return Character string identifying the BACI source.
parse_baci_source <- function(filepath) {
  # Match patterns like BACI_HS92_V202601 anywhere in the path
  m <- regmatches(filepath,
                  regexpr("BACI_HS\\d{2}_V\\d{6}", filepath, ignore.case = TRUE))
  if (length(m) == 1L && nchar(m) > 0L) {
    return(tolower(m))  # e.g., "baci_hs92_v202601"
  }
  "baci"
}


#' Build output file prefix from config.
#'
#' @param cfg Config list with filepath, use_regions, and agg_level.
#' @param scope Character: "regional" or "country". If NULL, inferred
#'   from cfg$use_regions.
#' @return Character string like "baci_hs92_v202601_elast_regional_hs4".
build_output_prefix <- function(cfg, scope = NULL) {
  source_id <- parse_baci_source(cfg$filepath)
  if (is.null(scope)) {
    scope <- if (isTRUE(cfg$use_regions)) "regional" else "country"
  }
  agg <- cfg$agg_level
  paste(source_id, "elast", scope, agg, sep = "_")
}
#' Base path of a run's records (patch 0111): the checkpoints, the Stage-2
#' optimizer-fallback table (<prefix>_stage2_fallbacks.csv) and the tail-trim
#' record (<prefix>_stage2_trimmed.csv/.rds). Through patch 0110 these were
#' written under the bare prefix, i.e. into the working directory, not
#' --out-dir: box sessions moved them into the output folder by hand
#' (docs/box_session_template.md) and two local runs from the same directory
#' overwrote each other's records -- the second run's stale-file sweep
#' (patch 0092) deleted the first's. scripts/run_estimation.R sets
#' cfg$run_record_dir to --out-dir; without it (library and test use) the
#' records stay in the working directory, as in every release.
run_record_base <- function(cfg) {
  d <- cfg[["run_record_dir"]]
  p <- build_output_prefix(cfg)
  if (is.null(d) || !nzchar(d)) p else file.path(d, p)
}


#' Rotate one gamma_V pass's run records to pass-suffixed names (patch 0116).
#'
#' run_estimation.R's native gamma_V iteration re-runs estimate_all_fixed_sigma()
#' once per pass, and every pass writes its records under the same base:
#' <prefix>_stage2_fallbacks.csv, <prefix>_stage2_trimmed.csv and, since patch
#' 0093, the bit-exact twin <prefix>_stage2_trimmed.rds. Through patch 0115 the
#' runner renamed the two CSVs to _pass<k>.csv after each pass but not the .rds,
#' so each pass overwrote the previous pass's twin and the one left behind
#' belonged to the final pass while its CSV had been renamed _pass<k>.csv. All
#' three now rotate together; a missing record is skipped.
#'
#' @param base run_record_base() of the pass's config.
#' @param k the pass number.
#' @return invisibly, the paths written (named by the original path).
rotate_pass_records <- function(base, k) {
  srcs <- paste0(base, c("_stage2_fallbacks.csv", "_stage2_trimmed.csv", "_stage2_trimmed.rds"))
  out <- character(0)
  for (f in srcs) {
    if (!file.exists(f)) next
    to <- sub("(\\.(csv|rds))$", sprintf("_pass%d\\1", as.integer(k)), f)
    if (file.exists(to)) file.remove(to)
    if (!file.rename(f, to)) stop("rotate_pass_records(): could not rename ", f, " to ", to)
    out[f] <- to
  }
  invisible(out)
}
