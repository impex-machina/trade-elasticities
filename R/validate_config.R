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

  # --- BW lag policy ---
  # Optional: absent means the estimators run "legacy" (the pre-v0.5.0
  # behaviour, so hand-built cfg lists keep reproducing published
  # v0.4.x). When present it must be a recognized mode, so a
  # typo cannot silently fall back to legacy on a run that intended the
  # calendar fix. NOT in `required` above: hand-built cfg lists (tests,
  # validation harnesses) predate the flag and stay valid without it.
  if (!is.null(cfg$bw_lag) && !cfg$bw_lag %in% c("legacy", "calendar")) {
    stop("bw_lag must be 'legacy' or 'calendar', got: ", cfg$bw_lag)
  }
  if (!is.null(cfg$stage2_gradient) &&
      !cfg$stage2_gradient %in% c("numeric", "analytic")) {
    stop("stage2_gradient must be 'numeric' or 'analytic', got: ", cfg$stage2_gradient)
  }
  if (!is.null(cfg$stage2_se) &&
      !cfg$stage2_se %in% c("legacy", "posterior", "sandwich")) {
    stop("stage2_se must be 'legacy', 'posterior' or 'sandwich', got: ", cfg$stage2_se)
  }
  if (!is.null(cfg[["stage2_prior"]]) && !cfg[["stage2_prior"]] %in% c("log", "level", "share", "shiftlog")) stop("stage2_prior must be 'log', 'level', 'share' or 'shiftlog', got: ", cfg[["stage2_prior"]])
  if (!is.null(cfg$stage2_prior_eps) && (!is.numeric(cfg$stage2_prior_eps) || cfg$stage2_prior_eps <= 0)) stop("stage2_prior_eps must be positive")
  if (!is.null(cfg$t_parity) && !cfg$t_parity %in% c("all", "odd", "even")) stop("t_parity must be 'all', 'odd' or 'even', got: ", cfg$t_parity)
  if (!is.null(cfg$stage2_maxit) && (!is.numeric(cfg$stage2_maxit) || cfg$stage2_maxit < 1)) stop("stage2_maxit must be a positive integer")
  if (!is.null(cfg$stage2_ref_export_moment) && !cfg$stage2_ref_export_moment %in% c("off", "on")) stop("stage2_ref_export_moment must be 'off' or 'on', got: ", cfg$stage2_ref_export_moment)
  if (!is.null(cfg$stage2_import_constant) && !cfg$stage2_import_constant %in% c("off", "on")) stop("stage2_import_constant must be 'off' or 'on', got: ", cfg$stage2_import_constant)
  if (!is.null(cfg$stage2_fallback) && !cfg$stage2_fallback %in% c("legacy", "best")) stop("stage2_fallback must be 'legacy' or 'best', got: ", cfg$stage2_fallback)   # patch 0077
  if (!is.null(cfg$stage2b_prior_source) && !cfg$stage2b_prior_source %in% c("all", "estimated")) stop("stage2b_prior_source must be 'all' or 'estimated', got: ", cfg$stage2b_prior_source)   # patch 0079
  if (!is.null(cfg$stage2_trim) && !cfg$stage2_trim %in% c("legacy", "v2")) stop("stage2_trim must be 'legacy' or 'v2', got: ", cfg$stage2_trim)   # patch 0083
  if (!is.null(cfg$stage2_gamma_v_source) && !cfg$stage2_gamma_v_source %in% c("regional", "table")) stop("stage2_gamma_v_source must be 'regional' or 'table', got: ", cfg$stage2_gamma_v_source)   # patch 0085
  if (!is.null(cfg$stage2_export_period_count) && !cfg$stage2_export_period_count %in% c("rows", "panel")) stop("stage2_export_period_count must be 'rows' or 'panel', got: ", cfg$stage2_export_period_count)   # patch 0085
  if (!is.null(cfg$stage1_sigma_cap) && !(is.finite(cfg$stage1_sigma_cap) && cfg$stage1_sigma_cap > 1)) stop("stage1_sigma_cap must be a number > 1, got: ", cfg$stage1_sigma_cap)   # patch 0084
  if (!is.null(cfg$stage1_capped_omega) && !cfg$stage1_capped_omega %in% c("keep", "drop")) stop("stage1_capped_omega must be 'keep' or 'drop', got: ", cfg$stage1_capped_omega)   # patch 0084
  if (!is.null(cfg$stage2_sigma_fallback_pin) && !is.na(cfg$stage2_sigma_fallback_pin) && !(is.finite(cfg$stage2_sigma_fallback_pin) && cfg$stage2_sigma_fallback_pin > 1)) stop("stage2_sigma_fallback_pin must be NA or a number > 1, got: ", cfg$stage2_sigma_fallback_pin)   # patch 0084
  if (!is.null(cfg$stage2_ridge_domain) &&
      !cfg$stage2_ridge_domain %in% c("legacy", "all")) {
    stop("stage2_ridge_domain must be 'legacy' or 'all', got: ", cfg$stage2_ridge_domain)
  }
  if (!is.null(cfg$stage1_uv_trim) && !is.na(cfg$stage1_uv_trim) &&
      !(is.finite(cfg$stage1_uv_trim) && cfg$stage1_uv_trim > 0)) {
    stop("stage1_uv_trim must be NA or a positive number, got: ", cfg$stage1_uv_trim)
  }
  if (!is.null(cfg$stage1_edge_se) && !cfg$stage1_edge_se %in% c("none", "hncs")) {
    stop("stage1_edge_se must be 'none' or 'hncs', got: ", cfg$stage1_edge_se)
  }
  if (!is.null(cfg$stage1_step2_vce) && !cfg$stage1_step2_vce %in% c("legacy", "kclass")) {
    stop("stage1_step2_vce must be 'legacy' or 'kclass', got: ", cfg$stage1_step2_vce)
  }
  if (!is.null(cfg$stage1_negative_omega) &&
      !cfg$stage1_negative_omega %in% c("floor", "reject")) {
    stop("stage1_negative_omega must be 'floor' or 'reject', got: ",
         cfg$stage1_negative_omega)
  }
  if (!is.null(cfg$stage1_cf_admissibility) &&
      !cfg$stage1_cf_admissibility %in% c("legacy", "strict")) {
    stop("stage1_cf_admissibility must be 'legacy' or 'strict', got: ",
         cfg$stage1_cf_admissibility)
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
