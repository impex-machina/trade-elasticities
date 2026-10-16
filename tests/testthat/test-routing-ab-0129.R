# ============================================================================
# test-routing-ab-0129.R  (patch 0129: Step 2 against the boundary search)
#
#   validation/routing_ab.R on hand-built Stage-1 tables: which cells are
#   comparable, the known-truth metrics, the period prediction, the shipped
#   summary (the fallback after the switch) and the reading.
# ============================================================================

.r29_root <- function() dirname(locate_source_dir())
.r29_env <- function() {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "validation/routing_ab.R")) sys.source(file.path(.r29_root(), f), envir = e)
  e
}
.r29_s1 <- function() data.table::data.table(
  importer = 1:6, good = "0101", status = "ok", convergence = 0L, sigma_se = 0.1, sigma_capped = FALSE, adjust = 0L,
  final_source = c("hliml", "step2_weighted", "step2_weighted", "step2_weighted", "hliml_boundary", "step2_weighted"),
  sigma = c(3, 1 + 2 * exp(1), 1 + 2 * exp(1), 1 + 2 * exp(1), 3, 1.5),
  sigma_hliml_bd = c(NA, 3, 3, 1 + 2 * exp(0.5), 3, 0.9),
  hliml_bd_usable = c(NA, TRUE, TRUE, FALSE, TRUE, TRUE),
  hliml_bd_edge = c(NA, "omega_floor", "sigma_cap", "omega_cap", "omega_floor", "omega_floor"))

test_that("comparable cells: Step-2 routed, usable boundary optimum, both sigmas above 1", {
  e <- .r29_env()
  p <- e$ra_pairs(.r29_s1())
  expect_identical(p$importer, c("2", "3"))                    # 4: boundary not usable; 6: boundary sigma below 1
  expect_equal(p$sigma_bd, c(3, 3))
})

test_that("known truth: Step 2 overstated, the boundary exact; a sigma-cap optimum publishes the fallback", {
  e <- .r29_env()
  w <- file.path(tempfile("ra_"), "w1_x1"); dir.create(file.path(w, "shipped"), recursive = TRUE)
  on.exit(unlink(dirname(w), recursive = TRUE), add = TRUE)
  saveRDS(.r29_s1(), file.path(w, "shipped", paste0(e$RA_PREFIX, "_feenstra_sigma.rds")))
  saveRDS(list(sigma = data.table::data.table(importer = 1:6, good = "0101", sigma_true = 3), meta = list(shock_scale = 1)),
          file.path(w, "truth.rds"))
  kt <- e$ra_known_truth(w)
  expect_identical(kt$overall$cells, 2L)
  expect_equal(kt$overall$bias_s2, 1); expect_equal(kt$overall$bias_bd, 0)
  expect_equal(kt$overall$share_bd_sigma_cap, 0.5)
  rd <- e$ra_reading(kt$by_scale, list(mae_s2 = 0.5, mae_bd = 0.4), list(mae_s2 = 0.5, mae_bd = 0.5))
  expect_identical(rd$verdict, "switch")
  expect_identical(e$ra_reading(kt$by_scale, list(mae_s2 = 0.5, mae_bd = 0.6), list(mae_s2 = 0.5, mae_bd = 0.4))$verdict, "keep Step 2")
})

test_that("period prediction and the shipped summary", {
  e <- .r29_env()
  from <- .r29_s1()
  to <- data.table::data.table(importer = 1:6, good = "0101", status = "ok", convergence = 0L, sigma = 3, sigma_se = 0.1, sigma_capped = FALSE)
  pr <- e$ra_period(from, to)
  expect_identical(pr$cells, 2L)
  expect_equal(pr$mae_s2, 1); expect_equal(pr$mae_bd, 0)
  sh <- e$ra_shipped(from)
  expect_identical(sh$step2_cells, 4L); expect_identical(sh$with_usable_boundary, 2L)
  expect_true(is.finite(sh$fallback_now) && is.finite(sh$fallback_after))
  expect_lte(sh$fallback_after, sh$fallback_now)                # the overstated Step-2 sigmas leave or move down
})
