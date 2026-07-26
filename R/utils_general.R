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
#'   calendar_lag(dt, value, t, by)                — previous-calendar-year value (fn14's x_{t-1})
#'   finalize_saved_output(x, sort_cols)           — strip volatile attrs + canonical sort for saveRDS
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


#' Previous-calendar-year value within a panel (fn 14's x_{t-1}).
#'
#' Returns, for each row, the `value` column at time t-1 located by an
#' explicit calendar match on the `t` column — NOT the previous retained
#' row. This is the lag Soderbery (2018, p. 50, fn 14) actually calls for:
#' x_{t-1} is data (the panel's previous-year customs value), not a
#' retained-row construct. A positional shift() silently substitutes a
#' stale x_{t-2+} whenever the row for t-1 has been filtered out of the
#' table being shifted; this helper is the calendar-correct replacement,
#' intended to be applied to the cell panel BEFORE moment filtering.
#'
#' Rows whose t-1 is not present in `dt` (within their `by` group) get NA;
#' bw_weight() maps NA to weight 1, so such rows fall to the same
#' near-zero-influence path as first rows — no new gap policy is needed.
#'
#' ASSUMES `t` is unique within each `by` group (base::match takes the
#' first hit on duplicates). The prepared panel satisfies this: it is
#' unique on (importer, exporter, good, t), so within one cell the groups
#' are (exporter, t)-unique and one bilateral series is t-unique.
#'
#' @param dt data.frame/data.table containing the `value`, `t`, and `by`
#'   columns. Not modified.
#' @param value Name of the value column. Default "cusval".
#' @param t Name of the integer time column. Default "t".
#' @param by Optional character vector of grouping columns (e.g.
#'   "exporter"). NULL treats dt as a single series.
#' @return Vector aligned to dt's rows: `value` at t-1 within the group,
#'   NA where t-1 is absent.
calendar_lag <- function(dt, value = "cusval", t = "t", by = NULL) {
  vv <- dt[[value]]
  tt <- dt[[t]]
  if (is.null(by)) {
    return(vv[match(tt - 1L, tt)])
  }
  grp <- if (length(by) == 1L) dt[[by]] else
    do.call(paste, c(unclass(dt)[by], sep = "\r"))
  out <- vv  # fully overwritten below: every row index falls in one group
  for (ix in split(seq_along(grp), grp)) {
    out[ix] <- vv[ix][match(tt[ix] - 1L, tt[ix])]
  }
  out
}


#' Finalize an estimator output table for saveRDS.
#'
#' Returns a COPY of x with the volatile attributes stripped (run_meta,
#' timing, failures — wall-clock metadata that made byte-identical data
#' hash differently across runs; see the lambda-sweep anchor
#' adjudication) and rows canonically sorted, so the saved file's sha256
#' certifies content rather than timestamps or parallel completion
#' order. The input object is NOT modified: summary generation reads
#' run_meta from the live object and is unaffected by save order.
#'
#' @param x data.table (or data.frame) estimator output.
#' @param sort_cols Candidate canonical key, applied as the intersection
#'   with names(x) in this order. The production outputs are row-unique
#'   on the surviving key; absent columns are skipped silently.
#' @return A finalized copy, ready for saveRDS.
finalize_saved_output <- function(x,
                                  sort_cols = c("good", "importer",
                                                "exporter")) {
  out <- data.table::copy(x)
  for (a in c("run_meta", "timing", "failures")) {
    data.table::setattr(out, a, NULL)
  }
  keys <- intersect(sort_cols, names(out))
  if (length(keys)) data.table::setorderv(out, keys)
  out
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
