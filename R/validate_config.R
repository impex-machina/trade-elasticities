#' R/validate_config.R
#'
#' Config validation: check the cfg list for completeness and internal
#' consistency before an estimation run.
#' Extracted from feen94_het_baci.R (lines 257-343) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   validate_config(cfg)  — validate an estimation config
#'
#' Depends on: none

# ===========================================================================
#  CONFIG VALIDATION
# ===========================================================================

#' Validate config for obvious misconfigurations before expensive operations.
#'
#' Checks that required fields exist, types are correct, and values are
#' logically consistent. Stops with an informative error on failure.
#' Warns on likely-problematic but non-fatal settings.
#'
#' @param cfg Config list.
validate_config <- function(cfg) {

  # --- Required fields ---
  required <- c("filepath", "value", "quan", "good", "importer", "exporter",
                "time", "minyear", "agg_level", "use_regions",
                "min_exporters", "min_destinations", "min_periods",
                "sigma_start", "gamma_start", "sigma_V_default",
                "gamma_V_default", "tail_trim_pct")
  missing <- setdiff(required, names(cfg))
  if (length(missing) > 0L) {
    stop("Config missing required fields: ", paste(missing, collapse = ", "))
  }

  # --- Filepath ---
  if (!file.exists(cfg$filepath)) {
    stop("Data path does not exist: ", cfg$filepath)
  }

  # --- Aggregation level ---
  if (!cfg$agg_level %in% c("hs4", "hs6")) {
    stop("agg_level must be 'hs4' or 'hs6', got: ", cfg$agg_level)
  }

  # --- Year range ---
  if (!is.numeric(cfg$minyear) || cfg$minyear < 1900 || cfg$minyear > 2100) {
    stop("minyear must be a reasonable year, got: ", cfg$minyear)
  }
  if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) {
    if (!is.numeric(cfg$maxyear) || cfg$maxyear < cfg$minyear) {
      stop("maxyear must be >= minyear (", cfg$minyear, "), got: ", cfg$maxyear)
    }
    year_span <- cfg$maxyear - cfg$minyear + 1L
    if (year_span < cfg$min_periods + 1L) {
      warning(sprintf(paste("Year range (%d-%d = %d years) may be too short",
                            "for min_periods=%d (need %d+ years of data",
                            "after first-differencing)."),
                      cfg$minyear, cfg$maxyear, year_span,
                      cfg$min_periods, cfg$min_periods + 1L))
    }
  }

  # --- Structural defaults ---
  if (cfg$sigma_V_default <= 1) {
    stop("sigma_V_default must be > 1, got: ", cfg$sigma_V_default)
  }
  if (cfg$gamma_V_default <= 0) {
    stop("gamma_V_default must be > 0, got: ", cfg$gamma_V_default)
  }
  if (cfg$sigma_start <= 1) {
    stop("sigma_start must be > 1, got: ", cfg$sigma_start)
  }
  if (cfg$gamma_start <= 0) {
    stop("gamma_start must be > 0, got: ", cfg$gamma_start)
  }

  # --- Filtering ---
  if (cfg$min_exporters < 1L) {
    stop("min_exporters must be >= 1, got: ", cfg$min_exporters)
  }
  if (cfg$min_periods < 2L) {
    warning("min_periods < 2 means single-observation cells may be estimated. ",
            "This is unlikely to produce reliable estimates.")
  }

  # --- Trimming ---
  if (!is.na(cfg$tail_trim_pct) && (cfg$tail_trim_pct < 0 || cfg$tail_trim_pct >= 0.5)) {
    stop("tail_trim_pct must be in [0, 0.5), got: ", cfg$tail_trim_pct)
  }

  invisible(TRUE)
}


# ===========================================================================
#  DATA QUALITY TRACKER
# ===========================================================================
