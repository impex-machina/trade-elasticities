# ============================================================================
# test-release-v0114-0148.R  (patch 0148, release v0.11.4)
#
# v0.11.4 re-publishes the two Stage-2b summary files rebuilt by
# scripts/rebuild_stage2b_summary.R (patch 0147). Locks:
#   1. the tool's default path checks the shipped files against the manifest
#      and accepts them (patch 0147 compared openssl's classed hash string
#      with identical() and refused every file -- the default path was never
#      exercised by its test), and still refuses a file that differs;
#   2. the summary text says the within-cell spread is lambda-dependent;
#   3. the card's top entry is v0.11.4, with the numbers of the compare run,
#      a data revision that is <fill> before the upload and the hub oid after,
#      and v0.11.3 pinned at its revision.
# ============================================================================

.rv_root <- function() dirname(locate_source_dir())

.rv_fixture <- function(dir) {
  suppressPackageStartupMessages(library(data.table))
  env <- new.env(parent = globalenv())
  for (f in c("utils_general.R", "iteration_helpers.R", "output_paths.R", "summary.R"))
    sys.source(file.path(.rv_root(), "R", f), envir = env)
  set.seed(9L)
  dt <- rbindlist(lapply(1:11, function(k) data.table(
    importer = sprintf("I%02d", k), good = "0101", exporter = sprintf("E%d", 1:3),
    sigma = 2.5, gamma = exp(rnorm(3, -0.4, 0.7)), tier = 1L, convergence = 0L)))
  dt <- rbind(dt, data.table(importer = "I99", good = "0101", exporter = c("E1", "E2"), sigma = 2.5, gamma = 0.6,
                             tier = c(3L, 0L), convergence = -1L))
  dt[, `:=`(trim_reason = NA_character_, opt_tariff = 0.3)]
  setattr(dt, "run_meta", list(timestamp = as.POSIXct("2026-10-14 12:00:00", tz = "UTC")))
  cfg <- list(filepath = "BACI_HS92_V202601/", agg_level = "hs4", minyear = 1995L, maxyear = NA, min_exporters = 2L,
              min_destinations = 2L, min_periods = 3L, uv_outlier_threshold = 2, tail_trim_pct = NA,
              sigma_V_default = 2.5, gamma_V_default = 0.6, sigma_start = 2.5, gamma_start = 0.6, use_regions = FALSE)
  old <- env$build_summary(dt, cfg, scope = "country")
  old$run_meta <- attr(dt, "run_meta")
  for (d in c("R", "scripts", "data/derived/stage2b")) dir.create(file.path(dir, d), recursive = TRUE, showWarnings = FALSE)
  for (f in c("utils_general.R", "iteration_helpers.R", "output_paths.R", "summary.R"))
    file.copy(file.path(.rv_root(), "R", f), file.path(dir, "R"))
  file.copy(file.path(.rv_root(), "scripts", "rebuild_stage2b_summary.R"), file.path(dir, "scripts"))
  paths <- c("data/derived/stage2b/x_fixed_sigma.rds", "data/derived/stage2b/x_summary.rds")
  saveRDS(dt, file.path(dir, paths[1])); saveRDS(old, file.path(dir, paths[2]))
  sha <- vapply(file.path(dir, paths), function(p) { con <- file(p, "rb"); on.exit(close(con)); as.character(openssl::sha256(con)) }, "")
  utils::write.csv(data.frame(local_path = paths, sha256 = unname(sha), hf_url = paste0("https://h/d/resolve/v0.11.4/", basename(paths))),
                   file.path(dir, "data", "manifest.csv"), row.names = FALSE)
  list(env = env, summary = old, paths = paths)
}

test_that("the compare tool's default path accepts the files the manifest pins and refuses one that differs", {
  skip_if_not_installed("openssl"); skip_if_not_installed("data.table")
  td <- normalizePath(tempfile("rv_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  fx <- .rv_fixture(td)
  rs <- file.path(R.home("bin"), "Rscript")
  od <- setwd(td); on.exit(setwd(od), add = TRUE)
  run <- function() {
    out <- suppressWarnings(system2(rs, shQuote("scripts/rebuild_stage2b_summary.R"), stdout = TRUE, stderr = TRUE))
    list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
  }
  r <- run()
  expect_identical(r$status, 0L, info = r$out)
  expect_match(r$out, "inputs match the manifest's sha256", fixed = TRUE)
  expect_match(r$out, "global block are unchanged", fixed = TRUE)
  cat("x", file = fx$paths[1], append = TRUE)
  r2 <- run()
  expect_identical(r2$status, 1L)
  expect_match(r2$out, "DIFFERS FROM THE MANIFEST: data/derived/stage2b/x_fixed_sigma.rds", fixed = TRUE)
})

test_that("the summary text says the within-cell spread is lambda-dependent", {
  skip_if_not_installed("openssl")
  td <- normalizePath(tempfile("rv_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  fx <- .rv_fixture(td)
  tf <- tempfile(fileext = ".txt"); on.exit(unlink(tf), add = TRUE)
  utils::capture.output(fx$env$write_summary_text(fx$summary, tf))
  txt <- paste(readLines(tf, warn = FALSE), collapse = "\n")
  expect_match(txt, "The within-cell spread of gamma scales with the ridge lambda", fixed = TRUE)
  expect_match(txt, "not\n  identified exporter heterogeneity", fixed = TRUE)
})

test_that("the card's top entry is v0.11.4, with the compare run's numbers and v0.11.3 pinned", {
  card <- readLines(file.path(.rv_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  heads <- grep("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+ \\(", card, value = TRUE)
  expect_match(heads[1], "^> \\*\\*v0\\.11\\.4 \\(2026-10-2[67]\\)\\.\\*\\*")
  i0 <- grep("^> \\*\\*v0\\.11\\.4 ", card); i1 <- grep("^> \\*\\*v0\\.11\\.3 ", card)
  entry <- paste(sub("^> ?", "", card[i0:(i1 - 1L)]), collapse = " ")
  for (s in c("1,819,483", "4,982,259", "0.120 (was 0.022; Soderbery 0.125)", "0.492 (was 0.363; Soderbery 0.625)",
              "0.408 (was 0.439; Soderbery 0.72)", "209,101", "(was 230,967)", "0.787 (was 0.804)",
              "scales with the ridge λ"))
    expect_true(grepl(s, entry, fixed = TRUE), info = s)
  expect_match(entry, "Data revision: `(<fill>|[0-9a-f]{40})`. \\*\\*v0\\.11\\.3 remains available pinned at revision `a8af84de0af983571c145b95e9f2a8892a7ed2fe`\\.\\*\\*")
})
