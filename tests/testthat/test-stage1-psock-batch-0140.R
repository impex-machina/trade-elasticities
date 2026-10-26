# ============================================================================
# test-stage1-psock-batch-0140.R  (patch 0140)
#
# Stage 1's PSOCK branch (Windows, --ncores > 1) now sends a worker copy of
# process_one_cell() with the global environment and the cells in batches.
#   1. static: stage1_worker_vars covers every variable process_one_cell()
#      reads from run_stage1_liml()'s frame (sigma_cap was missing before
#      0140 and reached workers only inside the serialized frame);
#   2. dynamic: on a synthetic panel the PSOCK branch, forced with
#      TE_STAGE1_PSOCK=1 on two workers, returns the same table as the
#      sequential run.
# ============================================================================

.s40_root <- function() dirname(locate_source_dir())

test_that("stage1_worker_vars covers every frame variable process_one_cell reads", {
  skip_if_not_installed("codetools")
  e <- new.env(); sys.source(file.path(.s40_root(), "R", "stage1_liml_wrapper.R"), envir = e)
  f <- e$run_stage1_liml; b <- body(f)
  find_def <- function(x) {
    if (is.call(x)) {
      if (identical(x[[1]], as.name("<-")) && identical(x[[2]], as.name("process_one_cell"))) return(x[[3]])
      for (k in seq_along(x)) { if (k == 1L) next; y <- x[[k]]; if (missing(y)) next; r <- find_def(y); if (!is.null(r)) return(r) }
    }
    NULL
  }
  pfun <- eval(find_def(b))
  g <- codetools::findGlobals(pfun, merge = FALSE)
  frame_vars <- union(names(formals(f)), all.vars(b))
  used <- intersect(g$variables, frame_vars)
  expect_true("sigma_cap" %in% used)
  expect_identical(setdiff(used, e$stage1_worker_vars), character(0))
})

test_that("the batched PSOCK branch reproduces the sequential Stage-1 table", {
  skip_if_not_installed("parallel")
  suppressPackageStartupMessages(library(data.table))                  # the wrapper calls setDT() unqualified
  root <- .s40_root(); r_dir <- file.path(root, "R")
  old_wd <- getwd(); on.exit(setwd(old_wd), add = TRUE); setwd(r_dir)
  env <- new.env()
  for (f in c("hs_codes.R", "utils_general.R", "liml_estimator.R", "stage1_liml_wrapper.R")) sys.source(file.path(r_dir, f), envir = env)
  if (!exists(".R_dir", envir = env)) assign(".R_dir", r_dir, envir = env)
  dt <- make_synthetic_baci(seed = 42L)[, .(importer, exporter, good, t, value = cusval, quantity)]   # the raw-panel columns Stage 1 reads
  d <- tempfile("s1_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  run <- function(n, out, psock) {
    old <- Sys.getenv("TE_STAGE1_PSOCK"); on.exit(Sys.setenv(TE_STAGE1_PSOCK = old), add = TRUE)
    Sys.setenv(TE_STAGE1_PSOCK = if (psock) "1" else "")
    capture.output(r <- env$run_stage1_liml(data.table::copy(dt), output_path = out, n_cores = n, sigma_cap = 50, verbose = FALSE))
    data.table::as.data.table(readRDS(out))
  }
  a <- run(1L, file.path(d, "seq.rds"), FALSE)
  b <- run(2L, file.path(d, "psock.rds"), TRUE)
  expect_gt(nrow(a), 0L)
  expect_identical(nrow(a), nrow(b))
  expect_true(isTRUE(all.equal(a, b, check.attributes = FALSE)))
})
