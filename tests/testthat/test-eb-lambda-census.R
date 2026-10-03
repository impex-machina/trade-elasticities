# ============================================================================
# test-eb-lambda-census.R  (patch 0082, 2026-10-03)
#
# analysis/eb_lambda_census.R estimates, per good, the signal variance tau^2
# of log gamma and the weighted residual variance s^2 from two calendar
# halves, under the one-dimensional shrinkage approximation
#   dev_h = (1 - s)(delta + e_h),  delta ~ N(0, tau^2),  e_h ~ N(0, s^2 / c),
#   c = lambda (1 - s) / s.
# This test builds two half tables and a Stage-2a prior table from exactly
# that model with known (tau^2, s^2) per good and checks that the script
# recovers them (within sampling tolerance at n = 6,000 rows per good), that
# lambda* = s^2 / tau^2 follows, and that the outputs are written.
# ============================================================================

.eb_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

test_that("the EB-lambda census recovers tau^2 and s^2 from synthetic halves", {
  .eb_setup()
  skip_if_not_installed("jsonlite")
  script <- file.path(locate_source_dir(), "..", "analysis", "eb_lambda_census.R")
  skip_if_not(file.exists(script))
  set.seed(20261003)
  lambda <- 0.1
  truth <- data.table(good = c("0101", "0202", "0303"), g = c(0.6, 0.9, 1.4),
                      tau2 = c(0.09, 0.36, 0.04), s2 = c(0.02, 0.02, 0.08))   # lambda* = 0.22, 0.056, 2.0
  n <- 6000L
  rows <- truth[, {
    delta <- rnorm(n, 0, sqrt(tau2))
    cvt <- exp(rnorm(n, log(lambda), 1.2))            # data curvature in log units, spread over two decades
    s <- lambda / (lambda + cvt)
    e_o <- rnorm(n, 0, sqrt(s2 / cvt)); e_e <- rnorm(n, 0, sqrt(s2 / cvt))
    .(importer = as.character(seq_len(n) %% 97L + 1L), exporter = paste0("e", seq_len(n)),
      lg_o = log(g) + (1 - s) * (delta + e_o), lg_e = log(g) + (1 - s) * (delta + e_e), s = s)
  }, by = good]
  mk_half <- function(col) data.table(importer = rows$importer, exporter = rows$exporter, good = rows$good,
                                      gamma = exp(rows[[col]]), gamma_shrink_wt = rows$s, tier = 1L, convergence = 0L, sigma = 3)
  reg <- truth[, .(importer = c("R1", "R2", "R3", "R4", "R5"), exporter = paste0("x", 1:5), gamma = g, sigma = 3,
                   tier = 1L, convergence = 0L), by = good]
  td <- tempfile("eb_"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  for (h in c("odd", "even")) {
    d <- file.path(td, paste0("test_", h)); dir.create(d)
    saveRDS(mk_half(if (h == "odd") "lg_o" else "lg_e"), file.path(d, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"))
  }
  dir.create(file.path(td, "2a_log"))
  saveRDS(reg, file.path(td, "2a_log", "baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds"))
  js <- file.path(td, "c.json"); md <- file.path(td, "c.md")
  rs <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rs, c(shQuote(script), "--config", "test", "--lambda", as.character(lambda), "--grid", shQuote(td),
                                        "--out", shQuote(js), "--md", shQuote(md)), stdout = TRUE, stderr = TRUE))
  expect_true(file.exists(js), info = paste(out, collapse = "\n"))
  expect_true(file.exists(md))
  j <- jsonlite::fromJSON(js)
  bg <- as.data.table(j$by_good); setkey(bg, good); setkey(truth, good)
  expect_equal(bg$good, truth$good)
  expect_true(all(bg$n >= n - 50L) && all(bg$n <= n))   # rows with shrink_wt > 0.99 are excluded by design
  expect_equal(bg$tau2, truth$tau2, tolerance = 0.12)
  expect_equal(bg$s2, truth$s2, tolerance = 0.15)
  expect_equal(bg$lambda_half, truth$s2 / truth$tau2, tolerance = 0.2)
  expect_equal(bg$lambda_full, bg$lambda_half / 2)
  expect_equal(j$summary$n_goods_usable, 3L)
  expect_equal(j$summary$fixed_lambda, lambda)
  expect_true(all(bg$r_parity > 0))
  expect_true(any(grepl("lambda", readLines(md))))
})
