# ============================================================================
# test-summary-estimated-rows-0147.R  (patch 0147)
#
# The Stage-2b summary's Soderbery comparisons (Table 2, the within-pair
# statistics, the variance decomposition) are computed over the directly
# estimated rows; Tier-3 rows carry the good-level prior and are counted, not
# summarized. Locks:
#   1. build_summary() on a table with estimated, mixed, all-Tier-3 and flagged
#      cells: the comparisons see exactly the estimated rows, the global block
#      still describes the published table and counts the imputed rows;
#   2. the text says which rows each section reads;
#   3. the README's opening counts estimated and Tier-3 rows from the record;
#   4. scripts/rebuild_stage2b_summary.R: compare mode writes nothing and finds
#      the untouched sections unchanged; --write writes both files.
# ============================================================================

.sm_root <- function() dirname(locate_source_dir())

.sm_env <- function(rev = NULL) {
  suppressPackageStartupMessages(library(data.table))
  env <- new.env(parent = globalenv())
  for (f in c("utils_general.R", "iteration_helpers.R", "output_paths.R")) sys.source(file.path(.sm_root(), "R", f), envir = env)
  if (is.null(rev)) sys.source(file.path(.sm_root(), "R", "summary.R"), envir = env)
  else eval(parse(text = rev), envir = env)
  env
}

.sm_table <- function() {
  suppressPackageStartupMessages(library(data.table))
  set.seed(5L)
  est <- rbindlist(lapply(1:12, function(k) data.table(
    importer = sprintf("I%02d", k), good = sprintf("%04d", 100 + (k %% 3)), exporter = sprintf("E%d", 1:4),
    sigma = 2 + k / 10, gamma = exp(rnorm(4, -0.5, 0.8)), tier = c(0L, 1L, 1L, 2L), convergence = 0L)))
  t3_mixed <- data.table(importer = "I01", good = "0101", exporter = c("E8", "E9"), sigma = 2.1, gamma = 0.6,
                         tier = 3L, convergence = -1L)
  all_t3 <- data.table(importer = "I99", good = "0101", exporter = c("E1", "E2", "E3", "E4"), sigma = 2.5, gamma = 0.6,
                       tier = c(3L, 3L, 3L, 0L), convergence = -1L)
  flagged <- data.table(importer = "I01", good = "0101", exporter = "E7", sigma = 2.1, gamma = 40, tier = 1L, convergence = 0L)
  dt <- rbindlist(list(est, t3_mixed, all_t3, flagged), use.names = TRUE)
  dt[, trim_reason := NA_character_][exporter == "E7", trim_reason := "gamma_hi"]
  dt[, opt_tariff := 1 / 3]
  data.table::setattr(dt, "run_meta", list(timestamp = as.POSIXct("2026-10-14 12:00:00", tz = "UTC")))
  dt
}

.sm_cfg <- function() list(filepath = "BACI_HS92_V202601/", agg_level = "hs4", minyear = 1995L, maxyear = NA,
                           min_exporters = 2L, min_destinations = 2L, min_periods = 3L, uv_outlier_threshold = 2,
                           tail_trim_pct = NA, sigma_V_default = 2.47, gamma_V_default = 0.6,
                           sigma_start = 2.47, gamma_start = 0.6, use_regions = FALSE)

test_that("the comparisons read the directly estimated rows; the global block counts the imputed ones", {
  e <- .sm_env(); dt <- .sm_table()
  s <- e$build_summary(dt, .sm_cfg(), scope = "country")
  expect_identical(s$heterogeneity_rows, "estimated")
  expect_equal(s$global$n_estimates, 48L + 2L + 4L)              # published rows: the flagged row is out
  expect_equal(s$global$n_estimated, 48L)
  expect_equal(s$global$n_imputed, 6L)                           # 2 mixed-cell Tier-3 rows + the all-Tier-3 cell (4)
  expect_equal(s$table2[importer == "World", obs], 48L)
  expect_equal(s$within_het$n_pairs, 12L)                        # the all-Tier-3 cell (I99) is not a pair of estimates
  expect_equal(s$var_decomp$n_obs, 48L)
  expect_equal(s$global$gamma_median_estimated, median(dt[tier < 3L & convergence != -1L & is.na(trim_reason), gamma]))
  expect_false("I99" %in% s$table2$importer)
  # the pre-0147 summary (from git) summarized the imputed rows too, for contrast
  old_src <- tryCatch(system2("git", c("-C", shQuote(.sm_root()), "show", "origin/main:R/summary.R"), stdout = TRUE, stderr = FALSE),
                      error = function(err) character(0))
  if (length(old_src) > 100L && !any(grepl("patch 0147", old_src, fixed = TRUE))) {
    o <- .sm_env(rev = paste(old_src, collapse = "\n"))$build_summary(dt, .sm_cfg(), scope = "country")
    expect_equal(o$var_decomp$n_obs, 54L)
    expect_equal(o$within_het$n_pairs, 13L)                     # the all-Tier-3 cell read as a pair of identical gammas
    expect_false(isTRUE(all.equal(o$var_decomp$r_squared, s$var_decomp$r_squared)))   # moved; the direction is data-dependent
  }
})

test_that("the text says which rows each section reads", {
  e <- .sm_env(); s <- e$build_summary(.sm_table(), .sm_cfg(), scope = "country")
  tf <- tempfile(fileext = ".txt"); on.exit(unlink(tf), add = TRUE)
  capture.output(e$write_summary_text(s, tf))
  txt <- paste(readLines(tf, warn = FALSE), collapse = "\n")
  for (p in c("Tier 3 (good-level prior, not estimated): 6", "directly estimated: 48",
              "PER-IMPORTER SUMMARY (cf. Soderbery Table 2; directly estimated rows)",
              "WITHIN IMPORTER-PRODUCT HETEROGENEITY (cf. Soderbery p. 52; directly estimated rows)",
              "VARIANCE DECOMPOSITION OF GAMMA (cf. Soderbery p. 52; directly estimated rows)",
              "Median over the directly estimated rows"))
    expect_true(grepl(p, txt, fixed = TRUE), info = p)
})

test_that("the README's opening counts estimated and Tier-3 rows from the record", {
  root <- .sm_root()
  j <- jsonlite::fromJSON(file.path(root, "results", "stage2b_summary.json"))
  readme <- paste(readLines(file.path(root, "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = " ")
  fi <- function(x) formatC(as.integer(x), big.mark = ",", format = "d")
  ss <- j$se_status
  expect_equal(ss$total, j$n_cells)
  expect_true(grepl(sprintf("producing %s (importer, exporter, HS4) rows of γ:", fi(j$n_cells)), readme, fixed = TRUE))
  expect_true(grepl(sprintf("%s estimated cell by cell", fi(ss$total - ss$tier3_prior)), readme, fixed = TRUE))
  expect_true(grepl(sprintf("%s (Tier 3) set to the good-level prior, with no standard error.", fi(ss$tier3_prior)), readme, fixed = TRUE))
  expect_false(grepl("cell-level γ estimates with standard errors", readme, fixed = TRUE))
})

test_that("rebuild_stage2b_summary.R compares without writing, then writes on request", {
  skip_if_not_installed("data.table")
  root <- .sm_root()
  td <- normalizePath(tempfile("sm_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  dt <- .sm_table()
  e <- .sm_env()
  old <- e$build_summary(dt, .sm_cfg(), scope = "country")
  old$heterogeneity_rows <- NULL; old$global$n_estimated <- NULL; old$global$n_imputed <- NULL; old$global$gamma_median_estimated <- NULL
  old$run_meta <- attr(dt, "run_meta")
  saveRDS(dt, file.path(td, "tab.rds")); saveRDS(old, file.path(td, "old_summary.rds"))
  rs <- file.path(R.home("bin"), "Rscript")
  od <- setwd(root); on.exit(setwd(od), add = TRUE)
  run <- function(extra) {
    out <- suppressWarnings(system2(rs, c(shQuote("scripts/rebuild_stage2b_summary.R"), "--table", shQuote(file.path(td, "tab.rds")),
                                          "--summary", shQuote(file.path(td, "old_summary.rds")), extra), stdout = TRUE, stderr = TRUE))
    list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
  }
  r <- run(character(0))
  expect_identical(r$status, 0L, info = r$out)
  expect_match(r$out, "global block are unchanged", fixed = TRUE)
  expect_match(r$out, "compare only: nothing written", fixed = TRUE)
  expect_match(r$out, "of which Tier 3 at the prior", fixed = TRUE)
  expect_length(list.files(td, pattern = "^new_"), 0L)
  r2 <- run(c("--write", shQuote(file.path(td, "new"))))
  expect_identical(r2$status, 0L, info = r2$out)
  expect_true(file.exists(file.path(td, "new_summary.rds")) && file.exists(file.path(td, "new_summary.txt")))
  n <- readRDS(file.path(td, "new_summary.rds"))
  expect_identical(n$heterogeneity_rows, "estimated"); expect_equal(n$global$n_imputed, 6L)
  expect_equal(n$run_meta, attr(dt, "run_meta"))
})
