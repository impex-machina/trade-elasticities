#!/usr/bin/env Rscript
#' ===========================================================================
#' scripts/run_estimation.R
#'
#' CLI-driven three-stage estimation pipeline. Functionally equivalent to
#' the original run_est_baci_hs92_v202601_hs4.R but accepts arguments for
#' data path, output directory, year range, ncores, shrinkage_lambda, and
#' stage selection — instead of hardcoding them.
#'
#' USAGE:
#'   Rscript scripts/run_estimation.R --data /path/to/BACI_HS92_V202601 \
#'                                    --out-dir results/2026-05 \
#'                                    --ncores 8 \
#'                                    --shrinkage-lambda 0.05 \
#'                                    --stage all
#'
#'   Rscript scripts/run_estimation.R --help     # full option listing
#'
#' SOURCE FILE LOCATION:
#'   Path resolution for feen94_het_baci.R and the two .cpp files follows
#'   the same env-var pattern as the test suite:
#'     1. TRADE_ELAST_SRC, if set
#'     2. Falls back to a path relative to this script
#'   If neither resolves, the runner errors before parsing CLI args (the
#'   message tells the user which env var to set).
#' ===========================================================================


# ---- 1. Locate source files ------------------------------------------------
# We need feen94_het_baci.R, the two .cpp files, AND R/parse_cli.R + R/build_config.R.
# The first three live in the old project's source/ directory; the latter two
# live in this repo's R/ directory.

.locate_source_dir <- function() {
  env_dir <- Sys.getenv("TRADE_ELAST_SRC", unset = "")
  if (nzchar(env_dir) && dir.exists(env_dir) &&
      file.exists(file.path(env_dir, "feen94_het_baci.R"))) {
    return(normalizePath(env_dir))
  }
  # B10 FIX (v0.3.0): fall back to this repo's R/ directory, where the
  # feen94_het_baci.R wrapper has lived since the step-3 refactor. The
  # README's replication instructions (`Rscript scripts/run_estimation.R
  # --data <dir>`) never mention TRADE_ELAST_SRC, so a fresh clone
  # previously failed here before parsing CLI args. The env var still
  # takes precedence for non-standard layouts.
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  script_dir <- if (length(file_arg) == 1L) {
    dirname(sub("^--file=", "", file_arg))
  } else {
    "."
  }
  repo_r <- normalizePath(file.path(script_dir, "..", "R"), mustWork = FALSE)
  if (dir.exists(repo_r) && file.exists(file.path(repo_r, "feen94_het_baci.R"))) {
    return(repo_r)
  }
  # Sourced interactively from the repo root
  cwd_r <- normalizePath(file.path(".", "R"), mustWork = FALSE)
  if (dir.exists(cwd_r) && file.exists(file.path(cwd_r, "feen94_het_baci.R"))) {
    return(cwd_r)
  }
  stop("Cannot locate feen94_het_baci.R. Set TRADE_ELAST_SRC to the ",
       "source directory:\n  ",
       "Sys.setenv(TRADE_ELAST_SRC = '/path/to/source')\nor in PowerShell:\n  ",
       "$env:TRADE_ELAST_SRC = 'C:\\path\\to\\source'",
       call. = FALSE)
}

.locate_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1L) {
    script_path <- sub("^--file=", "", file_arg)
    return(normalizePath(file.path(dirname(script_path), ".."),
                          mustWork = FALSE))
  }
  # Sourced interactively — assume cwd
  normalizePath(".")
}

src_dir  <- .locate_source_dir()
repo_dir <- .locate_repo_root()

# Source consolidated package dependencies first (C3, D14), then the CLI
# parser and config builder from the repo's R/ directory.
source(file.path(repo_dir, "R", "dependencies.R"))
source(file.path(repo_dir, "R", "parse_cli.R"))
source(file.path(repo_dir, "R", "build_config.R"))


# ---- 2. Parse CLI before doing anything expensive --------------------------
opts <- parse_cli()

cat("Three-stage pipeline\n")
cat(sprintf("  Data:             %s\n", opts$data))
cat(sprintf("  Output:           %s (run records too, patch 0111)\n", opts$out_dir))
cat(sprintf("  Years:            %d -- %s\n",
            opts$minyear,
            if (is.na(opts$maxyear)) "max" else as.character(opts$maxyear)))
cat(sprintf("  Aggregation:      %s\n", opts$agg_level))
cat(sprintf("  Cores:            %d\n", opts$ncores))
cat(sprintf("  Shrinkage lambda: %g\n", opts$shrinkage_lambda))
cat(sprintf("  Stage:            %s\n", opts[["stage"]]))
cat(sprintf("  BW lag mode:      %s | exporter weight: %s | reference rule: %s | export total: %s\n", opts$bw_lag, opts$exporter_weight, opts$stage2_reference_rule, opts$stage2_export_total))   # patch 0091 / 0105 / 0107
cat(sprintf("  Export moment:    %s | Stage-2a handoff rows: %s\n", opts$stage2_export_moment, opts$stage2a_handoff_rows))   # patch 0110
cat(sprintf("  Stage-1 HLIML:    %s\n", opts$stage1_hliml))
cat(sprintf("  Stage-1 CF rule:  %s\n", opts$stage1_cf_admissibility))
cat(sprintf("  Stage-1 neg-omega: %s\n", opts$stage1_negative_omega))
cat(sprintf("  Stage-1 edge SE:  %s\n", opts$stage1_edge_se))
cat(sprintf("  Stage-1 Step-2 VCE: %s\n", opts$stage1_step2_vce))
cat(sprintf("  Stage-1 sigma cap: %g | capped-cell omega in priors: %s | sigma fallback pin: %s\n",   # patch 0084
            opts$stage1_sigma_cap, opts$stage1_capped_omega,
            if (is.na(opts$stage2_sigma_fallback_pin)) "none" else format(opts$stage2_sigma_fallback_pin, digits = 17)))
cat(sprintf("  Stage-1 UV trim:  %s\n", if (is.na(opts$stage1_uv_trim)) "off" else sprintf("|d ln p| < %.1f", opts$stage1_uv_trim)))
cat(sprintf("  Stage-2 gradient: %s\n", opts$stage2_gradient))
cat(sprintf("  Stage-2 ridge domain: %s\n", if (is.null(opts$stage2_ridge_domain)) "legacy" else opts$stage2_ridge_domain))
cat(sprintf("  Stage-2 SE form: %s\n", if (is.null(opts$stage2_se)) "legacy" else opts$stage2_se))
cat(sprintf("  Stage-2 fallback: %s\n", if (is.null(opts$stage2_fallback)) "best" else opts$stage2_fallback))   # patch 0077/0080
cat(sprintf("  Stage-2b prior rows: %s\n", if (is.null(opts$stage2b_prior_source)) "estimated" else opts$stage2b_prior_source))   # patch 0079/0080
cat(sprintf("  Stage-2 trim: %s\n", if (is.null(opts[["stage2_trim"]])) "legacy" else opts[["stage2_trim"]]))   # patch 0083
cat(sprintf("  Stage-2 gamma_V source: %s%s | passes: %s | export period count: %s | sigma edge: %s | sigma pole: %s\n",   # patch 0085/0086/0099
            opts$stage2_gamma_v_source, if (identical(opts$stage2_gamma_v_source, "table")) paste0(" (", opts$stage2_gamma_v_table, ")") else "",
            if (is.null(opts$stage2_gamma_v_passes)) 1L else opts$stage2_gamma_v_passes, opts$stage2_export_period_count,
            if (is.null(opts$stage2_sigma_edge)) "fallback" else opts$stage2_sigma_edge,
            if (is.null(opts$stage2_sigma_pole_rule) || identical(opts$stage2_sigma_pole_rule, "none")) "none"
            else sprintf("%s (c = %s SE)", opts$stage2_sigma_pole_rule, if (is.null(opts$stage2_sigma_pole_se)) 1 else opts$stage2_sigma_pole_se)))
cat(sprintf("  Stage-2 prior: %s (eps %s) | maxit: %s | ref export moment: %s | import constant: %s | product sample: %s | t-parity: %s\n\n",
            if (is.null(opts[["stage2_prior"]])) "log" else opts[["stage2_prior"]], if (is.null(opts$stage2_prior_eps)) 0.01 else opts$stage2_prior_eps,
            if (is.null(opts$stage2_maxit)) 5000L else opts$stage2_maxit,
            if (is.null(opts$stage2_ref_export_moment)) "on" else opts$stage2_ref_export_moment,
            if (is.null(opts$stage2_import_constant)) "on" else opts$stage2_import_constant,
            if (is.null(opts$product_sample)) 1 else opts$product_sample, if (is.null(opts$t_parity)) "all" else opts$t_parity))


# ---- 3. Source library ----------------------------------------------------
# feen94_het_baci.R resolves its own location via .this_file_dir() and
# locates the .cpp files relative to that (CWD-independent), so we source
# it by absolute path with no setwd() (C2, D13).
source(file.path(src_dir, "feen94_het_baci.R"))


# ---- 4. Build config from CLI options -------------------------------------
config <- build_config(opts)
# (patch 0111) the run's records -- checkpoints, the optimizer-fallback table,
# the tail-trim record -- go to --out-dir beside the outputs (every derived
# stage config copies `config`); through patch 0110 they went to the working
# directory. run_record_base() in R/output_paths.R.
config$run_record_dir <- opts$out_dir
ncores <- opts$ncores

# Output prefixes include --out-dir so all downstream concatenations
# (paste0(out_base_*, "_feenstra_sigma.rds")) land in the right place.
out_base_country  <- build_output_path(config, opts$out_dir, scope = "country")
out_base_regional <- build_output_path(config, opts$out_dir, scope = "regional")

cat(sprintf("  Country output base:  %s\n", out_base_country))
cat(sprintf("  Regional output base: %s\n\n", out_base_regional))


# ---- 5. Stage gating helper ------------------------------------------------
# Encodes which stages to run given --stage. 'all' delegates to the
# downstream file.exists() checks (current behavior — resume from cache).
# Specific stages bypass those checks and force a recompute, but error
# if upstream outputs don't exist.

#' Decide whether a stage should run, and assert upstream outputs exist
#' when a specific stage is requested.
should_run <- function(stage, opts, paths) {
  if (opts[["stage"]] == "all") return(TRUE)
  if (opts[["stage"]] != stage) return(FALSE)

  # Specific stage requested: assert upstream files exist
  upstream <- switch(
    stage,
    "1"  = character(0),
    "2a" = paths$sigma_file,
    "2b" = c(paths$sigma_file, paths$regional_file)
  )
  missing <- upstream[!file.exists(upstream)]
  if (length(missing) > 0L) {
    stop(sprintf("--stage %s requires upstream output(s) that do not exist:\n  %s",
                 stage, paste(missing, collapse = "\n  ")),
         call. = FALSE)
  }
  TRUE
}


# ===========================================================================
#  DATA PREPARATION — LOAD ONCE, REUSE EVERYWHERE
# ===========================================================================
# Same as the original runner. Skip when --stage 2a or 2b are requested
# and the per-stage prepared_dt isn't needed (rare; safer to just always
# prepare since prepare_data is cheap relative to the cache file load).

raw_cache_file <- paste0(out_base_country, "_raw_cache.rds")

if (file.exists(raw_cache_file)) {
  cat("Loading cached raw data...\n")
  raw_cache <- readRDS(raw_cache_file)
  cat(sprintf("  %s obs from cache\n\n", format(nrow(raw_cache), big.mark = ",")))
} else {
  config_raw <- config
  config_raw$use_regions <- FALSE
  raw_cache <- prepare_raw_data(config_raw)
  saveRDS(raw_cache, raw_cache_file)
  cat(sprintf("  Cached to: %s\n\n", raw_cache_file))
}

# (patch 0107) --stage2-export-total all: read the all-value export totals once
# for both panels (prepare_data() maps them to regions for Stage 2a).
if (identical(opts$stage2_export_total, "all")) {
  .et_path <- if (!is.null(opts$export_totals_path) && nzchar(opts$export_totals_path)) opts$export_totals_path else paste0(out_base_country, "_export_totals.rds")
  if (!file.exists(.et_path)) stop("--stage2-export-total all: export-totals table not found at ", .et_path, " (build it with scripts/build_export_totals.R)")
  config$export_totals_tbl <- data.table::as.data.table(readRDS(.et_path))
  cat(sprintf("Export totals (all value, incl. flows without a quantity): %s rows from %s\n\n", format(nrow(config$export_totals_tbl), big.mark = ","), .et_path))
}

cat("Preparing country-level estimation data...\n")
config_country <- config
config_country$use_regions <- FALSE
# (patch 0071) --product-sample FRAC --product-seed N: exact for Stage 2
if (!is.null(opts$product_sample) && is.finite(opts$product_sample) && opts$product_sample < 1) {
  data.table::setDT(raw_cache)
  .keep <- sample_products(raw_cache$good, opts$product_sample, opts$product_seed)
  .n_all <- data.table::uniqueN(raw_cache$good)
  raw_cache <- raw_cache[good %in% .keep]
  cat(sprintf("Product sample: %d of %d goods kept (frac %.4f, seed %d); %s obs\n\n",
              length(.keep), .n_all, opts$product_sample, as.integer(opts$product_seed), format(nrow(raw_cache), big.mark = ",")))
}
prep_country <- prepare_data(config_country, raw_cache = raw_cache)
# (patch 0074) --t-parity odd|even: keep half the differenced observations by t
# parity, AFTER prepare_data (lags and shares already attached), for same-period
# split-half experiments; the Stage-2a priors/lookups come from a full-panel 2a
# table, so this is for --stage 2b passes.
if (!is.null(opts$t_parity) && opts$t_parity != "all") {
  .keep_par <- if (opts$t_parity == "odd") 1L else 0L
  .n0 <- nrow(prep_country$dt)
  prep_country$dt <- prep_country$dt[t %% 2L == .keep_par]
  cat(sprintf("t-parity filter (%s): %s of %s differenced observations kept\n\n", opts$t_parity,
              format(nrow(prep_country$dt), big.mark = ","), format(.n0, big.mark = ",")))
}
dt_country <- prep_country$dt
cat(sprintf("  Country data: %s obs\n\n",
            format(nrow(dt_country), big.mark = ",")))

cat("Preparing regional estimation data...\n")
config_regional <- config
config_regional$use_regions <- TRUE
prep_regional <- prepare_data(config_regional, raw_cache = raw_cache)
dt_regional <- prep_regional$dt
cat(sprintf("  Regional data: %s obs\n\n",
            format(nrow(dt_regional), big.mark = ",")))


# Paths used by both stage gating and the stage bodies below
paths <- list(
  sigma_file    = paste0(out_base_country,  "_feenstra_sigma.rds"),
  regional_file = paste0(out_base_regional, "_fixed_sigma.rds"),
  country_file  = paste0(out_base_country,  "_fixed_sigma.rds")
)


# ===========================================================================
#  STAGE 1: FEENSTRA (1994) SIGMA + GAMMA_COMMON
# ===========================================================================

if (should_run("1", opts, paths)) {
  sigma_file <- paths$sigma_file
  
  if (file.exists(sigma_file) && opts[["stage"]] == "all") {
    cat("\n========== STAGE 1: LOADING SIGMA ESTIMATES ==========\n")
    cat(sprintf("  Found: %s\n\n", sigma_file))
    sigma_estimates <- readRDS(sigma_file)
  } else {
    cat("\n========== STAGE 1: HLIML (Grant & Soderbery 2024) ==========\n")
    cat("  Estimator: HLIML with Fuller LIML feasibility fallback\n")
    cat(sprintf("  HLIML method: %s%s\n", opts$stage1_hliml,
                switch(opts$stage1_hliml,
                       closed = " (closed-form eigenvector; boundary routing for cells failing both HLIML and Step 2)",
                       bfgs   = " (v0.5.x wall-penalized BFGS; bit-for-bit reproducer)",
                       both   = " (census mode: bfgs routing + closed form alongside)", "")))
    cat("  Diagnostics: Kleibergen-Paap F, Sargan J, Stock-Yogo screening\n\n")
    
    # run_stage1_liml expects raw BACI columns: (importer, exporter, good, t, value, quantity)
    # prepare_raw_data() returns:               (importer, exporter, good, year, cusval, quantity)
    # Rename to match the wrapper's expected schema.
    baci_for_liml <- copy(raw_cache)
    setnames(baci_for_liml,
             old = c("year", "cusval"),
             new = c("t",    "value"))
    
    # Stage 1 output file from run_stage1_liml is the "rich" 30-column LIML output.
    # We write it to a sibling path so the legacy filename is preserved for traceability.
    liml_output_path <- sub("_feenstra_sigma\\.rds$",
                            "_feenstra_sigma_liml.rds",
                            sigma_file)
    
    run_stage1_liml(
      baci_dt       = baci_for_liml,
      output_path   = liml_output_path,
      n_cores       = ncores,
      min_year      = config_country$minyear,
      min_exporters = config_country$min_exporters,
      min_periods   = config_country$min_periods,
      hliml_method  = opts$stage1_hliml,
      cf_admissibility = opts$stage1_cf_admissibility,   # patch 0043
      negative_omega   = opts$stage1_negative_omega,      # patch 0046
      edge_se          = opts$stage1_edge_se,             # patch 0049
      uv_outlier_threshold = opts$stage1_uv_trim,         # patch 0057 (NA = off)
      step2_vce        = opts$stage1_step2_vce,           # patch 0061
      sigma_cap        = opts$stage1_sigma_cap,           # patch 0084 (10 = <= v0.8.3)
      verbose       = TRUE
    )
    
    # ---- Translate LIML schema → Stage 2 schema ------------------------------
    # Stage 2 reads `sigma`, `gamma`, `convergence`. The LIML output names them
    # `sigma`, `gamma_common`, and `status` ("ok" / various failure strings).
    # Rename + derive convergence here so Stage 2 doesn't need to know about
    # the upstream schema.
    #
    # B5 FIX (v0.3.0): Stage 2's `gamma` must be on the omega scale — the
    # inverse export-supply elasticity that het_obj_fixed_sigma optimizes
    # (its Eq. 10/11 coefficients are gamma/(1+gamma)/(sigma-1), i.e.
    # Soderbery's parameterization; cf. build_config's Soderbery-Table-2
    # defaults gamma_start = gamma_V_default = 0.69). The previous
    # translation renamed the wrapper's `gamma_common` = omega/(1+omega)
    # — a BOUNDED transform — into `gamma`, so the Stage 2a shrinkage
    # anchor (ln_gamma_prior), the plateau fallback, gamma_V_default, and
    # the Tier-3 imputations were all built on the wrong scale,
    # systematically pulling gamma down (by ~ln(1+omega) in logs). Use the
    # omega column directly; gamma_common stays in the rich LIML output.
    cat("\nTranslating LIML schema -> Stage 2 schema...\n")
    sigma_estimates <- readRDS(liml_output_path)
    setDT(sigma_estimates)
    sigma_estimates[, gamma := omega]
    sigma_estimates[, convergence := fifelse(status == "ok", 0L, -99L)]
    sigma_estimates[, good     := as.character(good)]
    sigma_estimates[, importer := as.integer(importer)]
    saveRDS(finalize_saved_output(sigma_estimates), sigma_file)
    cat(sprintf("  LIML output (rich): %s\n", liml_output_path))
    cat(sprintf("  Stage 2 input:      %s\n", sigma_file))
  }
} else {
  # --stage 2a or 2b — load existing Stage 1 output
  sigma_estimates <- readRDS(paths$sigma_file)
  cat(sprintf("Loaded Stage 1 output: %s\n", paths$sigma_file))
}

# The clean set: converged Stage-1 cells with sigma > 1, then (patch 0086)
# --stage2-sigma-edge fallback -- cells whose sigma is a box edge leave it --
# then (patch 0099) --stage2-sigma-pole-rule fallback -- cells whose sigma is
# within --stage2-sigma-pole-se SEs of the pole leave it; both take the
# fallback sigma, supply no sigma_V and leave the priors. Built by
# stage2_sigma_clean() (patch 0103), which also returns each cell's sigma
# provenance for the sigma_source column -- the same code path
# scripts/add_sigma_source.R uses on an existing table.
.sc <- stage2_sigma_clean(sigma_estimates,
                          edge_rule = if (is.null(opts$stage2_sigma_edge)) "fallback" else opts$stage2_sigma_edge,               # patch 0087: absent == fallback
                          pole_rule = if (is.null(opts$stage2_sigma_pole_rule)) "fallback" else opts$stage2_sigma_pole_rule,     # patch 0101: absent == fallback
                          pole_c    = if (is.null(opts$stage2_sigma_pole_se)) 1 else opts$stage2_sigma_pole_se)
sigma_clean <- .sc$clean
sigma_source_lookup <- .sc$source
if (isTRUE(.sc$n_edge_dropped > 0L)) {
  cat(sprintf("  sigma-edge cells dropped from the clean set (fallback sigma, no sigma_V, out of the priors): %s\n",
              format(.sc$n_edge_dropped, big.mark = ",")))
}
if (isTRUE(.sc$n_pole_dropped > 0L)) {
  cat(sprintf("  sigma-pole cells dropped from the clean set (sigma - 1 < %s * SE; fallback sigma, no sigma_V, out of the priors): %s\n",
              if (is.null(opts$stage2_sigma_pole_se)) 1 else opts$stage2_sigma_pole_se, format(.sc$n_pole_dropped, big.mark = ",")))
}
sigma_fallback <- median(sigma_clean$sigma, na.rm = TRUE)
# (patch 0084) --stage2-sigma-fallback-pin: hold the fallback sigma at a given
# value instead of the clean-cell median, so an experiment that changes the
# clean-cell population (a different Stage-1 cap) does not also move the
# sigma of every fallback row through the median. NA (default) = computed.
if (!is.null(opts$stage2_sigma_fallback_pin) && !is.na(opts$stage2_sigma_fallback_pin)) {
  cat(sprintf("  sigma fallback pinned: %.17g (computed median would be %.17g)\n",
              opts$stage2_sigma_fallback_pin, sigma_fallback))
  sigma_fallback <- opts$stage2_sigma_fallback_pin
}

cat(sprintf("\nStage 1: %s clean cells (of %s)\n",
            format(nrow(sigma_clean), big.mark = ","),
            format(nrow(sigma_estimates), big.mark = ",")))
cat(sprintf("  sigma median=%.3f, IQR=[%.3f, %.3f]\n",
            median(sigma_clean$sigma),
            quantile(sigma_clean$sigma, 0.25),
            quantile(sigma_clean$sigma, 0.75)))
cat(sprintf("  gamma (omega-scale) median=%.3f (used as Stage 2a prior)\n\n",
            median(sigma_clean$gamma, na.rm = TRUE)))


# Build Stage-1 priors (used by Stage 2a).
# B5 FIX (v0.3.0): gamma is now omega-scale (see schema translation above).
# Exclude cells where omega is a boundary artifact rather than an estimate:
# adjust == 5 reports the omega cap (10), and omega_floored cells sit at the
# 1e-4 admissibility floor (log = -9.2, which would drag per-good log-medians
# toward the floor for heavily-floored goods). Both are documented in the
# README's Known Limitations as caps/floors, not estimates.
# F2 (v0.4.0): also exclude omega_capped -- under B9 semantics, adjust == 4
# covers sigma-at-cap cells whose omega may ALSO sit at the cap (~0.6% of ok
# cells); without this clause those omega = 10 values leak into the priors.
feenstra_gamma_clean <- sigma_clean[!is.na(gamma) & gamma > 0 &
                                      adjust != 5L &
                                      !(omega_floored %in% TRUE) &
                                      !(omega_capped %in% TRUE)]
# (patch 0084) --stage1-capped-omega drop: a sigma-capped cell (adjust 4, or a
# boundary optimum on the sigma edge) has no sigma estimate, and on an
# adjust-4 cell the published omega was computed at the UNCAPPED Step-2 sigma
# and sits beside sigma = cap -- not a point of the inversion. Under "drop"
# such cells' omega stays out of the Stage-2a priors; "keep" (default) is
# the rule through v0.8.3.
if (identical(opts$stage1_capped_omega, "drop") && "sigma_capped" %in% names(feenstra_gamma_clean)) {
  n_before <- nrow(feenstra_gamma_clean)
  feenstra_gamma_clean <- feenstra_gamma_clean[!(sigma_capped %in% TRUE)]
  cat(sprintf("  Capped-cell omega dropped from the Stage-2a priors: %s of %s cells\n",
              format(n_before - nrow(feenstra_gamma_clean), big.mark = ","), format(n_before, big.mark = ",")))
}
feenstra_priors <- feenstra_gamma_clean[, .(
  ln_gamma_prior = median(log(gamma), na.rm = TRUE)
), by = good]

cat(sprintf("Stage 2a starting values from Feenstra: %d products, median gamma=%.3f\n\n",   # patch 0103: the plateau replacement was retired in v0.9.0
            nrow(feenstra_priors),
            exp(median(feenstra_priors$ln_gamma_prior))))

# Exit cleanly if only Stage 1 was requested.
# Without this, the script falls through to Stage 2a code at line 326,
# which tries to readRDS the regional_file that doesn't exist when stages
# 2a/2b haven't been run yet.
if (opts[["stage"]] == "1") {
  cat("========== STAGE 1 ONLY: PIPELINE EXITING ==========\n")
  cat(sprintf("  Stage 1 output:   %s\n", paths$sigma_file))
  cat(sprintf("  Rich LIML output: %s\n", liml_output_path))
  quit(save = "no", status = 0L)
}

# ===========================================================================
#  STAGE 2a: REGIONAL GAMMA (fixed sigma)
# ===========================================================================

if (should_run("2a", opts, paths)) {
  regional_file <- paths$regional_file

  if (file.exists(regional_file) && opts[["stage"]] == "all") {
    cat("========== STAGE 2a: LOADING REGIONAL ESTIMATES ==========\n")
    cat(sprintf("  Found: %s\n\n", regional_file))
    regional_results <- readRDS(regional_file)
  } else {
    # Stage 2a shrinkage lambda: light ridge pull toward the Stage-1
    # good-level priors. Defined BEFORE the banner so the banner cannot
    # drift from the value actually used (the pre-v0.3.1 banner claimed
    # lambda=0 while the config used 0.05). Whether 2a should be fully
    # unshrunk (lambda=0) is a methodological choice, not a display fix;
    # v0.2.0 and v0.3.0 both published with 0.05, so it stays.
    lambda_2a <- 0.05

    cat("========== STAGE 2a: REGIONAL GAMMA (fixed sigma, light shrinkage) ==========\n")
    cat(sprintf("  Shrinkage lambda=%g (ridge pull toward Stage-1 good-level priors)\n",
                lambda_2a))
    cat(if (identical(opts[["stage2_trim"]], "v2")) "  Plateau fallback: off under --stage2-trim v2 (the gamma tail trim handles the extremes)\n\n"
        else "  Plateau fallback: gamma > 20 replaced by Feenstra anchor\n\n")

    config_2a <- config_regional
    config_2a$shrinkage_lambda <- lambda_2a
    config_2a$shrinkage_priors <- feenstra_priors

    rmap <- build_region_map()
    sigma_wr <- copy(sigma_clean)
    sigma_wr[, region := assign_regions(as.integer(importer), rmap)]
    regional_sigma <- sigma_wr[, .(sigma = median(sigma, na.rm = TRUE)),
                                by = .(importer = region, good)]
    config_2a$sigma_lookup   <- regional_sigma
    config_2a$sigma_fallback <- sigma_fallback

    config_2a$sigma_V_default <- sigma_fallback
    # (patch 0092) 'clean' (every release): the median omega over the whole
    # clean set, floored / capped / sigma-edge cells included; 'priors': the
    # median over the rows the good-level priors use (feenstra_gamma_clean),
    # so the Stage-2a default gamma_V and the gamma start share the priors'
    # population. Default-off: a flip is a Stage-2a methodology change.
    config_2a$gamma_V_default <- stage2a_gamma_v_default(sigma_clean, feenstra_gamma_clean,
                                                         config$stage2a_gamma_v_default)
    config_2a$sigma_start     <- sigma_fallback
    config_2a$gamma_start     <- config_2a$gamma_V_default

    config_2a$sigma_V_lookup <- regional_sigma
    config_2a$gamma_V_lookup <- NULL

    regional_results <- estimate_all_fixed_sigma(
      config_2a, ncores = ncores, prepared_dt = dt_regional)

    # Plateau fallback.
    # B6 FIX (v0.3.0): three repairs to the replacement step —
    #   (1) only replace rows whose good actually has a prior (a missing
    #       prior previously wrote gamma := NA silently);
    #   (2) invalidate the stale gamma_se / gamma_se_total for replaced rows
    #       (the SE belonged to the pre-replacement blow-up) and tag the
    #       status so the rows are filterable downstream;
    #   (3) recompute opt_tariff / opt_tariff_all per (importer, good) cell
    #       after replacement (they were previously left at values derived
    #       from the replaced gamma).
    # The prior itself is now omega-scale (B5).
    # (patch 0083) the plateau replacement is a level-ridge-era rule (v0.3.0 B6):
    # under the log ridge gamma is bounded and the tail trim handles the
    # extremes, and the rows it imputes at the Stage-1 prior read as estimated
    # downstream (they entered the Stage-2b prior medians). Off under v2.
    if (identical(opts[["stage2_trim"]], "v2")) {
      cat("  Plateau fallback: off under --stage2-trim v2\n")
    } else {
    plateau_threshold <- 20
    has_tier <- "tier" %in% names(regional_results)
    plateau_idx <- if (has_tier) {
      regional_results$gamma > plateau_threshold &
        regional_results$tier != 3L &
        !is.na(regional_results$tier)
    } else {
      regional_results$gamma > plateau_threshold
    }

    n_plateau <- sum(plateau_idx, na.rm = TRUE)
    if (n_plateau > 0L) {
      fb <- feenstra_priors[regional_results[plateau_idx], on = "good"]
      has_prior <- !is.na(fb$ln_gamma_prior)
      n_no_prior <- sum(!has_prior)
      if (n_no_prior > 0L) {
        cat(sprintf("  Plateau fallback: %d cells lack a prior for their good; left at the plateau estimate\n",
                    n_no_prior))
      }
      repl_idx <- which(plateau_idx)[has_prior]
      cat(sprintf("  Plateau fallback: %d cells with gamma > %d replaced by the good-level prior\n",
                  length(repl_idx), plateau_threshold))
      if (length(repl_idx) > 0L) {
        regional_results[repl_idx, gamma := exp(fb$ln_gamma_prior[has_prior])]
        if ("gamma_se" %in% names(regional_results))
          regional_results[repl_idx, gamma_se := NA_real_]
        if ("gamma_se_total" %in% names(regional_results))
          regional_results[repl_idx, gamma_se_total := NA_real_]
        if ("gamma_se_status" %in% names(regional_results))
          regional_results[repl_idx, gamma_se_status := "plateau_fallback"]

        # Recompute optimal tariffs after the replacement -- for every cell,
        # through the published-row definition (patch 0081; only the touched
        # cells can change, since estimate_all_fixed_sigma() already applied
        # the same function after the trim).
        ot <- recompute_opt_tariff(regional_results)
        cat(sprintf("  Plateau fallback: opt_tariff recomputed over published rows, %s cells changed\n",
                    format(ot$n_changed, big.mark = ",")))
      }
    }
    }   # patch 0083: end of the legacy plateau block

    saveRDS(finalize_saved_output(regional_results), regional_file)
  }
} else {
  regional_results <- readRDS(paths$regional_file)
  cat(sprintf("Loaded Stage 2a output: %s\n", paths$regional_file))
}

# Save regional summary + CSV (cheap; run regardless of stage gating)
cat("\nSaving regional summary...\n")
# (patch 0110) --stage2a-handoff-rows: which Stage-2a rows build Stage 2b's
# priors, regional gamma_V and starting values ('all' = every release).
regional_handoff <- stage2a_handoff_rows(regional_results, opts$stage2a_handoff_rows)
if (nrow(regional_handoff) < nrow(regional_results))
  cat(sprintf("  Stage-2a handoff: %s published rows (%s flagged rows left out)\n",
              format(nrow(regional_handoff), big.mark = ","),
              format(nrow(regional_results) - nrow(regional_handoff), big.mark = ",")))
regional_clean <- regional_handoff[!is.na(sigma) & !is.na(gamma) & gamma > 0]
write_estimation_summary(regional_results, config, out_base_regional,
                         step1_results = NULL, scope = "regional")
fwrite(regional_results, paste0(out_base_regional, "_fixed_sigma.csv"))
cat(sprintf("  CSV: %s_fixed_sigma.csv\n\n", out_base_regional))


# ===========================================================================
#  STAGE 2b PRIORS (built from Stage 2a output)
# ===========================================================================

# (patch 0079/0080) --stage2b-prior-source {estimated|all}: which Stage-2a rows
# the good-level prior and the reference-destination gamma_V are medians over.
# "estimated" (v0.8.3 default) uses directly estimated rows only
# (is_estimated_row()); "all" (every release through v0.8.2) includes the
# Tier-3 rows Stage 2a imputed at the Stage-1 prior. See
# stage2b_priors_from_regional().
prior_rows_rule <- if (is.null(opts$stage2b_prior_source)) "estimated" else opts$stage2b_prior_source
s2b_priors <- stage2b_priors_from_regional(regional_clean, rows = prior_rows_rule)
country_priors <- s2b_priors$country_priors

cat(sprintf("Stage 2b priors (from Stage 2a, rows = %s: %s of %s rows): %d products, median gamma=%.3f\n\n",
            prior_rows_rule,
            format(s2b_priors$n_rows_used, big.mark = ","), format(s2b_priors$n_rows_all, big.mark = ","),
            nrow(country_priors),
            exp(median(country_priors$ln_gamma_prior))))

# Exit cleanly if only Stage 2a was requested. Same crash pattern as
# above: Stage 2b's else-branch tries to readRDS a country_file that
# doesn't exist when Stage 2b hasn't been run.
if (opts[["stage"]] == "2a") {
  cat("========== STAGE 2a ONLY: PIPELINE EXITING ==========\n")
  cat(sprintf("  Stage 2a output: %s\n", paths$regional_file))
  quit(save = "no", status = 0L)
}

# ===========================================================================
#  STAGE 2b: COUNTRY GAMMA (fixed sigma + shrinkage toward Stage 2a)
# ===========================================================================

if (should_run("2b", opts, paths)) {
  country_file <- paths$country_file

  if (file.exists(country_file) && opts[["stage"]] == "all") {
    cat("========== STAGE 2b: LOADING COUNTRY ESTIMATES ==========\n")
    cat(sprintf("  Found: %s\n\n", country_file))
    country_results <- readRDS(country_file)
  } else {
    cat("========== STAGE 2b: COUNTRY GAMMA (fixed sigma + shrinkage) ==========\n")
    cat(sprintf("  Shrinkage lambda=%.3f, prior=Stage 2a regional gamma\n\n",
                config$shrinkage_lambda))

    config_2b <- config_country
    # F7 (v0.4.0): character keys throughout -- dt_country's importer is
    # character, so stop relying on integer-to-string coercion in the joins.
    # (patch 0090) The sigma, sigma_se and adjust lookups are built from the
    # SAME clean set, so a cell that left it (no Stage-1 estimate, or a sigma
    # on a box edge under --stage2-sigma-edge fallback) carries no Stage-1
    # SE or adjust code into Stage 2b. Through v0.9.0 the SE and adjust
    # lookups were built from the FULL Stage-1 table: the 13,810 edge cells
    # took the fallback sigma while the propagation step still read their
    # Stage-1 SE -- finite on the omega-edge corner cells (adjust 6/8) -- so
    # sigma_se, dgamma_dsigma, gamma_se_total and sigma_robust were published
    # for a sigma the table does not carry. stage2b_sigma_lookups() in
    # R/iteration_helpers.R; scripts/apply_sigma_edge_se_rule.R corrects an
    # existing table.
    .lk <- stage2b_sigma_lookups(sigma_clean)
    config_2b$sigma_lookup        <- .lk$sigma_lookup
    config_2b$sigma_se_lookup     <- .lk$sigma_se_lookup
    config_2b$sigma_adjust_lookup <- .lk$sigma_adjust_lookup
    config_2b$sigma_fallback   <- sigma_fallback
    config_2b$shrinkage_priors <- country_priors
    config_2b$shrinkage_lambda <- config$shrinkage_lambda
    config_2b$tier1_min_periods <- config$tier1_min_periods
    config_2b$tier1_min_dests   <- config$tier1_min_dests
    config_2b$tier2_min_periods <- config$tier2_min_periods

    config_2b$sigma_V_default <- sigma_fallback
    config_2b$gamma_V_default <- exp(median(country_priors$ln_gamma_prior))
    config_2b$sigma_start     <- sigma_fallback
    config_2b$gamma_start     <- config_2b$gamma_V_default

    config_2b$sigma_V_lookup <- .lk$sigma_V_lookup   # patch 0090: the same clean set

    rmap_2b <- build_region_map()
    gam_V_regional <- s2b_priors$gam_V_regional   # patch 0079: same row rule as the prior
    country_codes_2b <- unique(as.integer(dt_country$importer))
    cty_to_region <- data.table(
      cty_code = country_codes_2b,
      region   = assign_regions(country_codes_2b, rmap_2b))
    gam_V_country <- merge(cty_to_region, gam_V_regional, by = "region",
                            allow.cartesian = TRUE)
    config_2b$gamma_V_lookup <- gam_V_country[, .(
      importer = as.character(cty_code), good, gamma)]
    # (patch 0085) --stage2-gamma-v-source table: exporter-specific gamma_V from a
    # previous Stage-2b pass (directly estimated, converged rows), used ahead
    # of the regional median where (V, j, good) is present.
    if (identical(opts$stage2_gamma_v_source, "table")) {
      gv_tab <- readRDS(opts$stage2_gamma_v_table); setDT(gv_tab)
      gv_tab <- gv_tab[is_estimated_row(tier, convergence) & convergence == 0L & is.finite(gamma) & gamma > 0 & is_published_row(gv_tab),   # patch 0093
                       .(importer = as.character(importer), exporter = as.character(exporter),
                         good = as.character(good), gamma)]
      config_2b$gamma_V_exporter_lookup <- gv_tab
      cat(sprintf("  gamma_V source: exporter-specific table, %s usable rows from %s (regional median where absent)\n",
                  format(nrow(gv_tab), big.mark = ","), opts$stage2_gamma_v_table))
    }

    config_2b <- init_from_regional(config_2b, regional_handoff)   # patch 0110 ('all' == regional_results)

    country_results <- estimate_all_fixed_sigma(
      config_2b, ncores = ncores, prepared_dt = dt_country)
    # (patch 0086) native exporter-specific gamma_V iteration: pass 1 above
    # (regional median, or the table named by --stage2-gamma-v-table); each
    # further pass takes gamma_jV from the previous pass's own table, under the
    # same flags. The pass tables, the fallback / trimmed tables of every pass
    # and the step log are kept beside the final table, so the published table
    # reproduces from this one command and each step is on record.
    gv_passes <- if (is.null(opts$stage2_gamma_v_passes)) 1L else as.integer(opts$stage2_gamma_v_passes)
    if (gv_passes > 1L) {
      prefix_country <- run_record_base(config_2b)   # patch 0111: the records live under --out-dir
      rotate_csvs <- function(k) {
        for (f in paste0(prefix_country, c("_stage2_fallbacks.csv", "_stage2_trimmed.csv")))
          if (file.exists(f)) file.rename(f, sub("\\.csv$", sprintf("_pass%d.csv", k), f))
      }
      rotate_csvs(1L)
      saveRDS(finalize_saved_output(country_results), paste0(out_base_country, "_fixed_sigma_pass1.rds"))
      pass_log <- list()
      for (k in 2:gv_passes) {
        prev <- country_results
        gv_tab <- prev[is_estimated_row(tier, convergence) & convergence == 0L & is.finite(gamma) & gamma > 0 & is_published_row(prev),   # patch 0093
                       .(importer = as.character(importer), exporter = as.character(exporter),
                         good = as.character(good), gamma)]
        config_2b$gamma_V_exporter_lookup <- gv_tab
        cat(sprintf("\n--- gamma_V pass %d of %d: exporter-specific gamma_jV from pass %d (%s usable rows) ---\n",
                    k, gv_passes, k - 1L, format(nrow(gv_tab), big.mark = ",")))
        country_results <- estimate_all_fixed_sigma(config_2b, ncores = ncores, prepared_dt = dt_country)
        step <- gamma_v_step(prev, country_results)
        pass_log[[length(pass_log) + 1L]] <- data.table(pass = k, from_pass = k - 1L, usable_rows = nrow(gv_tab),
                                                         tier1_rows = step[["n"]], abs_dlng_p50 = step[["p50"]], abs_dlng_p90 = step[["p90"]],
                                                         abs_dlng_p99 = step[["p99"]], abs_dlng_max = step[["max"]], share_lt_1e2 = step[["share_lt_1e2"]])
        cat(sprintf("  gamma_V pass %d step from pass %d: Tier-1 rows %s | abs d ln gamma p50 %.4g p90 %.4g p99 %.4g | share < 1e-2 %.1f%%\n",
                    k, k - 1L, format(step[["n"]], big.mark = ","), step[["p50"]], step[["p90"]], step[["p99"]], 100 * step[["share_lt_1e2"]]))
        rotate_csvs(k)
        if (k < gv_passes) saveRDS(finalize_saved_output(country_results), paste0(out_base_country, sprintf("_fixed_sigma_pass%d.rds", k)))
      }
      # (patch 0093) gamma_v_resid on the final table: |ln gamma - ln gamma_prev|
      # against the previous pass, NA where either pass has no published
      # directly estimated converged gamma for the row. scripts/add_gamma_v_resid.R
      # applies the same function to an existing final table and its pass table.
      gvr <- attach_gamma_v_resid(country_results, prev)
      cat(sprintf("  gamma_v_resid (pass %d vs %d): filled on %s of %s rows | p50 %.2e p90 %.3f p99 %.3f max %.3f | %.1f%% below 1e-2\n",
                  gv_passes, gv_passes - 1L, format(gvr$n_filled, big.mark = ","), format(gvr$n_rows, big.mark = ","),
                  gvr$p50, gvr$p90, gvr$p99, gvr$max, 100 * gvr$share_lt_1e2))
      fwrite(rbindlist(pass_log), paste0(out_base_country, "_gamma_v_passes.csv"))
      cat(sprintf("  gamma_V pass log: %s_gamma_v_passes.csv (final table = pass %d)\n", out_base_country, gv_passes))
    }
    # (patch 0103) sigma_source: where each row's sigma comes from
    data.table::setDT(country_results)   # patch 0114: restore the over-allocation the passes may have lost
    ssr <- attach_sigma_source(country_results, sigma_source_lookup)
    country_results <- ssr$table; ssc <- ssr$census   # patch 0114: the labelled table, assigned back
    cat(sprintf("  sigma_source (published rows): estimated %s | fallback_no_estimate %s | fallback_sigma_edge %s | fallback_sigma_pole %s\n",
                format(ssc$estimated, big.mark = ","), format(ssc$fallback_no_estimate, big.mark = ","),
                format(ssc$fallback_sigma_edge, big.mark = ","), format(ssc$fallback_sigma_pole, big.mark = ",")))
    saveRDS(finalize_saved_output(country_results), country_file)
  }
} else {
  # No Stage 2b run requested (e.g. --stage 2a) — done after Stage 2a.
  cat("\nStage 2b skipped per --stage flag.\n")
  quit(status = 0L)
}


# ===========================================================================
#  SAVE COUNTRY SUMMARY + CSV
# ===========================================================================

cat("\nSaving country summary...\n")
write_estimation_summary(country_results, config, out_base_country,
                         step1_results = NULL, scope = "country")
fwrite(country_results, paste0(out_base_country, "_fixed_sigma.csv"))
cat(sprintf("  CSV: %s_fixed_sigma.csv\n", out_base_country))


# ===========================================================================
#  FINAL REPORT
# ===========================================================================

cat("\n================================================================\n")
cat("  THREE-STAGE ESTIMATION COMPLETE\n")
# (patch 0102) the summary below is over the PUBLISHED rows: under the v0.10.0
# default --stage2-trim-action flag the tables carry the trimmed rows with
# trim_reason set, and through patch 0101 this block counted them (the 2b
# line read 6,892,008 estimates and Tier 0 232,246 where 6,801,807 / 222,804
# were published). The saved summary files always used the published rows.
regional_results <- regional_results[is_published_row(regional_results)]
country_results  <- country_results[is_published_row(country_results)]
cat("================================================================\n\n")

cat(sprintf("  Stage 1 (Feenstra sigma):    %s cells, sigma=%.3f, gamma_common=%.3f\n",
            format(nrow(sigma_clean), big.mark = ","),
            median(sigma_clean$sigma),
            median(sigma_clean$gamma, na.rm = TRUE)))
cat(sprintf("  Stage 2a (Regional gamma):   %s estimates, gamma=%.3f, tariff=%.3f\n",
            format(nrow(regional_results), big.mark = ","),
            median(regional_results$gamma, na.rm = TRUE),
            median(regional_results$opt_tariff, na.rm = TRUE)))
cat(sprintf("  Stage 2b (Country gamma):    %s estimates, gamma=%.3f, tariff=%.3f\n",
            format(nrow(country_results), big.mark = ","),
            median(country_results$gamma, na.rm = TRUE),
            median(country_results$opt_tariff, na.rm = TRUE)))

cr <- country_results[!is.na(sigma) & !is.na(gamma) & gamma > 0]
cat("\n  Structural ratios (country):\n")
cat(sprintf("    gamma/(1+gamma):              %.3f  (Soderbery: 0.408)\n",
            median(cr$gamma / (1 + cr$gamma))))
cat(sprintf("    1/(sigma-1):                  %.3f  (Soderbery: 0.532)\n",
            median(1 / (cr$sigma - 1))))
cat(sprintf("    gamma/((1+g)(s-1)):           %.3f  (Soderbery: 0.217)\n",
            median(cr$gamma / ((1 + cr$gamma) * (cr$sigma - 1)))))
cat(sprintf("    Convergence (code=0):         %.1f%%\n",
            100 * mean(cr$convergence == 0)))

rr <- regional_results[!is.na(sigma) & !is.na(gamma) & gamma > 0]
cat("\n  Structural ratios (regional):\n")
cat(sprintf("    gamma/(1+gamma):              %.3f\n",
            median(rr$gamma / (1 + rr$gamma))))
cat(sprintf("    1/(sigma-1):                  %.3f\n",
            median(1 / (rr$sigma - 1))))
cat(sprintf("    gamma/((1+g)(s-1)):           %.3f\n",
            median(rr$gamma / ((1 + rr$gamma) * (rr$sigma - 1)))))

if ("tier" %in% names(cr)) {
  cat("\n  Tier distribution (country):\n")
  tier_tab <- cr[, .N, by = tier]
  setorder(tier_tab, tier)
  for (i in seq_len(nrow(tier_tab))) {
    lbl <- switch(as.character(tier_tab$tier[i]),
                  "0" = "Reference exporter",
                  "1" = "Full (import+export)",
                  "2" = "Import-side only",
                  "3" = "Assigned from regional",
                  paste("Tier", tier_tab$tier[i]))
    cat(sprintf("    Tier %s (%s): %s (%.1f%%)\n",
                tier_tab$tier[i], lbl,
                format(tier_tab$N[i], big.mark = ","),
                100 * tier_tab$N[i] / nrow(cr)))
  }
}

cat("\n  Output files:\n")
cat(sprintf("    Stage 1:  %s\n", paths$sigma_file))
cat(sprintf("    Stage 2a: %s\n", paths$regional_file))
cat(sprintf("    Stage 2a: %s_summary.rds\n", out_base_regional))
cat(sprintf("    Stage 2b: %s\n", paths$country_file))
cat(sprintf("    Stage 2b: %s_summary.rds\n", out_base_country))

cat("\nDone.\n")



local({
  manifest_path <- file.path(repo_dir, "data", "manifest.csv")   # patch 0092: was CWD-relative
  if (!file.exists(manifest_path)) {
    message("[checksum] data/manifest.csv not found; skipping verification.")
    return(invisible(NULL))
  }
  manifest <- data.table::fread(manifest_path)
  for (i in seq_len(nrow(manifest))) {
    expected <- manifest$sha256[i]
    local_p  <- manifest$local_path[i]
    if (!file.exists(local_p)) next
    if (is.na(expected) || !nzchar(expected) || expected == "PLACEHOLDER") {
      message(sprintf("[checksum] %s: manifest has no real checksum yet (skip)",
                      local_p))
      next
    }
    # Binary-mode read (see R/load_outputs.R::verify_checksum and
    # scripts/rehash_manifest.R): text-mode file() mangles .rds bytes on
    # Windows and would report spurious "DIFFERS from manifest" warnings.
    con <- file(local_p, "rb")
    actual <- tolower(unclass(as.character(openssl::sha256(con))))  # unclass: see R/load_outputs.R
    close(con)
    if (identical(actual, expected)) {
      message(sprintf("[checksum] %s matches manifest", local_p))
    } else {
      warning(sprintf(paste0("[checksum] %s DIFFERS from manifest\n",
                             "  expected: %s\n  actual:   %s"),
                      local_p, expected, actual))
    }
  }
})

