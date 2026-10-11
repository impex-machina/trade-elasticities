#' R/iteration_helpers.R
#'
#' Iteration and starting-value helpers: seed two-step passes from prior
#' results and initialise country-level fits from regional estimates.
#' Extracted from feen94_het_baci.R (lines 1521-1608) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   update_defaults_from_results(cfg, results, pass)       — update starting values from a prior pass
#'   init_from_regional(cfg, regional_results, custom_map)  — seed country fits from regional results
#'
#' Depends on: none

# ===========================================================================
#  ITERATION AND STARTING VALUE HELPERS
# ===========================================================================

#' Update defaults from completed results for iterative refinement.
#'
#' NOTE: currently unused by run_estimation.R (three-stage pipeline uses
#' explicit Stage 1 -> Stage 2a -> Stage 2b handoff with its own default
#' updates). Retained for interactive use / iterative robustness checks.
update_defaults_from_results <- function(cfg, results, pass = 1L) {
  ms <- median(results$sigma, na.rm = TRUE)
  mg <- median(results$gamma, na.rm = TRUE)
  cfg$sigma_start <- ms; cfg$gamma_start <- mg
  cfg$sigma_V_default <- ms; cfg$gamma_V_default <- mg
  cat(sprintf("  Defaults updated from pass %d: sigma=%.3f, gamma=%.3f\n", pass, ms, mg))
  cfg
}


#' Stage-2b good-level priors and reference-destination gamma_V from the
#' Stage-2a table (patch 0077 fresh-eyes audit #4, delivered as patch 0079).
#'
#' Through v0.8.2 the runner took `median(log(gamma))` by good and
#' `median(gamma)` by (region, good) over EVERY Stage-2a row with a positive
#' gamma -- including the Tier-3 rows Stage 2a itself imputed at the Stage-1
#' good-level prior (convergence -1) and the all-Tier-3 early-return
#' reference rows -- so the country prior partly echoed the Stage-1 prior
#' back through Stage 2a. `rows = "estimated"` restricts both medians to
#' directly estimated Stage-2a rows (`is_estimated_row()`, the patch-0066
#' predicate the trim and opt_tariff already use); `rows = "all"` reproduces
#' the runner's rule through v0.8.2 bit for bit. Starting values
#' (init_from_regional) are not touched by this rule.
#'
#' @param regional_clean Stage-2a rows with !is.na(sigma), !is.na(gamma), gamma > 0.
#' @param rows "all" (<= v0.8.2) or "estimated".
#' @return list(country_priors = (good, ln_gamma_prior),
#'              gam_V_regional = (region, good, gamma), n_rows_used, n_rows_all).
stage2b_priors_from_regional <- function(regional_clean, rows = c("all", "estimated")) {
  rows <- match.arg(rows)
  src <- if (rows == "estimated") {
    if (!all(c("tier", "convergence") %in% names(regional_clean)))
      stop("stage2b_priors_from_regional(rows = 'estimated') needs tier and convergence columns")
    regional_clean[is_estimated_row(tier, convergence)]
  } else regional_clean
  list(
    country_priors = src[, .(ln_gamma_prior = median(log(gamma), na.rm = TRUE)), by = good],
    gam_V_regional = src[, .(gamma = median(gamma, na.rm = TRUE)), by = .(region = importer, good)],
    n_rows_used = nrow(src), n_rows_all = nrow(regional_clean), rows = rows)
}


#' Stage-2 sigma-edge rule (patch 0086).
#'
#' A Stage-1 cell whose published sigma is a box edge (sigma_capped: the Step-2
#' clamp, the sigma edge of the boundary box, or the corner of the omega-cap
#' edge) has no sigma estimate. Under rule "fallback" such cells leave the
#' clean set, so Stage 2 gives them the fallback sigma like any cell without
#' an estimate, sigma_robust is FALSE on them, they carry no sigma_V, and
#' their omega is out of the priors. "publish" (every release through v0.8.3)
#' keeps them with sigma = cap. "fallback" is the v0.9.0 default (patch 0087).
#' @return the (possibly filtered) table with attribute n_edge_dropped.
apply_sigma_edge_rule <- function(sigma_clean, rule = c("fallback", "publish")) {
  rule <- match.arg(rule)
  if (rule == "publish" || !"sigma_capped" %in% names(sigma_clean)) {
    data.table::setattr(sigma_clean, "n_edge_dropped", 0L); return(sigma_clean)
  }
  keep <- !(sigma_clean$sigma_capped %in% TRUE)
  out <- sigma_clean[keep]
  data.table::setattr(out, "n_edge_dropped", sum(!keep))
  out
}


#' The sigma-pole rule (patch 0099, experiment flag; default "none").
#'
#' Mirrors apply_sigma_edge_rule() at the other end of the sigma axis: a
#' Stage-1 cell whose sigma is within `c` standard errors of the pole,
#' sigma - 1 < c * sigma_se, leaves the clean set under rule "fallback" --
#' Stage 2 gives it the fallback sigma, it supplies no sigma_V and its omega
#' leaves the priors, exactly as the v0.9.0 cap-edge cells do. Motivation
#' (patch 0098): the gamma tails the trim removes are sigma-pole cells (88%
#' with sigma < 2, 65% within one SE of sigma = 1), where Eq. (10)'s
#' 1/(sigma - 1) coefficients send individual gammas to either end. A cell
#' with no finite SE cannot be assessed and is kept. "none" is the identity
#' (every release).
#'
#' @param sigma_clean the clean Stage-1 table after the edge rule.
#' @param rule "none" or "fallback".
#' @param c the threshold in SE units (default 1).
#' @return the filtered table with attribute n_pole_dropped.
apply_sigma_pole_rule <- function(sigma_clean, rule = c("none", "fallback"), c = 1) {
  rule <- match.arg(rule)
  if (rule == "none" || !"sigma_se" %in% names(sigma_clean)) {
    data.table::setattr(sigma_clean, "n_pole_dropped", 0L); return(sigma_clean)
  }
  if (!is.finite(c) || c <= 0) stop("apply_sigma_pole_rule(): c must be a positive number, got ", c)
  drop <- is.finite(sigma_clean$sigma_se) & (sigma_clean$sigma - 1) < c * sigma_clean$sigma_se
  out <- sigma_clean[!drop]
  data.table::setattr(out, "n_pole_dropped", sum(drop))
  out
}


#' Published-row mask (patch 0093): TRUE where the row is not a flagged
#' trimmed row (trim_reason NA, or no such column). Every consumer of a
#' Stage-2 table reads the published rows through this.
is_published_row <- function(dt) {
  if ("trim_reason" %in% names(dt)) is.na(dt$trim_reason) else rep(TRUE, nrow(dt))
}


#' Attach gamma_v_resid to a Stage-2b table (patch 0093).
#'
#' gamma_v_resid = |ln gamma_cur - ln gamma_prev| for every (importer,
#' exporter, good) row that is a directly estimated, converged, published
#' row with a finite positive gamma in BOTH passes -- the population the
#' exporter-specific gamma_V lookup is built from; NA on Tier-3 rows (their
#' gamma is the prior, identical across passes), on non-converged rows (a
#' fallback point), on flagged trimmed rows and on rows absent from the
#' previous pass. It is the per-row form of the pass-step census
#' (gamma_v_step()): the native gamma_V iteration is a fixed-point solve
#' with a contracting median and a tail that is not at a fixed point after
#' three passes (p99 of |d ln gamma| 0.40 at v0.9.0), and this column lets a
#' consumer see which rows are settled.
#'
#' @param cur the final pass table (modified by reference).
#' @param prev the previous pass table.
#' @return invisibly, a census list.
attach_gamma_v_resid <- function(cur, prev) {
  key <- c("importer", "exporter", "good")
  pick <- function(x) {
    ok <- is_estimated_row(x$tier, x$convergence) & x$convergence %in% 0L & is.finite(x$gamma) & x$gamma > 0 & is_published_row(x)
    y <- x[ok, c(key, "gamma"), with = FALSE]
    for (k in key) y[[k]] <- as.character(y[[k]])
    y
  }
  p <- pick(prev); data.table::setnames(p, "gamma", "gamma_prev")
  k_cur <- paste(as.character(cur$importer), as.character(cur$exporter), as.character(cur$good), sep = "\r")
  k_prev <- paste(p$importer, p$exporter, p$good, sep = "\r")
  m <- match(k_cur, k_prev)
  ok_cur <- is_estimated_row(cur$tier, cur$convergence) & cur$convergence %in% 0L & is.finite(cur$gamma) & cur$gamma > 0 & is_published_row(cur)
  res <- rep(NA_real_, nrow(cur))
  hit <- ok_cur & !is.na(m)
  res[hit] <- abs(log(cur$gamma[hit]) - log(p$gamma_prev[m[hit]]))
  cur[, gamma_v_resid := res]
  d <- res[is.finite(res)]
  q <- function(pr) if (length(d)) unname(stats::quantile(d, pr)) else NA_real_
  invisible(list(n_rows = nrow(cur), n_filled = length(d), p50 = q(.5), p90 = q(.9), p99 = q(.99),
                 max = if (length(d)) max(d) else NA_real_, share_lt_1e2 = if (length(d)) mean(d < 1e-2) else NA_real_))
}


#' Re-append trimmed rows to a drop-mode Stage-2b table as flagged rows (patch 0093).
#'
#' `trimmed` is the run's _stage2_trimmed.rds (bit-exact, written beside the
#' CSV since patch 0093) or _stage2_trimmed.csv (full rows + reason since
#' patch 0093, 15 significant digits; the 7-column record of earlier runs is
#' accepted, and its rows then carry NA in every unrecorded column). With
#' `trimmed = NULL` only the
#' trim_reason column (NA) is added -- the drop-mode schema. Rows already in
#' `dt` are refused (the record belongs to another run). Returns the table
#' (a new object: rbindlist) and the census as attributes.
add_trim_flags <- function(dt, trimmed = NULL) {
  dt <- data.table::copy(dt)
  if (!"gamma_v_resid" %in% names(dt)) dt[, gamma_v_resid := NA_real_]
  if (!"trim_reason" %in% names(dt)) dt[, trim_reason := NA_character_]
  if (is.null(trimmed) || nrow(trimmed) == 0L) {
    data.table::setattr(dt, "trim_flag_census", list(n_flagged_added = 0L, n_published = sum(is.na(dt$trim_reason))))
    return(dt)
  }
  tr <- data.table::copy(trimmed); data.table::setDT(tr)
  if (!"reason" %in% names(tr)) stop("add_trim_flags(): the trimmed record needs a 'reason' column")
  for (k in c("importer", "exporter", "good")) { data.table::set(tr, j = k, value = as.character(tr[[k]])); data.table::set(dt, j = k, value = as.character(dt[[k]])) }
  k_dt <- paste(dt$importer, dt$exporter, dt$good, sep = "\r"); k_tr <- paste(tr$importer, tr$exporter, tr$good, sep = "\r")
  if (any(k_tr %in% k_dt))
    stop(sprintf("add_trim_flags(): %d rows of the trimmed record are already in the table; the record belongs to another run", sum(k_tr %in% k_dt)))
  data.table::setnames(tr, "reason", "trim_reason")
  tr[, gamma_v_resid := NA_real_]
  extra <- setdiff(names(tr), names(dt))
  if (length(extra)) tr[, (extra) := NULL]
  # a CSV round trip loses storage classes (integer vs double, logical);
  # align each recorded column to the table's class. Code columns with
  # leading zeros must be READ as character (the script's fread does).
  for (c in intersect(names(tr), names(dt))) {
    if (!identical(class(tr[[c]]), class(dt[[c]]))) {
      cls <- class(dt[[c]])[1]
      data.table::set(tr, j = c, value = switch(cls, integer = as.integer(tr[[c]]), numeric = as.numeric(tr[[c]]),
                                                logical = as.logical(tr[[c]]), character = as.character(tr[[c]]), tr[[c]]))
    }
  }
  n_unrec <- length(setdiff(names(dt), names(tr)))
  out <- rbindlist(list(dt, tr), use.names = TRUE, fill = TRUE)
  data.table::setattr(out, "trim_flag_census",
                      list(n_flagged_added = nrow(tr), n_published = sum(is.na(out$trim_reason)),
                           n_unrecorded_columns = n_unrec, reasons = as.list(table(tr$trim_reason))))
  out
}


#' Stage 2a's default gamma_V and gamma start (patch 0092).
#'
#' @param sigma_clean the clean Stage-1 table (gamma = omega column).
#' @param priors_rows the rows the good-level priors are built from
#'   (feenstra_gamma_clean in run_estimation.R: gamma > 0, unfloored,
#'   uncapped, and -- under --stage1-capped-omega drop -- no sigma-edge cells).
#' @param rule "clean" (every release: median over sigma_clean) or "priors"
#'   (median over priors_rows). NULL/absent == "clean".
#' @return the default gamma_V (a scalar).
stage2a_gamma_v_default <- function(sigma_clean, priors_rows, rule = "clean") {
  if (is.null(rule)) rule <- "clean"
  if (!rule %in% c("clean", "priors")) stop("stage2a_gamma_v_default(): rule must be 'clean' or 'priors', got: ", rule)
  src <- if (rule == "priors") priors_rows else sigma_clean
  if (is.null(src) || !"gamma" %in% names(src) || !any(is.finite(src$gamma)))
    stop("stage2a_gamma_v_default(): no finite gamma in the '", rule, "' rows")
  stats::median(src$gamma, na.rm = TRUE)
}


#' Stage-2b sigma lookups from the clean Stage-1 set (patch 0090).
#'
#' The sigma lookup, the Stage-1 sigma_se and adjust-code lookups that the
#' sigma-propagation step reads, and the sigma_V lookup of Eq. (11) are all
#' built from ONE table: the clean set as it stands after the sigma-edge rule
#' (`apply_sigma_edge_rule()`). A cell absent from that set has no sigma
#' estimate in Stage 2b, and so no Stage-1 SE or adjust code either. Through
#' v0.9.0 run_estimation.R built the SE and adjust lookups from the full
#' Stage-1 table, so the 13,810 cells the edge rule dropped took the fallback
#' sigma while `assess_sigma_robust()` and `compute_dgamma_dsigma()` read the
#' SE of the discarded sigma = 50 point (finite on the omega-edge corner
#' cells, adjust 6/8): sigma_se, dgamma_dsigma, gamma_se_total and
#' sigma_robust were published for a sigma the table does not carry.
#'
#' @param sigma_clean the clean Stage-1 table (sigma > 1, converged, edge
#'   rule applied); needs importer, good, sigma; sigma_se and adjust are
#'   optional (a NULL lookup is returned where the column is absent).
#' @return list(sigma_lookup, sigma_se_lookup, sigma_adjust_lookup,
#'   sigma_V_lookup), each keyed on character (importer, good).
stage2b_sigma_lookups <- function(sigma_clean) {
  stopifnot(all(c("importer", "good", "sigma") %in% names(sigma_clean)))
  key <- sigma_clean[, .(importer = as.character(importer), good = as.character(good))]
  sl <- data.table::copy(key)[, sigma := sigma_clean$sigma]
  list(
    sigma_lookup        = sl,
    sigma_se_lookup     = if ("sigma_se" %in% names(sigma_clean))
      data.table::copy(key)[, sigma_se := sigma_clean$sigma_se] else NULL,
    sigma_adjust_lookup = if ("adjust" %in% names(sigma_clean))
      data.table::copy(key)[, adjust := as.integer(sigma_clean$adjust)] else NULL,
    sigma_V_lookup      = data.table::copy(sl))
}


#' Apply the sigma-edge SE rule to an EXISTING Stage-2b table (patch 0090).
#'
#' For every (importer, good) cell whose Stage-1 row has status "ok" and
#' `sigma_capped` TRUE -- the cells `--stage2-sigma-edge fallback` drops from
#' the clean set -- the table's rows must carry the fallback sigma, and the
#' columns the sigma-propagation step fills are reset to what the patched
#' pipeline publishes on a fallback cell: sigma_se, dgamma_dsigma and
#' gamma_se_total NA, sigma_robust FALSE on rows that carry a flag (Tier-3
#' rows and all-Tier-3 early-return rows keep NA). gamma, gamma_se and every
#' other column are untouched: the optimizer never read the SE. Idempotent.
#' This is how the v0.9.1 table is corrected from the shipped v0.9.0 table
#' without re-estimation (scripts/apply_sigma_edge_se_rule.R).
#'
#' @param dt Stage-2b table (modified by reference).
#' @param stage1 Stage-1 table with importer, good, status, sigma_capped.
#' @return invisibly, the census list.
apply_sigma_edge_se_rule <- function(dt, stage1) {
  need <- c("importer", "good", "sigma", "sigma_se", "dgamma_dsigma", "gamma_se_total", "sigma_robust")
  miss <- setdiff(need, names(dt))
  if (length(miss)) stop("apply_sigma_edge_se_rule(): table is missing columns: ", paste(miss, collapse = ", "))
  if (!all(c("importer", "good", "status", "sigma_capped") %in% names(stage1)))
    stop("apply_sigma_edge_se_rule(): Stage-1 table needs importer, good, status, sigma_capped")
  edge <- stage1[status == "ok" & sigma_capped %in% TRUE,
                 .(importer = as.character(importer), good = as.character(good))]
  edge_key <- paste(edge$importer, edge$good, sep = "\r")
  is_edge <- paste(as.character(dt$importer), as.character(dt$good), sep = "\r") %in% edge_key
  n_cells_edge_in_table <- data.table::uniqueN(paste(dt$importer[is_edge], dt$good[is_edge]))
  sig_edge <- unique(dt$sigma[is_edge])
  if (length(sig_edge) > 1L)
    stop(sprintf("apply_sigma_edge_se_rule(): the edge cells carry %d distinct sigma values (expected one, the fallback); the table was not produced under --stage2-sigma-edge fallback", length(sig_edge)))
  before <- list(sigma_se = sum(is.finite(dt$sigma_se[is_edge])),
                 dgamma_dsigma = sum(is.finite(dt$dgamma_dsigma[is_edge])),
                 gamma_se_total = sum(is.finite(dt$gamma_se_total[is_edge])),
                 sigma_robust_true = sum(dt$sigma_robust[is_edge] %in% TRUE))
  if (any(is_edge)) {
    dt[is_edge, `:=`(sigma_se = NA_real_, dgamma_dsigma = NA_real_, gamma_se_total = NA_real_)]
    dt[is_edge & !is.na(sigma_robust), sigma_robust := FALSE]
  }
  invisible(list(n_edge_cells_stage1 = nrow(edge), n_edge_cells_in_table = n_cells_edge_in_table,
                 n_edge_rows = sum(is_edge), sigma_edge_value = if (length(sig_edge)) sig_edge else NA_real_,
                 before = before,
                 n_values_reset = before$sigma_se + before$dgamma_dsigma + before$gamma_se_total + before$sigma_robust_true,
                 share_robust_true_before = if (any(is_edge)) before$sigma_robust_true / sum(is_edge) else NA_real_))
}


#' Step between two Stage-2b passes of the exporter-specific gamma_V
#' iteration (patch 0086): |d ln gamma| on Tier-1 rows directly estimated and
#' converged in both passes, the rows the iteration touches.
#' @return named numeric: n, p50, p90, p99, max, share_lt_1e2.
gamma_v_step <- function(prev, cur) {
  key <- c("importer", "exporter", "good")
  pick <- function(x) {
    y <- x[tier == 1L & convergence == 0L & is.finite(gamma) & gamma > 0 & is_published_row(x), c(key, "gamma"), with = FALSE]   # patch 0093: published rows
    for (k in key) y[[k]] <- as.character(y[[k]])
    y
  }
  m <- merge(pick(prev), pick(cur), by = key, suffixes = c(".a", ".b"))
  d <- abs(log(m$gamma.b) - log(m$gamma.a))
  q <- function(p) if (length(d)) unname(quantile(d, p)) else NA_real_
  c(n = nrow(m), p50 = q(.5), p90 = q(.9), p99 = q(.99), max = if (length(d)) max(d) else NA_real_,
    share_lt_1e2 = if (length(d)) mean(d < 1e-2) else NA_real_)
}


#' Initialize country-level starting values from regional estimates.
#'
#' Creates a lookup table mapping (region, product) -> (sigma, gamma)
#' from regional estimation results. When set on config, the estimator
#' uses per-cell starting values instead of global defaults, which
#' speeds convergence and reduces failures.
#'
#' @param cfg Config list (for country-level estimation).
#' @param regional_results data.table from a regional estimation run.
#' @param custom_map Optional region map. NULL uses build_region_map().
#' @return Config list with regional_starts and regional_starts_rmap set.
init_from_regional <- function(cfg, regional_results, custom_map = NULL) {

  # Build per-(region, product) medians from regional results
  starts <- regional_results[!is.na(sigma) & sigma > 1 & gamma > 0,
                              .(sigma = median(sigma),
                                gamma = median(gamma)),
                              by = .(region = importer, good)]

  cfg$regional_starts <- starts
  cfg$regional_starts_rmap <- if (!is.null(custom_map)) custom_map else build_region_map()

  cat(sprintf("  Regional starting values loaded: %d (region x product) cells\n",
              nrow(starts)))
  cat(sprintf("  Coverage: sigma range [%.2f, %.2f], gamma range [%.2f, %.2f]\n",
              min(starts$sigma), max(starts$sigma),
              min(starts$gamma), max(starts$gamma)))
  cfg
}


# ===========================================================================
#  LAMBDA CALIBRATION DIAGNOSTIC
#
#  Computes the four criteria from the README for choosing shrinkage
#  lambda empirically:
#    1. Within-pair gamma MAD — should approach Soderbery's 0.125
#    2. Cross-cell variance decomposition R-squared — should approach 0.72
#    3. Share of gamma estimates on the plateau — should be near 0
#    4. Distinctness of Tier 1 vs Tier 3 distributions (KS-style gap)
#
#  Designed to be called on the output of estimate_all_fixed_sigma()
#  for a single lambda value. Typical use:
#
#    for (lam in c(0.01, 0.05, 0.1, 0.2, 0.5)) {
#      cfg_test$shrinkage_lambda <- lam
#      res <- estimate_all_fixed_sigma(cfg_test, prepared_dt = dt_test)
#      diag <- lambda_calibration_diagnostic(res, lambda = lam)
#      print(diag)
#    }
#
#  Targets listed in the return value are the Soderbery benchmarks.
#  Interpretation:
#    - Very low lambda (0.01): weak regularization, high plateau share
#    - Very high lambda (0.5): within-pair MAD collapses (overshrinkage)
#    - Sweet spot: plateau share ~0, within-pair MAD near 0.125,
#      Tier 1 / Tier 3 distributions clearly distinct
# ===========================================================================

#' Compute lambda calibration diagnostic for a single fixed-sigma run.
#'
#' @param results Output of estimate_all_fixed_sigma().
#' @param lambda Scalar lambda value used for the run (for labeling).
#' @param plateau_gamma_cutoff gamma value above which estimates are
#'   considered on the plateau. Default 20 (gamma/(1+gamma) > 0.95).
#' @return data.table with one row of diagnostics. Columns:
#'   lambda, n_estimates, n_pairs, within_pair_mad,
#'   r_squared, plateau_share, tier1_gamma_median, tier3_gamma_median,
#'   tier_distinctness
