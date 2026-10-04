# `%||%` lives in R/utils_general.R (patch 0053); sourced before this file by feen94_het_baci.R and by every script that uses build_config().

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
    # patch 0068/0070: domain of the Stage-2 log-ridge. Absent key == all (v0.7.4 default).
    stage2_ridge_domain = opts$stage2_ridge_domain %||% "all",       # patch 0070: default all
    # patch 0069/0070: Stage-2 gamma variance formula. Absent key == sandwich (v0.7.4 default).
    stage2_se = opts$stage2_se %||% "sandwich",   # patch 0070: default sandwich
    # patch 0071/0073: absent == the v0.8.0 default (log prior, maxit 500, both moments on)
    stage2_prior = opts$stage2_prior %||% "log",
    stage2_prior_eps = opts$stage2_prior_eps %||% 0.01,   # patch 0074
    t_parity = opts$t_parity %||% "all",                   # patch 0074
    stage2_maxit = opts$stage2_maxit %||% 5000L,   # patch 0075: v0.8.1 default (500 through v0.8.0)
    stage2_ref_export_moment = opts$stage2_ref_export_moment %||% "on",    # patch 0073: v0.8.0 default
    stage2_import_constant = opts$stage2_import_constant %||% "on",        # patch 0073: v0.8.0 default
    # patch 0077/0080: Nelder-Mead fallback rule; absent key == best (v0.8.3 default; legacy = <= v0.8.2 reproducer).
    stage2_fallback = opts$stage2_fallback %||% "best",
    # patch 0079/0080: Stage-2a rows behind the 2b priors; absent key == estimated (v0.8.3 default; all = <= v0.8.2 reproducer).
    stage2b_prior_source = opts$stage2b_prior_source %||% "estimated",
    # patch 0083: tail-trim semantics; absent key == legacy (<= v0.8.3 reproducer).
    stage2_trim = opts$stage2_trim %||% "v2",                            # patch 0086: v0.9.0 default (legacy = <= v0.8.3)
    # patch 0085: gamma_V source (regional = <= v0.8.3), its table, and the export-side BW period count (rows = <= v0.8.3)
    stage2_gamma_v_source = opts$stage2_gamma_v_source %||% "regional",
    stage2_gamma_v_table = opts$stage2_gamma_v_table %||% "",
    stage2_export_period_count = opts$stage2_export_period_count %||% "panel",   # patch 0086: v0.9.0 default (rows = <= v0.8.3)
    # patch 0086: exporter-specific gamma_V passes (1 = <= v0.8.3) and the sigma-edge rule
    stage2_gamma_v_passes = opts$stage2_gamma_v_passes %||% 3L,
    stage2_sigma_edge = opts$stage2_sigma_edge %||% "publish",
    # patch 0043: closed-form admissibility rule (Stage 1 only; carried in
    # the config for provenance). Absent key == legacy, like bw_lag.
    stage1_cf_admissibility = opts$stage1_cf_admissibility %||% "legacy",
    # patch 0046: negative-omega rule for the Feenstra inversion (Stage 1).
    stage1_negative_omega = opts$stage1_negative_omega %||% "reject",
    # patch 0049: SEs for boundary (edge) optima.
    stage1_edge_se = opts$stage1_edge_se %||% "hncs",
    # patch 0061: sandwich behind the Step-2 SEs. Absent key == kclass
    # (the v0.7.3 default, patch 0064); pass "legacy" to reproduce <= v0.7.2.
    stage1_step2_vce = opts$stage1_step2_vce %||% "kclass",
    # patch 0057: Stage-2's unit-value trim applied inside Stage 1 (NA = off).
    stage1_uv_trim = if (is.null(opts$stage1_uv_trim)) NA_real_ else opts$stage1_uv_trim,
    # patch 0084: Stage-1 sigma cap (10 = <= v0.8.3), capped-cell omega rule, fallback pin (NA = computed)
    stage1_sigma_cap = opts$stage1_sigma_cap %||% 50,                    # patch 0086: v0.9.0 default (10 = <= v0.8.3)
    stage1_capped_omega = opts$stage1_capped_omega %||% "drop",           # patch 0086: v0.9.0 default
    stage2_sigma_fallback_pin = if (is.null(opts$stage2_sigma_fallback_pin)) NA_real_ else opts$stage2_sigma_fallback_pin,

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
