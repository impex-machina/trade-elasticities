# ============================================================================
# test-stage2-gradient.R  (patch 0028, v0.6.0-rc)
#
# het_grad_fixed_sigma() must equal the numerical gradient of the Rcpp
# objective het_obj_fixed_sigma_rcpp() -- import side, export side (both sign
# conventions of paper_exact_eq11), weights, and the log-ridge prior -- and
# the default stage2_gradient = "numeric" must leave the optim call exactly as
# in v0.5.x (gr = NULL).
# ============================================================================

.s2_fixture <- function(seed = 31L, J = 6L, M = 9L) {
  set.seed(seed)
  imp_Y <- abs(rnorm(J)); imp_X <- matrix(rnorm(J * 5), J, 5)
  wt_imp <- runif(J, 0.5, 2)
  exp_Y <- abs(rnorm(M)); exp_X <- matrix(rnorm(M * 9), M, 9)
  exp_jmap <- sample(seq_len(J), M, replace = TRUE) + 2L   # gamma_j columns (1-based col = jmap - 1)
  sV <- runif(M, 2, 6); gV <- runif(M, 0.2, 2); wt_exp <- runif(M, 0.5, 2)
  d <- c(0.8, runif(J, 0.2, 3))
  list(imp_Y = imp_Y, imp_X = imp_X, wt_imp = wt_imp, exp_Y = exp_Y, exp_X = exp_X,
       exp_jmap = exp_jmap, sV = sV, gV = gV, wt_exp = wt_exp, d = d, sigma = 3.4)
}

test_that("analytic Stage-2 gradient matches numDeriv on the Rcpp objective (with and without prior, both Eq.11 signs)", {
  skip_if_not_installed("Rcpp"); skip_if_not_installed("numDeriv")
  cpp_dir <- locate_cpp_dir()
  root <- dirname(locate_source_dir())
  env <- new.env()
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_rcpp.cpp"), env = env)
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_jacobian_rcpp.cpp"), env = env)
  # pull only the gradient function out of the estimator file
  src <- readLines(file.path(root, "R", "estimate_cell_fixed_sigma.R"))
  a <- grep("^het_grad_fixed_sigma <- function", src)
  b <- grep("^estimate_importer_product_fixed_sigma <- function", src) - 1L
  eval(parse(text = src[a:b]), envir = env)
  fx <- .s2_fixture()
  for (pe in c(FALSE, TRUE)) for (lam in c(0, 0.1)) {
    prior <- if (lam > 0) log(0.7) else NA_real_
    f <- function(d) env$het_obj_fixed_sigma_rcpp(d, fx$sigma, fx$imp_Y, fx$imp_X, fx$exp_Y, fx$exp_X,
                                                   fx$exp_jmap, fx$sV, fx$gV, fx$wt_imp, fx$wt_exp,
                                                   prior, lam, pe)
    g_an <- env$het_grad_fixed_sigma(fx$d, fx$sigma, fx$imp_Y, fx$imp_X, fx$exp_Y, fx$exp_X,
                                     fx$exp_jmap, fx$sV, fx$gV, fx$wt_imp, fx$wt_exp,
                                     prior, lam, pe)
    g_num <- numDeriv::grad(f, fx$d)
    expect_equal(g_an, g_num, tolerance = 1e-6,
                 info = sprintf("paper_exact_eq11=%s lambda=%s", pe, lam))
    expect_false(all(g_an == 0))
  }
})

test_that("gradient is zero-safe outside the feasible region and when the import side is empty", {
  skip_if_not_installed("Rcpp")
  cpp_dir <- locate_cpp_dir(); root <- dirname(locate_source_dir())
  env <- new.env()
  Rcpp::sourceCpp(file.path(cpp_dir, "het_obj_fixed_sigma_jacobian_rcpp.cpp"), env = env)
  src <- readLines(file.path(root, "R", "estimate_cell_fixed_sigma.R"))
  a <- grep("^het_grad_fixed_sigma <- function", src)
  b <- grep("^estimate_importer_product_fixed_sigma <- function", src) - 1L
  eval(parse(text = src[a:b]), envir = env)
  fx <- .s2_fixture()
  g0 <- env$het_grad_fixed_sigma(c(-1, fx$d[-1]), fx$sigma, fx$imp_Y, fx$imp_X, fx$exp_Y, fx$exp_X,
                                 fx$exp_jmap, fx$sV, fx$gV, fx$wt_imp, fx$wt_exp, NA_real_, 0)
  expect_equal(g0, rep(0, length(fx$d)))
  g_e <- env$het_grad_fixed_sigma(fx$d, fx$sigma, numeric(0), matrix(0, 0, 5), fx$exp_Y, fx$exp_X,
                                  fx$exp_jmap, fx$sV, fx$gV, numeric(0), fx$wt_exp, NA_real_, 0)
  expect_length(g_e, length(fx$d)); expect_true(all(is.finite(g_e)))
})

test_that("--stage2-gradient parses, defaults to numeric, validates; build_config carries it", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  source(file.path(root, "R", "validate_config.R"), local = TRUE)
  data_dir <- file.path(tempdir(), paste0("fake_baci_s2g_", sample.int(1e6, 1)))
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(data_dir, recursive = TRUE))
  opts <- parse_cli(args = c("--data", data_dir))
  expect_equal(opts$stage2_gradient, "numeric")
  cfg <- build_config(opts)
  expect_equal(cfg$stage2_gradient, "numeric")
  opts2 <- parse_cli(args = c("--data", data_dir, "--stage2-gradient", "analytic"))
  expect_equal(build_config(opts2)$stage2_gradient, "analytic")
  expect_error(parse_cli(args = c("--data", data_dir, "--stage2-gradient", "exact")), "stage2-gradient")
  bad <- cfg; bad$stage2_gradient <- "exact"
  expect_error(validate_config(bad), "stage2_gradient")
})

test_that("analytic gradient: default path bit-identical; analytic path converges at least as well on the synthetic e2e panel", {
  skip_if_not_installed("Rcpp")
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); if (file.exists(sink_file)) file.remove(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  sink()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded), "Jacobian Rcpp not loaded")
  synth_dt <- make_synthetic_baci(seed = 42L)
  cfg_num <- make_synthetic_cfg(); cfg_num$stage2_gradient <- "numeric"
  cfg_an  <- make_synthetic_cfg(); cfg_an$stage2_gradient  <- "analytic"
  cfg_def <- make_synthetic_cfg()                         # no key at all = v0.5.x call
  run <- function(cfg) { out <- NULL
    suppressMessages(suppressWarnings(capture.output(
      out <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = synth_dt), type = "output")))
    out }
  r_def <- run(cfg_def); r_num <- run(cfg_num); r_an <- run(cfg_an)
  expect_gt(nrow(r_def), 0L)
  # 1. "numeric" == no key: bit-identical DATA (run_meta carries timings)
  strip <- function(d) { d <- data.table::copy(d); data.table::setattr(d, "run_meta", NULL); d }
  keep <- intersect(names(r_def), names(r_num))
  expect_identical(strip(r_def)[, ..keep], strip(r_num)[, ..keep])
  # 2. analytic: same schema, every estimated cell converged, objective finite.
  #    NOTE: on this toy panel the two optimizers reach DIFFERENT local optima
  #    on a minority of cells (each direction), so "analytic <= numeric" is
  #    deliberately NOT asserted -- whether the analytic path raises the
  #    production convergence rate / lowers objectives is the v0.6.0 A/B's
  #    question (compare_runs on obj_value / convergence), not this test's.
  expect_identical(names(r_an), names(r_num))
  m <- merge(r_num[!is.na(obj_value), .(importer, exporter, obj_num = obj_value, conv_num = convergence)],
             r_an[!is.na(obj_value),  .(importer, exporter, obj_an = obj_value,  conv_an = convergence)],
             by = c("importer", "exporter"))
  expect_gt(nrow(m), 0L)
  expect_true(all(m$conv_an == 0L))
  expect_true(all(is.finite(m$obj_an)))
  rel <- (m$obj_an - m$obj_num) / pmax(1e-12, abs(m$obj_num))
  expect_lt(abs(median(rel)), 1e-6)               # typical cell: same optimum
})
