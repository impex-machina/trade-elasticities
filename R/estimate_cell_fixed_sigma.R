#' R/estimate_cell_fixed_sigma.R
#'
#' Fixed-sigma cell estimation: regional/country gamma at a sigma held
#' fixed from Stage 1, with the penalized Gauss-Newton SE.
#' Extracted from feen94_het_baci.R (lines 2621-3133) at refactor step 3;
#' content identical to the original, only sectioned into its own file.
#'
#' Exported functions:
#'   compute_exporter_dest_counts(dt_g)                                  — destination counts per exporter
#'   classify_exporter_tiers(dt_nonref, exporter_dests, cfg)             — tier classification
#'   compute_penalized_gn_se(d_hat, sigma_val, ...)                      — penalized Gauss-Newton SE
#'   estimate_importer_product_fixed_sigma(imp_dt, focal_importer, ...)  — per importer-product fixed-sigma fit
#'   estimate_product_fixed_sigma(g, dt_g, cfg)                          — per-product fixed-sigma fit
#'
#' Depends on: liml_estimator.R, estimate_cell_homogeneous.R

# ===========================================================================
#  EXPORTER TIER CLASSIFICATION
#
#  Tier 1: Dense — full import + export side estimation.
#  Tier 2: Moderate — import-side only, with shrinkage.
#  Tier 3: Sparse — gamma assigned from regional prior.
# ===========================================================================

#' Compute destination counts per exporter for an entire product.
#'
#' Called ONCE per product in estimate_product_fixed_sigma, then
#' passed to each cell. Eliminates redundant scans of all_dt.
#'
#' @param dt_g Full product data.table (all importers).
#' @return data.table with (exporter, n_dests_total).
compute_exporter_dest_counts <- function(dt_g) {
  dt_g[, .(n_dests_total = uniqueN(importer)), by = exporter]
}


#' Classify exporters into estimation tiers.
#'
#' @param dt_nonref Non-reference exporter data for the focal importer.
#' @param exporter_dests Pre-computed data.table with (exporter, n_dests_total).
#' @param cfg Config list.
#' @return data.table with (exporter, tier).
classify_exporter_tiers <- function(dt_nonref, exporter_dests, cfg) {

  tier1_min_periods <- if (!is.null(cfg$tier1_min_periods)) cfg$tier1_min_periods else 8L
  tier1_min_dests   <- if (!is.null(cfg$tier1_min_dests))   cfg$tier1_min_dests   else 3L
  tier2_min_periods <- if (!is.null(cfg$tier2_min_periods)) cfg$tier2_min_periods else 5L

  # Periods in focal market per exporter (cheap — just this importer's data)
  imp_stats <- dt_nonref[, .(n_periods = uniqueN(t)),
                          by = exporter]

  # Merge with pre-computed destination counts
  # Subtract 1 for the focal importer (they ship there, so n_dests excludes it)
  stats <- merge(imp_stats, exporter_dests, by = "exporter", all.x = TRUE)
  stats[is.na(n_dests_total), n_dests_total := 0L]
  stats[, n_dests := pmax(n_dests_total - 1L, 0L)]

  stats[, tier := 3L]
  stats[n_periods >= tier2_min_periods, tier := 2L]
  stats[n_periods >= tier1_min_periods & n_dests >= tier1_min_dests, tier := 1L]

  stats[, .(exporter, tier)]
}


# =========================================================================
# Penalized Gauss-Newton SE computation for a fitted cell.
#
# Returns a list of K-vectors:
#   $se     -- SE per parameter, NA if not computable
#   $status -- per-parameter status: "ok", "boundary", "plateau",
#              "singular", "negative_diag"
#   $exposure -- per-parameter count of residual rows contributing to
#                identification (import side + export side)
#
# Formula:  V = (SSR/df) * (J'WJ + lambda * 2*diag(1/theta^2))^{-1}
#
# This is the *correct* SE formula for this estimator. We verified via
# Monte Carlo (see source/monte_carlo_se*.R) that:
#   - The classical sandwich understates by ~30% (residual-Jacobian
#     correlation at the NLS optimum breaks the sandwich approximation)
#   - optim()$hessian is the FULL Hessian including residual*second-deriv
#     terms; using it directly gives 50%-too-large SE on this nonlinear
#     model. We use the Gauss-Newton J'WJ from our analytic Jacobian.
#   - Under shrinkage, the prior's Hessian must be added or the unpenalized
#     GN formula overstates SE by ~30%.
#
# The combined penalized GN formula calibrates within ~7% of empirical
# variability across all tested regimes (worst-regime median calibration
# error +6.7%; see results/pillar3_summary.json).
# =========================================================================
compute_penalized_gn_se <- function(d_hat, sigma_val,
                                    imp_Y_vec, imp_X_mat,
                                    exp_Y, exp_X, exp_jmap,
                                    exp_sig_V, exp_gam_V,
                                    wt_imp_vec, wt_exp,
                                    shrinkage_lambda,
                                    boundary_thresh = 0.01,
                                    plateau_thresh = 5.0,
                                    paper_exact_eq11 = FALSE) {
  
  K <- length(d_hat)
  na_result <- list(
    se        = rep(NA_real_, K),
    status    = rep("not_computed", K),
    exposure  = rep(NA_integer_, K),
    shrink_wt = rep(NA_real_, K)
  )
  
  # If Rcpp Jacobian not loaded, can't compute SE
  if (!exists(".het_jac_rcpp_loaded") || !.het_jac_rcpp_loaded) {
    return(na_result)
  }
  
  # Per-parameter boundary/plateau detection (applied per gamma)
  status <- rep("ok", K)
  status[d_hat < boundary_thresh] <- "boundary"
  status[d_hat > plateau_thresh]  <- "plateau"
  
  # Compute residuals and Jacobian
  jac <- tryCatch(
    het_residuals_and_jacobian_fixed_sigma_rcpp(
      d = d_hat, sigma = sigma_val,
      imp_Y = imp_Y_vec, imp_X = imp_X_mat,
      exp_Y = exp_Y, exp_X = exp_X,
      exp_jmap = exp_jmap,
      exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
      wt_imp = wt_imp_vec, wt_exp = wt_exp,
      paper_exact_eq11 = paper_exact_eq11
    ),
    error = function(e) NULL
  )
  if (is.null(jac) || !identical(jac$status, "ok")) return(na_result)
  
  # Per-parameter exposure: count of residual rows that involve each theta.
  # Import side: every import row j (J of them) contributes to gamma_k AND gamma_j+1.
  # Export side: each export row m contributes to one parameter (col_I = exp_jmap[m] - 2)
  J <- length(imp_Y_vec)
  exposure <- integer(K)
  exposure[1L] <- J  # gamma_k gets J import-side rows
  for (j in seq_len(J)) {
    exposure[j + 1L] <- exposure[j + 1L] + 1L  # gamma_j gets 1 import-side row
  }
  # Export-side: tabulate exp_jmap - 1 (1-based theta index)
  exp_col_1based <- exp_jmap - 1L
  exp_col_valid <- exp_col_1based[exp_col_1based >= 1L & exp_col_1based <= K]
  if (length(exp_col_valid) > 0L) {
    tab <- tabulate(exp_col_valid, nbins = K)
    exposure <- exposure + tab
  }
  
  # Build J'WJ from sparse triplets
  JtWJ <- matrix(0, K, K)
  rs <- jac$jac_row + 1L
  cs <- jac$jac_col + 1L
  vs <- jac$jac_val
  ws <- jac$weights
  ord <- order(rs)
  rs <- rs[ord]; cs <- cs[ord]; vs <- vs[ord]
  i <- 1L
  while (i <= length(rs)) {
    cr <- rs[i]; j2 <- i
    while (j2 <= length(rs) && rs[j2] == cr) j2 <- j2 + 1L
    rc <- cs[i:(j2 - 1L)]; rv <- vs[i:(j2 - 1L)]
    for (a in seq_along(rc)) for (b in seq_along(rc)) {
      JtWJ[rc[a], rc[b]] <- JtWJ[rc[a], rc[b]] + ws[cr] * rv[a] * rv[b]
    }
    i <- j2
  }
  
  # sigma_hat^2 = weighted SSR / df (using df without prior penalty correction)
  SSR <- sum(jac$weights * jac$residuals^2)
  n_obs <- length(jac$residuals)
  df_resid <- n_obs - K
  if (df_resid < 1L) {
    return(list(se = rep(NA_real_, K),
                status = rep("insufficient_df", K),
                exposure = exposure,
                shrink_wt = rep(NA_real_, K)))
  }
  sigma2 <- SSR / df_resid
  
  # Prior Hessian: 2 * lambda * diag(1/theta^2) where theta is above boundary
  H_prior <- matrix(0, K, K)
  if (shrinkage_lambda > 0) {
    for (k in seq_len(K)) {
      if (d_hat[k] > 1e-8) {
        H_prior[k, k] <- 2 * shrinkage_lambda / d_hat[k]^2
      }
    }
  }
  
  # Effective-shrinkage diagnostic (v0.4.0): per-parameter share of the
  # curvature at the optimum contributed by the prior. 0 = pure data,
  # 1 = pure prior; NA where neither side contributes. Published as
  # gamma_shrink_wt so users can see, cell by cell, how much of gamma
  # is data vs prior -- the binding question for Tier-2 cells.
  d_JtWJ <- diag(JtWJ)
  d_Hp   <- diag(H_prior)
  curv_tot <- d_JtWJ + d_Hp
  shrink_wt <- ifelse(curv_tot > 0, d_Hp / curv_tot, NA_real_)

  V <- tryCatch(sigma2 * solve(JtWJ + H_prior), error = function(e) NULL)
  if (is.null(V)) {
    return(list(se = rep(NA_real_, K),
                status = rep("singular", K),
                exposure = exposure,
                shrink_wt = shrink_wt))
  }
  
  d_V <- diag(V)
  se <- rep(NA_real_, K)
  for (k in seq_len(K)) {
    if (status[k] != "ok") next  # boundary/plateau: leave SE = NA
    if (is.na(d_V[k]) || d_V[k] <= 0) {
      status[k] <- "negative_diag"
      next
    }
    se[k] <- sqrt(d_V[k])
  }
  
  list(se = se, status = status, exposure = exposure, shrink_wt = shrink_wt)
}


# ===========================================================================
#  FIXED-SIGMA GAMMA ESTIMATION WITH TIERED EXPORT MOMENTS
# ===========================================================================

#' Sensitivity of the fixed-sigma gamma estimate to sigma (implicit-function thm).
#' dgamma/dsigma = -(J'WJ + H)^{-1} J'W (dr/dsigma); dr/dsigma by central FD of the
#' Rcpp residual routine holding gamma fixed. Returns length-K vector (d_hat order),
#' or all-NA on failure. See R/estimate_cell_fixed_sigma.R SE methodology notes.
compute_dgamma_dsigma <- function(d_hat, sigma_val,
                                  imp_Y_vec, imp_X_mat, exp_Y, exp_X, exp_jmap,
                                  exp_sig_V, exp_gam_V, wt_imp_vec, wt_exp,
                                  shrinkage_lambda, delta = 1e-4,
                                  paper_exact_eq11 = FALSE) {
  K  <- length(d_hat); na <- rep(NA_real_, K)
  if (!is.finite(sigma_val) || sigma_val <= 1) return(na)
  delta <- min(delta, (sigma_val - 1) / 10)
  JJ <- function(sg) tryCatch(
    het_residuals_and_jacobian_fixed_sigma_rcpp(
      d = d_hat, sigma = sg, imp_Y = imp_Y_vec, imp_X = imp_X_mat,
      exp_Y = exp_Y, exp_X = exp_X, exp_jmap = exp_jmap,
      exp_sig_V = exp_sig_V, exp_gam_V = exp_gam_V,
      wt_imp = wt_imp_vec, wt_exp = wt_exp,
      paper_exact_eq11 = paper_exact_eq11),
    error = function(e) NULL)
  j0 <- JJ(sigma_val)
  if (is.null(j0) || !identical(j0$status, "ok")) return(na)
  r <- j0$jac_row + 1L; c <- j0$jac_col + 1L; v <- j0$jac_val; w <- j0$weights
  A <- matrix(0, K, K)
  for (idx in split(seq_along(r), r)) {
    cc <- c[idx]; vv <- v[idx]; ww <- w[r[idx][1L]]
    for (a in seq_along(cc)) for (b in seq_along(cc))
      A[cc[a], cc[b]] <- A[cc[a], cc[b]] + ww * vv[a] * vv[b]
  }
  if (shrinkage_lambda > 0)
    for (k in seq_len(K)) if (d_hat[k] > 1e-8)
      A[k, k] <- A[k, k] + 2 * shrinkage_lambda / d_hat[k]^2
  jp <- JJ(sigma_val + delta); jm <- JJ(sigma_val - delta)
  if (is.null(jp) || is.null(jm) ||
      !identical(jp$status, "ok") || !identical(jm$status, "ok")) return(na)
  drds <- (jp$residuals - jm$residuals) / (2 * delta)
  g <- numeric(K)
  for (t in seq_along(r)) g[c[t]] <- g[c[t]] + w[r[t]] * v[t] * drds[r[t]]
  as.numeric(tryCatch(-solve(A, g), error = function(e) na))
}

#' Cell-level robustness screen for gamma under sigma uncertainty.
#' FALSE if sigma itself is clamped (adjust == 4), sigma_se non-finite, the
#' sigma band reaches the sigma=1 pole, or propagation more than
#' INFL_THRESH-folds any SE.
#' B9 NOTE (v0.3.0): previously failed adjust == 5 too. Under the new
#' adjust semantics code 5 means omega alone was capped while sigma is an
#' interior Step-2 estimate carrying a valid SE, so those cells are now
#' screened on the merits (pole distance + inflation) instead of
#' auto-failed.
assess_sigma_robust <- function(sigma_hat, sigma_se, adjust, se_cond, se_prop,
                                K_POLE = 2.5, INFL_THRESH = 2.0, eps = 1e-6) {
  if (isTRUE(adjust == 4L))                     return(FALSE)
  if (!is.finite(sigma_se))                     return(FALSE)
  if (sigma_hat - K_POLE * sigma_se <= 1 + eps) return(FALSE)
  ok <- is.finite(se_cond) & se_cond > 0 & is.finite(se_prop)
  if (any(ok)) {
    infl <- sqrt(se_cond[ok]^2 + se_prop[ok]^2) / se_cond[ok]
    if (any(infl > INFL_THRESH)) return(FALSE)
  }
  TRUE
}

estimate_importer_product_fixed_sigma <- function(imp_dt, focal_importer,
                                                   all_dt, cfg,
                                                   exporter_dests = NULL,
                                                   exp_lookup = NULL) {

  dt <- imp_dt[importer == focal_importer]
  n_exp <- uniqueN(dt$exporter)
  max_pd <- dt[, max(period_count)]

  if (n_exp < cfg$min_exporters || max_pd < cfg$min_periods)
    return(cell_failure("insufficient_data"))

  # --- Look up pre-estimated sigma ---
  g_code <- imp_dt$good[1]
  sigma_val <- NA_real_
  if (!is.null(cfg$sigma_lookup)) {
    match_row <- cfg$sigma_lookup[importer == focal_importer & good == g_code]
    if (nrow(match_row) > 0L) sigma_val <- match_row$sigma[1]
  }
  if (is.na(sigma_val) || sigma_val <= 1) {
    sigma_val <- if (!is.null(cfg$sigma_fallback)) cfg$sigma_fallback else
      return(cell_failure("no_sigma_estimate"))
  }

  # --- Look up shrinkage prior ---
  ln_gamma_prior <- NA_real_
  shrinkage_lambda <- if (!is.null(cfg$shrinkage_lambda)) cfg$shrinkage_lambda else 0
  if (shrinkage_lambda > 0 && !is.null(cfg$shrinkage_priors)) {
    prior_row <- cfg$shrinkage_priors[good == g_code]
    if (nrow(prior_row) > 0L) ln_gamma_prior <- prior_row$ln_gamma_prior[1]
  }

  # G1 (v0.4.1): corrected Eq. (11) x5/x6 signs are the default. Set
  # cfg$paper_exact_eq11 <- TRUE to reproduce the printed-equation
  # (v0.4.0) behaviour for comparison runs.
  pe11 <- isTRUE(cfg$paper_exact_eq11)

  # --- Reference-differencing and import-side moments ---
  ref_exporter <- choose_reference(dt)
  ref_vals <- dt[exporter == ref_exporter,
                 .(t, ref_ls_dif = ls_imp_dif, ref_lp_dif = lp_dif)]
  dt <- ref_vals[dt, on = "t"]
  dt <- dt[!is.na(ref_ls_dif) & !is.na(ref_lp_dif)]
  dt[, `:=`(Dk_lp = lp_dif - ref_lp_dif, Dk_ls = ls_imp_dif - ref_ls_dif)]
  dt[, `:=`(imp_y = Dk_lp^2, imp_x1 = Dk_ls^2, imp_x2 = Dk_ls * Dk_lp,
            imp_x3 = Dk_ls * lp_dif, imp_x4 = Dk_ls * ref_lp_dif,
            imp_x5 = Dk_lp * ref_lp_dif)]
  dt <- dt[!is.na(imp_y) & !is.na(imp_x1) & !is.na(imp_x2)]
  dt_nonref <- dt[exporter != ref_exporter]
  if (nrow(dt_nonref) == 0L) return(cell_failure("no_nonref_exporters"))

  # --- Tier classification (using pre-computed destination counts) ---
  if (is.null(exporter_dests)) {
    exporter_dests <- compute_exporter_dest_counts(all_dt)
  }
  tiers <- classify_exporter_tiers(dt_nonref, exporter_dests, cfg)

  tier1_exp <- tiers[tier == 1L, exporter]
  tier2_exp <- tiers[tier == 2L, exporter]
  tier3_exp <- tiers[tier == 3L, exporter]

  # Exporters to estimate: Tier 1 first, then Tier 2
  # (ordering matters for exp_jmap alignment)
  est_exporters <- c(tier1_exp, tier2_exp)
  if (length(est_exporters) == 0L) {
    # All exporters are Tier 3 — assign from prior only
    if (is.na(ln_gamma_prior)) return(cell_failure("all_tier3_no_prior"))
    gamma_prior <- exp(ln_gamma_prior)
    all_exp <- c(tiers$exporter, ref_exporter)
    return(data.table(
      importer = focal_importer, exporter = all_exp,
      sigma = sigma_val, gamma = gamma_prior,
      ref_exporter = ref_exporter, convergence = -1L,
      obj_value = NA_real_, tier = c(tiers$tier, 0L)
    ))
  }

  # --- BW weights ---
  setorder(dt_nonref, exporter, t)
  dt_nonref[, cusval_lag := shift(cusval, 1L), by = exporter]
  dt_nonref[, bw_w := bw_weight(cusval, cusval_lag, period_count)]

  # --- Import-side moments for estimated exporters only ---
  imp_moments <- dt_nonref[exporter %in% est_exporters,
    lapply(.SD, weighted.mean, w = bw_w, na.rm = TRUE),
    by = exporter,
    .SDcols = c("imp_y","imp_x1","imp_x2","imp_x3","imp_x4","imp_x5")]

  # Force ordering: Tier 1 first, then Tier 2
  imp_moments[, tier_order := match(exporter, est_exporters)]
  setorder(imp_moments, tier_order)
  imp_moments[, tier_order := NULL]

  J <- nrow(imp_moments)
  if (J < 1L) return(cell_failure("no_valid_moments"))

  exporter_order <- imp_moments$exporter
  N_tier1 <- sum(exporter_order %in% tier1_exp)

  imp_Y_vec  <- imp_moments$imp_y
  imp_X_mat  <- as.matrix(imp_moments[, .(imp_x1,imp_x2,imp_x3,imp_x4,imp_x5)])
  wt_imp_vec <- compute_exporter_weights(dt_nonref, exporter_order, cfg)

  # --- Export-side moments for Tier 1 only ---
  if (N_tier1 > 0L) {
    exp_mom <- build_export_moments(exporter_order[1:N_tier1],
                                     focal_importer, all_dt, cfg,
                                     exp_lookup = exp_lookup)
    # Align export-side weights with import-side weighting scheme.
    # exp_jmap[m] = j_idx + 2 where j_idx is the position within
    # exporter_order[1:N_tier1], so exp_jmap[m] - 2 is a valid index
    # into wt_imp_vec (Tier 1 exporters occupy positions 1:N_tier1).
    if (exp_mom$M > 0L) {
      exp_mom$wt_exp <- wt_imp_vec[exp_mom$jmap - 2L]
    }
  } else {
    exp_mom <- list(exp_Y = numeric(0), exp_X = matrix(nrow=0, ncol=9),
                    jmap = integer(0), sig_V = numeric(0),
                    gam_V = numeric(0), wt_exp = numeric(0), M = 0L)
  }

  # --- Optimization: gamma only ---
  gam_init <- cfg$gamma_start
  if (!is.null(cfg$regional_starts)) {
    imp_region <- focal_importer
    if (!is.null(cfg$regional_starts_rmap))
      imp_region <- assign_regions(focal_importer, cfg$regional_starts_rmap)
    match_row <- cfg$regional_starts[region == imp_region & good == g_code]
    if (nrow(match_row) > 0L) gam_init <- match_row$gamma[1]
  }

  d_start <- rep(gam_init, J + 1)  # gamma_k + J gamma_j
  lower_bounds <- rep(1e-6, J + 1)

  result <- tryCatch(
    optim(par = d_start, fn = het_obj_fixed_sigma, method = "L-BFGS-B",
          lower = lower_bounds, upper = rep(Inf, J + 1),
          sigma = sigma_val,
          imp_Y = imp_Y_vec, imp_X = imp_X_mat,
          exp_Y = exp_mom$exp_Y, exp_X = exp_mom$exp_X,
          exp_jmap = exp_mom$jmap,
          exp_sig_V = exp_mom$sig_V, exp_gam_V = exp_mom$gam_V,
          wt_imp = wt_imp_vec, wt_exp = exp_mom$wt_exp,
          ln_gamma_prior = ln_gamma_prior,
          shrinkage_lambda = shrinkage_lambda,
          paper_exact_eq11 = pe11,
          control = list(maxit = 500)),
    error = function(e) NULL)

  if (is.null(result) || result$convergence != 0) {
    result <- tryCatch(
      optim(par = d_start, fn = het_obj_fixed_sigma, method = "Nelder-Mead",
            sigma = sigma_val,
            imp_Y = imp_Y_vec, imp_X = imp_X_mat,
            exp_Y = exp_mom$exp_Y, exp_X = exp_mom$exp_X,
            exp_jmap = exp_mom$jmap,
            exp_sig_V = exp_mom$sig_V, exp_gam_V = exp_mom$gam_V,
            wt_imp = wt_imp_vec, wt_exp = exp_mom$wt_exp,
            ln_gamma_prior = ln_gamma_prior,
            shrinkage_lambda = shrinkage_lambda,
            paper_exact_eq11 = pe11,
            control = list(maxit = 1000)),
      error = function(e) NULL)
  }

  if (is.null(result)) return(cell_failure("optimizer_failed"))

  d_hat <- result$par
  gamma_k_hat <- max(d_hat[1], 0)
  gamma_j_hat <- pmax(d_hat[2:(J + 1)], 0)
  
  # --- Compute SE if convergence==0 ---
  if (result$convergence == 0L) {
    se_out <- compute_penalized_gn_se(
      d_hat = d_hat, sigma_val = sigma_val,
      imp_Y_vec = imp_Y_vec, imp_X_mat = imp_X_mat,
      exp_Y = exp_mom$exp_Y, exp_X = exp_mom$exp_X,
      exp_jmap = exp_mom$jmap,
      exp_sig_V = exp_mom$sig_V, exp_gam_V = exp_mom$gam_V,
      wt_imp_vec = wt_imp_vec, wt_exp = exp_mom$wt_exp,
      shrinkage_lambda = shrinkage_lambda,
      paper_exact_eq11 = pe11
    )
    gamma_k_se     <- se_out$se[1]
    gamma_j_se     <- se_out$se[2:(J + 1)]
    gamma_k_status <- se_out$status[1]
    gamma_j_status <- se_out$status[2:(J + 1)]
    gamma_k_expo   <- se_out$exposure[1]
    gamma_j_expo   <- se_out$exposure[2:(J + 1)]
    gamma_k_shrink <- se_out$shrink_wt[1]
    gamma_j_shrink <- se_out$shrink_wt[2:(J + 1)]
  } else {
    gamma_k_se     <- NA_real_
    gamma_j_se     <- rep(NA_real_, J)
    gamma_k_status <- "non_converged"
    gamma_j_status <- rep("non_converged", J)
    gamma_k_expo   <- NA_integer_
    gamma_j_expo   <- rep(NA_integer_, J)
    gamma_k_shrink <- NA_real_
    gamma_j_shrink <- rep(NA_real_, J)
  }
  
  # --- sigma-propagated SE + robustness flag ---
  # Stage-1 sigma SE + admissibility-adjust code, wired via cfg (run_estimation.R).
  sse_row <- if (!is.null(cfg$sigma_se_lookup))
    cfg$sigma_se_lookup[importer == focal_importer & good == g_code] else NULL
  sigma_se_cell <- if (!is.null(sse_row) && nrow(sse_row)) sse_row$sigma_se[1] else NA_real_
  adj_row <- if (!is.null(cfg$sigma_adjust_lookup))
    cfg$sigma_adjust_lookup[importer == focal_importer & good == g_code] else NULL
  adjust_cell <- if (!is.null(adj_row) && nrow(adj_row)) as.integer(adj_row$adjust[1]) else NA_integer_

  se_cond_vec <- c(gamma_k_se, gamma_j_se)            # d_hat order: [k, j_1..j_J]
  if (result$convergence == 0L && is.finite(sigma_se_cell)) {
    dgds <- compute_dgamma_dsigma(
      d_hat = d_hat, sigma_val = sigma_val,
      imp_Y_vec = imp_Y_vec, imp_X_mat = imp_X_mat,
      exp_Y = exp_mom$exp_Y, exp_X = exp_mom$exp_X, exp_jmap = exp_mom$jmap,
      exp_sig_V = exp_mom$sig_V, exp_gam_V = exp_mom$gam_V,
      wt_imp_vec = wt_imp_vec, wt_exp = exp_mom$wt_exp,
      shrinkage_lambda = shrinkage_lambda,
      paper_exact_eq11 = pe11)
    se_prop_vec <- abs(dgds) * sigma_se_cell
  } else {
    dgds <- rep(NA_real_, length(d_hat)); se_prop_vec <- rep(NA_real_, length(d_hat))
  }
  sigma_robust_flag <- assess_sigma_robust(
    sigma_hat = sigma_val, sigma_se = sigma_se_cell, adjust = adjust_cell,
    se_cond = se_cond_vec, se_prop = se_prop_vec)
  se_total_vec <- if (sigma_robust_flag)
    sqrt(se_cond_vec^2 + se_prop_vec^2) else rep(NA_real_, length(se_cond_vec))
  gamma_k_se_total <- se_total_vec[1]
  gamma_j_se_total <- se_total_vec[2:(J + 1)]

  # --- Assign tiers to output ---
  est_tier <- ifelse(exporter_order %in% tier1_exp, 1L, 2L)
  
  # Build estimated portion
  est_dt <- data.table(
    importer        = focal_importer,
    exporter        = c(exporter_order, ref_exporter),
    sigma           = sigma_val,
    gamma           = c(gamma_j_hat, gamma_k_hat),
    gamma_se        = c(gamma_j_se, gamma_k_se),
    gamma_se_total  = c(gamma_j_se_total, gamma_k_se_total),
    sigma_robust    = sigma_robust_flag,
    sigma_se        = sigma_se_cell,
    dgamma_dsigma   = c(dgds[2:(J + 1)], dgds[1]),
    gamma_se_status = c(gamma_j_status, gamma_k_status),
    gamma_exposure  = c(gamma_j_expo, gamma_k_expo),
    gamma_shrink_wt = c(gamma_j_shrink, gamma_k_shrink),
    ref_exporter    = ref_exporter,
    convergence     = result$convergence,
    obj_value       = result$value,
    tier            = c(est_tier, 0L)  # 0 = reference exporter
  )

  # Append Tier 3 with assigned gamma
  if (length(tier3_exp) > 0L) {
    gamma_t3 <- if (!is.na(ln_gamma_prior)) exp(ln_gamma_prior) else median(gamma_j_hat)
    t3_dt <- data.table(
      importer        = focal_importer,
      exporter        = tier3_exp,
      sigma           = sigma_val,
      gamma           = gamma_t3,
      gamma_se        = NA_real_,
      gamma_se_total  = NA_real_,
      sigma_robust    = NA,
      sigma_se        = NA_real_,
      dgamma_dsigma   = NA_real_,
      gamma_se_status = "tier3_prior",
      gamma_exposure  = NA_integer_,
      gamma_shrink_wt = NA_real_,
      ref_exporter    = ref_exporter,
      convergence     = -1L,   # flag: not estimated
      obj_value       = NA_real_,
      tier            = 3L
    )
    est_dt <- rbindlist(list(est_dt, t3_dt))
  }

  est_dt
}


#' Estimate gamma for all importers of one product with fixed sigma + tiers.
estimate_product_fixed_sigma <- function(g, dt_g, cfg) {
  t0 <- proc.time()["elapsed"]
  results_g <- list(); failures_g <- list()
  n_cells <- 0L; n_ok <- 0L; n_skipped <- 0L

  imp_stats <- dt_g[, .(n_exp = uniqueN(exporter),
                         max_pd = max(period_count)), by = importer]
  viable <- imp_stats[n_exp >= cfg$min_exporters &
                      max_pd >= cfg$min_periods, importer]
  n_skipped <- uniqueN(dt_g$importer) - length(viable)

  # Pre-compute destination counts ONCE for this product
  exporter_dests <- compute_exporter_dest_counts(dt_g)

  # Pre-split per-exporter data ONCE for this product (HS6 perf).
  # build_export_moments uses this to avoid O(N_exporters) repeated
  # filtering of dt_g on every cell.
  exp_lookup <- compute_exporter_lookup(dt_g)

  for (imp in viable) {
    n_cells <- n_cells + 1L
    est <- tryCatch(
      estimate_importer_product_fixed_sigma(dt_g, imp, dt_g, cfg,
                                             exporter_dests = exporter_dests,
                                             exp_lookup = exp_lookup),
      error = function(e) cell_failure(paste0("error: ", conditionMessage(e))))
    if (inherits(est, "cell_failure")) {
      failures_g[[length(failures_g) + 1L]] <- list(importer=imp, good=g, reason=est$reason)
      next
    }
    if (!is.null(est)) {
      est[, good := g]
      trade_wt <- dt_g[importer == imp,
                       .(avg_trade = mean(cusval, na.rm = TRUE)), by = exporter]
      est <- trade_wt[est, on = "exporter"]

      # -------------------------------------------------------------------
      #  OPTIMAL TARIFF COMPUTATION
      #
      #  Tier 3 exporters all share the same assigned gamma (the
      #  product-level regional prior). Including them in opt_tariff
      #  biases it toward the prior and masks the heterogeneous
      #  tariff that the identifying data supports.
      #
      #  Primary output (opt_tariff): computed from Tier 0/1/2 only —
      #  i.e., exporters whose gamma was directly estimated.
      #
      #  Secondary output (opt_tariff_all): computed using all exporters
      #  including Tier 3 imputations. Retained for downstream users who
      #  prefer full-coverage at the cost of bias toward the prior.
      # -------------------------------------------------------------------
      est_tiers <- if ("tier" %in% names(est)) est$tier else rep(0L, nrow(est))
      is_estimated <- !is.na(est_tiers) & est_tiers < 3L

      if (any(is_estimated)) {
        ot <- optimal_tariff(est$gamma[is_estimated],
                              est$sigma[is_estimated][1],
                              est$avg_trade[is_estimated])
      } else {
        ot <- NA_real_
      }
      ot_all <- optimal_tariff(est$gamma, est$sigma[1], est$avg_trade)

      est[, `:=`(opt_tariff = ot, opt_tariff_all = ot_all)]
      results_g[[length(results_g) + 1L]] <- est
      n_ok <- n_ok + 1L
    }
  }
  elapsed <- as.numeric(proc.time()["elapsed"] - t0)
  if (length(results_g) > 0L) {
    out <- rbindlist(results_g, fill = TRUE)
    attr(out, "timing") <- list(product=g, seconds=elapsed,
                                cells=n_cells, succeeded=n_ok, skipped=n_skipped)
    attr(out, "failures") <- failures_g
    out
  } else NULL
}


#' Run fixed-sigma gamma estimation across all products.
#' @param cfg Config list with sigma_lookup, shrinkage_lambda, shrinkage_priors.
#' @param ncores Number of cores.
#' @param prepared_dt Optional pre-prepared data from prepare_data().
