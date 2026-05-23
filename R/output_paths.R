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
