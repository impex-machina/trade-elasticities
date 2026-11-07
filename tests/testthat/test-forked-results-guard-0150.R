# ============================================================================
# test-forked-results-guard-0150.R
#
# (patch 0150) assert_forked_results(): a NULL or "try-error" element among
# forked-worker results stops the run. Through v0.11.4 a killed worker's
# products were filed under "no estimates" by estimate_all_fixed_sigma()'s
# forked path, and its cells were skipped by run_stage1_liml()'s
# rbindlist(fill = TRUE); both paths now call the guard on every batch.
# ============================================================================

test_that("assert_forked_results passes clean results and stops on lost, errored or short results", {
  src <- locate_source_dir()
  source(file.path(src, "utils_general.R"), local = TRUE)
  ok <- list(data.frame(a = 1), data.frame(a = 2))
  expect_true(assert_forked_results(ok, c("p1", "p2"), what = "product"))
  expect_error(assert_forked_results(list(data.frame(a = 1), NULL), c("p1", "p2"), what = "product"),
               "1 of 2 tasks came back NULL.*p2")
  err <- try(stop("boom"), silent = TRUE)
  expect_error(assert_forked_results(list(err, data.frame(a = 1)), c("p1", "p2"), what = "product"),
               "1 errored \\(p1; first message: boom\\)")
  expect_error(assert_forked_results(list(data.frame(a = 1)), c("p1", "p2"), what = "product"),
               "returned 1 results for 2 tasks")
})

test_that("a forked worker killed mid-batch is caught (the mclapply NULL-with-a-warning case)", {
  skip_on_os("windows")
  src <- locate_source_dir()
  source(file.path(src, "utils_general.R"), local = TRUE)
  res <- suppressWarnings(parallel::mclapply(1:2, function(i) {
    if (i == 2L) tools::pskill(Sys.getpid(), tools::SIGKILL)
    i
  }, mc.cores = 2L))
  expect_true(any(vapply(res, is.null, logical(1))))   # what mclapply hands back
  expect_error(assert_forked_results(res, c("p1", "p2"), what = "task"), "came back NULL")
})
