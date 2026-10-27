# ============================================================================
# test-trim-sensitivity-0145.R  (patch 0145)
#
# analysis/sigma_uv_trim_sensitivity.R re-estimates Stage 1 on a subsample of
# cells, untrimmed and trimmed. Patch 0145 adds --check-shipped (the untrimmed
# run must reproduce the published Stage-1 table before any trimmed run
# starts, or the script exits 3), --thresholds (one baseline, one trimmed run
# per threshold) and per-run timing. On a synthetic cache whose "published"
# table is the shipped estimator's own output:
#   1. the check passes and both thresholds are written, with the check, the
#      timing and the provenance recorded;
#   2. against a doctored table the script exits 3 and writes nothing;
#   3. the single-threshold mode the cap-10 records came from still works.
# ============================================================================

.ts_root <- function() dirname(locate_source_dir())

.ts_run <- function(args) {
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(.ts_root()); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, c(shQuote("analysis/sigma_uv_trim_sensitivity.R"), args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(status = if (is.null(st)) 0L else as.integer(st), out = paste(out, collapse = "\n"))
}

.ts_fixture <- function(dir) {
  suppressPackageStartupMessages(library(data.table))   # the library calls data.table unqualified
  env <- new.env(parent = globalenv())
  for (f in c("hs_codes.R", "utils_general.R", "liml_estimator.R", "stage1_liml_wrapper.R"))
    sys.source(file.path(.ts_root(), "R", f), envir = env)
  set.seed(11L)
  g <- data.table::CJ(importer = c(842L, 276L), good = c("0101", "0202"), exporter = 1:7, year = 1995:2008)
  g[, `:=`(cusval = exp(rnorm(.N, 10, 1)), quantity = exp(rnorm(.N, 5, 1)))]
  saveRDS(g, file.path(dir, "cache.rds"))
  d <- data.table::copy(g); data.table::setnames(d, c("year", "cusval"), c("t", "value"))
  utils::capture.output(env$run_stage1_liml(d, output_path = file.path(dir, "pub.rds"), n_cores = 1L, min_exporters = 2L,
                                            min_periods = 3L, verbose = FALSE, sigma_cap = 50))
  p <- data.table::as.data.table(readRDS(file.path(dir, "pub.rds")))
  p[, sigma := sigma * 1.1]; saveRDS(p, file.path(dir, "pub_bad.rds"))
  invisible(dir)
}

test_that("the shipped check passes on the shipped estimator's own table; both thresholds are written", {
  skip_if_not_installed("data.table"); skip_if_not_installed("jsonlite")
  td <- normalizePath(tempfile("ts_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  .ts_fixture(td)
  r <- .ts_run(c("--cache", shQuote(file.path(td, "cache.rds")), "--frac", "1", "--thresholds", "3,2", "--ncores", "1",
                 "--check-shipped", shQuote(file.path(td, "pub.rds")),
                 "--out-prefix", shQuote(file.path(td, "out", "sens")), "--md-prefix", shQuote(file.path(td, "out", "sens"))))
  expect_identical(r$status, 0L, info = r$out)
  expect_match(r$out, "shipped check passed", fixed = TRUE)
  expect_identical(sort(list.files(file.path(td, "out"))), c("sens_t2.json", "sens_t2.md", "sens_t3.json", "sens_t3.md"))
  j <- jsonlite::fromJSON(file.path(td, "out", "sens_t2.json"))
  expect_equal(j$threshold, 2); expect_equal(j$sigma_cap, 50)
  expect_equal(j$shipped_check$sigma_match_share, 1); expect_equal(j$shipped_check$status_agree_share, 1)
  expect_equal(j$shipped_check$n_in_table, j$shipped_check$n_cells)
  expect_true(all(c("shipped_s", "trimmed_s", "n_cells") %in% names(j$timing)))
  expect_equal(j$n_cells_universe, 4L)
  expect_identical(j$meta$cache, "cache.rds")
  j3 <- jsonlite::fromJSON(file.path(td, "out", "sens_t3.json"))
  expect_equal(j3$threshold, 3)
  expect_equal(j3$timing$shipped_s, j$timing$shipped_s)          # one baseline for both thresholds
  expect_match(paste(readLines(file.path(td, "out", "sens_t2.md")), collapse = "\n"), "reproduces the published Stage-1 table", fixed = TRUE)
})

test_that("against a doctored table the script exits 3 before any trimmed run and writes nothing", {
  skip_if_not_installed("data.table"); skip_if_not_installed("jsonlite")
  td <- normalizePath(tempfile("ts_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  .ts_fixture(td)
  r <- .ts_run(c("--cache", shQuote(file.path(td, "cache.rds")), "--frac", "1", "--thresholds", "3,2", "--ncores", "1",
                 "--check-shipped", shQuote(file.path(td, "pub_bad.rds")),
                 "--out-prefix", shQuote(file.path(td, "out", "sens")), "--md-prefix", shQuote(file.path(td, "out", "sens"))))
  expect_identical(r$status, 3L, info = r$out)
  expect_match(r$out, "SHIPPED CHECK FAILED", fixed = TRUE)
  expect_false(grepl("Stage 1, trim", r$out, fixed = TRUE))
  expect_false(dir.exists(file.path(td, "out")) && length(list.files(file.path(td, "out"))) > 0L)
  # the single-threshold mode (the cap-10 records' path) is unchanged
  r2 <- .ts_run(c("--cache", shQuote(file.path(td, "cache.rds")), "--frac", "1", "--threshold", "2", "--ncores", "1",
                  "--out", shQuote(file.path(td, "legacy.json")), "--md", shQuote(file.path(td, "legacy.md"))))
  expect_identical(r2$status, 0L, info = r2$out)
  l <- jsonlite::fromJSON(file.path(td, "legacy.json"))
  expect_equal(l$threshold, 2); expect_length(l$shipped_check, 0L)
  r3 <- .ts_run(c("--cache", shQuote(file.path(td, "cache.rds")), "--thresholds", "3,2"))   # no output prefixes
  expect_false(r3$status == 0L)
  expect_match(r3$out, "--thresholds needs --out-prefix and --md-prefix", fixed = TRUE)
})
