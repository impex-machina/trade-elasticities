# ============================================================================
# test-ridge-closed-0136.R  (patch 0136: the ridge experiment closed)
# ============================================================================

.c36_root <- function() dirname(locate_source_dir())

test_that("README: the bullet's title and close follow the tariff reading", {
  bf <- readLines(file.path(.c36_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^ridge_experiment_bullet <- function", bf); i1 <- grep("^# --- Stage-2 DGP harness line", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  eval(parse(text = bf[i0:i1]), envir = env)
  rd <- function(n) jsonlite::fromJSON(file.path(.c36_root(), "results", paste0(n, ".json")), simplifyVector = FALSE)
  args <- list(rd("known_truth_ridge"), rd("known_truth_eb"), rd("ridge_tau2_eb"), rd("ridge_tau2_check"))
  closed <- do.call(env$ridge_experiment_bullet, c(args, list(rd("ridge_tariff_check"))))
  expect_match(closed, "was tested and not adopted (patches 0132\u20130136).", fixed = TRUE)
  expect_match(closed, "Row-level ln \u03b3 reproduces at 0.240 against 0.337.", fixed = TRUE)
  expect_match(closed, "so the shipped ridge stays; the flags remain in the code, off by default", fixed = TRUE)
  open_ <- do.call(env$ridge_experiment_bullet, args)
  expect_match(open_, "is being tested", fixed = TRUE)
  readme <- paste(readLines(file.path(.c36_root(), "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(readme, "was tested and not adopted (patches 0132\u20130136).", fixed = TRUE)
  doc <- paste(readLines(file.path(.c36_root(), "docs", "methodology", "stage2_country.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(doc, "**The experiment is closed (patch 0136)**", fixed = TRUE)
  cli <- paste(readLines(file.path(.c36_root(), "R", "parse_cli.R"), warn = FALSE), collapse = "\n")
  expect_match(cli, "tested and not adopted (patch 0136", fixed = TRUE)
})
