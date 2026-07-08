# ============================================================================
# test-cell-moments-gaps.R
#
# Stage-1 counterpart of test-prepare-data-gaps.R: prepare_cell_moments()
# (R/liml_estimator.R) computes its own first differences from the raw cache
# and must not treat a multi-year gap as a one-period change. The B1 guard
# in prepare_data.R protects only the Stage-2 path; this locks the Stage-1
# path.
#
# Fixture: two exporters trading in a single cell. Exporter 1 trades every
# year 1:6 (the reference, longest panel). Exporter 2 trades in years
# 1, 2, 5, 6 — so its 2 -> 5 adjacency spans a 3-year gap and must NOT
# yield a usable moment row, while 1 -> 2 and 5 -> 6 must.
# ============================================================================

test_that("prepare_cell_moments nulls first differences across year gaps", {
  skip_if_not_installed("data.table")

  # Source the estimator library directly (prepare_cell_moments lives there
  # and has no dependencies on the rest of the package).
  src_dir <- locate_source_dir()
  source(file.path(src_dir, "liml_estimator.R"), local = TRUE)

  set.seed(7)
  e1 <- data.frame(exporter = 1L, t = 1:6,
                   value = exp(rnorm(6, 5, .1)), quantity = exp(rnorm(6, 3, .1)))
  e2_years <- c(1L, 2L, 5L, 6L)
  e2 <- data.frame(exporter = 2L, t = e2_years,
                   value = exp(rnorm(4, 5, .1)), quantity = exp(rnorm(4, 3, .1)))
  trade <- rbind(e1, e2)

  prep <- prepare_cell_moments(trade,
                               exporter_col = "exporter", time_col = "t",
                               value_col = "value", quantity_col = "quantity")

  expect_false(is.null(prep$moments))
  m <- prep$moments

  # Reference exporter is exporter 1 (longest panel). Moments are built
  # from BOTH exporters' diffs joined on t, and only rows where both sides
  # are finite survive. Exporter 2's usable diffs land at t = 2 and t = 6;
  # t = 5 spans the 2 -> 5 gap and must be excluded.
  e2_rows <- m[m$exporter == 2L, ]
  expect_true(all(e2_rows$t %in% c(2L, 6L)))
  expect_false(5L %in% e2_rows$t)

  # And the consecutive-year diffs must be present (the guard must not
  # over-delete).
  expect_setequal(e2_rows$t, c(2L, 6L))
})

test_that("gap guard does not change moments for gap-free panels", {
  skip_if_not_installed("data.table")

  src_dir <- locate_source_dir()
  source(file.path(src_dir, "liml_estimator.R"), local = TRUE)

  set.seed(11)
  trade <- do.call(rbind, lapply(1:4, function(e) {
    data.frame(exporter = e, t = 1:8,
               value = exp(rnorm(8, 5, .2)), quantity = exp(rnorm(8, 3, .2)))
  }))

  prep <- prepare_cell_moments(trade,
                               exporter_col = "exporter", time_col = "t",
                               value_col = "value", quantity_col = "quantity")
  m <- prep$moments

  # Every exporter has 7 consecutive diffs; non-reference exporters keep all
  # rows where the reference diff also exists (t = 2..8).
  non_ref <- m[m$exporter != prep$ref_exporter, ]
  expect_true(all(table(non_ref$exporter) == 7L))
})
