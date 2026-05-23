#' R/utils_general.R
#'
#' General-purpose utility functions for the trade-elasticities pipeline.
#' These are small, topic-independent helpers used across the estimation
#' layer: reference-exporter selection, BW weighting, a cell-failure
#' indicator, and the optimal-tariff formula.
#'
#' (Renamed from helpers.R during the N+6 R/ conventions pass. The functions
#' were originally extracted from the monolithic feen94_het_baci.R during the
#' May 2026 step-3 refactor.)
#'
#' Exported functions:
#'   choose_reference(dt)                          — pick reference exporter for a market
#'   bw_weight(cusval_t, cusval_lag, T_count)      — BW weights (Soderbery 2018, p.50 fn14)
#'   cell_failure(reason)                          — lightweight cell-level failure indicator
#'   optimal_tariff(gamma, sigma, trade_values)    — trade-weighted optimal tariff
#'
#' Depends on: none (base R + data.table semantics at call sites)

#' Choose reference exporter within an import market.
#' Selects the largest, most persistent exporter.
choose_reference <- function(dt) {
  stats <- dt[, .(n_periods = uniqueN(t),
                   total_value = sum(cusval, na.rm = TRUE)),
              by = exporter]
  max_pd <- max(stats$n_periods)
  candidates <- stats[n_periods >= max_pd]
  candidates$exporter[which.max(candidates$total_value)]
}


#' Compute BW weights (paper p. 50, fn 14).
#' Weight = T^(3/2) * (1/x_t + 1/x_{t-1})^(-1/2)
bw_weight <- function(cusval_t, cusval_lag, T_count) {
  w <- T_count^1.5 * (1 / cusval_t + 1 / cusval_lag)^(-0.5)
  w[is.na(w) | !is.finite(w)] <- 1
  w
}


#' Lightweight failure indicator for cell-level diagnostics.
#' Returned instead of NULL so that estimate_product can log the reason.
cell_failure <- function(reason) {
  structure(list(reason = reason), class = "cell_failure")
}


#' Trade-weighted optimal tariff across exporters within a cell.
#' Returns NA if no exporter has a valid (positive) gamma and trade value.
optimal_tariff <- function(gamma, sigma, trade_values = NULL) {
  if (is.null(trade_values)) trade_values <- rep(1, length(gamma))
  ok <- gamma > 0 & !is.na(gamma) & trade_values > 0
  if (sum(ok) == 0L) return(NA_real_)
  g <- gamma[ok]; w <- trade_values[ok]
  num <- sum(w * g / (1 + g * sigma))
  den <- sum(w / (1 + g * sigma))
  if (den == 0) NA_real_ else num / den
}
