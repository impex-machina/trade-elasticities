# ============================================================================
# test-ridge-0135.R  (patch 0135: the tariff check and the README record)
# ============================================================================

.r35_root <- function() dirname(locate_source_dir())

test_that("tariff check: cells in all four tables, the 0.02 tolerance", {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "analysis/ridge_tau2_eb.R")) sys.source(file.path(.r35_root(), f), envir = e)
  set.seed(5); n <- 60; base <- rnorm(n, 0, 0.5)
  mk <- function(lt) data.table::data.table(importer = seq_len(n), exporter = 1L, good = "0101", gamma = exp(lt), opt_tariff = exp(lt),
                                            tier = 0L, convergence = 0L, trim_reason = NA_character_)
  co <- mk(base + rnorm(n, 0, 0.2)); ce <- mk(base + rnorm(n, 0, 0.2))
  so <- mk(base + rnorm(n, 0, 0.2)); se <- mk(base + rnorm(n, 0, 0.2))
  r <- e$eb_tariff_check(co, ce, so, se)
  expect_identical(r$cells, 60L)
  expect_true(r$reading %in% c("proceed to a release", "do not release"))
  bad <- e$eb_tariff_check(mk(rnorm(n)), mk(rnorm(n)), so, se)          # candidate halves unrelated
  expect_identical(bad$reading, "do not release")
  same <- e$eb_tariff_check(so, se, so, se)
  expect_identical(same$reading, "proceed to a release")
})

test_that("README records the ridge experiment from its JSONs, NULL-tolerant", {
  bf <- readLines(file.path(.r35_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^ridge_experiment_bullet <- function", bf); i1 <- grep("^# --- Stage-2 DGP harness line", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  eval(parse(text = bf[i0:i1]), envir = env)
  rd <- function(n) jsonlite::fromJSON(file.path(.r35_root(), "results", paste0(n, ".json")), simplifyVector = FALSE)
  expect_identical(env$ridge_experiment_bullet(NULL, NULL, NULL, NULL), "")
  txt <- env$ridge_experiment_bullet(rd("known_truth_ridge"), rd("known_truth_eb"), rd("ridge_tau2_eb"), rd("ridge_tau2_check"))
  expect_match(txt, "importer differences within a product at r 0.49 / 0.43", fixed = TRUE)
  expect_match(txt, "it gives \u03c4\u00b2 = 0.89", fixed = TRUE)
  expect_match(txt, "reproduce across the halves at 0.292 against 0.266", fixed = TRUE)
  expect_false(grepl("Cell-level `opt_tariff`", txt, fixed = TRUE))
  tc <- list(tariff_candidate = 0.61, tariff_shipped = 0.6, reading = "proceed to a release")
  expect_match(env$ridge_experiment_bullet(rd("known_truth_ridge"), rd("known_truth_eb"), rd("ridge_tau2_eb"), rd("ridge_tau2_check"), tc),
               "reproduces across the halves at 0.610 against 0.600", fixed = TRUE)
  readme <- generated_docs_text(.r35_root())   # patch 0143: README.md + the long-form record
  expect_match(readme, "A ridge that does not scale with price volatility ", fixed = TRUE)   # title by outcome since patch 0136
})
