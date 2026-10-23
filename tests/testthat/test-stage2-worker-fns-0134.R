# ============================================================================
# test-stage2-worker-fns-0134.R  (patch 0134)
#
# Every function of this repo that the Stage-2 worker functions call must be
# exported to PSOCK workers (stage2_worker_fns). Patch 0132's
# .ridge_cell_scale() was not: under --stage2-ridge-scale cell on Windows with
# --ncores > 1 every cell failed with "could not find function", while the
# single-core tests and the known-truth harness passed. The PSOCK test
# (test-stage2-worker-env.R) runs the default configuration only; this static
# check covers every branch. Also: the checkpoint stamp carries 0132's flags,
# and the runner stops when Stage 2b estimates no row.
# ============================================================================

.w34_root <- function() dirname(locate_source_dir())

test_that("every repo function the Stage-2 worker functions call is exported to workers", {
  skip_if_not_installed("codetools")
  suppressPackageStartupMessages(library(data.table))
  root <- .w34_root()
  e <- new.env()
  for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE))
    tryCatch(suppressWarnings(sys.source(f, envir = e)), error = function(err) NULL)
  nm <- ls(e, all.names = TRUE)
  repo_fns <- nm[vapply(nm, function(n) is.function(get(n, e)), TRUE)]
  w <- get("stage2_worker_fns", e)
  expect_true(all(c("estimate_importer_product_fixed_sigma", ".ridge_cell_scale") %in% w))
  called <- unique(unlist(lapply(intersect(w, repo_fns), function(f) codetools::findGlobals(get(f, e), merge = FALSE)$functions)))
  missing <- setdiff(intersect(called, repo_fns), w)
  expect_identical(missing, character(0), info = paste("not exported to Stage-2 workers:", paste(missing, collapse = ", ")))
})

test_that("the checkpoint stamp covers the ridge flags; the runner stops on an all-failed Stage 2b", {
  src <- paste(readLines(file.path(.w34_root(), "R", "estimate_parallel.R"), warn = FALSE), collapse = "\n")
  expect_match(src, '"ridge_scale", "ridge_tau2",', fixed = TRUE)
  run <- paste(readLines(file.path(.w34_root(), "scripts", "run_estimation.R"), warn = FALSE), collapse = "\n")
  expect_match(run, 'stop("Stage 2b estimated no rows: every cell failed.', fixed = TRUE)
  eb <- paste(readLines(file.path(.w34_root(), "analysis", "ridge_tau2_eb.R"), warn = FALSE), collapse = "\n")
  expect_match(eb, "no usable rows estimated in both halves", fixed = TRUE)
})
