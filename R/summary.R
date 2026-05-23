#' R/summary.R
#'
#' Estimation summary: build the results tables, within-pair statistics,
#' variance decomposition, and the human-readable summary text/files.
#' Extracted from feen94_het_baci.R (lines 1721-2305) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   build_summary(results, cfg, step1_results, scope)        — assemble the summary object
#'   build_table2(results)                                    — build the Table 2 summary
#'   within_pair_stats(results)                               — within-pair statistics
#'   variance_decomposition(results)                          — variance decomposition
#'   write_summary_text(summary, filepath)                    — write summary as text
#'   write_estimation_summary(results, cfg, out_prefix, ...)  — write full summary outputs
#'
#' Depends on: none

# ===========================================================================
#  ESTIMATION SUMMARY
#
#  Builds a comprehensive summary from estimation results, modeled on
#  the diagnostics reported in Soderbery (2018):
#    - Table 2-style per-importer distributional statistics
#    - Variance decomposition of gamma (importer×product FE R²)
#    - Within importer-product heterogeneity statistics
#    - Trade value coverage
#    - Performance and convergence diagnostics
#    - Config provenance
#
#  Output: both a machine-readable RDS list and a formatted text report.
# ===========================================================================


#' Build a per-importer summary table in the style of Soderbery Table 2.
#'
#' For each importer, reports: observation count, mean/median/MAD of
#' sigma and gamma. The "World" row gives pooled statistics.
#'
#' @param results data.table of estimation results.
#' @return data.table with one row per importer plus a "World" row.
build_table2 <- function(results) {
  dt <- results[!is.na(sigma) & !is.na(gamma)]
  by_imp <- dt[, .(
    obs          = .N,
    sigma_mean   = mean(sigma),
    sigma_median = median(sigma),
    sigma_mad    = mad(sigma, constant = 1),
    gamma_mean   = mean(gamma),
    gamma_median = median(gamma),
    gamma_mad    = mad(gamma, constant = 1)
  ), by = importer]
  setorder(by_imp, importer)

  world <- dt[, .(
    importer     = "World",
    obs          = .N,
    sigma_mean   = mean(sigma),
    sigma_median = median(sigma),
    sigma_mad    = mad(sigma, constant = 1),
    gamma_mean   = mean(gamma),
    gamma_median = median(gamma),
    gamma_mad    = mad(gamma, constant = 1)
  )]

  rbindlist(list(by_imp, world))
}


#' Compute within importer-product heterogeneity statistics.
#'
#' For each (importer, product), computes the within-pair median,
#' SD, and MAD of gamma. Then reports the median of these statistics
#' across all importer-product pairs, plus 25th/75th percentiles.
#' (Corresponds to Soderbery p. 52 discussion.)
#'
#' @param results data.table of estimation results.
#' @return Named list of within-pair statistics.
within_pair_stats <- function(results) {
  dt <- results[!is.na(gamma) & gamma > 0]
  # Need at least 2 exporters per (importer, good) to have within-pair variation
  pair_stats <- dt[, .(
    n_exporters  = .N,
    within_med   = median(gamma),
    within_sd    = if (.N > 1L) sd(gamma) else NA_real_,
    within_mad   = mad(gamma, constant = 1)
  ), by = .(importer, good)]

  pair_stats <- pair_stats[n_exporters >= 2L]

  if (nrow(pair_stats) == 0L) return(NULL)

  list(
    n_pairs                = nrow(pair_stats),
    median_of_within_med   = median(pair_stats$within_med, na.rm = TRUE),
    median_of_within_sd    = median(pair_stats$within_sd, na.rm = TRUE),
    median_of_within_mad   = median(pair_stats$within_mad, na.rm = TRUE),
    q25_within_med         = quantile(pair_stats$within_med, 0.25, na.rm = TRUE),
    q75_within_med         = quantile(pair_stats$within_med, 0.75, na.rm = TRUE),
    q25_within_sd          = quantile(pair_stats$within_sd, 0.25, na.rm = TRUE),
    q75_within_sd          = quantile(pair_stats$within_sd, 0.75, na.rm = TRUE),
    q25_within_mad         = quantile(pair_stats$within_mad, 0.25, na.rm = TRUE),
    q75_within_mad         = quantile(pair_stats$within_mad, 0.75, na.rm = TRUE)
  )
}


#' Compute variance decomposition of gamma.
#'
#' Regresses log(gamma) on importer×product fixed effects and reports R².
#' This measures how much of the variation in export supply elasticities
#' is explained by the import market vs. exporter heterogeneity within
#' markets. Soderbery reports 72% (p. 52).
#'
#' @param results data.table of estimation results.
#' @return Named list with r_squared and n_obs, or NULL if insufficient data.
variance_decomposition <- function(results) {
  dt <- results[!is.na(gamma) & gamma > 0]
  dt[, log_gamma := log(gamma)]
  dt[, imp_good := paste(importer, good, sep = "_")]

  # Need enough variation — at least some groups with > 1 obs
  grp <- dt[, .N, by = imp_good]
  if (sum(grp$N > 1L) < 10L) return(NULL)

  # Use within-group SS / total SS for R² (equivalent to FE regression)
  grand_mean <- mean(dt$log_gamma, na.rm = TRUE)
  ss_total   <- sum((dt$log_gamma - grand_mean)^2, na.rm = TRUE)

  group_means <- dt[, .(gm = mean(log_gamma, na.rm = TRUE)), by = imp_good]
  dt <- group_means[dt, on = "imp_good"]
  ss_within  <- sum((dt$log_gamma - dt$gm)^2, na.rm = TRUE)

  r_sq <- 1 - ss_within / ss_total

  list(
    r_squared = r_sq,
    n_obs     = nrow(dt),
    n_groups  = nrow(group_means)
  )
}


#' Build the full estimation summary.
#'
#' @param results data.table of final (Step 2) results.
#' @param cfg Config list used for the estimation.
#' @param step1_results Optional data.table of Step 1 results for comparison.
#' @param scope Character: "regional" or "country".
#' @return Named list containing all summary components.
build_summary <- function(results, cfg, step1_results = NULL, scope = NULL) {

  if (is.null(scope)) {
    scope <- if (isTRUE(cfg$use_regions)) "regional" else "country"
  }

  meta <- attr(results, "run_meta")
  dt <- results[!is.na(sigma) & !is.na(gamma)]

  # --- Config provenance ---
  provenance <- list(
    baci_source       = parse_baci_source(cfg$filepath),
    filepath          = cfg$filepath,
    scope             = scope,
    agg_level         = cfg$agg_level,
    minyear           = cfg$minyear,
    maxyear           = cfg$maxyear,
    min_exporters     = cfg$min_exporters,
    min_destinations  = cfg$min_destinations,
    min_periods       = cfg$min_periods,
    uv_outlier_thresh = cfg$uv_outlier_threshold,
    tail_trim_pct     = cfg$tail_trim_pct,
    sigma_V_default   = cfg$sigma_V_default,
    gamma_V_default   = cfg$gamma_V_default,
    sigma_start       = cfg$sigma_start,
    gamma_start       = cfg$gamma_start,
    timestamp         = if (!is.null(meta)) meta$timestamp else Sys.time()
  )

  # --- Performance ---
  perf <- list(ncores = NULL, rcpp = NULL, elapsed_min = NULL,
               products_per_min = NULL, per_product_median_s = NULL,
               per_product_mean_s = NULL, per_product_max_s = NULL,
               cells_attempted = NULL, cells_succeeded = NULL,
               cell_success_rate = NULL)
  if (!is.null(meta)) {
    perf$ncores            <- meta$ncores
    perf$rcpp              <- meta$rcpp_loaded
    perf$elapsed_min       <- meta$t_elapsed
    perf$elapsed_hours     <- meta$t_elapsed / 60
    perf$n_products        <- meta$n_products
    perf$n_succeeded       <- meta$n_succeeded
    perf$n_failed          <- meta$n_failed
    perf$products_per_min  <- meta$n_succeeded / max(meta$t_elapsed, 0.01)
    if (length(meta$timing_info) > 0L) {
      ps <- sapply(meta$timing_info, function(x) x$seconds)
      pc <- sapply(meta$timing_info, function(x) x$cells)
      po <- sapply(meta$timing_info, function(x) x$succeeded)
      perf$per_product_median_s <- median(ps)
      perf$per_product_mean_s   <- mean(ps)
      perf$per_product_max_s    <- max(ps)
      perf$cells_attempted      <- sum(pc)
      perf$cells_succeeded      <- sum(po)
      perf$cell_success_rate    <- 100 * sum(po) / max(sum(pc), 1)
    }
  }

  # --- Data quality (from qlog) ---
  quality <- NULL
  if (!is.null(meta) && !is.null(meta$qlog)) {
    ql <- meta$qlog
    quality <- data.table(
      stage       = sapply(ql$steps, function(s) s$stage),
      n_obs       = sapply(ql$steps, function(s) s$n_obs),
      n_dropped   = sapply(ql$steps, function(s) s$n_dropped),
      trade_value = sapply(ql$steps, function(s) s$trade_value),
      detail      = sapply(ql$steps, function(s) s$detail)
    )
  }

  # --- Global distributional statistics ---
  global <- list(
    n_estimates    = nrow(dt),
    n_products     = uniqueN(dt$good),
    n_importers    = uniqueN(dt$importer),
    n_exporters    = uniqueN(dt$exporter),
    n_sigma        = nrow(unique(dt[, .(importer, good)])),
    n_gamma        = nrow(dt),
    sigma_median   = median(dt$sigma),
    sigma_mean     = mean(dt$sigma),
    sigma_sd       = sd(dt$sigma),
    sigma_q25      = as.numeric(quantile(dt$sigma, 0.25)),
    sigma_q75      = as.numeric(quantile(dt$sigma, 0.75)),
    gamma_median   = median(dt$gamma),
    gamma_mean     = mean(dt$gamma),
    gamma_sd       = sd(dt$gamma),
    gamma_mad      = mad(dt$gamma, constant = 1),
    gamma_q25      = as.numeric(quantile(dt$gamma, 0.25)),
    gamma_q75      = as.numeric(quantile(dt$gamma, 0.75)),
    opt_tariff_median = median(dt$opt_tariff, na.rm = TRUE),
    opt_tariff_mean   = mean(dt$opt_tariff, na.rm = TRUE)
  )
  # Trim bounds
  if (!is.null(meta) && !is.null(meta$trim_bounds)) {
    global$trim <- meta$trim_bounds
    global$n_pre_trim <- meta$n_pre_trim
    global$n_trimmed  <- meta$n_trimmed
  }

  # --- Table 2 (per-importer) ---
  table2 <- build_table2(results)

  # --- Within importer-product heterogeneity ---
  within_het <- within_pair_stats(results)

  # --- Variance decomposition ---
  var_decomp <- variance_decomposition(results)

  # --- Two-step comparison ---
  step_comparison <- NULL
  if (!is.null(step1_results)) {
    s1 <- step1_results[!is.na(sigma) & !is.na(gamma)]
    med_s1_sig <- median(s1$sigma, na.rm = TRUE)
    med_s1_gam <- median(s1$gamma, na.rm = TRUE)
    med_s2_sig <- global$sigma_median
    med_s2_gam <- global$gamma_median

    merged <- merge(
      s1[, .(importer, exporter, good, sigma_1 = sigma, gamma_1 = gamma)],
      dt[, .(importer, exporter, good, sigma_2 = sigma, gamma_2 = gamma)],
      by = c("importer", "exporter", "good"))

    step_comparison <- list(
      step1_sigma_median = med_s1_sig,
      step1_gamma_median = med_s1_gam,
      step2_sigma_median = med_s2_sig,
      step2_gamma_median = med_s2_gam,
      sigma_shift        = med_s2_sig - med_s1_sig,
      gamma_shift        = med_s2_gam - med_s1_gam,
      sigma_shift_pct    = 100 * (med_s2_sig - med_s1_sig) / med_s1_sig,
      gamma_shift_pct    = 100 * (med_s2_gam - med_s1_gam) / med_s1_gam,
      n_matched          = nrow(merged)
    )
    if (nrow(merged) > 10L) {
      step_comparison$cor_sigma <- cor(merged$sigma_1, merged$sigma_2, use = "complete.obs")
      step_comparison$cor_gamma <- cor(merged$gamma_1, merged$gamma_2, use = "complete.obs")
    }
  }

  # --- Failure diagnostics ---
  fail_summary <- NULL
  if (!is.null(meta) && length(meta$failure_info) > 0L) {
    fail_dt <- rbindlist(meta$failure_info)
    fail_summary <- fail_dt[, .N, by = reason]
    setorder(fail_summary, -N)
    setnames(fail_summary, c("reason", "count"))
  }

  list(
    provenance      = provenance,
    performance     = perf,
    quality         = quality,
    global          = global,
    table2          = table2,
    within_het      = within_het,
    var_decomp      = var_decomp,
    step_comparison = step_comparison,
    failures        = fail_summary
  )
}


#' Write summary to a formatted text file.
#'
#' @param summary List from build_summary().
#' @param filepath Path to write the text file.
write_summary_text <- function(summary, filepath) {

  lines <- character(0)
  a <- function(...) lines <<- c(lines, sprintf(...))
  rule <- function() a(paste(rep("=", 72), collapse = ""))
  dash <- function() a(paste(rep("-", 72), collapse = ""))

  prov <- summary$provenance
  perf <- summary$performance
  glob <- summary$global
  tb2  <- summary$table2
  wh   <- summary$within_het
  vd   <- summary$var_decomp
  sc   <- summary$step_comparison
  fl   <- summary$failures

  rule()
  a("  ESTIMATION SUMMARY REPORT")
  a("  Soderbery (2018) Heterogeneous Elasticity Estimator")
  rule()
  a("")

  # --- Provenance ---
  a("CONFIGURATION")
  dash()
  a("  BACI source:          %s", prov$baci_source)
  a("  Data path:            %s", prov$filepath)
  a("  Scope:                %s", prov$scope)
  a("  Aggregation:          %s", prov$agg_level)
  a("  Min year:             %d", prov$minyear)
  a("  Max year:             %s", if (is.null(prov$maxyear) || is.na(prov$maxyear))
                                    "all available" else as.character(prov$maxyear))
  a("  Structural defaults:  sigma_V=%.3f, gamma_V=%.3f", prov$sigma_V_default, prov$gamma_V_default)
  a("  Starting values:      sigma=%.3f, gamma=%.3f", prov$sigma_start, prov$gamma_start)
  a("  Min exporters:        %d", prov$min_exporters)
  a("  Min destinations:     %d", prov$min_destinations)
  a("  Min periods:          %d", prov$min_periods)
  a("  UV outlier threshold: %s", if (is.na(prov$uv_outlier_thresh)) "disabled"
                                  else sprintf("%.1f", prov$uv_outlier_thresh))
  a("  Tail trim:            %.1f%% each tail", prov$tail_trim_pct * 100)
  a("  Timestamp:            %s", format(prov$timestamp, "%Y-%m-%d %H:%M:%S"))
  a("")

  # --- Performance ---
  if (!is.null(perf$ncores)) {
    a("PERFORMANCE")
    dash()
    a("  Cores:                %d", perf$ncores)
    a("  Objective function:   %s", if (isTRUE(perf$rcpp)) "Rcpp (C++)" else "pure R")
    a("  Wall clock time:      %.1f min (%.2f hours)", perf$elapsed_min, perf$elapsed_hours)
    a("  Products:             %d total, %d succeeded, %d failed",
      perf$n_products, perf$n_succeeded, perf$n_failed)
    a("  Throughput:           %.1f products/min", perf$products_per_min)
    if (!is.null(perf$per_product_median_s)) {
      a("  Per product (sec):    median=%.1f, mean=%.1f, max=%.1f",
        perf$per_product_median_s, perf$per_product_mean_s, perf$per_product_max_s)
    }
    if (!is.null(perf$cells_attempted)) {
      a("  Cell convergence:     %d / %d (%.1f%%)",
        perf$cells_succeeded, perf$cells_attempted, perf$cell_success_rate)
    }
    a("")
  }

  # --- Data quality ---
  if (!is.null(summary$quality)) {
    ql <- summary$quality
    a("DATA PIPELINE")
    dash()
    has_tv <- any(!is.na(ql$trade_value))
    if (has_tv) {
      a("  %-38s %12s %12s %14s", "Stage", "Obs", "Dropped", "Trade Val ($B)")
      a("  %-38s %12s %12s %14s",
        paste(rep("-", 38), collapse = ""),
        paste(rep("-", 12), collapse = ""),
        paste(rep("-", 12), collapse = ""),
        paste(rep("-", 14), collapse = ""))
    } else {
      a("  %-40s %12s %12s", "Stage", "Obs", "Dropped")
      a("  %-40s %12s %12s",
        paste(rep("-", 40), collapse = ""),
        paste(rep("-", 12), collapse = ""),
        paste(rep("-", 12), collapse = ""))
    }
    for (i in seq_len(nrow(ql))) {
      n_str <- format(ql$n_obs[i], big.mark = ",")
      d_str <- if (is.na(ql$n_dropped[i])) "" else format(ql$n_dropped[i], big.mark = ",")
      if (has_tv) {
        tv_str <- if (is.na(ql$trade_value[i])) "" else sprintf("%.1f", ql$trade_value[i] / 1e6)
        a("  %-38s %12s %12s %14s", ql$stage[i], n_str, d_str, tv_str)
      } else {
        a("  %-40s %12s %12s", ql$stage[i], n_str, d_str)
      }
      if (nchar(ql$detail[i]) > 0) a("    %s", ql$detail[i])
    }
    # Trade value retention
    if (has_tv) {
      tv_first <- ql$trade_value[which(!is.na(ql$trade_value))[1]]
      tv_last  <- ql$trade_value[max(which(!is.na(ql$trade_value)))]
      if (!is.na(tv_first) && !is.na(tv_last) && tv_first > 0) {
        a("")
        a("  Trade value retention: $%.1fB / $%.1fB (%.1f%%)",
          tv_last / 1e6, tv_first / 1e6, 100 * tv_last / tv_first)
      }
    }
    a("")
  }

  # --- Global distributional statistics ---
  a("GLOBAL DISTRIBUTIONAL STATISTICS")
  dash()
  a("  Total estimate rows:  %s", format(glob$n_estimates, big.mark = ","))
  a("  Products:             %d", glob$n_products)
  a("  Importers:            %d", glob$n_importers)
  a("  Exporters:            %d", glob$n_exporters)
  a("  Unique sigma (imp x good): %s", format(glob$n_sigma, big.mark = ","))
  a("  Unique gamma (imp x exp x good): %s", format(glob$n_gamma, big.mark = ","))
  a("")
  a("  Sigma (elasticity of substitution):")
  a("    Median=%.3f  Mean=%.3f  SD=%.3f  IQR=[%.3f, %.3f]",
    glob$sigma_median, glob$sigma_mean, glob$sigma_sd, glob$sigma_q25, glob$sigma_q75)
  a("")
  a("  Gamma (inverse export supply elasticity):")
  a("    Median=%.3f  Mean=%.3f  SD=%.3f  MAD=%.3f  IQR=[%.3f, %.3f]",
    glob$gamma_median, glob$gamma_mean, glob$gamma_sd, glob$gamma_mad,
    glob$gamma_q25, glob$gamma_q75)
  a("")
  a("  Optimal tariff (Proposition 1):")
  a("    Median=%.3f  Mean=%.3f", glob$opt_tariff_median, glob$opt_tariff_mean)
  if (!is.null(glob$trim)) {
    a("")
    a("  Trim bounds applied:")
    a("    Sigma: [%.3f, %.3f]  Gamma: [%.4f, %.4f]",
      glob$trim$sig_lo, glob$trim$sig_hi, glob$trim$gam_lo, glob$trim$gam_hi)
    a("    Pre-trim: %s  Trimmed: %s",
      format(glob$n_pre_trim, big.mark = ","), format(glob$n_trimmed, big.mark = ","))
  }
  a("")

  # --- Table 2 (per-importer) ---
  a("PER-IMPORTER SUMMARY (cf. Soderbery Table 2)")
  dash()
  a("  %-20s %7s %8s %8s %8s %8s %8s %8s",
    "Importer", "Obs", "sig_mn", "sig_md", "sig_MAD", "gam_mn", "gam_md", "gam_MAD")
  a("  %-20s %7s %8s %8s %8s %8s %8s %8s",
    paste(rep("-", 20), collapse = ""),
    paste(rep("-", 7), collapse = ""),
    paste(rep("-", 8), collapse = ""),
    paste(rep("-", 8), collapse = ""),
    paste(rep("-", 8), collapse = ""),
    paste(rep("-", 8), collapse = ""),
    paste(rep("-", 8), collapse = ""),
    paste(rep("-", 8), collapse = ""))
  for (i in seq_len(nrow(tb2))) {
    r <- tb2[i]
    a("  %-20s %7s %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f",
      r$importer, format(r$obs, big.mark = ","),
      r$sigma_mean, r$sigma_median, r$sigma_mad,
      r$gamma_mean, r$gamma_median, r$gamma_mad)
  }
  a("")

  # --- Within importer-product heterogeneity ---
  if (!is.null(wh)) {
    a("WITHIN IMPORTER-PRODUCT HETEROGENEITY (cf. Soderbery p. 52)")
    dash()
    a("  Importer-product pairs with 2+ exporters: %s", format(wh$n_pairs, big.mark = ","))
    a("")
    a("  Median gamma within pair:  %.3f  [Q25=%.3f, Q75=%.3f]",
      wh$median_of_within_med, wh$q25_within_med, wh$q75_within_med)
    a("  SD of gamma within pair:   %.3f  [Q25=%.3f, Q75=%.3f]",
      wh$median_of_within_sd, wh$q25_within_sd, wh$q75_within_sd)
    a("  MAD of gamma within pair:  %.3f  [Q25=%.3f, Q75=%.3f]",
      wh$median_of_within_mad, wh$q25_within_mad, wh$q75_within_mad)
    a("")
    a("  Interpretation: For the median importer-product, exporters have")
    a("  a median inverse supply elasticity of %.3f with within-pair", wh$median_of_within_med)
    a("  SD of %.3f. Soderbery reports: median=0.712, SD=0.625, MAD=0.125.", wh$median_of_within_sd)
    a("")
  }

  # --- Variance decomposition ---
  if (!is.null(vd)) {
    a("VARIANCE DECOMPOSITION OF GAMMA (cf. Soderbery p. 52)")
    dash()
    a("  R-squared (importer x product FEs on log gamma): %.3f", vd$r_squared)
    a("  Observations: %s  Groups: %s",
      format(vd$n_obs, big.mark = ","), format(vd$n_groups, big.mark = ","))
    a("")
    a("  Interpretation: %.0f%% of variation in log(gamma) is explained by",
      vd$r_squared * 100)
    a("  importer-product fixed effects. The remaining %.0f%% comes from",
      (1 - vd$r_squared) * 100)
    a("  exporter heterogeneity within importer-product pairs.")
    a("  Soderbery reports 72%% explained by importer-product FEs.")
    a("")
  }

  # --- Cell failure diagnostics ---
  if (!is.null(fl) && nrow(fl) > 0L) {
    a("CELL FAILURE DIAGNOSTICS")
    dash()
    total_fails <- sum(fl$count)
    a("  Total failed cells: %s", format(total_fails, big.mark = ","))
    a("")
    a("  %-35s %8s", "Reason", "Count")
    a("  %-35s %8s", paste(rep("-", 35), collapse = ""),
      paste(rep("-", 8), collapse = ""))
    for (i in seq_len(nrow(fl))) {
      a("  %-35s %8s", fl$reason[i], format(fl$count[i], big.mark = ","))
    }
    a("")
  }

  # --- Two-step comparison ---
  if (!is.null(sc)) {
    a("TWO-STEP SENSITIVITY COMPARISON")
    dash()
    a("  Step 1 medians (Comtrade defaults): sigma=%.3f  gamma=%.3f",
      sc$step1_sigma_median, sc$step1_gamma_median)
    a("  Step 2 medians (BACI defaults):     sigma=%.3f  gamma=%.3f",
      sc$step2_sigma_median, sc$step2_gamma_median)
    a("  Shift: sigma %+.3f (%.1f%%)  gamma %+.3f (%.1f%%)",
      sc$sigma_shift, sc$sigma_shift_pct, sc$gamma_shift, sc$gamma_shift_pct)
    if (!is.null(sc$cor_sigma)) {
      a("  Cross-step correlation: sigma=%.4f  gamma=%.4f", sc$cor_sigma, sc$cor_gamma)
    }
    a("  Matched cells: %s", format(sc$n_matched, big.mark = ","))
    a("")
  }

  rule()
  a("  END OF REPORT")
  rule()

  writeLines(lines, filepath)
  cat(sprintf("  Summary text: %s\n", filepath))
}


#' Write full summary (RDS + text).
#'
#' @param results Final (Step 2) results data.table.
#' @param cfg Config list.
#' @param out_prefix Output file prefix from build_output_prefix().
#' @param step1_results Optional Step 1 results for comparison.
#' @param scope Character: "regional" or "country".
write_estimation_summary <- function(results, cfg, out_prefix,
                                     step1_results = NULL, scope = NULL) {
  cat("\nBuilding estimation summary...\n")
  summary <- build_summary(results, cfg, step1_results, scope)

  rds_path  <- paste0(out_prefix, "_summary.rds")
  text_path <- paste0(out_prefix, "_summary.txt")

  saveRDS(summary, rds_path)
  cat(sprintf("  Summary RDS:  %s\n", rds_path))

  write_summary_text(summary, text_path)
}
#
#  Generates a file prefix from config parameters so output files
#  reflect the data source and estimation settings.
#
#  Example outputs:
#    baci_hs92_v202601_elast_regional_hs4
#    baci_hs07_v202601_elast_country_hs6
#
#  The prefix is built from:
#    - baci_source:  e.g., "baci_hs92_v202601" (parsed from filepath)
#    - scope:        "regional" or "country" (from use_regions)
#    - agg_level:    "hs4" or "hs6" (from config)
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
