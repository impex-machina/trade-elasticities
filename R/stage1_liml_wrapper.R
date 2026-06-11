#' R/stage1_liml_wrapper.R
#'
#' Stage 1 HLIML orchestration: drives R/liml_estimator.R across all cells,
#' in parallel over PSOCK workers, and assembles the Stage 1 sigma table.
#'
#' C3 NOTE: the suppressPackageStartupMessages(library(data.table)) inside
#' the clusterEvalQ() block is worker-scoped (loads data.table into each
#' PSOCK worker) and is intentionally not consolidated into R/dependencies.R.
#'
#' C4 NOTE: the sample() at the cell-subsetting step is self-seeded
#' (set.seed(20250511)) and fires only on the optional sample_cells testing
#' path; production runs (sample_cells = NULL) draw no random numbers.
#'
#' Exported functions:
#'   (see file for the Stage 1 orchestration entry points)  — Stage 1 HLIML driver
#'
#' Depends on: liml_estimator.R; parallel (base)



run_stage1_liml <- function(baci_dt,
                            output_path,
                            n_cores = parallel::detectCores() - 1,
                            min_year = 1995,
                            min_exporters = 4,
                            min_periods = 3,
                            sample_cells = NULL,
                            verbose = TRUE) {
  # baci_dt: data.table with (importer, exporter, good, t, value, quantity)
  # output_path: where to write _feenstra_sigma.rds
  # n_cores: number of parallel workers (Linux/Mac: mclapply; Windows: PSOCK)
  # min_year: earliest year of data to use
  # min_exporters / min_periods: skip cells too thin to identify
  # sample_cells: integer, if non-NULL, only process this many cells (for testing)
  
  setDT(baci_dt)
  
  if (verbose) {
    cat(sprintf("Stage 1 LIML driver starting.\n"))
    cat(sprintf("  Input panel: %d rows\n", nrow(baci_dt)))
    cat(sprintf("  n_cores: %d\n", n_cores))
  }
  
  # Identify cells
  cells <- unique(baci_dt[, .(importer, good)])
  if (!is.null(sample_cells)) {
    if (verbose) cat(sprintf("  Sampling %d cells for testing\n", sample_cells))
    set.seed(20250511)
    cells <- cells[sample(.N, min(sample_cells, .N))]
  }
  if (verbose) cat(sprintf("  Cells to process: %d\n", nrow(cells)))
  
  # Key the panel for fast subsetting
  setkey(baci_dt, importer, good)
  
  # ----- Pre-split data per cell -----
  # On Windows PSOCK, exporting the full 117M-row baci_dt to each worker
  # is hugely expensive (24+GB copies). Instead, pre-split into per-cell
  # data.frames on the master and send only the slice each worker needs.
  if (verbose) cat("  Pre-splitting panel into per-cell slices...\n")
  t_split0 <- Sys.time()
  # Build a list keyed by (importer, good) with each cell's rows
  # We loop with vapply-style indexing for predictable memory use
  cell_keys <- paste(cells$importer, cells$good, sep = "_")
  cell_data_list <- vector("list", nrow(cells))
  for (i in seq_len(nrow(cells))) {
    imp <- cells$importer[i]
    gd  <- cells$good[i]
    cell_data_list[[i]] <- baci_dt[.(imp, gd),
                                   .(exporter, t, value, quantity),
                                   nomatch = 0L]
  }
  names(cell_data_list) <- cell_keys
  t_split1 <- Sys.time()
  if (verbose) {
    cat(sprintf("  Split done in %.1f sec (memory of slices ~ %.0f MB)\n",
                as.numeric(difftime(t_split1, t_split0, units = "secs")),
                as.numeric(object.size(cell_data_list)) / 1024^2))
  }
  
  # ----- Worker function -----
  # Takes a pre-extracted cell data.frame + key metadata. No need to access
  # the global baci_dt from within the worker.
  process_one_cell <- function(idx, cell_data, imp, gd) {
    data.table::setDTthreads(1)
    
    if (is.null(cell_data) || nrow(cell_data) == 0)
      return(list(importer = imp, good = gd, status = "no_data"))
    
    n_exp <- data.table::uniqueN(cell_data$exporter)
    n_per <- data.table::uniqueN(cell_data$t)
    if (n_exp < min_exporters || n_per < min_periods)
      return(list(importer = imp, good = gd,
                  status = sprintf("thin_panel_e%d_t%d", n_exp, n_per),
                  n_obs = nrow(cell_data),
                  n_exporters = n_exp))
    
    # Prepare moments. NOTE: prepare_cell_moments returns
    #   list(moments = data.frame, ref_exporter, n_obs, n_exporters)
    # and does NOT set a $status field. We validate by $n_obs.
    prep <- tryCatch(
      prepare_cell_moments(
        as.data.frame(cell_data),
        exporter_col = "exporter", time_col = "t",
        value_col = "value", quantity_col = "quantity",
        min_year = min_year),
      error = function(e) list(moments = NULL, n_obs = 0,
                               err = sprintf("prep_error_%s",
                                             substr(conditionMessage(e), 1, 40)))
    )
    if (is.null(prep$moments) || is.null(prep$n_obs) || prep$n_obs < 5)
      return(list(importer = imp, good = gd,
                  status = if (!is.null(prep$err)) prep$err else
                    sprintf("prep_thin_n%d",
                            if (is.null(prep$n_obs)) 0L else prep$n_obs),
                  n_obs = nrow(cell_data)))
    
    fit <- tryCatch(
      estimate_cell_liml(prep$moments, ref_exporter = prep$ref_exporter),
      error = function(e) list(status = sprintf("est_error_%s",
                                                substr(conditionMessage(e), 1, 40)))
    )
    
    if (!isTRUE(fit$status == "ok"))
      return(list(importer = imp, good = gd, status = fit$status,
                  n_obs = nrow(prep$moments)))
    
    # Build output row
    list(
      importer = imp,
      good = gd,
      sigma = fit$sigma,
      omega = fit$omega,
      rho = fit$rho,
      gamma_common = if (!is.na(fit$omega)) fit$omega / (1 + fit$omega) else NA_real_,
      omega_floored = isTRUE(fit$omega_floored),
      sigma_capped  = isTRUE(fit$sigma_capped),
      omega_capped  = isTRUE(fit$omega_capped),
      sigma_se = fit$sigma_se,
      omega_se = fit$omega_se,
      rho_se = fit$rho_se,
      fstat_kp = fit$fstat_kp,
      fstat_het = fit$fstat_het,
      jstat = fit$jstat,
      jstat_pval = fit$jstat_pval,
      jstat_h = fit$jstat_h,
      stockyogo_pass = fit$stockyogo_pass,
      stockyogo_cv = fit$stockyogo_cv,
      adjust = fit$adjust,
      final_source = fit$final_source,
      hliml_status = fit$hliml_status,
      sigma_step2 = fit$sigma_step2,
      omega_step2 = fit$omega_step2,
      rho_step2 = fit$rho_step2,
      sigma_hliml = fit$sigma_hliml,
      omega_hliml = fit$omega_hliml,
      rho_hliml = fit$rho_hliml,
      n_obs = fit$n,
      n_exporters = fit$n_exporters,
      kappa = fit$kappa,
      lambda_min = fit$lambda_min,
      status = "ok"
    )
  }
  
  # ----- Run -----
  t0 <- Sys.time()
  # Build per-cell argument tuples for clusterMap / Map
  imp_vec <- cells$importer
  good_vec <- cells$good
  idx_vec <- seq_len(nrow(cells))
  
  if (.Platform$OS.type == "windows" && n_cores > 1L) {
    # PSOCK cluster on Windows
    # outfile captures worker stdout/stderr so that crashes are diagnosable.
    # Without this, worker output is silently discarded on Windows.
    worker_log <- file.path(dirname(output_path), "stage1_workers.log")
    dir.create(dirname(worker_log), showWarnings = FALSE, recursive = TRUE)
    cl <- parallel::makePSOCKcluster(n_cores, outfile = worker_log)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterEvalQ(cl, {
      suppressPackageStartupMessages(library(data.table))
      data.table::setDTthreads(1)
    })
    # Source liml_estimator.R on each worker. Use absolute path if
    # the workers might have a different working directory than master.
    src_path <- normalizePath(file.path(.R_dir, "liml_estimator.R"), mustWork = TRUE)
    parallel::clusterExport(cl, "src_path", envir = environment())
    parallel::clusterEvalQ(cl, source(src_path))
    parallel::clusterExport(cl,
                            c("min_year", "min_exporters", "min_periods", "process_one_cell"),
                            envir = environment())
    results <- parallel::clusterMap(cl, process_one_cell,
                                    idx = idx_vec,
                                    cell_data = cell_data_list,
                                    imp = imp_vec,
                                    gd = good_vec,
                                    SIMPLIFY = FALSE,
                                    .scheduling = "dynamic")
  } else if (n_cores > 1L) {
    # preschedule=TRUE: fork once per core, each worker burns through its
    # chunk of cells. Far faster than preschedule=FALSE for many short tasks.
    # The cost: if one worker hits a slow cell it can't be load-balanced.
    # Acceptable here since per-cell time is reasonably uniform.
    # mc.silent = FALSE keeps worker stderr connected to master's terminal,
    # so per-cell errors and crashes are visible in the run log.
    results <- parallel::mcmapply(process_one_cell,
                                  idx = idx_vec,
                                  cell_data = cell_data_list,
                                  imp = imp_vec,
                                  gd = good_vec,
                                  SIMPLIFY = FALSE,
                                  mc.cores = n_cores,
                                  mc.preschedule = TRUE,
                                  mc.silent = FALSE)
  } else {
    results <- vector("list", nrow(cells))
    for (i in idx_vec) {
      if (verbose && i %% 500 == 0)
        cat(sprintf("  [%d / %d]\n", i, nrow(cells)))
      results[[i]] <- process_one_cell(i, cell_data_list[[i]],
                                       imp_vec[i], good_vec[i])
    }
  }
  t1 <- Sys.time()
  if (verbose) {
    cat(sprintf("Cells processed in %.1f minutes.\n",
                as.numeric(difftime(t1, t0, units = "mins"))))
  }
  
  # ----- Bind & write -----
  # Convert each result list to a data.table row with all columns,
  # using fill = TRUE so missing fields become NA.
  out_dt <- rbindlist(results, fill = TRUE, use.names = TRUE)
  
  # Summary diagnostics
  if (verbose) {
    n_total  <- nrow(out_dt)
    n_ok     <- sum(out_dt$status == "ok", na.rm = TRUE)
    n_hliml  <- sum(out_dt$final_source == "hliml", na.rm = TRUE)
    n_step2  <- sum(out_dt$final_source == "step2_weighted", na.rm = TRUE)
    cat(sprintf("\n--- Stage 1 LIML summary ---\n"))
    cat(sprintf("  Total cells:        %d\n", n_total))
    cat(sprintf("  Successful (ok):    %d (%.1f%%)\n",
                n_ok, 100 * n_ok / n_total))
    cat(sprintf("    HLIML primary:    %d (%.1f%% of ok)\n",
                n_hliml, if (n_ok>0) 100 * n_hliml / n_ok else 0))
    cat(sprintf("    Step 2 fallback:  %d (%.1f%% of ok)\n",
                n_step2, if (n_ok>0) 100 * n_step2 / n_ok else 0))
    if (n_ok > 0) {
      cat(sprintf("  Sigma quartiles:    %s\n",
                  paste(sprintf("%.2f", quantile(out_dt$sigma, c(.25,.5,.75),
                                                 na.rm = TRUE)),
                        collapse = ", ")))
      cat(sprintf("  Omega quartiles:    %s\n",
                  paste(sprintf("%.4f", quantile(out_dt$omega, c(.25,.5,.75),
                                                 na.rm = TRUE)),
                        collapse = ", ")))
      cat(sprintf("  F_kp quartiles:     %s\n",
                  paste(sprintf("%.1f", quantile(out_dt$fstat_kp, c(.25,.5,.75),
                                                 na.rm = TRUE)),
                        collapse = ", ")))
    }
  }
  
  if (verbose) cat(sprintf("\nWriting output: %s\n", output_path))
  saveRDS(out_dt, output_path)
  if (verbose) cat("Done.\n")
  invisible(out_dt)
}

# Small helper used in worker
`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a
