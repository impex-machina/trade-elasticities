# ============================================================================
# test-stage1-wrapper-smoke.R  (patch 0030)
#
# run_stage1_liml() end-to-end on a tiny synthetic raw panel (importer,
# exporter, good, t, value, quantity). Nothing in the suite exercised the
# wrapper's signature before 0030: the 0025 patch left a formal inside the
# n_cores default (`parallel::detectCores(, hliml_method = "bfgs") - 1`), which
# parsed, passed every test, and failed on the first real call
# ("unused argument (hliml_method = ...)"). This locks: the formals, the
# default path, and hliml_method = "both" writing the *_cf / *_bd columns.
# ============================================================================

.raw_panel <- function(seed = 4L, n_goods = 2L, J = 8L, T = 14L) {
  set.seed(seed)
  rows <- list()
  for (g in seq_len(n_goods)) for (e in seq_len(J)) {
    p <- exp(cumsum(rnorm(T, 0, 0.15)) + rnorm(1, 0, 0.3))
    q <- exp(cumsum(rnorm(T, 0, 0.25)) + rnorm(1, 3, 0.5))
    rows[[length(rows) + 1L]] <- data.table::data.table(
      importer = 840L, exporter = 100L + e, good = sprintf("%04d", 1000L + g),
      t = 1995L + seq_len(T) - 1L, value = p * q, quantity = q)
  }
  data.table::rbindlist(rows)
}

test_that("run_stage1_liml() has the expected formals and runs on the default path", {
  suppressPackageStartupMessages(library(data.table))
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  source(file.path(root, "R", "utils_general.R"), local = TRUE)   # finalize_saved_output()
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  fm <- names(formals(run_stage1_liml))
  expect_true(all(c("baci_dt", "output_path", "n_cores", "min_year", "min_exporters",
                    "min_periods", "sample_cells", "verbose", "hliml_method") %in% fm))
  expect_identical(formals(run_stage1_liml)$hliml_method, "bfgs")
  # the n_cores default must be a clean call (the 0025 regression put a formal inside it)
  expect_identical(deparse(formals(run_stage1_liml)$n_cores), "parallel::detectCores() - 1")
  out_path <- tempfile(fileext = ".rds")
  res <- suppressMessages(run_stage1_liml(.raw_panel(), output_path = out_path, n_cores = 1L,
                                          min_year = 1995L, min_exporters = 3L, min_periods = 3L,
                                          verbose = FALSE))
  expect_true(file.exists(out_path))
  tab <- readRDS(out_path)
  expect_equal(nrow(tab), 2L)
  expect_true(all(c("importer", "good", "status", "hliml_status", "hliml_method") %in% names(tab)))
  expect_true(all(tab$hliml_method == "bfgs"))
  expect_true(all(is.na(tab$sigma_hliml_cf)))
})

test_that("run_stage1_liml(hliml_method = 'both') writes the closed-form and boundary columns", {
  suppressPackageStartupMessages(library(data.table))
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  source(file.path(root, "R", "utils_general.R"), local = TRUE)   # finalize_saved_output()
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  out_path <- tempfile(fileext = ".rds")
  res <- suppressMessages(run_stage1_liml(.raw_panel(), output_path = out_path, n_cores = 1L,
                                          min_year = 1995L, min_exporters = 3L, min_periods = 3L,
                                          verbose = FALSE, hliml_method = "both"))
  tab <- readRDS(out_path)
  need <- c("hliml_Q", "sigma_hliml_cf", "omega_hliml_cf", "hliml_cf_status",
            "hliml_cf_admissible", "hliml_Q_cf", "sigma_hliml_bd", "hliml_bd_edge",
            "hliml_bd_usable", "hliml_Q_bd")
  expect_true(all(need %in% names(tab)))
  expect_true(all(tab$hliml_method == "both"))
  # every cell that reached Step 3 carries a closed-form status
  reached <- tab[!is.na(tab$hliml_status), ]
  expect_true(all(!is.na(reached$hliml_cf_status)))
})
