#' R/estimate_stage1_feenstra.R
#'
#' Alternative Stage 1 estimator: Feenstra (1994) weighted NLS on import-side
#' moments under homogeneity (gamma_j = gamma_k). NOT the default Stage 1 —
#' the default is HLIML (R/liml_estimator.R, R/stage1_liml_wrapper.R)
#' implementing Grant & Soderbery (2024). Preserved as an optional baseline.
#'
#' Exported functions:
#'   feenstra_sigma_obj(d, imp_Y, imp_X, wt_imp)                — Feenstra sigma objective
#'   estimate_feenstra_sigma_cell(imp_dt, focal_importer, cfg)  — per-cell Feenstra sigma
#'   estimate_product_feenstra(g, dt_g, cfg)                    — per-product Feenstra fit
#'   estimate_all_feenstra_sigma(cfg, ncores, prepared_dt)      — all-cells Feenstra Stage 1
#'
#' Depends on: estimate_cell_homogeneous.R; parallel (base)

# ===========================================================================
#  FEENSTRA (1994) SIGMA ESTIMATION
#
#  Import-side-only, 2-parameter (sigma, gamma_common) objective.
#  Under homogeneity gamma_j = gamma_k, Eq (10) simplifies.
# ===========================================================================

feenstra_sigma_obj <- function(d, imp_Y, imp_X, wt_imp) {
  sig <- d[1]
  gam <- d[2]
  if (sig <= 1 || gam <= 0) return(1e12)
  sm1    <- sig - 1
  g_frac <- gam / (1 + gam)
  pred <- (g_frac / sm1)   * imp_X[, 1] +
          g_frac           * imp_X[, 2] +
          (-1 / sm1)       * imp_X[, 3] +
          (g_frac^2 / sm1) * imp_X[, 4]
  sum(wt_imp * (imp_Y - pred)^2)
}


estimate_feenstra_sigma_cell <- function(imp_dt, focal_importer, cfg) {
  dt <- imp_dt[importer == focal_importer]
  n_exp <- uniqueN(dt$exporter)
  max_pd <- dt[, max(period_count)]
  if (n_exp < cfg$min_exporters || max_pd < cfg$min_periods)
    return(cell_failure("insufficient_data"))

  ref_exporter <- choose_reference(dt)
  ref_vals <- dt[exporter == ref_exporter,
                 .(t, ref_ls_dif = ls_imp_dif, ref_lp_dif = lp_dif)]
  dt <- ref_vals[dt, on = "t"]
  dt <- dt[!is.na(ref_ls_dif) & !is.na(ref_lp_dif)]
  dt[, `:=`(Dk_lp = lp_dif - ref_lp_dif, Dk_ls = ls_imp_dif - ref_ls_dif)]
  dt[, `:=`(imp_y = Dk_lp^2, imp_x1 = Dk_ls^2, imp_x2 = Dk_ls * Dk_lp,
            imp_x3 = Dk_ls * lp_dif, imp_x4 = Dk_ls * ref_lp_dif,
            imp_x5 = Dk_lp * ref_lp_dif)]
  dt <- dt[!is.na(imp_y) & !is.na(imp_x1)]
  dt_nonref <- dt[exporter != ref_exporter]
  if (nrow(dt_nonref) == 0L) return(cell_failure("no_nonref_exporters"))

  setorder(dt_nonref, exporter, t)
  dt_nonref[, cusval_lag := shift(cusval, 1L), by = exporter]
  dt_nonref[, bw_w := bw_weight(cusval, cusval_lag, period_count)]
  imp_moments <- dt_nonref[,
    lapply(.SD, weighted.mean, w = bw_w, na.rm = TRUE),
    by = exporter, .SDcols = c("imp_y","imp_x1","imp_x2","imp_x3","imp_x4","imp_x5")]
  J <- nrow(imp_moments)
  if (J < 1L) return(cell_failure("no_valid_moments"))

  imp_Y_vec  <- imp_moments$imp_y
  imp_X_mat  <- as.matrix(imp_moments[, .(imp_x1,imp_x2,imp_x3,imp_x4,imp_x5)])
  wt_imp_vec <- compute_exporter_weights(dt_nonref, imp_moments$exporter, cfg)

  result <- tryCatch(
    optim(par = c(cfg$sigma_start, cfg$gamma_start),
          fn = feenstra_sigma_obj, method = "L-BFGS-B",
          lower = c(1 + 1e-6, 1e-6), upper = c(Inf, Inf),
          imp_Y = imp_Y_vec, imp_X = imp_X_mat, wt_imp = wt_imp_vec,
          control = list(maxit = 500)),
    error = function(e) NULL)

  if (is.null(result) || result$convergence != 0) {
    result <- tryCatch(
      optim(par = c(cfg$sigma_start, cfg$gamma_start),
            fn = feenstra_sigma_obj, method = "Nelder-Mead",
            imp_Y = imp_Y_vec, imp_X = imp_X_mat, wt_imp = wt_imp_vec,
            control = list(maxit = 1000)),
      error = function(e) NULL)
  }

  if (is.null(result)) return(cell_failure("optimizer_failed"))
  sig_hat <- result$par[1]; gam_hat <- result$par[2]
  if (sig_hat <= 1) sig_hat <- NA_real_
  if (gam_hat <= 0) gam_hat <- NA_real_
  list(importer = focal_importer, sigma = sig_hat, gamma = gam_hat,
       convergence = result$convergence, obj_value = result$value)
}


estimate_product_feenstra <- function(g, dt_g, cfg) {
  t0 <- proc.time()["elapsed"]
  results_g <- list(); failures_g <- list()
  n_cells <- 0L; n_ok <- 0L

  imp_stats <- dt_g[, .(n_exp = uniqueN(exporter),
                         max_pd = max(period_count)), by = importer]
  viable <- imp_stats[n_exp >= cfg$min_exporters &
                      max_pd >= cfg$min_periods, importer]

  for (imp in viable) {
    n_cells <- n_cells + 1L
    est <- tryCatch(estimate_feenstra_sigma_cell(dt_g, imp, cfg),
                    error = function(e) cell_failure(paste0("error: ", conditionMessage(e))))
    if (inherits(est, "cell_failure")) {
      failures_g[[length(failures_g) + 1L]] <- list(importer=imp, good=g, reason=est$reason)
      next
    }
    if (!is.null(est) && !is.na(est$sigma)) {
      results_g[[length(results_g) + 1L]] <- data.table(
        importer=est$importer, good=g, sigma=est$sigma, gamma=est$gamma,
        convergence=est$convergence, obj_value=est$obj_value)
      n_ok <- n_ok + 1L
    }
  }
  elapsed <- as.numeric(proc.time()["elapsed"] - t0)
  if (length(results_g) > 0L) {
    out <- rbindlist(results_g)
    attr(out, "timing") <- list(product=g, seconds=elapsed, cells=n_cells, succeeded=n_ok)
    attr(out, "failures") <- failures_g
    out
  } else NULL
}


#' Run Feenstra sigma estimation.
#' @param cfg Config list.
#' @param ncores Cores.
#' @param prepared_dt Optional pre-prepared data.table from prepare_data().
estimate_all_feenstra_sigma <- function(cfg, ncores = NULL, prepared_dt = NULL) {
  if (is.null(ncores)) ncores <- max(1L, detectCores() - 2L)
  ncores <- min(ncores, detectCores())
  cat(sprintf("FEENSTRA (1994) SIGMA ESTIMATION: %d cores\n\n", ncores))

  if (is.null(prepared_dt)) {
    prep <- prepare_data(cfg)
    dt <- prep$dt
  } else {
    dt <- prepared_dt
  }

  products <- unique(dt$good)
  n_products <- length(products)
  dt_by_product <- split(dt, by = "good", keep.by = TRUE)

  t_start <- Sys.time()
  is_windows <- .Platform$OS.type == "windows"

  if (ncores == 1L) {
    results_list <- list()
    for (idx in seq_along(products)) {
      g <- products[idx]
      if (idx %% 50 == 0 || idx == 1L) {
        el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
        cat(sprintf("  [%d/%d] %.1f min elapsed\n", idx, n_products, el))
      }
      results_list[[idx]] <- estimate_product_feenstra(g, dt_by_product[[g]], cfg)
    }
  } else if (is_windows) {
    tmp_dir <- file.path(tempdir(), "het_feenstra")
    dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)
    for (g in products) saveRDS(dt_by_product[[g]], file.path(tmp_dir, paste0(g, ".rds")))
    rm(dt_by_product); gc()

    cl <- makeCluster(ncores)
    on.exit({ tryCatch(stopCluster(cl), error = function(e) NULL)
              unlink(tmp_dir, recursive = TRUE) }, add = TRUE)

    clusterExport(cl, varlist = c("estimate_product_feenstra",
      "estimate_feenstra_sigma_cell", "choose_reference", "bw_weight",
      "feenstra_sigma_obj", "compute_exporter_weights",
      "cell_failure", "cfg", "tmp_dir"),
      envir = environment())
    clusterEvalQ(cl, library(data.table))

    results_list <- parLapply(cl, products, function(g) {
      dt_g <- readRDS(file.path(tmp_dir, paste0(g, ".rds")))
      estimate_product_feenstra(g, dt_g, cfg)
    })
  } else {
    # Forked parallel path (Unix/Mac) with batch checkpointing.
    checkpoint_file <- paste0(build_output_prefix(cfg), "_feenstra_checkpoint.rds")
    batch_size <- max(ncores * 4L, 50L)
    n_batches <- ceiling(n_products / batch_size)

    results_list <- list()
    start_batch <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_batch <- ckpt$next_batch
      cat(sprintf("  Resuming Feenstra from checkpoint: %d/%d batches done\n",
                  start_batch - 1L, n_batches))
    }

    cat(sprintf("  Forked parallel: %d products in %d batches of ~%d\n\n",
                n_products, n_batches, batch_size))

    for (b in seq(start_batch, n_batches)) {
      if (b > n_batches) break
      idx_s <- (b - 1L) * batch_size + 1L
      idx_e <- min(b * batch_size, n_products)
      batch_products <- products[idx_s:idx_e]

      batch_res <- mclapply(batch_products, function(g)
        estimate_product_feenstra(g, dt_by_product[[g]], cfg),
        mc.cores = ncores)
      results_list <- c(results_list, batch_res)

      saveRDS(list(results = results_list, next_batch = b + 1L),
              checkpoint_file)

      el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
      cat(sprintf("  Batch %d/%d: products %d-%d (%.0f%%) | %.1f min\n",
                  b, n_batches, idx_s, idx_e, 100*idx_e/n_products, el))
    }
  }

  t_elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
  results_list <- results_list[!sapply(results_list, is.null)]
  if (length(results_list) == 0L) { cat("\nNo sigma estimates.\n"); return(NULL) }
  output <- rbindlist(results_list)

  # Clean up Feenstra checkpoint after successful completion
  ckpt_cleanup <- paste0(build_output_prefix(cfg), "_feenstra_checkpoint.rds")
  if (file.exists(ckpt_cleanup)) {
    file.remove(ckpt_cleanup)
    cat(sprintf("  Feenstra checkpoint removed: %s\n", ckpt_cleanup))
  }

  cat(sprintf("\nFeenstra sigma: %.1f min, %s cells, sigma median=%.3f\n",
              t_elapsed, format(nrow(output), big.mark = ","),
              median(output$sigma, na.rm = TRUE)))
  output
}


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
