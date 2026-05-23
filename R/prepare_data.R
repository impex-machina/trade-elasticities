#' R/prepare_data.R
#'
#' Data preparation pipeline: from raw BACI to the cell-level panel the
#' estimators consume.
#' Extracted from feen94_het_baci.R (lines 976-1179) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   prepare_raw_data(cfg)         — load and pre-clean raw BACI
#'   prepare_data(cfg, raw_cache)  — build the cell-level estimation panel
#'
#' Depends on: load_baci.R, hs_codes.R, region_map.R, quality_log.R

# ===========================================================================
#  DATA PREPARATION PIPELINE
# ===========================================================================

#' Load and clean BACI data through HS4 aggregation (cacheable).
#'
#' Performs steps 1-5 of the data pipeline: load, clean, year filter,
#' HS4 aggregation. The result can be cached and reused across stages
#' to avoid reloading 270M+ rows multiple times.
#'
#' @param cfg Config list.
#' @return data.table with columns: year, good, importer, exporter, cusval, quantity.
prepare_raw_data <- function(cfg) {
  cat("Loading BACI data (raw prep for caching)...\n")
  raw <- load_baci(cfg$filepath)

  setnames(raw,
    old = c(cfg$value, cfg$quan, cfg$good, cfg$importer, cfg$exporter, cfg$time),
    new = c("cusval", "quantity", "good", "importer", "exporter", "year"),
    skip_absent = TRUE)

  raw <- raw[cusval > 0 & quantity > 0 & !is.na(cusval) & !is.na(quantity)]
  raw <- raw[year >= cfg$minyear]
  if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) raw <- raw[year <= cfg$maxyear]

  raw[, good := pad_hs6(good)]
  raw <- raw[nchar(good) == 6L]

  if (cfg$agg_level == "hs4") {
    raw[, good := hs6_to_hs4(good)]
    raw <- raw[, .(cusval = sum(cusval), quantity = sum(quantity)),
               by = .(year, good, importer, exporter)]
  }

  cat(sprintf("  Raw data cached: %s obs, %d products, years %d-%d\n",
              format(nrow(raw), big.mark = ","), uniqueN(raw$good),
              min(raw$year), max(raw$year)))
  raw
}


#' Full data preparation pipeline.
#'
#' @param cfg Config list.
#' @param raw_cache Optional pre-loaded data.table from prepare_raw_data().
#'   If provided, skips the expensive loading/cleaning/aggregation steps.
#' @return Named list with dt (estimation data) and qlog (quality log).
prepare_data <- function(cfg, raw_cache = NULL) {

  validate_config(cfg)

  qlog <- new_quality_log()

  if (!is.null(raw_cache)) {
    cat("Using cached raw data (skipping load/clean/aggregate)...\n")
    raw <- copy(raw_cache)
    qlog$add("Raw data (from cache)", n_obs = nrow(raw),
             trade_value = sum(raw$cusval, na.rm = TRUE),
             detail = sprintf("%d products, %d importers, %d exporters",
                              uniqueN(raw$good), uniqueN(raw$importer),
                              uniqueN(raw$exporter)))
  } else {
    cat("Loading BACI data...\n")
    raw <- load_baci(cfg$filepath)

  setnames(raw,
    old = c(cfg$value, cfg$quan, cfg$good, cfg$importer, cfg$exporter, cfg$time),
    new = c("cusval", "quantity", "good", "importer", "exporter", "year"),
    skip_absent = TRUE)

  qlog$add("Raw data loaded", n_obs = nrow(raw),
           trade_value = sum(raw$cusval, na.rm = TRUE),
           detail = sprintf("%d products (HS6), %d importers, %d exporters, years %d-%d",
                            uniqueN(raw$good), uniqueN(raw$importer),
                            uniqueN(raw$exporter), min(raw$year), max(raw$year)))

  n_before <- nrow(raw)
  raw <- raw[cusval > 0 & quantity > 0 & !is.na(cusval) & !is.na(quantity)]
  qlog$add("Drop zero/missing value or quantity",
           n_obs = nrow(raw), n_dropped = n_before - nrow(raw),
           trade_value = sum(raw$cusval, na.rm = TRUE))

  n_before <- nrow(raw)
  raw <- raw[year >= cfg$minyear]
  if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) {
    raw <- raw[year <= cfg$maxyear]
  }
  actual_maxyear <- if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) cfg$maxyear else max(raw$year)
  qlog$add(sprintf("Keep years %d-%d", cfg$minyear, actual_maxyear),
           n_obs = nrow(raw), n_dropped = n_before - nrow(raw),
           trade_value = sum(raw$cusval, na.rm = TRUE))

  # HS6 -> HS4
  raw[, good := pad_hs6(good)]
  bad_len <- sum(nchar(raw$good) != 6L)
  if (bad_len > 0L) {
    warning(sprintf("%d HS6 codes not 6 digits after padding; dropping.", bad_len))
    raw <- raw[nchar(good) == 6L]
  }

  if (cfg$agg_level == "hs4") {
    raw[, good := hs6_to_hs4(good)]
    n_before <- nrow(raw)
    raw <- raw[, .(cusval = sum(cusval), quantity = sum(quantity)),
               by = .(year, good, importer, exporter)]
    qlog$add("Aggregate HS6 to HS4", n_obs = nrow(raw),
             n_dropped = n_before - nrow(raw),
             trade_value = sum(raw$cusval, na.rm = TRUE),
             detail = sprintf("%d unique HS4 products", uniqueN(raw$good)))
  }
  } # end if/else raw_cache

  # Regional aggregation
  if (cfg$use_regions) {
    rmap <- if (!is.null(cfg$custom_region_map)) cfg$custom_region_map else build_region_map()
    rmap[, cty_code := as.integer(cty_code)]

    imp_merged <- rmap[data.table(cty_code = as.integer(raw$importer)), on = "cty_code"]
    imp_merged[is.na(region), region := "OTHER"]
    raw[, importer := imp_merged$region]

    exp_merged <- rmap[data.table(cty_code = as.integer(raw$exporter)), on = "cty_code"]
    exp_merged[is.na(region), region := "OTHER"]
    raw[, exporter := exp_merged$region]

    n_unmapped_imp <- sum(raw$importer == "OTHER")
    n_unmapped_exp <- sum(raw$exporter == "OTHER")

    n_before <- nrow(raw)
    raw <- raw[, .(cusval = sum(cusval), quantity = sum(quantity)),
               by = .(year, good, importer, exporter)]
    qlog$add("Regional aggregation (Soderbery Table 1)", n_obs = nrow(raw),
             n_dropped = n_before - nrow(raw),
             trade_value = sum(raw$cusval, na.rm = TRUE),
             detail = sprintf("%d importers, %d exporters; %s unmapped imp, %s unmapped exp",
                              uniqueN(raw$importer), uniqueN(raw$exporter),
                              format(n_unmapped_imp, big.mark = ","),
                              format(n_unmapped_exp, big.mark = ",")))
  } else {
    raw[, `:=`(importer = as.character(importer), exporter = as.character(exporter))]
    qlog$add("No regional aggregation (individual countries)", n_obs = nrow(raw),
             trade_value = sum(raw$cusval, na.rm = TRUE),
             detail = sprintf("%d importers, %d exporters",
                              uniqueN(raw$importer), uniqueN(raw$exporter)))
  }

  # Prices, shares, first-differences
  dt <- copy(raw)
  dt[, `:=`(t = year - cfg$minyear + 1L, lp = log(cusval / quantity))]
  dt[, imp_total := sum(cusval), by = .(t, importer, good)]
  dt[, `:=`(s_imp = cusval / imp_total, ls_imp = log(cusval / imp_total))]
  dt[, exp_total := sum(cusval), by = .(t, exporter, good)]
  dt[, `:=`(s_exp = cusval / exp_total, ls_exp = log(cusval / exp_total))]

  setorder(dt, importer, exporter, good, t)
  dt[, `:=`(lp_dif = lp - shift(lp, 1L),
            ls_imp_dif = ls_imp - shift(ls_imp, 1L),
            ls_exp_dif = ls_exp - shift(ls_exp, 1L),
            period_count = .N), by = .(importer, exporter, good)]

  n_before <- nrow(dt)
  dt <- dt[!is.na(lp_dif)]
  qlog$add("First-differencing (drop first obs per panel)",
           n_obs = nrow(dt), n_dropped = n_before - nrow(dt),
           trade_value = sum(dt$cusval, na.rm = TRUE))

  if (!is.na(cfg$uv_outlier_threshold) && cfg$uv_outlier_threshold > 0) {
    thresh <- cfg$uv_outlier_threshold
    n_before <- nrow(dt)
    dt <- dt[abs(lp_dif) < thresh]
    qlog$add(sprintf("Unit value outlier filter |d ln(p)| < %.1f", thresh),
             n_obs = nrow(dt), n_dropped = n_before - nrow(dt),
             trade_value = sum(dt$cusval, na.rm = TRUE),
             detail = sprintf("Threshold = factor of ~%.1f in levels", exp(thresh)))
  }

  qlog$add("Data entering estimation", n_obs = nrow(dt),
           trade_value = sum(dt$cusval, na.rm = TRUE),
           detail = sprintf("%d products, %d importers, %d exporters",
                            uniqueN(dt$good), uniqueN(dt$importer),
                            uniqueN(dt$exporter)))

  cat(sprintf("\nEstimation sample: %s obs, %d products, %d importers, %d exporters\n",
              format(nrow(dt), big.mark = ","),
              uniqueN(dt$good), uniqueN(dt$importer), uniqueN(dt$exporter)))

  cell_stats <- dt[, .(n_exp = uniqueN(exporter), n_per = uniqueN(t)),
                   by = .(importer, good)]
  cat(sprintf("  Cells: %s | Exporters/cell: median=%d, mean=%.1f | Periods/cell: median=%d, mean=%.1f\n\n",
              format(nrow(cell_stats), big.mark = ","),
              median(cell_stats$n_exp), mean(cell_stats$n_exp),
              median(cell_stats$n_per), mean(cell_stats$n_per)))

  list(dt = dt, qlog = qlog)
}


# ===========================================================================
#  PARALLEL ESTIMATION ENGINE
# ===========================================================================

#' @param cfg Config list.
#' @param ncores Number of CPU cores. NULL = detectCores() - 2.
#' @return data.table of estimates.
