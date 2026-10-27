#' R/estimate_cell_homogeneous.R
#'
#' Shared Stage-2 helpers: the exporter weights, the export-side moments of
#' Eq. (11) and the per-product exporter lookup, used by the fixed-sigma
#' estimator (R/estimate_cell_fixed_sigma.R, Stages 2a and 2b) and, for the
#' weights, by the legacy Feenstra Stage 1 (R/estimate_stage1_feenstra.R).
#' The file is named for the homogeneous (single-gamma) cell estimator it
#' was extracted with (feen94_het_baci.R, refactor step 3).
#' (Patch 0149) That estimator -- estimate_importer_product() and
#' estimate_product(), driven by estimate_all_parallel() -- had no caller in
#' the pipeline and was removed; git history keeps it (through v0.11.4).
#'
#' Exported functions:
#'   compute_exporter_weights(dt_nonref, exporter_order, cfg)                — exporter weights
#'   build_export_moments(exporter_order, focal_importer, all_dt, cfg, ...)  — export-side moments
#'   compute_exporter_lookup(dt_g)                                           — exporter lookup table
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
  } else if (mode == "bw_sum") {
    # (patch 0091) The cross-variety weight implied by Broda & Weinstein's
    # observation-level weights in Feenstra's "2SLS with exporter dummies ==
    # WLS on exporter averages" equivalence: exporter j's averaged moment row
    # is weighted by the SUM of its row weights, sum_t T^{3/2} (1/x_t +
    # 1/x_{t-1})^{-1/2}. Inside the within-exporter weighted mean the T^{3/2}
    # factor cancels (T is constant within an exporter), so under
    # "trade_value" the persistence weight of fn. 14 never reaches the
    # objective; here it does, through this sum. Needs the bw_w column the
    # cell estimator attaches before calling. Normalized to sum to J, as
    # "trade_value" is, so lambda keeps its meaning against the data block.
    if (!"bw_w" %in% names(dt_nonref))
      stop("exporter_weight = 'bw_sum' needs the bw_w column (attach the BW weights first)")
    stats <- dt_nonref[, .(wt = sum(bw_w, na.rm = TRUE)), by = exporter]
    setkey(stats, exporter)
    w <- stats[J(exporter_order)]$wt
    tot <- sum(w, na.rm = TRUE)
    if (is.finite(tot) && tot > 0) w <- w * J / tot
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
#' Extracted from the homogeneous cell estimator (removed in patch 0149) for clarity.
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

  # Post-v0.4.1 audit, deferred BW-lag item. This function computes the
  # export-side fn-14 weights for every caller -- Stages 2a and 2b
  # (estimate_importer_product_fixed_sigma; the homogeneous estimator, removed
  # in patch 0149, was the other), so gating it here
  # covers every export-side moment. Semantics mirror the import sites: see
  # build_config.R for the v0.5.0 default-flip record and absent-key rule.
  bw_lag_calendar <- identical(cfg$bw_lag, "calendar")
  bw_lag_raw      <- identical(cfg$bw_lag, "raw")   # patch 0091: prepared cusval_lag column

  # Helpers: lookup (importer, good) -> (sigma, gamma) with fallback.
  # Indexed by importer for O(log n) lookup via setkey; caller is
  # responsible for having keyed these lookups once upstream.
  sig_V_lkp <- cfg$sigma_V_lookup
  gam_V_lkp <- cfg$gamma_V_lookup
  # (patch 0085) exporter-specific gamma_V: a keyed (importer = V, exporter,
  # good, gamma) table from a previous Stage-2b pass, already subset to this
  # product by estimate_product_fixed_sigma(). Eq. (11)'s object is exporter
  # j's own supply parameter at the reference destination V; the regional
  # median was a proxy for it. Used where (V, j) is present, regional median
  # (then the default) otherwise; NULL reproduces every release through v0.8.3.
  gam_V_exp_lkp <- cfg$gamma_V_exporter_lookup
  gv_counts <- c(exporter = 0L, regional = 0L, default = 0L)
  export_pc <- if (is.null(cfg$stage2_export_period_count)) "panel" else cfg$stage2_export_period_count   # patch 0086: absent == panel (v0.9.0)

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
    if (bw_lag_raw && !"cusval_lag" %in% names(focal_vals))
      stop("bw_lag = 'raw' needs the cusval_lag column prepare_data() attaches (patch 0091)")
    # calendar mode: attach the fn-14 lag on the pre-filter bilateral
    # series (one exporter -> the focal importer, so no `by` needed),
    # before the reference-destination join and exp_y filter can drop
    # rows and stale a positional shift.
    if (bw_lag_calendar) {
      focal_vals[, cusval_lag := calendar_lag(focal_vals,
                                              value = "cusval", t = "t")]
    }
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
    if (bw_lag_calendar || bw_lag_raw) {   # patch 0091: raw keeps the prepared lag
      focal_vals[, pd_e := .N]
    } else {
      focal_vals[, `:=`(cusval_lag = shift(cusval, 1L), pd_e = .N)]
    }
    # (patch 0085) --stage2-export-period-count panel: the Broda-Weinstein T
    # of the export row is the pair's panel length (period_count, counted
    # before the differencing filters), the same definition the import side
    # uses; "rows" (default, through v0.8.3) is the post-filter row count.
    if (export_pc == "panel" && "period_count" %in% names(focal_vals)) focal_vals[, pd_e := period_count[1]]
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
    gv_src <- "default"
    if (!is.null(gam_V_exp_lkp)) {                                        # patch 0085
      row_e <- gam_V_exp_lkp[.(as.character(ref_dest), as.character(exp_j)), nomatch = 0L]
      if (nrow(row_e) > 0L && !is.na(row_e$gamma[1]) && row_e$gamma[1] > 0) {
        gam_V_val <- row_e$gamma[1]; gv_src <- "exporter"
      }
    }
    if (gv_src == "default" && !is.null(gam_V_lkp)) {
      row_g <- gam_V_lkp[importer == ref_dest & good == g_code]
      if (nrow(row_g) > 0L && !is.na(row_g$gamma[1]) && row_g$gamma[1] > 0) {
        gam_V_val <- row_g$gamma[1]; gv_src <- "regional"
      }
    }
    gv_counts[gv_src] <- gv_counts[gv_src] + 1L

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
      M      = M,
      gv_counts = gv_counts                                             # patch 0085
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
#' Called ONCE per product (not per importer) in estimate_product_fixed_sigma.
#'
#' @param dt_g Product-level data.table.
#' @return Named list; names are exporter codes, values are their subsets.
compute_exporter_lookup <- function(dt_g) {
  split(dt_g, by = "exporter", keep.by = TRUE)
}
