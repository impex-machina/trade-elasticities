#' R/estimate_parallel.R
#'
#' Parallel estimation engine: distributes per-product estimation across
#' PSOCK workers for both the heterogeneous and fixed-sigma passes.
#' Extracted from feen94_het_baci.R (lines 1173-1529, 3134-3434) at
#' refactor step 3; content identical to the original, only sectioned.
#'
#' C3 NOTE: the library(data.table) calls inside the clusterEvalQ() blocks
#' are worker-scoped — they load the package into each PSOCK worker session,
#' which does not inherit the master's search path. They are intentionally
#' NOT consolidated into R/dependencies.R (that file governs master-side
#' top-level library() only).
#'
#' Exported functions:
#'   estimate_all_parallel(cfg, ncores)                  — heterogeneous parallel estimation
#'   estimate_all_fixed_sigma(cfg, ncores, prepared_dt)  — fixed-sigma parallel estimation
#'
#' Depends on: estimate_cell_homogeneous.R, estimate_cell_fixed_sigma.R; parallel (base)

# ===========================================================================
#  PARALLEL ESTIMATION ENGINE
# ===========================================================================

#' @param cfg Config list.
#' @param ncores Number of CPU cores. NULL = detectCores() - 2.
#' @return data.table of estimates.
estimate_all_parallel <- function(cfg, ncores = NULL) {

  if (is.null(ncores)) ncores <- max(1L, detectCores() - 2L)
  ncores <- min(ncores, detectCores())
  cat(sprintf("Estimation: %d cores, OS = %s\n\n", ncores, .Platform$OS.type))

  prep <- prepare_data(cfg)
  dt <- prep$dt; qlog <- prep$qlog

  products <- unique(dt$good)
  n_products <- length(products)
  dt_by_product <- split(dt, by = "good", keep.by = TRUE)

  worker_fns <- c("estimate_product", "estimate_importer_product",
                   "choose_reference", "bw_weight", "optimal_tariff",
                   "assign_regions", "build_region_map",
                   "build_export_moments", "compute_exporter_lookup",
                   "compute_exporter_weights", "cell_failure")

  is_windows <- .Platform$OS.type == "windows"
  t_start <- Sys.time()

  if (ncores == 1L) {
    cat("Running serially (ncores = 1) with incremental checkpoints...\n")

    # --- Checkpoint configuration ---
    checkpoint_every <- 50L  # Save every N products
    checkpoint_file  <- paste0(build_output_prefix(cfg), "_checkpoint.rds")

    # --- Resume from checkpoint if available ---
    results_list <- list()
    start_idx <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_idx <- ckpt$next_idx
      cat(sprintf("  Resuming from checkpoint: %d/%d products already done (%s)\n",
                  start_idx - 1L, n_products, checkpoint_file))
    }

    if (start_idx <= n_products) {
      for (idx in start_idx:n_products) {
        g <- products[idx]
        if (idx %% 10 == 0 || idx == start_idx) {
          el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
          done <- idx - start_idx
          rate <- if (done > 0L) el / done else NA
          eta  <- if (done > 0L) rate * (n_products - idx) else NA
          cat(sprintf("  [%d/%d] %.1f min elapsed%s\n",
                      idx, n_products, el,
                      if (!is.na(eta)) sprintf(", ~%.1f min remaining", eta) else ""))
        }
        res <- estimate_product(g, dt_by_product[[g]], cfg)
        results_list[[idx]] <- res

        # --- Checkpoint save ---
        if (idx %% checkpoint_every == 0L) {
          saveRDS(list(results = results_list, next_idx = idx + 1L),
                  checkpoint_file)
          cat(sprintf("    >> Checkpoint saved at product %d/%d (%s)\n",
                      idx, n_products, checkpoint_file))
        }
      }
    } # end if (start_idx <= n_products)

    # Final checkpoint (in case n_products is not a multiple of checkpoint_every)
    if (n_products %% checkpoint_every != 0L) {
      saveRDS(list(results = results_list, next_idx = n_products + 1L),
              checkpoint_file)
    }

    # Clean up checkpoint after successful completion
    # (kept until post-processing succeeds — deleted at the end of the function)

  } else if (is_windows) {
    cat("Starting socket cluster (Windows)...\n")

    # --- Write product slices to temp files ---
    # Windows socket clusters serialize everything sent to workers.
    # With 90M+ rows, sending data through parLapply causes memory
    # failures. Instead, we write each product's data to a small
    # temp RDS file and have workers read only their own slice.
    tmp_dir <- file.path(tempdir(), "het_products")
    dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

    cat(sprintf("  Writing %d product slices to temp dir...\n", n_products))
    for (g in products) {
      saveRDS(dt_by_product[[g]], file.path(tmp_dir, paste0(g, ".rds")))
    }
    # Free memory — workers will read from disk
    rm(dt_by_product); gc()
    cat("  Product slices written. Starting workers...\n")

    cl <- makeCluster(ncores)
    on.exit({
      tryCatch(stopCluster(cl), error = function(e) NULL)
      unlink(tmp_dir, recursive = TRUE)
    }, add = TRUE)

    clusterExport(cl, varlist = worker_fns, envir = environment())
    clusterExport(cl, varlist = c("cfg", "tmp_dir"), envir = environment())

    # Load het_obj on each worker: try Rcpp, fall back to R
    clusterEvalQ(cl, {
      library(data.table)
      .loaded_rcpp <- FALSE
      tryCatch({
        if (requireNamespace("Rcpp", quietly = TRUE) &&
            file.exists("het_obj_rcpp.cpp")) {
          Rcpp::sourceCpp("het_obj_rcpp.cpp")
          het_obj <- het_obj_rcpp
          .loaded_rcpp <- TRUE
        }
      }, error = function(e) NULL)
      if (!.loaded_rcpp) source("het_obj.R")
    })

    batch_size <- ncores * 2L
    n_batches <- ceiling(n_products / batch_size)
    checkpoint_file <- paste0(build_output_prefix(cfg), "_checkpoint.rds")

    # --- Resume from checkpoint if available ---
    results_list <- list()
    start_batch <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_batch <- ckpt$next_batch
      cat(sprintf("  Resuming from checkpoint: %d/%d batches already done (%s)\n",
                  start_batch - 1L, n_batches, checkpoint_file))
    }

    cat(sprintf("Estimating %d products in %d batches of ~%d...\n\n",
                n_products, n_batches, batch_size))

    for (b in seq(start_batch, n_batches)) {
      if (b > n_batches) break
      idx_s <- (b - 1L) * batch_size + 1L
      idx_e <- min(b * batch_size, n_products)
      batch_products <- products[idx_s:idx_e]

      # Send only product names — workers read their own data from disk
      batch_res <- parLapply(cl, batch_products, function(g) {
        dt_g <- readRDS(file.path(tmp_dir, paste0(g, ".rds")))
        estimate_product(g, dt_g, cfg)
      })
      results_list <- c(results_list, batch_res)

      # --- Checkpoint save after every batch ---
      saveRDS(list(results = results_list, next_batch = b + 1L),
              checkpoint_file)

      el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
      cat(sprintf("  Batch %d/%d: products %d-%d of %d (%.0f%%) | %.1f min, ~%.1f min left\n",
                  b, n_batches, idx_s, idx_e, n_products,
                  100 * idx_e / n_products, el, el / idx_e * (n_products - idx_e)))
    }

  } else {
    cat("Using forked parallelism (Unix/Mac)...\n")
    # Batch checkpointing for the joint estimator.
    checkpoint_file <- paste0(build_output_prefix(cfg), "_checkpoint.rds")
    batch_size <- max(ncores * 4L, 50L)
    n_batches <- ceiling(n_products / batch_size)

    results_list <- list()
    start_batch <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_batch <- ckpt$next_batch
      cat(sprintf("  Resuming joint from checkpoint: %d/%d batches done\n",
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
        estimate_product(g, dt_by_product[[g]], cfg), mc.cores = ncores)
      results_list <- c(results_list, batch_res)

      saveRDS(list(results = results_list, next_batch = b + 1L),
              checkpoint_file)

      el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
      cat(sprintf("  Batch %d/%d: products %d-%d (%.0f%%) | %.1f min\n",
                  b, n_batches, idx_s, idx_e, 100*idx_e/n_products, el))
    }
  }

  t_elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))

  # --- Combine and truncate ---
  results_list <- results_list[!sapply(results_list, is.null)]
  if (length(results_list) == 0L) { cat("\nNo estimates produced.\n"); return(NULL) }

  # Extract timing and failures before rbindlist strips attributes
  timing_info <- lapply(results_list, function(r) attr(r, "timing"))
  timing_info <- timing_info[!sapply(timing_info, is.null)]

  failure_info <- unlist(lapply(results_list, function(r) attr(r, "failures")),
                         recursive = FALSE)
  if (is.null(failure_info)) failure_info <- list()

  output <- rbindlist(results_list)
  n_raw <- nrow(output)
  n_succeeded <- length(results_list)

  # -------------------------------------------------------------------
  # OUTPUT COLUMN INTERPRETATION
  #
  # sigma  Elasticity of substitution (positive, > 1). NOT the price
  #        elasticity of demand. Price elasticity = -sigma.
  # gamma  Inverse export supply elasticity (positive). Supply
  #        elasticity = 1/gamma. Pass-through = 1/(1+gamma).
  # opt_tariff  Heterogeneous formula (Eq. 15). Do NOT use 1/gamma.
  # -------------------------------------------------------------------

  # --- Post-estimation trimming ---
  # Symmetric percentile trim applied to both sigma and gamma.
  # Drops the top and bottom tail_trim_pct of each distribution.
  # This is the approach Soderbery uses for gamma (paper Table 2
  # footnote); we extend it to sigma for consistency rather than
  # hardcoding his 99.5th percentile (131.05), which is specific
  # to his Comtrade sample.

  n_trim_total <- 0L
  trim_pct <- cfg$tail_trim_pct

  if (!is.na(trim_pct) && trim_pct > 0) {
    n_b <- nrow(output)
    output <- output[!is.na(sigma) & !is.na(gamma)]

    sig_lo <- quantile(output$sigma, trim_pct, na.rm = TRUE)
    sig_hi <- quantile(output$sigma, 1 - trim_pct, na.rm = TRUE)
    gam_lo <- quantile(output$gamma, trim_pct, na.rm = TRUE)
    gam_hi <- quantile(output$gamma, 1 - trim_pct, na.rm = TRUE)

    output <- output[sigma >= sig_lo & sigma <= sig_hi &
                     gamma >= gam_lo & gamma <= gam_hi]

    n_trim_total <- n_b - nrow(output)

    cat(sprintf("  Trimmed: %s rows (%.1f%% each tail)\n",
                format(n_trim_total, big.mark = ","), trim_pct * 100))
    cat(sprintf("    Sigma kept: [%.2f, %.2f]  Gamma kept: [%.3f, %.3f]\n",
                sig_lo, sig_hi, gam_lo, gam_hi))
  }

  output <- output[, .(importer, exporter, good, sigma, gamma,
                       ref_exporter, opt_tariff, convergence, obj_value)]

  # --- Quality log ---
  qlog$add("Estimation results (pre-trim)", n_obs = n_raw,
           detail = sprintf("%d products succeeded, %d failed, %.1f min",
                            n_succeeded, n_products - n_succeeded, t_elapsed))
  qlog$add(sprintf("Symmetric tail trim (%.1f%% each tail, both sigma and gamma)",
                   trim_pct * 100),
           n_obs = nrow(output), n_dropped = n_trim_total)

  # --- Final summary ---
  cat("\n=============================================\n")
  cat("ESTIMATION COMPLETE\n")
  cat("=============================================\n\n")

  if (length(timing_info) > 0L) {
    ps <- sapply(timing_info, function(x) x$seconds)
    pc <- sapply(timing_info, function(x) x$cells)
    po <- sapply(timing_info, function(x) x$succeeded)
    cat(sprintf("  Time: %.1f min (%.2f hours) | %.1f products/min\n",
                t_elapsed, t_elapsed / 60, length(timing_info) / t_elapsed))
    cat(sprintf("  Per product: median=%.1fs, mean=%.1fs, max=%.1fs\n",
                median(ps), mean(ps), max(ps)))
    cat(sprintf("  Cell success: %d/%d (%.1f%%)\n\n",
                sum(po), sum(pc), 100 * sum(po) / sum(pc)))
  }

  # --- Failure summary ---
  if (length(failure_info) > 0L) {
    fail_dt <- rbindlist(failure_info)
    fail_counts <- fail_dt[, .N, by = reason]
    setorder(fail_counts, -N)
    cat(sprintf("  Cell failures: %d total\n", nrow(fail_dt)))
    for (i in seq_len(nrow(fail_counts))) {
      cat(sprintf("    %-30s %d\n", fail_counts$reason[i], fail_counts$N[i]))
    }
    cat("\n")
  }

  cat(sprintf("  Estimates: %s rows\n", format(nrow(output), big.mark = ",")))
  cat(sprintf("  Sigma:  median=%.3f, mean=%.3f, IQR=[%.3f, %.3f]\n",
              median(output$sigma, na.rm = TRUE), mean(output$sigma, na.rm = TRUE),
              quantile(output$sigma, .25, na.rm = TRUE),
              quantile(output$sigma, .75, na.rm = TRUE)))
  cat(sprintf("  Gamma:  median=%.3f, mean=%.3f, MAD=%.3f\n",
              median(output$gamma, na.rm = TRUE), mean(output$gamma, na.rm = TRUE),
              mad(output$gamma, na.rm = TRUE)))
  cat(sprintf("  Opt tariff: median=%.3f, mean=%.3f\n",
              median(output$opt_tariff, na.rm = TRUE),
              mean(output$opt_tariff, na.rm = TRUE)))

  print_quality_log(qlog)

  # --- Attach metadata for summary generation ---
  attr(output, "run_meta") <- list(
    qlog         = qlog,
    timing_info  = timing_info,
    failure_info = failure_info,
    n_products   = n_products,
    n_succeeded  = n_succeeded,
    n_failed     = n_products - n_succeeded,
    t_elapsed    = t_elapsed,
    ncores       = ncores,
    rcpp_loaded  = .het_obj_rcpp_loaded,
    trim_pct     = trim_pct,
    trim_bounds  = if (exists("sig_lo")) list(
      sig_lo = sig_lo, sig_hi = sig_hi, gam_lo = gam_lo, gam_hi = gam_hi
    ) else NULL,
    n_pre_trim   = n_raw,
    n_trimmed    = n_trim_total,
    timestamp    = Sys.time()
  )

  # --- Clean up checkpoint file after successful completion ---
  checkpoint_file_cleanup <- paste0(build_output_prefix(cfg), "_checkpoint.rds")
  if (file.exists(checkpoint_file_cleanup)) {
    file.remove(checkpoint_file_cleanup)
    cat(sprintf("  Checkpoint file removed: %s\n", checkpoint_file_cleanup))
  }

  output
}


# ===========================================================================
#  ITERATION AND STARTING VALUE HELPERS
# ===========================================================================

#' Update defaults from completed results for iterative refinement.
#'
#' NOTE: currently unused by run_estimation.R (three-stage pipeline uses
#' explicit Stage 1 -> Stage 2a -> Stage 2b handoff with its own default
#' updates). Retained for interactive use / iterative robustness checks.


estimate_all_fixed_sigma <- function(cfg, ncores = NULL, prepared_dt = NULL) {

  if (is.null(ncores)) ncores <- max(1L, detectCores() - 2L)
  ncores <- min(ncores, detectCores())
  lam <- if (!is.null(cfg$shrinkage_lambda)) cfg$shrinkage_lambda else 0
  cat(sprintf("FIXED-SIGMA GAMMA ESTIMATION: %d cores, lambda=%.3f\n\n", ncores, lam))

  if (is.null(prepared_dt)) {
    prep <- prepare_data(cfg)
    dt <- prep$dt; qlog <- prep$qlog
  } else {
    dt <- prepared_dt
    qlog <- new_quality_log()
    qlog$add("Data (pre-prepared)", n_obs = nrow(dt))
  }

  products <- unique(dt$good)
  n_products <- length(products)
  dt_by_product <- split(dt, by = "good", keep.by = TRUE)

  # Functions needed by workers
  worker_fns <- c("estimate_product_fixed_sigma",
                   "estimate_importer_product_fixed_sigma",
                   "classify_exporter_tiers",
                   "compute_exporter_dest_counts",
                   "compute_exporter_lookup",
                   "compute_exporter_weights",
                   "choose_reference", "bw_weight", "optimal_tariff",
                   "assign_regions", "build_region_map",
                   "build_export_moments", "cell_failure",
                   "compute_dgamma_dsigma", "assess_sigma_robust",
                   "het_obj_fixed_sigma")

  is_windows <- .Platform$OS.type == "windows"
  t_start <- Sys.time()

  if (ncores == 1L) {
    checkpoint_file <- paste0(build_output_prefix(cfg), "_fs_checkpoint.rds")
    results_list <- list()
    start_idx <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_idx <- ckpt$next_idx
      cat(sprintf("  Resuming from checkpoint: %d/%d products done\n",
                  start_idx - 1L, n_products))
    }
    if (start_idx <= n_products) {
      for (idx in start_idx:n_products) {
        g <- products[idx]
        if (idx %% 10 == 0 || idx == start_idx) {
          el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
          done <- idx - start_idx
          rate <- if (done > 0L) el / done else NA
          eta  <- if (done > 0L) rate * (n_products - idx) else NA
          cat(sprintf("  [%d/%d] %.1f min elapsed%s\n",
                      idx, n_products, el,
                      if (!is.na(eta)) sprintf(", ~%.1f min left", eta) else ""))
        }
        results_list[[idx]] <- estimate_product_fixed_sigma(g, dt_by_product[[g]], cfg)
        if (idx %% 50 == 0L) {
          saveRDS(list(results = results_list, next_idx = idx + 1L), checkpoint_file)
        }
      }
    }
    saveRDS(list(results = results_list, next_idx = n_products + 1L), checkpoint_file)
  } else if (is_windows) {
    tmp_dir <- file.path(tempdir(), "het_fixed_sigma")
    dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)
    cat(sprintf("  Writing %d product slices to temp dir...\n", n_products))
    for (g in products) saveRDS(dt_by_product[[g]], file.path(tmp_dir, paste0(g, ".rds")))
    rm(dt_by_product); gc()

    cl <- makeCluster(ncores)
    on.exit({ tryCatch(stopCluster(cl), error = function(e) NULL)
              unlink(tmp_dir, recursive = TRUE) }, add = TRUE)

    # Export all worker functions + config
    clusterExport(cl, varlist = c(worker_fns, "cfg", "tmp_dir"),
                  envir = environment())

    # Also export het_obj (needed by R fallback wrapper) and the Rcpp originals
    if (exists("het_obj", envir = .GlobalEnv)) {
      clusterExport(cl, varlist = "het_obj", envir = .GlobalEnv)
    }

    # Load data.table + try Rcpp on workers
    clusterEvalQ(cl, {
      library(data.table)
      # Try fixed-sigma Rcpp first
      .loaded_fs <- FALSE
      tryCatch({
        if (requireNamespace("Rcpp", quietly = TRUE)) {
          if (file.exists("het_obj_fixed_sigma_rcpp.cpp")) {
            Rcpp::sourceCpp("het_obj_fixed_sigma_rcpp.cpp")
            het_obj_fixed_sigma <- het_obj_fixed_sigma_rcpp
            .loaded_fs <- TRUE
          }
        }
      }, error = function(e) NULL)
      # If Rcpp failed, het_obj_fixed_sigma (the R wrapper) was already
      # exported via clusterExport above — workers will use it.
      # But the R wrapper needs het_obj, which also needs to be available:
      if (!.loaded_fs && !exists("het_obj")) {
        tryCatch({
          if (requireNamespace("Rcpp", quietly = TRUE) &&
              file.exists("het_obj_rcpp.cpp")) {
            Rcpp::sourceCpp("het_obj_rcpp.cpp")
            het_obj <- het_obj_rcpp
          } else {
            source("het_obj.R")
          }
        }, error = function(e) source("het_obj.R"))
      }
    })

    batch_size <- ncores * 2L
    n_batches <- ceiling(n_products / batch_size)
    checkpoint_file <- paste0(build_output_prefix(cfg), "_fs_checkpoint.rds")

    results_list <- list()
    start_batch <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_batch <- ckpt$next_batch
      cat(sprintf("  Resuming from checkpoint: %d/%d batches done\n",
                  start_batch - 1L, n_batches))
    }

    cat(sprintf("Estimating %d products in %d batches of ~%d...\n\n",
                n_products, n_batches, batch_size))

    for (b in seq(start_batch, n_batches)) {
      if (b > n_batches) break
      idx_s <- (b - 1L) * batch_size + 1L
      idx_e <- min(b * batch_size, n_products)
      batch_products <- products[idx_s:idx_e]

      batch_res <- parLapply(cl, batch_products, function(g) {
        dt_g <- readRDS(file.path(tmp_dir, paste0(g, ".rds")))
        estimate_product_fixed_sigma(g, dt_g, cfg)
      })
      results_list <- c(results_list, batch_res)

      # Checkpoint after every batch
      saveRDS(list(results = results_list, next_batch = b + 1L),
              checkpoint_file)

      el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
      cat(sprintf("  Batch %d/%d: products %d-%d (%.0f%%) | %.1f min\n",
                  b, n_batches, idx_s, idx_e, 100*idx_e/n_products, el))
    }
  } else {
    # --------------------------------------------------------------
    #  Forked parallel path (Unix/Mac) with batch checkpointing.
    #  Previously ran as a single mclapply with no resume capability —
    #  a crash at hour N of an M-hour run wasted all N hours. The
    #  batch-checkpoint scheme matches the Windows path's resilience.
    #
    #  Batch size on forked is larger than on socket because fork has
    #  effectively zero per-batch overhead (no serialization), so we
    #  want fewer, larger batches to minimize checkpoint I/O.
    # --------------------------------------------------------------
    checkpoint_file <- paste0(build_output_prefix(cfg), "_fs_checkpoint.rds")
    batch_size <- max(ncores * 4L, 50L)
    n_batches <- ceiling(n_products / batch_size)

    results_list <- list()
    start_batch <- 1L
    if (file.exists(checkpoint_file)) {
      ckpt <- readRDS(checkpoint_file)
      results_list <- ckpt$results
      start_batch <- ckpt$next_batch
      cat(sprintf("  Resuming from checkpoint: %d/%d batches done\n",
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
        estimate_product_fixed_sigma(g, dt_by_product[[g]], cfg),
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
  if (length(results_list) == 0L) { cat("\nNo estimates.\n"); return(NULL) }

  timing_info <- lapply(results_list, function(r) attr(r, "timing"))
  timing_info <- timing_info[!sapply(timing_info, is.null)]
  failure_info <- unlist(lapply(results_list, function(r) attr(r, "failures")),
                         recursive = FALSE)
  if (is.null(failure_info)) failure_info <- list()

  output <- rbindlist(results_list, fill = TRUE)
  n_raw <- nrow(output)
  n_succeeded <- length(results_list)

  # --- Post-estimation trimming ---
  # Trim bounds are computed from directly-estimated exporters only
  # (tier 0/1/2). Tier 3 rows share a clustered value at the product-level
  # prior and would bias the quantile cuts toward the prior if included.
  # The bounds are then applied to all rows.
  n_trim_total <- 0L
  trim_pct <- cfg$tail_trim_pct
  if (!is.na(trim_pct) && trim_pct > 0) {
    n_b <- nrow(output)
    output <- output[!is.na(sigma) & !is.na(gamma)]

    if ("tier" %in% names(output)) {
      trim_src <- output[is.na(tier) | tier < 3L]
    } else {
      trim_src <- output
    }
    # Safety fallback: if tier filtering leaves < 100 rows (e.g. thin
    # HS6 product), fall back to full distribution to avoid degenerate
    # quantiles. This is loud — we cat() a warning.
    if (nrow(trim_src) < 100L) {
      cat(sprintf("  [trim] warning: only %d non-Tier-3 rows, using full distribution\n",
                  nrow(trim_src)))
      trim_src <- output
    }

    sig_lo <- quantile(trim_src$sigma, trim_pct, na.rm = TRUE)
    sig_hi <- quantile(trim_src$sigma, 1 - trim_pct, na.rm = TRUE)
    gam_lo <- quantile(trim_src$gamma, trim_pct, na.rm = TRUE)
    gam_hi <- quantile(trim_src$gamma, 1 - trim_pct, na.rm = TRUE)
    output <- output[sigma >= sig_lo & sigma <= sig_hi &
                     gamma >= gam_lo & gamma <= gam_hi]
    n_trim_total <- n_b - nrow(output)
  }

  # Ensure tier column exists
  if (!"tier" %in% names(output)) output[, tier := NA_integer_]

  # Retain avg_trade so downstream recomputations (e.g. plateau fallback
  # in run_estimation.R) can re-weight optimal tariffs without re-reading
  # the full data.
  keep_cols <- intersect(names(output),
    c("importer","exporter","good","sigma","gamma","gamma_se",
      "gamma_se_total","sigma_robust","sigma_se","dgamma_dsigma",
      "gamma_se_status","gamma_exposure","ref_exporter",
      "opt_tariff","opt_tariff_all","convergence","obj_value","tier",
      "avg_trade"))
  output <- output[, ..keep_cols]

  # --- Summary ---
  cat(sprintf("\nFixed-sigma estimation: %.1f min, %s estimates\n",
              t_elapsed, format(nrow(output), big.mark = ",")))
  cat(sprintf("  sigma median=%.3f, gamma median=%.3f, opt_tariff median=%.3f\n",
              median(output$sigma, na.rm=TRUE), median(output$gamma, na.rm=TRUE),
              median(output$opt_tariff, na.rm=TRUE)))
  if ("tier" %in% names(output)) {
    tier_tab <- output[, .N, by = tier]
    setorder(tier_tab, tier)
    for (i in seq_len(nrow(tier_tab))) {
      cat(sprintf("  Tier %s: %s estimates (%.1f%%)\n",
                  as.character(tier_tab$tier[i]),
                  format(tier_tab$N[i], big.mark = ","),
                  100 * tier_tab$N[i] / nrow(output)))
    }
  }

  attr(output, "run_meta") <- list(
    qlog = qlog, timing_info = timing_info, failure_info = failure_info,
    n_products = n_products, n_succeeded = n_succeeded,
    n_failed = n_products - n_succeeded, t_elapsed = t_elapsed,
    ncores = ncores, rcpp_loaded = .het_obj_fs_rcpp_loaded,
    trim_pct = trim_pct,
    trim_bounds = if (exists("sig_lo")) list(
      sig_lo=sig_lo, sig_hi=sig_hi, gam_lo=gam_lo, gam_hi=gam_hi) else NULL,
    n_pre_trim = n_raw, n_trimmed = n_trim_total,
    timestamp = Sys.time()
  )

  # Clean up checkpoint file after successful completion
  ckpt_cleanup <- paste0(build_output_prefix(cfg), "_fs_checkpoint.rds")
  if (file.exists(ckpt_cleanup)) {
    file.remove(ckpt_cleanup)
    cat(sprintf("  Checkpoint removed: %s\n", ckpt_cleanup))
  }

  output
}


