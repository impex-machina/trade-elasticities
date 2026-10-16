# ============================================================================
# test-audit8-0127.R  (patch 0127: the routing check and the product table)
#
#   1. validation/known_truth_routing.R: accuracy by route on a hand-built
#      world (truth.rds + the shipped arm's Stage-1 table) and the reading;
#   2. analysis/product_summary.R: the product table on a hand-built Stage-2b
#      table (counts, medians, the importer bootstrap, one opt_tariff per
#      cell), the reproducibility correlation and the reading;
#   3. both indexed in the methodology README.
# ============================================================================

.a27_root <- function() dirname(locate_source_dir())
.a27_env <- function() {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "validation/known_truth_routing.R", "analysis/product_summary.R"))
    sys.source(file.path(.a27_root(), f), envir = e)
  e
}

test_that("routing check: accuracy by route and the reading", {
  e <- .a27_env()
  w <- file.path(tempfile("kr_"), "w7_x1"); dir.create(file.path(w, "shipped"), recursive = TRUE)
  on.exit(unlink(dirname(w), recursive = TRUE), add = TRUE)
  truth <- list(sigma = data.table::data.table(importer = 1:6, good = "0101", sigma_true = 3),
                meta = list(seed = 7L, shock_scale = 1))
  saveRDS(truth, file.path(w, "truth.rds"))
  # sigma - 1 = 2 is the truth; step2 cells overstate it by a factor e (ln ratio +1), hliml cells are exact
  s1 <- data.table::data.table(importer = 1:6, good = "0101", status = "ok", convergence = 0L,
                               final_source = c("hliml", "hliml", "hliml", "step2_weighted", "step2_weighted", "hliml_boundary"),
                               sigma = c(3, 3, 3, 1 + 2 * exp(1), 1 + 2 * exp(1), 3), sigma_se = 0.1, sigma_capped = FALSE, adjust = 0L)
  saveRDS(s1, file.path(w, "shipped", paste0(e$KR_PREFIX, "_feenstra_sigma.rds")))
  cells <- e$kr_world(w)
  s <- e$kr_summarise(cells)
  expect_equal(s$overall[route == "step2_weighted"]$bias_raw, 1)
  expect_equal(s$overall[route == "hliml"]$error_raw, 0)
  expect_identical(e$kr_reading(s$by_scale)$verdict, "biased")   # bias +1 > 0.2 and error 1 >= 1.5 x 0
  bs <- data.table::data.table(scale = c(1, 1, 3, 3), route = rep(c("hliml", "step2_weighted"), 2),
                               bias_raw = c(0.05, 0.4, 0.1, 0.3), error_raw = c(0.2, 0.4, 0.2, 0.35))
  expect_identical(e$kr_reading(bs)$verdict, "biased")
  bs$bias_raw[4] <- 0.15
  expect_identical(e$kr_reading(bs)$verdict, "closed")
})

test_that("product table: counts, medians, one opt_tariff per cell (no intervals since patch 0128)", {
  e <- .a27_env()
  s2b <- data.table::data.table(
    importer = rep(1:4, each = 3), exporter = rep(11:13, 4), good = rep(c("0101", "0202"), each = 6),
    gamma = c(0.5, 0.6, 0.7, 0.55, 0.65, 0.75, 1.0, 1.2, 1.4, 1.1, 1.3, 1.5),
    tier = c(0L, 1L, 3L, 0L, 1L, 1L, 0L, 1L, 1L, 0L, 1L, 1L), convergence = c(0L, 0L, -1L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L),
    avg_trade = 1, sigma = rep(c(2.5, 3, 2.47, 2.47), each = 3), sigma_source = rep(c("estimated", "estimated", "fallback_sigma_pole", "estimated"), each = 3),
    opt_tariff = rep(c(0.6, 0.7, 1.2, 1.3), each = 3), trim_reason = NA_character_)
  s2b[12, trim_reason := "gamma_hi"]                                  # a flagged row is left out
  tab <- e$product_summary(s2b)
  expect_identical(tab$good, c("0101", "0202"))
  expect_identical(tab$n_rows, c(6L, 5L))
  expect_identical(tab$n_rows_estimated, c(5L, 5L))                 # the Tier-3 row is not directly estimated
  expect_equal(tab$gamma_median, c(stats::median(c(0.5, 0.6, 0.55, 0.65, 0.75)), stats::median(c(1.0, 1.2, 1.4, 1.1, 1.3))))
  expect_equal(tab$opt_tariff_median, c(0.65, 1.25))                 # one value per cell
  expect_equal(tab$share_cells_own_sigma, c(1, 0.5))
  expect_false(any(c("gamma_lo", "gamma_hi", "opt_tariff_lo", "opt_tariff_hi") %in% names(tab)))
})

test_that("product reproducibility and the reading", {
  e <- .a27_env()
  a <- data.table::data.table(good = sprintf("%04d", 1:8), gamma_median = 1:8, opt_tariff_median = 1:8)
  r <- e$product_reproducibility(a, data.table::copy(a), B = 100L)
  expect_equal(r$gamma_median$spearman, 1); expect_identical(r$gamma_median$products, 8L)
  expect_identical(e$product_reading(r), "publish")
  b <- data.table::copy(a)[, `:=`(gamma_median = c(4, 8, 1, 6, 2, 7, 3, 5), opt_tariff_median = c(5, 2, 8, 1, 6, 3, 7, 4))]
  r2 <- e$product_reproducibility(a, b, B = 100L)
  expect_identical(e$product_reading(r2), if (all(c(r2$gamma_median$spearman, r2$opt_tariff_median$spearman) < 0.3)) "do not publish" else
    if (all(c(r2$gamma_median$spearman, r2$opt_tariff_median$spearman) >= 0.5)) "publish" else "partial")
  expect_identical(e$product_reading(NULL), "not measured")
  doc <- paste(readLines(file.path(.a27_root(), "docs", "methodology", "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(doc, "known_truth_routing.R", fixed = TRUE)
  expect_match(doc, "analysis/product_summary.R", fixed = TRUE)
})
