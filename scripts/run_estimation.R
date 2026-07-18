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
cat(sprintf("  Output:           %s\n", opts$out_dir))
cat(sprintf("  Years:            %d -- %s\n",
            opts$minyear,
            if (is.na(opts$maxyear)) "max" else as.character(opts$maxyear)))
cat(sprintf("  Aggregation:      %s\n", opts$agg_level))
cat(sprintf("  Cores:            %d\n", opts$ncores))
cat(sprintf("  Shrinkage lambda: %g\n", opts$shrinkage_lambda))
cat(sprintf("  Stage:            %s\n\n", opts$stage))


# ---- 3. Source library ----------------------------------------------------
# feen94_het_baci.R resolves its own location via .this_file_dir() and
# locates the .cpp files relative to that (CWD-independent), so we source
# it by absolute path with no setwd() (C2, D13).
source(file.path(src_dir, "feen94_het_baci.R"))


# ---- 4. Build config from CLI options -------------------------------------
config <- build_config(opts)
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
  if (opts$stage == "all") return(TRUE)
  if (opts$stage != stage) return(FALSE)

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

cat("Preparing country-level estimation data...\n")
config_country <- config
config_country$use_regions <- FALSE
prep_country <- prepare_data(config_country, raw_cache = raw_cache)
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
  
  if (file.exists(sigma_file) && opts$stage == "all") {
    cat("\n========== STAGE 1: LOADING SIGMA ESTIMATES ==========\n")
    cat(sprintf("  Found: %s\n\n", sigma_file))
    sigma_estimates <- readRDS(sigma_file)
  } else {
    cat("\n========== STAGE 1: HLIML (Grant & Soderbery 2024) ==========\n")
    cat("  Estimator: HLIML with Fuller LIML feasibility fallback\n")
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
    saveRDS(sigma_estimates, sigma_file)
    cat(sprintf("  LIML output (rich): %s\n", liml_output_path))
    cat(sprintf("  Stage 2 input:      %s\n", sigma_file))
  }
} else {
  # --stage 2a or 2b — load existing Stage 1 output
  sigma_estimates <- readRDS(paths$sigma_file)
  cat(sprintf("Loaded Stage 1 output: %s\n", paths$sigma_file))
}

sigma_clean <- sigma_estimates[!is.na(sigma) & sigma > 1 & convergence == 0]
sigma_fallback <- median(sigma_clean$sigma, na.rm = TRUE)

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
feenstra_priors <- feenstra_gamma_clean[, .(
  ln_gamma_prior = median(log(gamma), na.rm = TRUE)
), by = good]

cat(sprintf("Stage 2a starting values / plateau fallback from Feenstra: %d products, median gamma=%.3f\n\n",
            nrow(feenstra_priors),
            exp(median(feenstra_priors$ln_gamma_prior))))

# Exit cleanly if only Stage 1 was requested.
# Without this, the script falls through to Stage 2a code at line 326,
# which tries to readRDS the regional_file that doesn't exist when stages
# 2a/2b haven't been run yet.
if (opts$stage == "1") {
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

  if (file.exists(regional_file) && opts$stage == "all") {
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
    cat("  Plateau fallback: gamma > 20 replaced by Feenstra anchor\n\n")

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
    config_2a$gamma_V_default <- median(sigma_clean$gamma, na.rm = TRUE)
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

        # Recompute optimal tariffs for every cell touched by a replacement.
        touched <- unique(regional_results[repl_idx, .(importer, good)])
        regional_results[touched, on = .(importer, good), `:=`(
          opt_tariff = {
            est <- !is.na(tier) & tier < 3L
            if (any(est)) optimal_tariff(gamma[est], sigma[est][1], avg_trade[est])
            else NA_real_
          },
          opt_tariff_all = optimal_tariff(gamma, sigma[1], avg_trade)
        ), by = .EACHI]
      }
    }

    saveRDS(regional_results, regional_file)
  }
} else {
  regional_results <- readRDS(paths$regional_file)
  cat(sprintf("Loaded Stage 2a output: %s\n", paths$regional_file))
}

# Save regional summary + CSV (cheap; run regardless of stage gating)
cat("\nSaving regional summary...\n")
regional_clean <- regional_results[!is.na(sigma) & !is.na(gamma) & gamma > 0]
write_estimation_summary(regional_results, config, out_base_regional,
                         step1_results = NULL, scope = "regional")
fwrite(regional_results, paste0(out_base_regional, "_fixed_sigma.csv"))
cat(sprintf("  CSV: %s_fixed_sigma.csv\n\n", out_base_regional))


# ===========================================================================
#  STAGE 2b PRIORS (built from Stage 2a output)
# ===========================================================================

country_priors <- regional_clean[, .(
  ln_gamma_prior = median(log(gamma), na.rm = TRUE)
), by = good]

cat(sprintf("Stage 2b priors (from Stage 2a): %d products, median gamma=%.3f\n\n",
            nrow(country_priors),
            exp(median(country_priors$ln_gamma_prior))))

# Exit cleanly if only Stage 2a was requested. Same crash pattern as
# above: Stage 2b's else-branch tries to readRDS a country_file that
# doesn't exist when Stage 2b hasn't been run.
if (opts$stage == "2a") {
  cat("========== STAGE 2a ONLY: PIPELINE EXITING ==========\n")
  cat(sprintf("  Stage 2a output: %s\n", paths$regional_file))
  quit(save = "no", status = 0L)
}

# ===========================================================================
#  STAGE 2b: COUNTRY GAMMA (fixed sigma + shrinkage toward Stage 2a)
# ===========================================================================

if (should_run("2b", opts, paths)) {
  country_file <- paths$country_file

  if (file.exists(country_file) && opts$stage == "all") {
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
    config_2b$sigma_lookup     <- sigma_clean[, .(importer = as.character(importer), good, sigma)]

    config_2b$sigma_se_lookup     <- sigma_estimates[, .(importer = as.character(importer),
                                                         good     = as.character(good), sigma_se)]
    config_2b$sigma_adjust_lookup <- sigma_estimates[, .(importer = as.character(importer),
                                                         good     = as.character(good), adjust)]
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

    config_2b$sigma_V_lookup <- sigma_clean[, .(importer = as.character(importer), good, sigma)]

    rmap_2b <- build_region_map()
    gam_V_regional <- regional_clean[, .(gamma = median(gamma, na.rm = TRUE)),
                                       by = .(region = importer, good)]
    country_codes_2b <- unique(as.integer(dt_country$importer))
    cty_to_region <- data.table(
      cty_code = country_codes_2b,
      region   = assign_regions(country_codes_2b, rmap_2b))
    gam_V_country <- merge(cty_to_region, gam_V_regional, by = "region",
                            allow.cartesian = TRUE)
    config_2b$gamma_V_lookup <- gam_V_country[, .(
      importer = as.character(cty_code), good, gamma)]

    config_2b <- init_from_regional(config_2b, regional_results)

    country_results <- estimate_all_fixed_sigma(
      config_2b, ncores = ncores, prepared_dt = dt_country)
    saveRDS(country_results, country_file)
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
  manifest_path <- "data/manifest.csv"
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
    actual <- as.character(openssl::sha256(file(local_p)))
    if (identical(actual, expected)) {
      message(sprintf("[checksum] %s matches manifest", local_p))
    } else {
      warning(sprintf(paste0("[checksum] %s DIFFERS from manifest\n",
                             "  expected: %s\n  actual:   %s"),
                      local_p, expected, actual))
    }
  }
})

