# ============================================================================
# test-sigma-update-0152.R
#
# (patch 0152) --stage2-sigma-update import: sigma re-solved per cell from the
# Eq. (10) block at the Stage-2b gamma-hats, then Stage 2b once more.
#   1. estimate_importer_product_fixed_sigma(return_moments = TRUE) returns the
#      cell's moments and the default path is unchanged; sigma_profile_import()
#      on those moments equals an independent oracle that reads the same
#      quantities off the estimator's body by introspection (the harnesses'
#      original route), cell by cell, to 1e-10.
#   2. The runner under the flag: the update files and log lines exist, the
#      updated rows carry sigma_source 'updated_import' with the Stage-1 label
#      in sigma_source_stage1, sigma_se NA, sigma_robust FALSE, gamma_se_total
#      NA; every other published cell keeps the sigma of the default run; and
#      the default run's table has no sigma_source_stage1 column.
# ============================================================================

.su_root <- function() dirname(locate_source_dir())

.su_world <- function(td) {
  root <- .su_root()
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  truth <- sb$make_synthetic_baci_dir(baci, n_goods = 3L,
                                      countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L),
                                      years = 1995:2014, seed = 20261015L)
  list(baci = baci, truth = truth)
}

.su_run <- function(args, wd) {
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(wd); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, args, stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

test_that("return_moments = TRUE returns the cell's moments, and sigma_profile_import() matches an introspection oracle", {
  for (p in c("data.table", "Rcpp")) skip_if_not_installed(p)
  root <- .su_root(); src_dir <- locate_source_dir()
  td <- normalizePath(tempfile("te_su_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  w <- .su_world(td)
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); if (file.exists(sink_file)) file.remove(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  source(file.path(src_dir, "build_config.R"), local = FALSE)
  cfg <- build_config(list(data = w$baci, minyear = 1995L, maxyear = NA_integer_, agg_level = "hs4",
                           shrinkage_lambda = 0.1, bw_lag = "calendar"))
  cfg$use_regions <- FALSE
  raw <- prepare_raw_data(cfg); dt <- prepare_data(cfg, raw_cache = raw)$dt
  sink()
  tr_sig <- data.table::copy(w$truth$sigma)[, `:=`(importer = as.character(importer), good = as.character(good))]
  tr_gam <- data.table::copy(w$truth$gamma)[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]
  cfg$sigma_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]; cfg$sigma_fallback <- median(tr_sig$sigma_true)
  cfg$sigma_V_lookup <- cfg$sigma_lookup; cfg$sigma_V_default <- cfg$sigma_fallback
  cfg$gamma_V_exporter_lookup <- tr_gam[, .(importer, exporter, good, gamma = gamma_true)]; cfg$gamma_V_lookup <- NULL
  cfg$gamma_V_default <- median(tr_gam$gamma_true); cfg$gamma_start <- cfg$gamma_V_default
  cfg$shrinkage_priors <- NULL

  # the oracle: the estimator's body up to its optimizer call, then the same profile on its internal objects
  f <- estimate_importer_product_fixed_sigma; b <- as.list(body(f))
  idx <- which(vapply(b, function(st) grepl("^d_start <- rep\\(gam_init", paste(deparse(st), collapse = "")), logical(1)))
  expect_length(idx, 1L)
  tail <- quote({
    keys <- c(ref_exporter, exporter_order)
    mi <- match(paste(as.character(focal_importer), as.character(keys)), paste(gamma_tbl$importer, gamma_tbl$exporter))
    dvec <- gamma_tbl$gamma_true[mi]
    obj <- function(s) het_obj_fixed_sigma(d = dvec, sigma = s, imp_Y = imp_Y_vec, imp_X = imp_X_mat,
                                           exp_Y = numeric(0), exp_X = matrix(numeric(0), nrow = 0, ncol = 9), exp_jmap = integer(0),
                                           exp_sig_V = numeric(0), exp_gam_V = numeric(0), wt_imp = wt_imp_vec, wt_exp = numeric(0),
                                           ln_gamma_prior = ln_gamma_prior, shrinkage_lambda = 0, paper_exact_eq11 = pe11,
                                           ridge_all_coords = ridge_all, prior_form = prior_code, import_constant = FALSE, prior_eps = prior_eps)
    grid <- exp(seq(log(1.02), log(50), length.out = 240L)); q <- vapply(grid, obj, numeric(1)); i <- which.min(q)
    pol <- optimize(obj, c(grid[max(1L, i - 1L)], grid[min(240L, i + 1L)]), tol = 1e-8)
    if (pol$objective > q[i]) pol <- list(minimum = grid[i], objective = q[i])
    list(sigma = pol$minimum, J = J, ref = ref_exporter)
  })
  oracle <- f; body(oracle) <- as.call(c(b[seq_len(idx - 1L)], as.list(tail)[-1L]))
  formals(oracle) <- c(formals(f), alist(gamma_tbl = ))

  n_cells <- 0L
  for (g in unique(dt$good)) {
    dt_g <- dt[good == g]
    ed <- compute_exporter_dest_counts(dt_g); el <- compute_exporter_lookup(dt_g)
    cfg_g <- cfg; gvt <- cfg_g$gamma_V_exporter_lookup[good == g]; data.table::setkeyv(gvt, c("importer", "exporter")); cfg_g$gamma_V_exporter_lookup <- gvt
    imp_stats <- dt_g[, .(n_exp = uniqueN(exporter), max_pd = max(period_count)), by = importer]
    viable <- imp_stats[n_exp >= cfg_g$min_exporters & max_pd >= cfg_g$min_periods, importer]
    gt_g <- tr_gam[good == g]
    for (imp in viable[seq_len(min(4L, length(viable)))]) {
      m <- estimate_importer_product_fixed_sigma(dt_g, imp, dt_g, cfg_g, exporter_dests = ed, exp_lookup = el, return_moments = TRUE)
      if (!is.list(m) || is.null(m$imp_Y)) next
      # the default path is a data.table with the usual columns, not the moments
      est <- estimate_importer_product_fixed_sigma(dt_g, imp, dt_g, cfg_g, exporter_dests = ed, exp_lookup = el)
      expect_true(data.table::is.data.table(est)); expect_true(all(c("gamma", "sigma", "tier") %in% names(est)))
      expect_equal(nrow(m$imp_X), m$J); expect_length(m$imp_Y, m$J); expect_length(m$wt_imp, m$J)
      keys <- c(m$ref_exporter, m$exporter_order)
      gv <- gt_g$gamma_true[match(paste(m$importer, keys), paste(gt_g$importer, gt_g$exporter))]
      lib <- sigma_profile_import(m, gv, floor = 1.02, ceiling = 50)
      ora <- oracle(dt_g, imp, dt_g, cfg_g, exporter_dests = ed, exp_lookup = el, gamma_tbl = gt_g)
      expect_equal(lib$sigma, ora$sigma, tolerance = 1e-10)
      expect_equal(m$J, ora$J); expect_equal(m$ref_exporter, ora$ref)
      expect_true(lib$status %in% c("ok", "floor", "ceiling"))
      n_cells <- n_cells + 1L
    }
  }
  expect_gt(n_cells, 5L)
  # the driver: one row per profiled cell, the same sigmas; the parallel paths (patch 0155) equal the serial one
  upd <- sigma_update_import(cfg, dt, tr_gam[, .(importer, exporter, good, gamma = gamma_true)], floor = 1.02, ceiling = 50)
  expect_true(all(c("importer", "good", "sigma_before", "sigma", "status", "J") %in% names(upd)))
  expect_gt(nrow(upd), 5L)
  expect_true(all(upd$status %in% c("ok", "floor", "ceiling", "flat", "no_gamma")))
  up2 <- sigma_update_import(cfg, dt, tr_gam[, .(importer, exporter, good, gamma = gamma_true)], floor = 1.02, ceiling = 50, ncores = 2L)
  data.table::setorder(upd, importer, good); data.table::setorder(up2, importer, good)
  expect_equal(nrow(up2), nrow(upd)); expect_equal(up2$sigma, upd$sigma, tolerance = 1e-12); expect_equal(up2$status, upd$status)
})

test_that("the runner under --stage2-sigma-update import updates sigma, labels and SE fields, and leaves other cells alone", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "Rcpp")) skip_if_not_installed(p)
  root <- .su_root()
  td <- normalizePath(tempfile("te_su_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  w <- .su_world(td)
  runner <- shQuote(file.path(root, "scripts", "run_estimation.R"))
  out0 <- file.path(td, "out0"); dir.create(out0)
  r0 <- .su_run(c(runner, "--data", shQuote(w$baci), "--out-dir", shQuote(out0), "--ncores", "1", "--stage2-sigma-update", "off"), wd = td)   # patch 0155: the update is the default
  expect_equal(r0$status, 0L, info = paste(utils::tail(r0$out, 30), collapse = "\n"))
  log0 <- paste(r0$out, collapse = "\n")
  expect_match(log0, "Stage-2 sigma update: off", fixed = TRUE)
  out1 <- file.path(td, "out1"); dir.create(out1)
  r1 <- .su_run(c(runner, "--data", shQuote(w$baci), "--out-dir", shQuote(out1), "--ncores", "1", "--stage2-sigma-update", "import", "--stage2-sigma-shrink", "0"), wd = td)   # the unshrunk update
  expect_equal(r1$status, 0L, info = paste(utils::tail(r1$out, 30), collapse = "\n"))
  log1 <- paste(r1$out, collapse = "\n")
  expect_match(log1, "Stage-2 sigma update: import (passes: 1, scope: 2a2b", fixed = TRUE)   # 2a2b is the default since patch 0167
  expect_match(log1, "| shrink: off", fixed = TRUE)
  expect_match(log1, "sigma update pass 1 of 1", fixed = TRUE)
  expect_match(log1, "updated_import", fixed = TRUE)
  expect_match(log1, "THREE-STAGE ESTIMATION COMPLETE", fixed = TRUE)

  pre0 <- file.path(out0, "baci_hs92_v202601_elast_country_hs4"); pre1 <- file.path(out1, "baci_hs92_v202601_elast_country_hs4")
  for (f in c("_sigma_update_pass1.csv", "_sigma_update_passes.csv", "_fixed_sigma_pass3.rds", "_fixed_sigma.rds")) expect_true(file.exists(paste0(pre1, f)), info = f)
  t0 <- readRDS(paste0(pre0, "_fixed_sigma.rds")); data.table::setDT(t0)
  t1 <- readRDS(paste0(pre1, "_fixed_sigma.rds")); data.table::setDT(t1)
  prof <- data.table::fread(paste0(pre1, "_sigma_update_pass1.csv"), colClasses = list(character = c("importer", "good")))
  expect_false("sigma_source_stage1" %in% names(t0))
  expect_true(all(c("sigma_source", "sigma_source_stage1") %in% names(t1)))
  expect_true(all(t1$sigma_source_stage1 %in% c("estimated", "fallback_no_estimate", "fallback_sigma_edge", "fallback_sigma_pole")))
  upd <- t1[sigma_source == "updated_import"]
  expect_gt(nrow(upd), 0L)
  expect_true(all(is.na(upd$sigma_se))); expect_true(all(upd$sigma_robust %in% FALSE)); expect_true(all(is.na(upd$gamma_se_total)))
  # updated cells carry the profile's sigma; the profile says so cell by cell
  ok <- prof[status == "ok"]
  cu <- unique(upd[, .(importer = as.character(importer), good = as.character(good), sigma)])
  cu <- merge(cu, ok[, .(importer, good, sigma_prof = sigma)], by = c("importer", "good"))
  expect_equal(nrow(cu), nrow(unique(upd[, .(importer, good)])))
  expect_equal(cu$sigma, cu$sigma_prof, tolerance = 1e-10)
  # every cell that was not updated keeps the default run's sigma and label
  c0 <- unique(t0[, .(importer = as.character(importer), good = as.character(good), sigma0 = sigma, src0 = sigma_source)])
  c1 <- unique(t1[sigma_source != "updated_import", .(importer = as.character(importer), good = as.character(good), sigma1 = sigma, src1 = sigma_source)])
  cc <- merge(c0, c1, by = c("importer", "good"))
  expect_equal(nrow(cc), nrow(c1))
  expect_equal(cc$sigma0, cc$sigma1, tolerance = 1e-12)
  expect_equal(cc$src0, cc$src1)
  # the pass-3 table saved under the flag is the default run's final table (same sigma, same gammas)
  p3 <- readRDS(paste0(pre1, "_fixed_sigma_pass3.rds")); data.table::setDT(p3)
  k <- c("importer", "exporter", "good")
  m3 <- merge(t0[, c(k, "sigma", "gamma"), with = FALSE], p3[, c(k, "sigma", "gamma"), with = FALSE], by = k, suffixes = c("", "_p3"))
  expect_equal(nrow(m3), nrow(t0)); expect_equal(m3$sigma, m3$sigma_p3, tolerance = 1e-12); expect_equal(m3$gamma, m3$gamma_p3, tolerance = 1e-12)
})
