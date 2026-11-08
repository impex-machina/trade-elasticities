#' sigma_update.R -- the Stage-2b sigma update (patch 0152)
#'
#' Stage 1 estimates sigma under homogeneous supply (gamma_j = gamma_k); Stage
#' 2b relaxes exactly that restriction conditional on the restricted sigma. At
#' known truth the Stage-1 sigma is biased upward in proportion to the
#' within-cell gamma heterogeneity, and re-solving sigma per cell from the
#' Eq. (10) block of the Stage-2 objective at the Stage-2b gamma-hats removes
#' most of that bias and a third of the dispersion -- with the export block
#' (Eq. (11)) left out, because that block does not identify sigma even at the
#' truth (docs/results/known_truth_eq11.md, sections 2 and 7, arm S).
#'
#' sigma_profile_import() profiles the import-block objective over sigma for
#' one cell at fixed gammas: a 240-point log grid from `floor` to `ceiling`,
#' then optimize() in the bracket around the grid minimum (lambda 0 -- the
#' ridge is on gamma and does not move the argmin over sigma). A minimum at
#' the floor or at the ceiling is a failed update (`status`).
#'
#' sigma_update_import() drives it over every viable cell of a prepared panel
#' the way estimate_product_fixed_sigma() drives the cell estimator, through
#' estimate_importer_product_fixed_sigma(return_moments = TRUE), so the
#' moments, weights, reference exporter and settings are the estimator's own.
#'
#' Depends on: estimate_cell_fixed_sigma.R (the entry point), load_rcpp.R
#'   (het_obj_fixed_sigma), estimate_cell_homogeneous.R (the lookups).

#' @param m the list estimate_importer_product_fixed_sigma(..., return_moments = TRUE) returns.
#' @param gamma_vec gammas in d order: gamma_k (the reference exporter), then gamma_j in m$exporter_order.
#' @param floor,ceiling the profile's range (the pipeline uses 1.02 and --stage1-sigma-cap).
#' @param n_grid grid points (log-spaced).
#' @return list(sigma, status in {ok, floor, ceiling, flat}, objective, objective_at_input).
sigma_profile_import <- function(m, gamma_vec, floor = 1.02, ceiling = 50, n_grid = 240L) {
  if (any(!is.finite(gamma_vec)) || any(gamma_vec <= 0)) return(list(sigma = NA_real_, status = "no_gamma", objective = NA_real_, objective_at_input = NA_real_))
  obj <- function(s) het_obj_fixed_sigma(d = gamma_vec, sigma = s, imp_Y = m$imp_Y, imp_X = m$imp_X,
                                         exp_Y = numeric(0), exp_X = matrix(numeric(0), nrow = 0, ncol = 9), exp_jmap = integer(0),
                                         exp_sig_V = numeric(0), exp_gam_V = numeric(0),
                                         wt_imp = m$wt_imp, wt_exp = numeric(0),
                                         ln_gamma_prior = m$ln_gamma_prior, shrinkage_lambda = 0,
                                         paper_exact_eq11 = m$paper_exact_eq11, ridge_all_coords = m$ridge_all_coords,
                                         prior_form = m$prior_form, import_constant = FALSE, prior_eps = m$prior_eps)
  grid <- exp(seq(log(floor), log(ceiling), length.out = n_grid))
  q <- vapply(grid, obj, numeric(1))
  if (!any(is.finite(q))) return(list(sigma = NA_real_, status = "flat", objective = NA_real_, objective_at_input = NA_real_))
  i <- which.min(q)
  pol <- tryCatch(optimize(obj, c(grid[max(1L, i - 1L)], grid[min(n_grid, i + 1L)]), tol = 1e-8),
                  error = function(e) list(minimum = grid[i], objective = q[i]))
  if (!is.finite(pol$objective) || pol$objective > q[i]) pol <- list(minimum = grid[i], objective = q[i])
  status <- if (i == 1L) "floor" else if (i == n_grid) "ceiling" else "ok"
  out <- list(sigma = pol$minimum, status = status, objective = pol$objective, objective_at_input = obj(m$sigma), se_ln = NA_real_, n_score = NA_integer_)
  # (patch 0160) a sandwich standard error for the profile minimiser. With the import constant off the import block is
  # a sum over the cell's J rows, Q(s) = sum_j q_j(s), so the minimiser solves sum_j q_j'(s) = 0 and
  # Var(s_hat) = sum_j q_j'(s_hat)^2 / Q''(s_hat)^2 (one-parameter M-estimator; scores by finite difference on single-row
  # objective calls, curvature by a central second difference). Reported on the ln(sigma - 1) scale, conditional on the
  # gammas the profile was run at (as gamma_se is conditional on sigma). NA at the floor / cap, with fewer than 3 rows, or
  # when the curvature is not positive.
  if (status == "ok" && m$J >= 3L) {
    s_hat <- pol$minimum; h <- 1e-3 * max(s_hat - 1, 1e-2)
    row_obj <- function(j, s) het_obj_fixed_sigma(d = gamma_vec, sigma = s, imp_Y = m$imp_Y[j], imp_X = m$imp_X[j, , drop = FALSE],
                                                  exp_Y = numeric(0), exp_X = matrix(numeric(0), nrow = 0, ncol = 9), exp_jmap = integer(0),
                                                  exp_sig_V = numeric(0), exp_gam_V = numeric(0), wt_imp = m$wt_imp[j], wt_exp = numeric(0),
                                                  ln_gamma_prior = m$ln_gamma_prior, shrinkage_lambda = 0, paper_exact_eq11 = m$paper_exact_eq11,
                                                  ridge_all_coords = m$ridge_all_coords, prior_form = m$prior_form, import_constant = FALSE, prior_eps = m$prior_eps)
    g <- vapply(seq_len(m$J), function(j) (row_obj(j, s_hat + h) - row_obj(j, s_hat - h)) / (2 * h), numeric(1))
    q0 <- obj(s_hat); curv <- (obj(s_hat + h) - 2 * q0 + obj(s_hat - h)) / h^2
    if (all(is.finite(g)) && is.finite(curv) && curv > 0) { se_sigma <- sqrt(sum(g^2)) / curv; out$se_ln <- se_sigma / (s_hat - 1); out$n_score <- m$J }
  }
  out
}

#' One good of the profile (the unit of parallel work). Never returns NULL:
#' an empty result is an empty table, so a NULL from a forked worker means
#' the worker died (assert_forked_results, patch 0150).
.sigma_update_one_good <- function(g, dt_g, gt_g, cfg, floor, ceiling) {
  empty <- data.table::data.table(importer = character(), good = character(), sigma_before = numeric(),
                                  sigma_before_is_fallback = logical(), sigma = numeric(), status = character(),
                                  objective = numeric(), objective_at_input = numeric(), J = integer(), n_tier1 = integer(),
                                  se_ln = numeric())
  if (!nrow(dt_g)) return(empty)
  exporter_dests <- compute_exporter_dest_counts(dt_g)
  exp_lookup <- compute_exporter_lookup(dt_g)
  cfg_g <- cfg
  if (!is.null(cfg_g$gamma_V_exporter_lookup)) {
    gvt <- cfg_g$gamma_V_exporter_lookup[good == as.character(g)]
    data.table::setkeyv(gvt, c("importer", "exporter")); cfg_g$gamma_V_exporter_lookup <- gvt
  }
  imp_stats <- dt_g[, .(n_exp = uniqueN(exporter), max_pd = max(period_count)), by = importer]
  viable <- imp_stats[n_exp >= cfg_g$min_exporters & max_pd >= cfg_g$min_periods, importer]
  out <- list()
  for (imp in viable) {
    m <- tryCatch(estimate_importer_product_fixed_sigma(dt_g, imp, dt_g, cfg_g, exporter_dests = exporter_dests,
                                                        exp_lookup = exp_lookup, return_moments = TRUE),
                  error = function(e) NULL)
    if (!is.list(m) || is.null(m$imp_Y)) next            # cell_failure, or every exporter Tier 3
    keys <- c(m$ref_exporter, m$exporter_order)
    mi <- match(paste(m$importer, as.character(keys)), paste(gt_g$importer, gt_g$exporter))
    pr <- sigma_profile_import(m, gt_g$gamma[mi], floor = floor, ceiling = ceiling)
    out[[length(out) + 1L]] <- data.table::data.table(importer = m$importer, good = m$good,
                                                      sigma_before = m$sigma, sigma_before_is_fallback = isTRUE(m$sigma_is_fallback),
                                                      sigma = pr$sigma, status = pr$status, objective = pr$objective,
                                                      objective_at_input = pr$objective_at_input, J = m$J, n_tier1 = m$n_tier1,
                                                      se_ln = pr$se_ln)   # patch 0160: sandwich SE of ln(sigma - 1), NA where not computable
  }
  if (!length(out)) empty else data.table::rbindlist(out)
}

#' @param cfg the Stage-2b config (lookups, thresholds, flags) as estimate_all_fixed_sigma() takes it.
#' @param prepared_dt the prepared country panel (prepare_data()$dt).
#' @param gamma_table (importer, exporter, good, gamma): the gammas to profile at, e.g. a Stage-2b table.
#' @param ncores goods are profiled in parallel: forked (mclapply, with the lost-worker guard of patch 0150)
#'   on Unix, PSOCK on Windows through stage2_psock_provision(); 1 = serial. (patch 0155)
#' @return one row per profiled cell: importer, good, sigma_before, sigma_before_is_fallback, sigma, status,
#'   objective, objective_at_input, J, n_tier1. Cells without import rows (every exporter Tier 3) do not appear.
sigma_update_import <- function(cfg, prepared_dt, gamma_table, floor = 1.02, ceiling = 50, ncores = 1L) {
  gt <- data.table::as.data.table(gamma_table)[, .(importer = as.character(importer), exporter = as.character(exporter),
                                                   good = as.character(good), gamma)]
  goods <- as.character(unique(prepared_dt$good))
  ncores <- max(1L, min(as.integer(ncores), length(goods)))
  if (ncores == 1L) {
    res <- lapply(goods, function(g) .sigma_update_one_good(g, prepared_dt[good == g], gt[good == g], cfg, floor, ceiling))
  } else if (.Platform$OS.type != "windows") {
    res <- parallel::mclapply(goods, function(g) .sigma_update_one_good(g, prepared_dt[good == g], gt[good == g], cfg, floor, ceiling),
                              mc.cores = ncores)
    assert_forked_results(res, goods, what = "sigma profile (good)")
  } else {
    tmp_dir <- file.path(tempdir(), "het_sigma_update"); dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)
    for (g in goods) saveRDS(list(dt = prepared_dt[good == g], gt = gt[good == g]), file.path(tmp_dir, paste0(g, ".rds")))
    cl <- parallel::makeCluster(ncores)
    on.exit({ tryCatch(parallel::stopCluster(cl), error = function(e) NULL); unlink(tmp_dir, recursive = TRUE) }, add = TRUE)
    su_floor <- floor; su_ceiling <- ceiling
    parallel::clusterExport(cl, varlist = c("cfg", "tmp_dir", "su_floor", "su_ceiling"), envir = environment())
    cpp_dir <- if (exists(".resolve_cpp_dir", mode = "function")) .resolve_cpp_dir() else normalizePath(file.path(getwd(), "src"), mustWork = FALSE)
    stage2_psock_provision(cl, cpp_dir, worker_fns = c(stage2_worker_fns, "sigma_profile_import", ".sigma_update_one_good"), env = environment())
    res <- parallel::parLapply(cl, goods, function(g) {
      sl <- readRDS(file.path(tmp_dir, paste0(g, ".rds")))
      .sigma_update_one_good(g, sl$dt, sl$gt, cfg, su_floor, su_ceiling)
    })
  }
  out <- data.table::rbindlist(res)
  if (!nrow(out)) return(.sigma_update_one_good("none", prepared_dt[0], gt[0], cfg, floor, ceiling))
  out
}
