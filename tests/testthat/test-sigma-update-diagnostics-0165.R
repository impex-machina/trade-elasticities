# ============================================================================
# test-sigma-update-diagnostics-0165.R  (patch 0165, fresh-eyes audit #11)
#
# The measurement tooling and the profile speed-up, all behind flags whose
# defaults leave every published number unchanged:
#   1. the closed-form profile equals the grid search on random cells (status,
#      and sigma to 1e-6 in ln(sigma - 1) away from the bounds); 'both' returns
#      the grid's answer beside it; flat / no_gamma cells return every field;
#      the structure check sends a non-quadratic objective back to the grid;
#   2. return_moments = "import" returns the import moments of TRUE without the
#      export moments, and the profile over a synthetic world is the same under
#      'grid' as through TRUE's moments, and under 'closed' / 'both' as the grid;
#   3. refresh_step() measures rows (every directly estimated tier) and cells;
#   4. the sensitivity census's three rules read as written;
#   5. the CLI accepts and validates the three flags; the runner passes the
#      method to the profile and gates the refresh and the trim grid on them.
# ============================================================================

.s65_root <- function() dirname(locate_source_dir())
.s65_lib <- function() {
  sink_file <- tempfile(fileext = ".log"); sink(sink_file); on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) })
  source(file.path(locate_source_dir(), "feen94_het_baci.R"), local = FALSE)
}

# a random cell in the shape estimate_importer_product_fixed_sigma(return_moments = ...) returns
.s65_cell <- function(J, seed) {
  set.seed(seed)
  sig0 <- 1 + exp(rnorm(1, 0.5, 0.8)); g <- exp(rnorm(J + 1, -0.3, 0.6))
  X <- cbind(abs(rnorm(J, 0.6, 0.4)), rnorm(J, 0, 0.2), rnorm(J, 0, 0.2), rnorm(J, 0, 0.1), rnorm(J, 0.05, 0.1))
  gk <- g[1]; gj <- g[-1]; rho <- gj / (1 + gj); sm1 <- sig0 - 1
  Y <- rho / sm1 * X[, 1] + rho * X[, 2] - X[, 3] / sm1 + rho * (1 + gk) / (gk * sm1) * X[, 4] + (gj - gk) / (gk * (1 + gj)) * X[, 5] + rnorm(J, 0, 0.05)
  list(m = list(imp_Y = Y, imp_X = X, wt_imp = runif(J, 0.2, 3), ln_gamma_prior = 0, paper_exact_eq11 = FALSE, ridge_all_coords = TRUE,
                prior_form = 0L, prior_eps = 0.01, sigma = sig0, J = J), g = g)
}

test_that("closed-form profile: same status and sigma as the grid; 'both' carries the grid; every status returns every field", {
  for (p in c("data.table", "Rcpp")) skip_if_not_installed(p)
  .s65_lib()
  grid_step <- (log(50) - log(1.02)) / 239
  n_same <- 0L; n_ok <- 0L; worst <- 0
  for (r in 1:300) {
    cc <- .s65_cell(sample(2:12, 1), 1000L + r)
    gr <- sigma_profile_import(cc$m, cc$g, method = "grid"); cl <- sigma_profile_import(cc$m, cc$g, method = "closed")
    expect_identical(cl$method, "closed")
    near_bound <- is.finite(cl$sigma) && (abs(log(cl$sigma) - log(1.02)) < 1.5 * grid_step || abs(log(cl$sigma) - log(50)) < 1.5 * grid_step)
    if (!near_bound) { expect_identical(cl$status, gr$status, info = paste("cell", r)); n_same <- n_same + 1L }
    if (gr$status == "ok" && cl$status == "ok") { n_ok <- n_ok + 1L; worst <- max(worst, abs(log(cl$sigma - 1) - log(gr$sigma - 1))) }
    if (r %% 50 == 0) {
      bo <- sigma_profile_import(cc$m, cc$g, method = "both")
      expect_identical(bo$sigma, cl$sigma); expect_identical(bo$status, cl$status)
      expect_equal(bo$sigma_grid, gr$sigma); expect_identical(bo$status_grid, gr$status)
    }
  }
  expect_gt(n_same, 250L); expect_gt(n_ok, 200L); expect_lt(worst, 1e-6)
  # beyond the bounds: a cell whose least-squares theta is negative ("beyond infinity") is a cap profile
  cc <- .s65_cell(6L, 7L); cc$m$imp_Y <- -abs(cc$m$imp_Y) * 50
  expect_identical(sigma_profile_import(cc$m, cc$g, method = "closed")$status, sigma_profile_import(cc$m, cc$g, method = "grid")$status)
  # flat and no_gamma return the full set of fields under every method (through 0164: four fields, and rbindlist() would stop)
  cc <- .s65_cell(4L, 9L)
  for (mth in c("grid", "closed", "both")) {
    ng <- sigma_profile_import(cc$m, c(NA, cc$g[-1]), method = mth)
    expect_identical(ng$status, "no_gamma"); expect_true(all(c("se_ln", "n_score", "method") %in% names(ng)))
    if (mth == "both") expect_true(all(c("sigma_grid", "status_grid") %in% names(ng)))
  }
  flat <- cc; flat$m$imp_X[] <- 0
  expect_identical(sigma_profile_import(flat$m, flat$g, method = "closed")$status, "flat")
  # the structure check: an objective that is not affine in the quadratic sends the cell back to the grid
  expect_null(.sigma_profile_closed(cc$m, cc$g, 1.02, 50, obj = function(s) (log(s) - 1)^2))
})

test_that("return_moments = 'import' gives TRUE's import moments without the export moments; the world's profile is unchanged", {
  for (p in c("data.table", "Rcpp")) skip_if_not_installed(p)
  root <- .s65_root(); src_dir <- locate_source_dir()
  td <- normalizePath(tempfile("te_s65_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  truth <- sb$make_synthetic_baci_dir(baci, n_goods = 3L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L),
                                      years = 1995:2014, seed = 20261015L)
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); if (file.exists(sink_file)) file.remove(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE); source(file.path(src_dir, "build_config.R"), local = FALSE)
  cfg <- build_config(list(data = baci, minyear = 1995L, maxyear = NA_integer_, agg_level = "hs4", shrinkage_lambda = 0.1, bw_lag = "calendar"))
  cfg$use_regions <- FALSE
  dt <- prepare_data(cfg, raw_cache = prepare_raw_data(cfg))$dt
  sink()
  tr_sig <- data.table::copy(truth$sigma)[, `:=`(importer = as.character(importer), good = as.character(good))]
  tr_gam <- data.table::copy(truth$gamma)[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]
  cfg$sigma_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]; cfg$sigma_fallback <- median(tr_sig$sigma_true)
  cfg$sigma_V_lookup <- cfg$sigma_lookup; cfg$sigma_V_default <- cfg$sigma_fallback
  cfg$gamma_V_exporter_lookup <- tr_gam[, .(importer, exporter, good, gamma = gamma_true)]; cfg$gamma_V_lookup <- NULL
  cfg$gamma_V_default <- median(tr_gam$gamma_true); cfg$gamma_start <- cfg$gamma_V_default; cfg$shrinkage_priors <- NULL
  g1 <- as.character(unique(dt$good))[1]; dg <- dt[good == g1]
  ed <- compute_exporter_dest_counts(dg); el <- compute_exporter_lookup(dg)
  cfg_g <- cfg; gvt <- cfg$gamma_V_exporter_lookup[good == g1]; data.table::setkeyv(gvt, c("importer", "exporter")); cfg_g$gamma_V_exporter_lookup <- gvt   # as .sigma_update_one_good() keys it
  imp <- dg[, .(n = data.table::uniqueN(exporter)), by = importer][n >= 3L, importer][1]
  mt <- estimate_importer_product_fixed_sigma(dg, imp, dg, cfg_g, exporter_dests = ed, exp_lookup = el, return_moments = TRUE)
  mi <- estimate_importer_product_fixed_sigma(dg, imp, dg, cfg_g, exporter_dests = ed, exp_lookup = el, return_moments = "import")
  for (k in c("imp_Y", "imp_X", "wt_imp", "sigma", "J", "n_tier1", "ref_exporter", "exporter_order", "ln_gamma_prior")) expect_identical(mi[[k]], mt[[k]], info = k)
  expect_identical(mi$exp_mom$M, 0L); expect_gt(mt$exp_mom$M, 0L)
  gam <- tr_gam[, .(importer, exporter, good, gamma = gamma_true)]
  pg <- sigma_update_import(cfg, dt, gam, floor = 1.02, ceiling = 50, method = "grid")
  pc <- sigma_update_import(cfg, dt, gam, floor = 1.02, ceiling = 50, method = "closed")
  pb <- sigma_update_import(cfg, dt, gam, floor = 1.02, ceiling = 50, method = "both")
  expect_false("profile_method" %in% names(pg))                              # the default's CSV keeps its v0.12.0 columns
  expect_true(all(c("profile_method", "sigma_grid", "status_grid") %in% names(pb)))
  expect_identical(pb$sigma, pc$sigma); expect_equal(pb$sigma_grid, pg$sigma); expect_identical(pb$status_grid, pg$status)
  # in parallel: forked workers on Unix, PSOCK on Windows, where the closed form must be provisioned to every worker
  pb2 <- sigma_update_import(cfg, dt, gam, floor = 1.02, ceiling = 50, method = "both", ncores = 2L)
  data.table::setorder(pb2, importer, good); pbo <- data.table::copy(pb); data.table::setorder(pbo, importer, good)
  expect_equal(pb2, pbo)
  okb <- pg$status == "ok" & pc$status == "ok"
  expect_gt(sum(okb), 5L); expect_lt(max(abs(log(pc$sigma[okb] - 1) - log(pg$sigma[okb] - 1))), 1e-6)
  expect_gte(mean(pc$status == pg$status), 0.95)
})

test_that("refresh_step: every directly estimated tier, and the cells' opt_tariff", {
  e <- new.env(); for (f in c("R/utils_general.R", "R/iteration_helpers.R")) sys.source(file.path(.s65_root(), f), envir = e)
  suppressPackageStartupMessages(library(data.table))
  a <- data.table(importer = 1L, exporter = c("x", "y", "z", "w"), good = "0101", tier = c(0L, 1L, 2L, 3L), convergence = c(0L, 0L, 0L, -1L),
                  gamma = c(1, 1, 1, 0.7), opt_tariff = 0.5, trim_reason = NA_character_)
  b <- copy(a); b[, gamma := c(1.005, 1.05, 1.2, 0.7)]; b[, opt_tariff := 0.52]
  st <- e$refresh_step(a, b)
  expect_identical(st$rows, 3L)                                              # tiers 0, 1, 2; not the Tier-3 prior
  expect_equal(st$share_rows_gt_1pct, 2 / 3)
  expect_identical(st$cells, 1L); expect_equal(st$share_cells_tariff_gt_1pct, 1)
  expect_equal(st$max, log(1.2))
})

test_that("sensitivity census: the three rules read as written", {
  e <- new.env(); sys.source(file.path(.s65_root(), "analysis", "sigma_update_sensitivity_census.R"), envir = e)
  suppressPackageStartupMessages(library(data.table))
  set.seed(4)
  n <- 4000L; s <- 1 + exp(rnorm(n, 0.5, 0.4))
  prof <- data.table(importer = as.character(1:n), good = "0101", sigma = s, status = "ok", sigma_grid = s * (1 + 1e-9), status_grid = "ok", profile_method = "closed")
  expect_identical(e$profile_method_reading(prof)$reading, "ADOPTABLE")
  prof2 <- copy(prof); prof2[1:10, status_grid := "floor"]                    # 0.25% disagree
  expect_identical(e$profile_method_reading(prof2)$reading, "NOT ADOPTABLE")
  expect_null(e$profile_method_reading(prof[, !c("sigma_grid", "status_grid")]))
  expect_identical(e$refresh_reading(data.table(refresh = 1L, rows = 100L, abs_dlng_p50 = 1e-4, abs_dlng_p90 = 3e-3, abs_dlng_p99 = 0.02,
                                                 share_rows_gt_1pct = 0.04, cells = 20L, share_cells_tariff_gt_1pct = 0.05))$reading, "CLOSE")
  expect_identical(e$refresh_reading(data.table(refresh = 1L, rows = 100L, abs_dlng_p50 = 1e-3, abs_dlng_p90 = 0.03, abs_dlng_p99 = 0.1,
                                                 share_rows_gt_1pct = 0.04, cells = 20L, share_cells_tariff_gt_1pct = 0.12))$reading, "ADOPT")
  base <- data.table(importer = as.character(1:500), good = "0101", status = "ok")
  z <- rnorm(500, 0.5, 0.5)
  mk <- function(thr, shift, noise) copy(base)[, `:=`(threshold = thr, sigma = 1 + exp(z + shift + rnorm(500, 0, noise)))]
  tg <- rbind(mk("1.5", 0.02, 0.05), mk("2", 0, 0.05), mk("3", -0.01, 0.05), mk("off", -0.04, 0.05))
  r <- e$trim_grid_reading(tg)
  expect_identical(r$reading, "ROBUST"); expect_identical(r$curve$threshold, c("1.5", "2", "3", "off"))
  expect_true(all(c("med_abs", "spearman", "share_gt_10pct") %in% names(r$curve)))
  tg2 <- rbind(mk("1.5", 0.25, 0.05), mk("2", 0, 0.05), mk("3", -0.2, 0.05))
  expect_identical(e$trim_grid_reading(tg2)$reading, "THRESHOLD-DEPENDENT")
  expect_match(e$trim_grid_reading(tg[threshold != "3"])$reading, "^not measured")
  tab <- data.table(trim_reason = c(NA, NA, "sigma_lo", "gamma_hi"))
  expect_identical(e$trim_reason_counts(tab)[trim_reason == "published", rows], 2L)
})

test_that("CLI: the three flags are accepted and validated; the runner wires them", {
  src_dir <- locate_source_dir(); source(file.path(src_dir, "parse_cli.R"), local = TRUE)
  td <- tempfile("te_s65c_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  base <- c("--data", td, "--out-dir", td)
  o <- parse_cli(args = base)
  expect_identical(o$stage2_sigma_profile, "grid"); expect_identical(o$stage2_gamma_v_refresh, 0L); expect_null(o$stage2_sigma_update_trim_grid)
  o2 <- parse_cli(args = c(base, "--stage2-sigma-profile", "both", "--stage2-gamma-v-refresh", "1", "--stage2-sigma-update-trim-grid", "1.5,2,3,off"))
  expect_identical(o2$stage2_sigma_profile, "both"); expect_identical(o2$stage2_gamma_v_refresh, 1L)
  expect_equal(parse_trim_grid(o2$stage2_sigma_update_trim_grid), c(1.5, 2, 3, NA))
  expect_error(parse_cli(args = c(base, "--stage2-sigma-profile", "newton")), "must be 'grid', 'closed' or 'both'")
  expect_error(parse_cli(args = c(base, "--stage2-gamma-v-refresh", "-1")), "must be an integer >= 0")
  expect_error(parse_cli(args = c(base, "--stage2-sigma-update-trim-grid", "2,zero")), "comma-separated list")
  run <- paste(readLines(file.path(.s65_root(), "scripts", "run_estimation.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(run, 'method = opts$stage2_sigma_profile %||% "grid")', fixed = TRUE)
  expect_match(run, "gvr_n <- as.integer(opts$stage2_gamma_v_refresh %||% 0L)", fixed = TRUE)
  expect_match(run, "if (!is.null(opts$stage2_sigma_update_trim_grid)) {", fixed = TRUE)
  expect_match(run, '"_gamma_v_refresh.csv"', fixed = TRUE); expect_match(run, '"_sigma_update_trimgrid.csv"', fixed = TRUE)
  su <- paste(readLines(file.path(.s65_root(), "R", "sigma_update.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(su, '"sigma_profile_import", ".sigma_profile_closed", ".sigma_update_one_good"', fixed = TRUE)   # PSOCK workers get the closed form
})
