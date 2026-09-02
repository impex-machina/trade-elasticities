`%||%` <- function(a, b) if (is.null(a)) b else a

#' R/build_config.R
#'
#' Constructs the cfg list consumed by feen94_het_baci.R from parsed CLI
#' options. Methodological constants (column names, starting values,
#' weighting scheme, trimming) are baked in here — changing them requires
#' editing source, the correct discipline for reproducibility.
#'
#' Exported functions:
#'   build_config(opts)                      — build estimation config from parsed CLI options
#'   build_output_path(cfg, out_dir, scope)  — construct a scoped output path
#'
#' Depends on: parse_cli.R (consumes opts); none at load time


#' Build the estimation config from parsed CLI options.
#'
#' @param opts Output of parse_cli().
#' @return A list satisfying validate_config() in feen94_het_baci.R.
#' @export
build_config <- function(opts) {

  # NA from --maxyear means "use all data"; the library expects NULL there.
  maxyear <- if (is.na(opts$maxyear)) NULL else as.integer(opts$maxyear)

  list(
    # --- BACI column names (BACI schema is fixed) ---
    value    = "v",
    quan     = "q",
    good     = "k",
    importer = "j",
    exporter = "i",
    time     = "t",

    # --- Data (from CLI) ---
    filepath  = opts$data,
    minyear   = as.integer(opts$minyear),
    maxyear   = maxyear,
    agg_level = opts$agg_level,

    # --- Aggregation (set per stage by the runner) ---
    use_regions       = NULL,
    custom_region_map = NULL,

    # --- Filtering (methodological constants) ---
    min_exporters        = 2L,
    min_destinations     = 2L,
    min_periods          = 3L,
    uv_outlier_threshold = 2.0,

    # --- Starting values (Soderbery Table 2 medians) ---
    sigma_start     = 2.88,
    gamma_start     = 0.69,
    sigma_V_default = 2.88,
    gamma_V_default = 0.69,

    # --- Shrinkage (from CLI) ---
    shrinkage_lambda = opts$shrinkage_lambda,

    # --- BW weight lag policy (from CLI) ---
    #
    # v0.5.0: the CLI default is "calendar" — the fn-14 lag is the cell
    # panel's previous CALENDAR year (Soderbery p. 50 fn 14), attached
    # before cell-level filtering; rows whose t-1 is genuinely unobserved
    # fall to bw_weight()'s NA -> 1 fallback. "legacy" (the previous
    # RETAINED row via positional shift — after a filtered-out year, a
    # stale x_{t-2+}) reproduces published v0.4.x output bit-for-bit and
    # remains available for reproduction runs and the negative-control
    # tests.
    #
    # ABSENT-KEY RULE: the estimators read the flag with
    # identical(cfg$bw_lag, "calendar"), so a cfg list WITHOUT the key
    # runs legacy. That is deliberate — hand-built cfg lists (tests,
    # validation harnesses, captures) predate the flag and must keep
    # reproducing published v0.4.x bit-for-bit; only CLI-built configs
    # carry the new default. The flip shipped with the v0.5.0 release
    # train (EC2 rerun, compare_runs.R A/B v0.4.1 -> v0.5.0-rc, card
    # changelog + supersession, manifest rehash, gated HF upload). Both
    # modes stay locked by tests/testthat/test-bw-weight-gaps.R.
    bw_lag = opts$bw_lag,
    stage2_gradient = opts$stage2_gradient %||% "numeric",
    # patch 0043: closed-form admissibility rule (Stage 1 only; carried in
    # the config for provenance). Absent key == legacy, like bw_lag.
    stage1_cf_admissibility = opts$stage1_cf_admissibility %||% "legacy",
    # patch 0046: negative-omega rule for the Feenstra inversion (Stage 1).
    stage1_negative_omega = opts$stage1_negative_omega %||% "reject",

    # --- Across-exporter weighting (methodological) ---
    exporter_weight     = "trade_value",
    weight_period_floor = 10L,

    # --- Tier thresholds (methodological) ---
    tier1_min_periods = 3L,
    tier1_min_dests   = 2L,
    tier2_min_periods = 3L,

    # --- Post-estimation trimming (methodological) ---
    tail_trim_pct = 0.005
  )
}


#' Build a fully-qualified output prefix combining --out-dir with the
#' source-derived basename.
#'
#' The library's build_output_prefix() returns a bare basename like
#' "baci_hs92_v202601_elast_country_hs4". This wraps it so all downstream
#' file paths land in --out-dir without touching the stage bodies in
#' run_estimation.R.
#'
#' @param cfg A config list (from build_config).
#' @param out_dir Output directory (from opts$out_dir).
#' @param scope "country" or "regional".
#' @return Path prefix usable with paste0() to construct output filenames.
#' @export
build_output_path <- function(cfg, out_dir, scope) {
  if (!exists("build_output_prefix")) {
    stop("build_output_prefix() not found. Source feen94_het_baci.R first.")
  }
  file.path(out_dir, build_output_prefix(cfg, scope = scope))
}
