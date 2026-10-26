# ============================================================================
# test-stage1-sigma-cap-guard.R  (patch 0142, fresh-eyes audit #9)
#
# run_stage1_liml() has no default for sigma_cap. Through patch 0141 the
# wrapper defaulted it to 10 after v0.9.0 shipped at 50, so a script that
# called the wrapper without the argument silently ran the pre-v0.9.0
# estimator (analysis/sigma_uv_trim_sensitivity.R did). Locks:
#   1. the formal has no default (the empty symbol) and a call without it
#      stops with the message naming the config key; NULL, NA, a vector and
#      a cap <= 1 stop before anything is written;
#   2. with the cap passed the wrapper runs, and the table does not depend on
#      how the cap is typed (50, 50L, "50");
#   3. the runner passes the config value, and build_config() ships 50;
#   4. no R file in the repo calls the wrapper without naming sigma_cap.
# ============================================================================

.cg_root <- function() dirname(locate_source_dir())

.cg_panel <- function() {
  # one estimable cell: six exporters over twelve years (the fixture of
  # test-stage1-negative-omega.R)
  set.seed(1L)
  data.table::data.table(importer = 1L, good = "0202",
    exporter = rep(1:6, each = 12L), t = rep(1995:2006, 6L),
    value = exp(rnorm(72)), quantity = exp(rnorm(72)))
}

.cg_env <- function() {
  env <- new.env(parent = globalenv())
  for (f in c("hs_codes.R", "utils_general.R", "liml_estimator.R", "stage1_liml_wrapper.R"))
    sys.source(file.path(.cg_root(), "R", f), envir = env)
  env
}

test_that("sigma_cap has no default; a call without it, or with an unusable one, stops", {
  suppressPackageStartupMessages(library(data.table))
  e <- .cg_env()
  expect_true(identical(formals(e$run_stage1_liml)[["sigma_cap"]], quote(expr = )))   # the empty symbol: no default
  dt <- .cg_panel()
  out <- tempfile(fileext = ".rds"); on.exit(unlink(out), add = TRUE)
  expect_error(e$run_stage1_liml(copy(dt), output_path = out, n_cores = 1L, verbose = FALSE),
               "sigma_cap must be passed explicitly")
  expect_error(e$run_stage1_liml(copy(dt), output_path = out, n_cores = 1L, verbose = FALSE, sigma_cap = NULL),
               "stage1_sigma_cap")
  expect_error(e$run_stage1_liml(copy(dt), output_path = out, n_cores = 1L, verbose = FALSE, sigma_cap = NA),
               "one finite number")
  expect_error(e$run_stage1_liml(copy(dt), output_path = out, n_cores = 1L, verbose = FALSE, sigma_cap = c(10, 50)),
               "one finite number")
  expect_error(e$run_stage1_liml(copy(dt), output_path = out, n_cores = 1L, verbose = FALSE, sigma_cap = 1),
               "greater than 1")
  expect_false(file.exists(out))                      # the guard fires before anything is written
})

test_that("with the cap passed the wrapper runs, and its table is the same whether the cap arrives as 50 or 50L or '50'", {
  suppressPackageStartupMessages(library(data.table))
  e <- .cg_env()
  dt <- .cg_panel()
  run <- function(cap) {
    out <- tempfile(fileext = ".rds"); on.exit(unlink(out), add = TRUE)
    capture.output(e$run_stage1_liml(copy(dt), output_path = out, n_cores = 1L, verbose = FALSE, sigma_cap = cap,
                                     min_exporters = 2L, min_periods = 3L))
    as.data.table(readRDS(out))
  }
  a <- run(50); b <- run(50L); c <- run("50")
  expect_identical(nrow(a), 1L)
  expect_identical(a$status, "ok")
  expect_identical(a, b); expect_identical(a, c)
})

test_that("the runner passes the config value and build_config() ships 50", {
  root <- .cg_root()
  src <- readLines(file.path(root, "scripts", "run_estimation.R"), warn = FALSE)
  expect_true(any(grepl("sigma_cap\\s*=\\s*opts\\$stage1_sigma_cap", src)))
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  cfg <- build_config(parse_cli(c("--data", tempdir())))
  expect_equal(cfg$stage1_sigma_cap, 50)
})

test_that("every repo call of run_stage1_liml() names sigma_cap", {
  root <- .cg_root()
  files <- list.files(root, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/renv/", files) & !grepl("stage1_liml_wrapper\\.R$", files) &
                 !grepl("test-stage1-sigma-cap-guard\\.R$", files)]   # this file calls without the cap on purpose
  offenders <- character(0)
  for (f in files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    # each call: from "run_stage1_liml(" to its matching ")" (no nested parens beyond one level matter here)
    starts <- gregexpr("run_stage1_liml\\(", txt)[[1]]
    if (starts[1] < 0) next
    for (s0 in starts) {
      depth <- 0L; i <- s0 + nchar("run_stage1_liml(") - 1L; n <- nchar(txt)
      while (i <= n) {
        ch <- substr(txt, i, i)
        if (ch == "(") depth <- depth + 1L
        if (ch == ")") { depth <- depth - 1L; if (depth == 0L) break }
        i <- i + 1L
      }
      call <- substr(txt, s0, i)
      if (!grepl("output_path", call, fixed = TRUE)) next   # every real call names output_path; a mention in prose or a test title does not
      if (!grepl("sigma_cap\\s*=", call)) offenders <- c(offenders, sprintf("%s: %s", basename(f), substr(call, 1, 60)))
    }
  }
  expect_identical(offenders, character(0))
})
