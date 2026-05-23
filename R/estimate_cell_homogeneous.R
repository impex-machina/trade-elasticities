#' R/estimate_cell_homogeneous.R
#'
#' Homogeneous (single-gamma) cell estimation: the Soderbery (2018) HLIML
#' path that estimates sigma and a common gamma per cell.
#' Extracted from feen94_het_baci.R (lines 517-902, 921-987) at refactor
#' step 3; content identical to the original, only sectioned.
#'
#' Exported functions:
#'   compute_exporter_weights(dt_nonref, exporter_order, cfg)                — exporter weights
#'   build_export_moments(exporter_order, focal_importer, all_dt, cfg, ...)  — export-side moments
#'   compute_exporter_lookup(dt_g)                                           — exporter lookup table
#'   estimate_importer_product(imp_dt, focal_importer, all_dt, cfg, ...)     — per importer-product fit
#'   estimate_product(g, dt_g, cfg)                                          — per-product fit
#'
#' Depends on: liml_estimator.R

compute_exporter_weights <- function(dt_nonref, exporter_order, cfg) {
  mode <- if (!is.null(cfg$exporter_weight)) cfg$exporter_weight else "uniform"
  J <- length(exporter_order)
  if (J == 0L) return(numeric(0))

  if (mode == "trade_value") {
    # Aggregate trade value AND period count per exporter in one pass
    stats <- dt_nonref[, .(wt = sum(cusval, na.rm = TRUE),
                            n_per = uniqueN(t)), by = exporter]
    setkey(stats, exporter)
    matched <- stats[J(exporter_order)]
    w     <- matched$wt
    n_per <- matched$n_per

    # Period-count floor: exporters with < period_floor_ref periods
    # get their weight scaled by n_periods / period_floor_ref.
    period_floor_ref <- if (!is.null(cfg$weight_period_floor))
      cfg$weight_period_floor else 10L
    if (period_floor_ref > 0L) {
      adj <- pmin(n_per, period_floor_ref) / period_floor_ref
      adj[is.na(adj)] <- 0
      w <- w * adj
    }

    tot <- sum(w, na.rm = TRUE)
    if (is.finite(tot) && tot > 0) {
      w <- w * J / tot
    }
    w[is.na(w) | !is.finite(w) | w <= 0] <- 1
    w
  } else {
    rep(1, J)
  }
}


#' Build export-side moment matrices (Eq. 11).
#'
#' For each non-reference exporter j, constructs the BW-weighted
#' time-averaged export-side moments by looking at j's export
#' shares across destinations. Returns the matrices, index map,
#' and reference-destination elasticities needed by the objective.
#'
#' Extracted from estimate_importer_product for clarity.
#' The computation is identical — this is a structural refactor only.
#'
#' @param exporter_order Character vector of non-reference exporters.
#' @param focal_importer The importer being estimated.
#' @param all_dt Full product-level data.table (all importers).
#'   Used only if exp_lookup is NULL.
#' @param cfg Config list. Reads cfg$sigma_V_default, cfg$gamma_V_default,
#'   and optionally cfg$sigma_V_lookup, cfg$gamma_V_lookup.
#' @param exp_lookup Optional named list of per-exporter data.tables
#'   (produced by compute_exporter_lookup). If provided, avoids repeated
#'   O(n) filtering of all_dt — key perf optimization for HS6.
#'   exp_lookup[[exp_j]] returns the subset of all_dt where exporter == exp_j.
#' @return Named list with exp_Y, exp_X, exp_jmap, sig_V, gam_V, wt_exp.
#'
#' REFERENCE-DESTINATION ELASTICITY LOOKUP:
#'   Soderbery's Eq. (11) parameterizes the export-side moments by
#'   (sigma_V, gamma_V) at the reference destination V. The baseline
#'   treatment uses a single global default for all exporters.
#'
#'   When cfg$sigma_V_lookup / cfg$gamma_V_lookup are provided, each
#'   Tier 1 exporter's reference destination gets its own (sigma, gamma)
#'   drawn from Stage 1 / Stage 2a estimates:
#'     - sigma_V_lookup: data.table(importer, good, sigma) — Stage 1 output
#'     - gamma_V_lookup: data.table(importer, good, gamma) — Stage 2a output
#'         (at Stage 2b; at Stage 2a, gamma_V_lookup is typically NULL
#'         and the global default is used)
#'   Lookup falls back to cfg$sigma_V_default / cfg$gamma_V_default when
#'   no match is found (thin bilateral relationships, non-overlapping
#'   product coverage, etc.).
build_export_moments <- function(exporter_order, focal_importer, all_dt, cfg,
                                  exp_lookup = NULL) {

  exp_Y_list   <- list()
  exp_X_list   <- list()
  exp_jmap_vec <- integer(0)
  sig_V_vec    <- numeric(0)
  gam_V_vec    <- numeric(0)

  # Helpers: lookup (importer, good) -> (sigma, gamma) with fallback.
  # Indexed by importer for O(log n) lookup via setkey; caller is
  # responsible for having keyed these lookups once upstream.
  sig_V_lkp <- cfg$sigma_V_lookup
  gam_V_lkp <- cfg$gamma_V_lookup

  for (j_idx in seq_along(exporter_order)) {
    exp_j <- exporter_order[j_idx]

    # Use pre-split lookup if available (HS6 perf optimization);
    # else fall back to O(n) filter of all_dt.
    if (!is.null(exp_lookup)) {
      exp_flows <- exp_lookup[[exp_j]]
      if (is.null(exp_flows) || nrow(exp_flows) == 0L) next
    } else {
      exp_flows <- all_dt[exporter == exp_j]
    }
    n_dest <- uniqueN(exp_flows$importer)
    if (n_dest < cfg$min_destinations) next

    dest_stats <- exp_flows[importer != focal_importer,
                            .(dest_val = sum(cusval, na.rm = TRUE)),
                            by = importer]
    if (nrow(dest_stats) == 0L) next

    ref_dest <- dest_stats$importer[which.max(dest_stats$dest_val)]

    ref_dest_vals <- exp_flows[importer == ref_dest,
                               .(t, ref_lp_exp = lp_dif,
                                 ref_ls_exp = ls_exp_dif)]

    focal_vals <- exp_flows[importer == focal_importer]
    focal_vals <- ref_dest_vals[focal_vals, on = "t"]
    focal_vals <- focal_vals[!is.na(ref_lp_exp) & !is.na(ref_ls_exp) &
                             !is.na(lp_dif) & !is.na(ls_exp_dif)]

    if (nrow(focal_vals) == 0L) next

    focal_vals[, `:=`(
      exp_y  = (lp_dif - ref_lp_exp)^2,
      exp_x1 = ls_exp_dif^2,
      exp_x2 = ls_exp_dif * lp_dif,
      exp_x3 = ref_ls_exp^2,
      exp_x4 = ref_ls_exp * lp_dif,
      exp_x5 = ref_ls_exp * ref_lp_exp,
      exp_x6 = ls_exp_dif * ref_lp_exp,
      exp_x7 = ls_exp_dif * ref_ls_exp,
      exp_x8 = ref_lp_exp^2,
      exp_x9 = ref_lp_exp * lp_dif
    )]
    focal_vals <- focal_vals[!is.na(exp_y)]
    if (nrow(focal_vals) == 0L) next

    setorder(focal_vals, t)
    focal_vals[, `:=`(cusval_lag = shift(cusval, 1L), pd_e = .N)]
    focal_vals[, bw_w_e := bw_weight(cusval, cusval_lag, pd_e)]

    exp_cols <- c("exp_y","exp_x1","exp_x2","exp_x3","exp_x4",
                  "exp_x5","exp_x6","exp_x7","exp_x8","exp_x9")
    exp_mom <- focal_vals[,
      lapply(.SD, weighted.mean, w = bw_w_e, na.rm = TRUE),
      .SDcols = exp_cols
    ]

    exp_Y_list[[length(exp_Y_list) + 1L]] <- exp_mom$exp_y
    exp_X_list[[length(exp_X_list) + 1L]] <- as.numeric(
      exp_mom[, .(exp_x1,exp_x2,exp_x3,exp_x4,exp_x5,
                  exp_x6,exp_x7,exp_x8,exp_x9)]
    )
    exp_jmap_vec <- c(exp_jmap_vec, j_idx + 2L)

    # --- Per-ref-destination (sig_V, gam_V) lookup with fallback ---
    # g_code is the product for this product-level estimation call.
    # all_dt$good[1] holds it (all rows share a single product).
    g_code <- all_dt$good[1]

    sig_V_val <- cfg$sigma_V_default
    if (!is.null(sig_V_lkp)) {
      row_s <- sig_V_lkp[importer == ref_dest & good == g_code]
      if (nrow(row_s) > 0L && !is.na(row_s$sigma[1]) && row_s$sigma[1] > 1) {
        sig_V_val <- row_s$sigma[1]
      }
    }

    gam_V_val <- cfg$gamma_V_default
    if (!is.null(gam_V_lkp)) {
      row_g <- gam_V_lkp[importer == ref_dest & good == g_code]
      if (nrow(row_g) > 0L && !is.na(row_g$gamma[1]) && row_g$gamma[1] > 0) {
        gam_V_val <- row_g$gamma[1]
      }
    }

    sig_V_vec    <- c(sig_V_vec, sig_V_val)
    gam_V_vec    <- c(gam_V_vec, gam_V_val)
  }

  M <- length(exp_Y_list)

  if (M > 0L) {
    list(
      exp_Y  = unlist(exp_Y_list),
      exp_X  = matrix(unlist(exp_X_list), nrow = M, ncol = 9, byrow = TRUE),
      jmap   = exp_jmap_vec,
      sig_V  = sig_V_vec,
      gam_V  = gam_V_vec,
      wt_exp = rep(1, M),
      M      = M
    )
  } else {
    list(
      exp_Y  = numeric(0),
      exp_X  = matrix(nrow = 0, ncol = 9),
      jmap   = integer(0),
      sig_V  = numeric(0),
      gam_V  = numeric(0),
      wt_exp = numeric(0),
      M      = 0L
    )
  }
}


#' Pre-split a product-level data.table by exporter.
#'
#' Constructs a named list of per-exporter data.table slices. Passing this
#' to build_export_moments converts O(N_exporters) repeated filtering of
#' all_dt into O(1) list indexing. At HS6 scale (5,300 products, many
#' exporters per product) this is a meaningful performance win.
#'
#' Called ONCE per product (not per importer) in estimate_product /
#' estimate_product_fixed_sigma.
#'
#' @param dt_g Product-level data.table.
#' @return Named list; names are exporter codes, values are their subsets.
compute_exporter_lookup <- function(dt_g) {
  split(dt_g, by = "exporter", keep.by = TRUE)
}


#' Estimate one (importer, product) cell.
#'
#' Returns a data.table on success, or a cell_failure object with
#' a diagnostic reason on failure. The cell_failure is collected
#' by estimate_product for the failure log.
#'
#' @param exp_lookup Optional pre-split per-exporter lookup (see
#'   compute_exporter_lookup). Passed through to build_export_moments.
estimate_importer_product <- function(imp_dt, focal_importer, all_dt, cfg,
                                      exp_lookup = NULL) {

  dt <- imp_dt[importer == focal_importer]

  n_exp <- uniqueN(dt$exporter)
  max_pd <- dt[, max(period_count)]

  if (n_exp < cfg$min_exporters || max_pd < cfg$min_periods) {
    return(cell_failure("insufficient_data"))
  }

  # --- Choose reference exporter k ---
  ref_exporter <- choose_reference(dt)

  # --- Reference-differencing (import side) ---
  ref_vals <- dt[exporter == ref_exporter,
                 .(t, ref_ls_dif = ls_imp_dif, ref_lp_dif = lp_dif)]

  dt <- ref_vals[dt, on = "t"]
  dt <- dt[!is.na(ref_ls_dif) & !is.na(ref_lp_dif)]

  dt[, `:=`(Dk_lp = lp_dif - ref_lp_dif,
            Dk_ls = ls_imp_dif - ref_ls_dif)]

  # --- Import-side moment variables (eq 10) ---
  dt[, `:=`(
    imp_y  = Dk_lp^2,
    imp_x1 = Dk_ls^2,
    imp_x2 = Dk_ls * Dk_lp,
    imp_x3 = Dk_ls * lp_dif,
    imp_x4 = Dk_ls * ref_lp_dif,
    imp_x5 = Dk_lp * ref_lp_dif
  )]

  dt <- dt[!is.na(imp_y) & !is.na(imp_x1) & !is.na(imp_x2)]

  dt_nonref <- dt[exporter != ref_exporter]
  if (nrow(dt_nonref) == 0L) return(cell_failure("no_nonref_exporters"))

  # --- BW weights ---
  setorder(dt_nonref, exporter, t)
  dt_nonref[, cusval_lag := shift(cusval, 1L), by = exporter]
  dt_nonref[, bw_w := bw_weight(cusval, cusval_lag, period_count)]

  # --- Time-average with BW weights ---
  imp_moments <- dt_nonref[,
    lapply(.SD, weighted.mean, w = bw_w, na.rm = TRUE),
    by = exporter,
    .SDcols = c("imp_y", "imp_x1", "imp_x2", "imp_x3", "imp_x4", "imp_x5")
  ]
  setorder(imp_moments, exporter)

  J <- nrow(imp_moments)
  if (J < 1L) return(cell_failure("no_valid_moments"))

  exporter_order <- imp_moments$exporter
  imp_Y_vec <- imp_moments$imp_y
  imp_X_mat <- as.matrix(imp_moments[, .(imp_x1, imp_x2, imp_x3,
                                          imp_x4, imp_x5)])
  wt_imp_vec <- rep(1, J)


  # =========================================================
  #  EXPORT-SIDE MOMENT VARIABLES (eq 11)
  # =========================================================

  exp_mom <- build_export_moments(exporter_order, focal_importer, all_dt, cfg,
                                   exp_lookup = exp_lookup)
  exp_Y_vec    <- exp_mom$exp_Y
  exp_X_mat    <- exp_mom$exp_X
  exp_jmap_vec <- exp_mom$jmap
  sig_V_vec    <- exp_mom$sig_V
  gam_V_vec    <- exp_mom$gam_V
  wt_exp_vec   <- exp_mom$wt_exp


  # =========================================================
  #  JOINT NONLINEAR SUR ESTIMATION
  # =========================================================

  # Per-cell starting values from regional estimates if available
  sig_init <- cfg$sigma_start
  gam_init <- cfg$gamma_start

  if (!is.null(cfg$regional_starts)) {
    g_code <- imp_dt$good[1]
    imp_region <- focal_importer
    # If running country-level, map country code to region
    if (!is.null(cfg$regional_starts_rmap)) {
      imp_region <- assign_regions(focal_importer, cfg$regional_starts_rmap)
    }
    match_row <- cfg$regional_starts[region == imp_region & good == g_code]
    if (nrow(match_row) > 0L) {
      sig_init <- match_row$sigma[1]
      gam_init <- match_row$gamma[1]
    }
  }

  d_start <- c(sig_init, gam_init, rep(gam_init, J))
  lower_bounds <- c(1 + 1e-6, rep(1e-6, J + 1))

  result <- tryCatch(
    optim(
      par    = d_start,
      fn     = het_obj,
      method = "L-BFGS-B",
      lower  = lower_bounds,
      upper  = rep(Inf, J + 2),
      imp_Y  = imp_Y_vec,  imp_X = imp_X_mat,
      exp_Y  = exp_Y_vec,  exp_X = exp_X_mat,
      exp_jmap  = exp_jmap_vec,
      exp_sig_V = sig_V_vec, exp_gam_V = gam_V_vec,
      wt_imp = wt_imp_vec, wt_exp = wt_exp_vec,
      control = list(maxit = 500)
    ),
    error = function(e) NULL
  )

  if (is.null(result) || result$convergence != 0) {
    result <- tryCatch(
      optim(
        par = d_start, fn = het_obj, method = "Nelder-Mead",
        imp_Y = imp_Y_vec, imp_X = imp_X_mat,
        exp_Y = exp_Y_vec, exp_X = exp_X_mat,
        exp_jmap = exp_jmap_vec,
        exp_sig_V = sig_V_vec, exp_gam_V = gam_V_vec,
        wt_imp = wt_imp_vec, wt_exp = wt_exp_vec,
        control = list(maxit = 1000)
      ),
      error = function(e) NULL
    )
  }

  if (is.null(result)) return(cell_failure("optimizer_failed"))

  d_hat <- result$par
  sigma_hat   <- d_hat[1]
  gamma_k_hat <- d_hat[2]
  gamma_j_hat <- d_hat[3:(J + 2)]

  if (sigma_hat <= 1) sigma_hat <- NA_real_
  gamma_k_hat <- max(gamma_k_hat, 0)
  gamma_j_hat <- pmax(gamma_j_hat, 0)

  data.table(
    importer     = focal_importer,
    exporter     = c(exporter_order, ref_exporter),
    sigma        = sigma_hat,
    gamma        = c(gamma_j_hat, gamma_k_hat),
    ref_exporter = ref_exporter,
    convergence  = result$convergence,
    obj_value    = result$value
  )
}




estimate_product <- function(g, dt_g, cfg) {
  t0 <- proc.time()["elapsed"]
  importers <- unique(dt_g$importer)
  results_g <- list()
  failures_g <- list()
  n_cells <- 0L; n_ok <- 0L; n_skipped <- 0L

  # --- Pre-filter: skip importers that cannot meet minimum requirements ---
  imp_stats <- dt_g[, .(n_exp = uniqueN(exporter),
                         max_pd = max(period_count)),
                     by = importer]
  viable_importers <- imp_stats[n_exp >= cfg$min_exporters &
                                max_pd >= cfg$min_periods, importer]
  n_skipped <- length(importers) - length(viable_importers)

  # --- Pre-split per-exporter slices ONCE per product (HS6 perf) ---
  exp_lookup <- compute_exporter_lookup(dt_g)

  for (imp in viable_importers) {
    n_cells <- n_cells + 1L
    est <- tryCatch(
      estimate_importer_product(dt_g, imp, dt_g, cfg, exp_lookup = exp_lookup),
      error = function(e) cell_failure(paste0("error: ", conditionMessage(e)))
    )

    if (inherits(est, "cell_failure")) {
      failures_g[[length(failures_g) + 1L]] <- list(
        importer = imp, good = g, reason = est$reason)
      next
    }

    if (!is.null(est)) {
      est[, good := g]
      trade_wt <- dt_g[importer == imp,
                       .(avg_trade = mean(cusval, na.rm = TRUE)), by = exporter]
      est <- trade_wt[est, on = "exporter"]
      ot <- optimal_tariff(est$gamma, est$sigma[1], est$avg_trade)
      est[, opt_tariff := ot]
      results_g[[length(results_g) + 1L]] <- est
      n_ok <- n_ok + 1L
    }
  }

  elapsed <- as.numeric(proc.time()["elapsed"] - t0)
  if (length(results_g) > 0L) {
    out <- rbindlist(results_g)
    attr(out, "timing") <- list(product = g, seconds = elapsed,
                                cells = n_cells, succeeded = n_ok,
                                skipped = n_skipped)
    attr(out, "failures") <- failures_g
    out
  } else { NULL }
}


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
