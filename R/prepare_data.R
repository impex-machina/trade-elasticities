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
    old = c(cfg$value, cfg$quan, cfg$good, cfg$importer, cfg[["exporter"]], cfg$time),
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
    old = c(cfg$value, cfg$quan, cfg$good, cfg$importer, cfg[["exporter"]], cfg$time),
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

  # (patch 0072) The raw cache carries the year window it was built with
  # (prepare_raw_data's minyear/maxyear). A narrower window on the CLI must
  # still apply to a cached run; before this patch --minyear/--maxyear were
  # printed in the run header and silently ignored whenever the cache was
  # used, so any year-window experiment on the cache reproduced the full
  # panel (v0.8.0 grid, 2026-09-28). Bit-preserving when the window equals
  # the cache's.
  if (!is.null(raw_cache)) {
    n_before <- nrow(raw)
    raw <- raw[year >= cfg$minyear]
    if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) raw <- raw[year <= cfg$maxyear]
    if (nrow(raw) != n_before) {
      cat(sprintf("  Year window applied to cache: keep %d-%s (%s obs dropped)\n", cfg$minyear,
                  if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) as.character(cfg$maxyear) else "max",
                  format(n_before - nrow(raw), big.mark = ",")))
      qlog$add(sprintf("Keep years %d-%s (window applied to cache)", cfg$minyear,
                       if (!is.null(cfg$maxyear) && !is.na(cfg$maxyear)) as.character(cfg$maxyear) else "max"),
               n_obs = nrow(raw), n_dropped = n_before - nrow(raw),
               trade_value = sum(raw$cusval, na.rm = TRUE))
    }
  }

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
  # (patch 0107) --stage2-export-total all: the exporter's total exports of the
  # good include the value of flows without a quantity (dropped from the panel
  # at the HS6 line because they have no unit value), as Eq. (11)'s share
  # s^J_ij = x_ij / V_j defines V_j. The table comes from
  # scripts/build_export_totals.R; apply_export_totals() checks that its
  # quantity-observed column reproduces the panel's exp_total before use.
  if (identical(cfg[["stage2_export_total"]], "all")) dt <- apply_export_totals(dt, cfg)
  dt[, `:=`(s_exp = cusval / exp_total, ls_exp = log(cusval / exp_total))]
  # (patch 0110) --stage2-export-moment value: Eq. (11)'s export "share" terms on
  # log export VALUES. From Eq. (7), ln p_ij = eta/(1+g_ij) + rho_ij ln(p_ij x_ij)
  # exactly, so Eq. (8) holds on values; on shares it omits
  # (rho_I - rho_V) * dln V_j, V_j the exporter's total sales, which moves with
  # the Eq. (9) demand residual whenever gamma_I != gamma_V. Eq. (9) is a
  # difference across destinations, identical on either. The exporter total
  # then enters nothing (--stage2-export-total is moot). 'share' = every release.
  if (identical(cfg[["stage2_export_moment"]], "value")) dt[, ls_exp := log(cusval)]

  setorder(dt, importer, exporter, good, t)
  dt[, `:=`(lp_dif = lp - shift(lp, 1L),
            ls_imp_dif = ls_imp - shift(ls_imp, 1L),
            ls_exp_dif = ls_exp - shift(ls_exp, 1L),
            # (patch 0091) the Broda-Weinstein fn-14 lag x_{t-1}, taken HERE on
            # the pre-differencing panel: the customs value of the previous
            # calendar year, NA where that year is absent. Read by the
            # estimators under cfg$bw_lag = "raw"; the legacy and calendar
            # modes recompute their own lag on the cell panel and overwrite
            # this column, so they are unchanged by its presence. Under
            # "calendar" the lag is looked up on the DIFFERENCED table, which
            # has no row for a panel's first year, so the first differenced
            # observation of every run took bw_weight()'s NA -> 1 fallback --
            # a weight of ~1 beside 10-3,000 for its neighbours -- although
            # x_{t-1} is in the data; this column carries it.
            cusval_lag = shift(cusval, 1L),
            t_gap = t - shift(t, 1L),
            period_count = .N), by = .(importer, exporter, good)]

  # Consecutive-year guard. shift() pairs adjacent rows in the time order but
  # does not check the year step; a panel that trades in 2002 then 2007 would
  # otherwise be first-differenced across the gap as if it were a one-period
  # change, contaminating the d-log price/share moments. A first difference is
  # only meaningful across consecutive years, so null the diffs where the step
  # is not exactly 1; the !is.na(lp_dif) filter below then drops them alongside
  # each panel's leading NA.
  n_gap_spanning <- dt[!is.na(t_gap) & t_gap != 1L, .N]
  dt[is.na(t_gap) | t_gap != 1L,
     `:=`(lp_dif = NA_real_, ls_imp_dif = NA_real_, ls_exp_dif = NA_real_,
          cusval_lag = NA_real_)]   # patch 0091: the lag is the previous CALENDAR year's value or nothing
  dt[, t_gap := NULL]

  n_before <- nrow(dt)
  dt <- dt[!is.na(lp_dif)]
  qlog$add("First-differencing (drop leading obs + non-consecutive-year steps)",
           n_obs = nrow(dt), n_dropped = n_before - nrow(dt),
           trade_value = sum(dt$cusval, na.rm = TRUE),
           detail = sprintf("%s rows spanned a >1-year gap and were excluded",
                            format(n_gap_spanning, big.mark = ",")))

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


#' Country code -> region, exactly as prepare_data()'s regional aggregation
#' maps importers and exporters (unmapped codes -> "OTHER"). Patch 0107.
region_of <- function(codes, cfg) {
  rmap <- if (!is.null(cfg$custom_region_map)) data.table::copy(data.table::as.data.table(cfg$custom_region_map)) else build_region_map()
  rmap[, cty_code := as.integer(cty_code)]
  m <- rmap[data.table::data.table(cty_code = as.integer(codes)), on = "cty_code"]
  m[is.na(region), region := "OTHER"]
  m$region
}


#' Replace the panel's exporter totals with all-value totals (patch 0107).
#'
#' @param dt the panel after the exp_total step of prepare_data().
#' @param cfg needs `export_totals_tbl`: a table from scripts/build_export_totals.R
#'   with year, good, exporter (country codes), value_all, value_qobs.
#' @return dt with exp_total replaced; stops if the table's quantity-observed
#'   totals do not reproduce the panel's (the table was not built with the
#'   cache's rules) or if a panel cell has no total.
apply_export_totals <- function(dt, cfg) {
  tot <- cfg[["export_totals_tbl"]]
  if (is.null(tot)) stop("stage2_export_total = 'all' needs the export-totals table (scripts/build_export_totals.R; --export-totals-path)")
  tot <- data.table::as.data.table(tot)
  need <- c("year", "good", "exporter", "value_all", "value_qobs")
  if (length(setdiff(need, names(tot)))) stop("export-totals table is missing: ", paste(setdiff(need, names(tot)), collapse = ", "))
  tot <- tot[, .(year = as.integer(year), good = as.character(good), exporter = as.character(exporter), value_all, value_qobs)]
  if (isTRUE(cfg$use_regions)) {
    tot[, exporter := region_of(exporter, cfg)]
    tot <- tot[, .(value_all = sum(value_all), value_qobs = sum(value_qobs)), by = .(year, good, exporter)]
  }
  keys <- unique(dt[, .(year = as.integer(year), good = as.character(good), exporter = as.character(exporter), exp_total)])
  m <- tot[keys, on = .(year, good, exporter)]
  if (anyNA(m$value_all)) stop(sprintf("export-totals table has no row for %d panel (year, good, exporter) cells", sum(is.na(m$value_all))))
  rel <- abs(m$value_qobs - m$exp_total) / pmax(abs(m$exp_total), 1e-12)
  if (max(rel) > 1e-9) stop(sprintf("export-totals table was not built with the cache's rules: its quantity-observed value differs from the panel's exporter totals on %d of %d cells (max relative difference %.3g)", sum(rel > 1e-9), nrow(m), max(rel)))
  m[, yr := year]
  dt[, `:=`(.yr = as.integer(year), .gd = as.character(good), .ex = as.character(exporter))]
  dt[m, exp_total := i.value_all, on = .(.yr = yr, .gd = good, .ex = exporter)]
  dt[, c(".yr", ".gd", ".ex") := NULL]
  data.table::setattr(dt, "export_totals_census",
                      list(cells = nrow(m), cells_raised = sum(m$value_all > m$value_qobs * (1 + 1e-12)),
                           value_share_added = sum(m$value_all - m$value_qobs) / sum(m$value_all)))
  dt
}
