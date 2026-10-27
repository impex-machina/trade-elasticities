# ============================================================================
# test-legacy-estimator-removed-0149.R  (patch 0149)
#
# The legacy homogeneous estimator -- estimate_importer_product(),
# estimate_product() and their driver estimate_all_parallel() -- had no
# caller in the pipeline and was removed. Its file keeps the three helpers the
# shipped Stage 2 (and the legacy Feenstra Stage 1) use. Locks:
#   1. the library loads; the removed functions are gone; the helpers remain;
#   2. every name the shipped Stage-2 PSOCK workers are sent exists -- a
#      clusterExport() of a missing name would stop every Windows-parallel run;
#   3. no code line in the repo calls a removed function.
# ============================================================================

.lg_root <- function() dirname(locate_source_dir())

# the whole library, loaded the way test-stage2-worker-env.R loads it: from
# inside R/, into the global environment (the loader sources its parts there)
.lg_env <- function() {
  suppressPackageStartupMessages(library(data.table))
  src <- locate_source_dir()
  old <- setwd(src); on.exit(setwd(old), add = TRUE)
  sink(tempfile()); on.exit(sink(), add = TRUE)
  source(file.path(src, "feen94_het_baci.R"), local = FALSE)
  globalenv()
}

test_that("the library loads without the legacy estimator and keeps the shared helpers", {
  e <- .lg_env()
  for (f in c("estimate_importer_product", "estimate_product", "estimate_all_parallel"))
    expect_false(exists(f, envir = e, inherits = FALSE), info = f)
  for (f in c("compute_exporter_weights", "build_export_moments", "compute_exporter_lookup",
              "estimate_product_fixed_sigma", "estimate_importer_product_fixed_sigma", "estimate_all_fixed_sigma"))
    expect_true(is.function(get0(f, envir = e, inherits = FALSE)), info = f)
})

test_that("every name the shipped Stage-2 workers are sent exists", {
  e <- .lg_env()
  w <- get0("stage2_worker_fns", envir = e, inherits = FALSE)
  expect_true(is.character(w) && length(w) > 10L)
  missing <- w[!vapply(w, exists, logical(1), envir = e, inherits = FALSE)]
  expect_identical(missing, character(0), info = paste("sent to workers but not defined:", paste(missing, collapse = ", ")))
})

test_that("no code line in the repo calls a removed function", {
  root <- .lg_root()
  files <- list.files(root, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/renv/", files) & !grepl("test-legacy-estimator-removed-0149\\.R$", files)]
  hits <- character(0)
  for (f in files) {
    code <- sub("#.*$", "", readLines(f, warn = FALSE))                 # comments may name them; code may not
    i <- grep("\\b(estimate_importer_product|estimate_product|estimate_all_parallel)\\s*\\(", code, perl = TRUE)
    if (length(i)) hits <- c(hits, sprintf("%s:%d", basename(f), i))
  }
  expect_identical(hits, character(0))
})
