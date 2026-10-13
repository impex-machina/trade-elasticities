# ============================================================================
# test-validation-sigma-cap.R  (patch 0109)
#
# Pillar 2's fits run at the shipped Stage-1 sigma cap: the default of
# validate_liml.R's .validation_sigma_cap() must equal build_config()'s
# stage1_sigma_cap default (through patch 0108 the fits took the estimator's
# library default of 10 while production ran at 50), every fit in the harness
# goes through .fit_cell(), and the capture writes the cap into its CSVs.
# ============================================================================

test_that("validation fits default to the shipped Stage-1 sigma cap", {
  root <- dirname(locate_source_dir())
  bc <- readLines(file.path(root, "R", "build_config.R"), warn = FALSE)
  m <- regmatches(bc, regexpr("stage1_sigma_cap = opts\\$stage1_sigma_cap %\\|\\|% [0-9.]+", bc))
  expect_length(m, 1L)
  shipped <- as.numeric(sub(".*% ", "", m))
  vl <- readLines(file.path(root, "validation", "validate_liml.R"), warn = FALSE)
  def <- grep("^\\.validation_sigma_cap <- function", vl, value = TRUE)
  expect_length(def, 1L)
  env <- new.env(); eval(parse(text = def), envir = env)
  old <- options(te.validation_sigma_cap = NULL); on.exit(options(old), add = TRUE)
  expect_equal(env$.validation_sigma_cap(), shipped)
  options(te.validation_sigma_cap = 10)
  expect_equal(env$.validation_sigma_cap(), 10)
  calls <- grep("estimate_cell_liml\\((mom|m_try|m,|bad_mom)", vl, value = TRUE)   # every fit goes through the helper
  expect_length(calls, 1L)
  expect_match(calls, "^\\.fit_cell <- function")
  expect_equal(sum(grepl("\\.fit_cell\\(", vl)), 6L)                              # the 6 call sites
  cap <- readLines(file.path(root, "validation", "capture_liml_validation.R"), warn = FALSE)
  expect_true(any(grepl("tier1a$sigma_cap <- .validation_sigma_cap()", cap, fixed = TRUE)))
  expect_true(any(grepl("tier1b$sigma_cap <- .validation_sigma_cap()", cap, fixed = TRUE)))
})
