# ============================================================================
# test-tariff-weight-0138.R  (patch 0138: opt_tariff under total-trade weights)
# ============================================================================

.t38_root <- function() dirname(locate_source_dir())

test_that("the census replicates the published tariff and reweights by total trade", {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "analysis/tariff_weight_census.R")) sys.source(file.path(.t38_root(), f), envir = e)
  # one cell, two estimated exporters: 1 trades 20 years at 10 a year, 2 trades 4 years at 10 a year
  pn <- data.table::data.table(importer = 842L, good = "0101", exporter = c(1L, 2L), n_dif_trim = c(20L, 4L), total_dif_trim = c(200, 40))
  g <- c(0.5, 2); s <- 3
  pub <- e$optimal_tariff(g, s, c(10, 10))
  s2b <- data.table::data.table(importer = 842L, exporter = c(1L, 2L), good = "0101", gamma = g, sigma = s, avg_trade = 10,
                                opt_tariff = pub, tier = 0L, convergence = 0L, trim_reason = NA_character_)
  r <- e$tariff_weight_census(pn, s2b)
  expect_equal(r$replication_avg_trade, 1); expect_equal(r$replication_opt_tariff, 1)
  tot <- e$optimal_tariff(g, s, c(200, 40))
  chg <- exp(abs(log(tot / pub))) - 1                      # the census's symmetric change: max(ratio, 1 / ratio) - 1
  expect_equal(r$cell_change$p50, chg)
  expect_identical(r$reading, if (chg > 0.10) "material" else "immaterial")
  same <- e$tariff_weight_census(data.table::copy(pn)[, `:=`(n_dif_trim = 10L, total_dif_trim = 100)], s2b)
  expect_equal(same$cell_change$p50, 0); expect_identical(same$reading, "immaterial")
  doc <- paste(readLines(file.path(.t38_root(), "docs", "methodology", "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(doc, "analysis/tariff_weight_census.R", fixed = TRUE)
})
