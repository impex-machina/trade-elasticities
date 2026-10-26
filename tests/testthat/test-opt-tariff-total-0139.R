# ============================================================================
# test-opt-tariff-total-0139.R  (patch 0139: total_trade and opt_tariff_total, v0.11.3)
#
#   recompute_opt_tariff() recomputes opt_tariff_total from total_trade;
#   scripts/add_opt_tariff_total.R attaches both columns to an existing table,
#   with its checks and the flagged-row rule; the product table's new median;
#   the README rows and note; the card's v0.11.3 entry (before or after its
#   revision is filled). The native computation is checked end to end in the
#   runner smoke test.
# ============================================================================

.o39_root <- function() dirname(locate_source_dir())

.o39_env <- function() {
  e <- new.env()
  for (f in c("R/utils_general.R", "scripts/add_opt_tariff_total.R", "analysis/product_summary.R"))
    sys.source(file.path(.o39_root(), f), envir = e)
  e
}

.o39_toy <- function() data.table::data.table(
  importer = 842L, exporter = c(1L, 2L, 3L), good = "0101", gamma = c(0.5, 2, 1), sigma = 3,
  avg_trade = c(10, 10, 5), tier = c(0L, 1L, 3L), convergence = 0L, trim_reason = NA_character_)

test_that("recompute_opt_tariff recomputes opt_tariff_total from total_trade", {
  e <- .o39_env(); x <- .o39_toy()
  x[, `:=`(total_trade = avg_trade * c(20, 4, 2), opt_tariff = 0, opt_tariff_all = 0, opt_tariff_total = 0)]
  e$recompute_opt_tariff(x)
  expect_equal(x$opt_tariff_total[1], e$optimal_tariff(c(0.5, 2), 3, c(200, 40)))
  expect_equal(x$opt_tariff[1], e$optimal_tariff(c(0.5, 2), 3, c(10, 10)))
})

test_that("attach: values, checks and the flagged-row rule", {
  e <- .o39_env(); x <- .o39_toy()
  x[, `:=`(opt_tariff = e$optimal_tariff(c(0.5, 2), 3, c(10, 10)), opt_tariff_all = 0)]
  pn <- data.table::data.table(importer = 842L, good = "0101", exporter = 1:3, n_dif_trim = c(20L, 4L, 2L), total_dif_trim = c(200, 40, 10))
  r <- e$attach_opt_tariff_total(x, pn)
  expect_identical(r$checks$unmatched, 0L); expect_equal(r$checks$rep_avg_trade, 1); expect_equal(r$checks$rep_opt_tariff, 1)
  expect_true(r$checks$other_columns_unchanged)
  expect_equal(r$table$total_trade, c(200, 40, 10))
  expect_equal(unique(r$table$opt_tariff_total), e$optimal_tariff(c(0.5, 2), 3, c(200, 40)))
  expect_identical(names(r$table)[match("avg_trade", names(r$table)) + 1L], "total_trade")
  # a row whose panel mean disagrees with avg_trade fails the check
  bad <- data.table::copy(pn)[exporter == 2L, total_dif_trim := 44]
  expect_lt(e$attach_opt_tariff_total(x, bad)$checks$rep_avg_trade, 1)
  # flagged rows carry the pre-trim cell value when the pre-trim opt_tariff reproduces
  y <- rbind(x, data.table::data.table(importer = 842L, exporter = 4L, good = "0101", gamma = 4, sigma = 3, avg_trade = 10, tier = 1L,
                                       convergence = 0L, trim_reason = "gamma_hi", opt_tariff = e$optimal_tariff(c(0.5, 2, 4), 3, c(10, 10, 10)),
                                       opt_tariff_all = 0))
  pn4 <- rbind(pn, data.table::data.table(importer = 842L, good = "0101", exporter = 4L, n_dif_trim = 3L, total_dif_trim = 30))
  r4 <- e$attach_opt_tariff_total(y, pn4)
  expect_identical(r4$checks$flagged_rule, "pre-trim values (reproduced exactly)")
  expect_equal(r4$table[exporter == 4L, opt_tariff_total], e$optimal_tariff(c(0.5, 2, 4), 3, c(200, 40, 30)))
  expect_equal(r4$table[exporter == 1L, opt_tariff_total], e$optimal_tariff(c(0.5, 2), 3, c(200, 40)))
})

test_that("product table: opt_tariff_total_median where the column exists", {
  e <- .o39_env(); x <- .o39_toy()
  x[, `:=`(opt_tariff = 0.4, opt_tariff_all = 0.4, total_trade = avg_trade * 3, opt_tariff_total = 0.5)]
  t1 <- e$product_summary(x)
  expect_true("opt_tariff_total_median" %in% names(t1)); expect_equal(t1$opt_tariff_total_median, 0.5)
  expect_identical(names(t1)[match("opt_tariff_median", names(t1)) + 1L], "opt_tariff_total_median")
  t0 <- e$product_summary(x[, !c("total_trade", "opt_tariff_total")])
  expect_false("opt_tariff_total_median" %in% names(t0))
})

test_that("README rows and note; the card's v0.11.3 entry", {
  readme <- paste(readLines(file.path(.o39_root(), "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(readme, "| `opt_tariff_total` | Since v0.11.3.", fixed = TRUE)
  expect_match(readme, "| `avg_trade`, `total_trade` |", fixed = TRUE)
  expect_match(readme, "more than 10% in 35.3% of cells", fixed = TRUE)
  expect_match(readme, "`opt_tariff_total_median` (since v0.11.3", fixed = TRUE)
  card <- paste(readLines(file.path(.o39_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(card, "> **v0.11.3 (2026-10-25).**", fixed = TRUE)
  expect_match(card, "Data revision: `(<fill>|[0-9a-f]{40})`. \\*\\*v0.11.2 remains available pinned at revision")
})
