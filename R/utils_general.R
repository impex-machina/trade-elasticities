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


#' Deterministic product subsample for local Stage-2 experiments (patch 0071).
#' Every quantity in prepare_data() is within good, so subsetting the raw cache
#' to the sampled goods BEFORE prepare_data() is exact for Stage 2. Returns the
#' sorted vector of goods to keep; frac = 1 returns all goods.
sample_products <- function(goods, frac, seed) {
  goods <- sort(unique(as.character(goods)))
  if (!is.finite(frac) || frac <= 0 || frac > 1) stop("product sample fraction must be in (0, 1]")
  if (frac >= 1) return(goods)
  n <- max(1L, as.integer(round(length(goods) * frac)))
  set.seed(as.integer(seed))
  sort(sample(goods, n))
}

#' Directly-estimated row predicate for a Stage-2 output (patch 0066,
#' 2026-09-24 fresh-eyes audit). A row's gamma was produced by the
#' optimizer iff its tier is 0/1/2 AND the cell was fitted: the all-Tier-3
#' early return in estimate_importer_product_fixed_sigma() gives the
#' REFERENCE exporter tier 0 with the good-level prior and convergence -1,
#' and `tier < 3` alone let that imputed row pass as an estimate at the three
#' sites that filter on it (opt_tariff, the plateau-fallback recompute in
#' scripts/run_estimation.R, and the tail-trim source in
#' estimate_all_fixed_sigma()). Tier-3 rows of fitted cells carry
#' convergence -1 too, so the rule is simply: tier < 3 and not imputed.
is_estimated_row <- function(tier, convergence) {
  !is.na(tier) & tier < 3L & !(convergence %in% -1L)
}


#' Recompute opt_tariff / opt_tariff_all for every (importer, good) cell over
#' the rows PRESENT in `dt` -- the published-row definition (patch 0081).
#'
#' Through v0.8.2 each cell's opt_tariff was computed inside the cell
#' estimator from all of the cell's rows, BEFORE estimate_all_fixed_sigma()'s
#' 0.5%-per-tail trim removed rows, and only cells touched by the Stage-2a
#' plateau replacement were ever recomputed afterwards. A cell statistic
#' therefore depended on rows the table does not publish: on the shipped
#' v0.8.2 Stage-2b table 27,797 cells (12.0%) carried a value that differs
#' from the published-row value (median relative difference 19.5%, p90 162%)
#' and 1,571 cells stated an optimal tariff above every gamma they publish,
#' which a trade-weighted mean of published gamma cannot do; Stage 2a: 1,766
#' cells (7.0%), 126 impossible. This function is now called once for every
#' cell after the trim (estimate_all_fixed_sigma) and again after the
#' Stage-2a plateau replacement (run_estimation.R), and
#' scripts/recompute_opt_tariff.R applies it to an existing table. It is
#' idempotent: on a table whose values already satisfy the definition it
#' changes nothing.
#'
#' @param dt data.table with importer, good, gamma, sigma, avg_trade, tier,
#'   convergence, opt_tariff, opt_tariff_all; modified by reference.
#' @return invisibly, list(n_cells, n_changed, n_above_gmax_before,
#'   n_above_gmax_after, median_before, median_after) at the cell level.
recompute_opt_tariff <- function(dt) {
  need <- c("importer", "good", "gamma", "sigma", "avg_trade", "tier", "convergence",
            "opt_tariff", "opt_tariff_all")
  miss <- setdiff(need, names(dt))
  if (length(miss)) stop("recompute_opt_tariff(): missing columns: ", paste(miss, collapse = ", "))
  cell_view <- function(d) d[, .(ot = opt_tariff[1], ota = opt_tariff_all[1],
                                 gmax = suppressWarnings(max(gamma, na.rm = TRUE))), by = .(importer, good)]
  before <- cell_view(dt)
  dt[, `:=`(
    opt_tariff = {
      est <- is_estimated_row(tier, convergence)
      if (any(est)) optimal_tariff(gamma[est], sigma[est][1], avg_trade[est]) else NA_real_
    },
    opt_tariff_all = optimal_tariff(gamma, sigma[1], avg_trade)
  ), by = .(importer, good)]
  after <- cell_view(dt)
  dif <- function(a, b) !((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= 1e-9 * pmax(abs(a), 1)))
  invisible(list(
    n_cells = nrow(after),
    n_changed = sum(dif(before$ot, after$ot) | dif(before$ota, after$ota)),
    n_above_gmax_before = sum(before$ot > before$gmax + 1e-9, na.rm = TRUE),
    n_above_gmax_after  = sum(after$ot > after$gmax + 1e-9, na.rm = TRUE),
    median_before = median(before$ot, na.rm = TRUE),
    median_after  = median(after$ot, na.rm = TRUE)))
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


# ---------------------------------------------------------------------------
# boundary_flags(): value-based cap flags for boundary-search optima.
#
# Patch 0031 set sigma_capped / omega_capped from the boundary EDGE label
# alone. hliml_boundary_search() runs a 1-D optimize() ALONG each edge, so
# the free parameter can itself land at (within optimize() tolerance of) its
# own cap -- a corner solution. In the v0.6.0-rc run, 1,934 of 30,056
# boundary cells sat at sigma >= 9.999 without sigma_capped (949 on the
# omega_floor edge, 985 on the omega_cap edge). Downstream consumers filter
# on the flags, so the flags must record the VALUE state; the ROUTE is
# recorded separately in hliml_boundary_edge.
#
# tol = 1e-3 matches the at-cap census definition (sigma >= cap - 1e-3);
# optimize() endpoints land within its convergence tolerance of the cap,
# never exactly on it, so exact equality would undercount corners.
# scripts/patch_stage1_boundary_flags.R sources THIS function to correct
# already-shipped artifacts, so pipeline and patch share one definition.
boundary_flags <- function(edge, sigma, omega, sigma_cap, omega_cap,
                           tol = 1e-3) {
  list(
    sigma_capped = isTRUE(identical(edge, "sigma_cap") ||
                            (!is.na(sigma) && sigma >= sigma_cap - tol)),
    omega_capped = isTRUE(identical(edge, "omega_cap") ||
                            (!is.na(omega) && omega >= omega_cap - tol))
  )
}


# ---------------------------------------------------------------------------
# (patch 0053) The one `%||%` for the whole pipeline. NULL-or-NA semantics --
# the estimator's per-cell lists carry NA for "not computed" as often as
# NULL for "absent", and every call site passes a scalar. Previously
# defined in five files with two different semantics (NULL-only in
# build_config.R / master.R / validate_liml.R / the test helper, NULL-or-NA
# in the Stage-1 wrapper); whichever was sourced last won. R >= 4.4 ships a
# NULL-only base version, which this masks deliberately.
# ---------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
