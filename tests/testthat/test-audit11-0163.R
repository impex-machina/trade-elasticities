# ============================================================================
# test-audit11-0163.R  (patch 0163, fresh-eyes audit #11: what v0.12.0's sigma
# update left behind in the analysis layer and the generated documents)
#
#   1. sigma_is_cell_specific(): the one definition of "the row's sigma is the
#      cell's own" -- the update's labels count, the level and the fallbacks do
#      not -- and the three readers that tested `sigma_source == "estimated"`
#      (the product table's share_cells_own_sigma, the pillar-1 console line,
#      the fallback-hierarchy census) no longer do;
#   2. the product table on a v0.12.0-style table: the share is the share of
#      cells with their own sigma, not ~0; unchanged on a pre-update table;
#   3. the fallback-hierarchy census reads the STAGE-1 label column of a table
#      that carries the update;
#   4. stage2_summary_cfg(): a summary reports the stage's own defaults, or NA
#      for a table loaded from a file; the runner hands them over;
#   5. paired_gain_cluster_boot(): the gain, reproducible draws, and a case
#      where resampling goods widens an interval that resampling cells does not;
#   6. md_table_cell_mismatches(): an unescaped "|" in a table cell is caught,
#      an escaped one is not, the builder stops on such a row, and the
#      generated README has none (v0.12.0's `sigma` row had two: GitHub cut the
#      cell there and did not show the rest);
#   7. the generated documents say what the table holds: gamma_se_total on no
#      row, gamma_exposure as a count of moment rows, the level sigma's cells.
# ============================================================================

.a63_root <- function() dirname(locate_source_dir())
.a63_env <- function(files) {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in files) sys.source(file.path(.a63_root(), f), envir = e)
  e
}
# a top-level function of a SCRIPT (one that runs when sourced), by name
.a63_script_fn <- function(script, name) {
  ex <- parse(file.path(.a63_root(), script), keep.source = FALSE)
  hit <- Filter(function(x) is.call(x) && identical(x[[1L]], as.name("<-")) && identical(x[[2L]], as.name(name)), ex)
  if (length(hit) != 1L) stop("expected one top-level definition of ", name, " in ", script)
  eval(hit[[1L]][[3L]], envir = baseenv())
}

test_that("sigma_is_cell_specific: the update's labels are a cell's own sigma; the level and the fallbacks are not", {
  e <- .a63_env("R/utils_general.R")
  lab <- c("estimated", "updated_import", "updated_import_shrunk", "updated_level",
           "fallback_no_estimate", "fallback_sigma_edge", "fallback_sigma_pole", NA)
  expect_identical(e$sigma_is_cell_specific(lab), c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  root <- .a63_root()
  rd <- function(f) paste(readLines(file.path(root, f), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  # the readers: none decides "own sigma" by the label "estimated" alone any more
  p1 <- rd("analysis/01_pillar1_empirical_overview.R"); ps <- rd("analysis/product_summary.R"); hc <- rd("analysis/sigma_fallback_hierarchy_census.R")
  code <- function(txt) paste(grep("^\\s*#", strsplit(txt, "\n", fixed = TRUE)[[1L]], invert = TRUE, value = TRUE), collapse = "\n")
  expect_false(grepl("sigma_source %in% \"estimated\"", code(p1), fixed = TRUE))
  expect_match(code(p1), "sigma_is_cell_specific(s2$sigma_source)", fixed = TRUE)
  expect_false(grepl("sigma_source[1L] == \"estimated\"", code(ps), fixed = TRUE))
  expect_match(code(ps), "sigma_is_cell_specific(sigma_source[1L])", fixed = TRUE)
  expect_false(grepl("pub[sigma_source != \"estimated\"", code(hc), fixed = TRUE))
  expect_match(code(hc), "sigma_stage1_label_column(pub)", fixed = TRUE)
})

test_that("product table: share_cells_own_sigma counts the cells with their own sigma on a table that carries the update", {
  e <- .a63_env(c("R/utils_general.R", "analysis/product_summary.R"))
  mk <- function(src) data.table::data.table(
    importer = rep(1:4, each = 2), exporter = rep(11:12, 4), good = "0101",
    gamma = seq(0.5, 1.2, length.out = 8), tier = rep(c(0L, 1L), 4), convergence = 0L, avg_trade = 1,
    sigma = rep(c(2.5, 2.9, 2.68, 2.68), each = 2), sigma_source = rep(src, each = 2),
    opt_tariff = rep(c(0.6, 0.7, 0.8, 0.9), each = 2), trim_reason = NA_character_)
  # v0.12.0: two cells with a shrunk update, one at the level (cap / floor profile), one fallback (no import rows)
  t12 <- e$product_summary(mk(c("updated_import_shrunk", "updated_import_shrunk", "updated_level", "fallback_no_estimate")))
  expect_equal(t12$share_cells_own_sigma, 0.5)          # through patch 0162: 0
  # a cell that keeps its Stage-1 sigma still counts, and so does an unshrunk update
  t12b <- e$product_summary(mk(c("estimated", "updated_import", "updated_level", "updated_level")))
  expect_equal(t12b$share_cells_own_sigma, 0.5)
  # a table from before the update: the old and the new definition coincide
  t11 <- e$product_summary(mk(c("estimated", "estimated", "fallback_sigma_pole", "estimated")))
  expect_equal(t11$share_cells_own_sigma, 0.75)
  expect_equal(t12$sigma_median, stats::median(c(2.5, 2.9, 2.68, 2.68)))
})

test_that("fallback-hierarchy census: the cells without a Stage-1 sigma are read from sigma_source_stage1 where the table has it", {
  root <- .a63_root()
  for (f in c("R/utils_general.R", "R/region_map.R", "R/iteration_helpers.R")) source(file.path(root, f), local = FALSE)
  env <- new.env(); sys.source(file.path(root, "analysis", "sigma_fallback_hierarchy_census.R"), envir = env)
  set.seed(8)
  goods <- sprintf("%04d", 1:20); imps <- c(36L, 76L, 124L, 156L, 276L, 251L, 826L, 380L, 392L, 484L, 643L, 842L)
  s1 <- data.table::CJ(importer = imps, good = goods)
  gsig <- setNames(1 + exp(rnorm(length(goods), log(2), 0.8)), goods)
  s1[, sigma := 1 + (gsig[good] - 1) * exp(rnorm(.N, 0, 0.15))]
  s1[, `:=`(status = "ok", convergence = 0L, sigma_se = 0.1 * sigma, sigma_capped = FALSE)]
  s1[sample(.N, 30), sigma_se := 5]                                   # 30 cells the pole rule drops
  s1[, importer := as.character(importer)]
  sc <- stage2_sigma_clean(s1, "fallback", "fallback", 1)
  old <- merge(s1[, .(importer, good, exporter = "x", tier = 1L, convergence = 0L)], sc$source, by = c("importer", "good"), all.x = TRUE)
  old[is.na(sigma_source), sigma_source := "fallback_no_estimate"]
  # the same table as v0.12.0 publishes it: the Stage-1 label moves to sigma_source_stage1, sigma_source says "updated_*"
  new <- data.table::copy(old)
  new[, sigma_source_stage1 := sigma_source][, sigma_source := "updated_import_shrunk"]
  new[sample(.N, 12), sigma_source := "updated_level"]
  expect_identical(env$sigma_stage1_label_column(old), "sigma_source")
  expect_identical(env$sigma_stage1_label_column(new), "sigma_source_stage1")
  r_old <- env$sigma_hierarchy_census(s1, old, k = 3L)
  r_new <- env$sigma_hierarchy_census(s1, new, k = 3L)
  n_fb <- sum(old$sigma_source != "estimated")
  expect_identical(r_old$fallback$cells, n_fb)
  expect_identical(r_new$fallback$cells, n_fb)                        # through patch 0162: every cell of the table (240)
  expect_lt(r_new$fallback$cells, nrow(new))
  expect_equal(r_new$fallback$by_source, r_old$fallback$by_source)     # labelled by the Stage-1 status, as before the update
  expect_equal(r_new$loo, r_old$loo)
})

test_that("stage2_summary_cfg: a summary reports the stage's own defaults, and the runner hands them over", {
  e <- .a63_env(c("R/utils_general.R", "R/summary.R"))
  base <- list(filepath = "x/BACI_HS92_V202601", agg_level = "hs4", sigma_V_default = 2.88, gamma_V_default = 0.69,
               sigma_start = 2.88, gamma_start = 0.69, min_exporters = 2L)
  got <- e$stage2_summary_cfg(base, list(sigma_V_default = 2.678, gamma_V_default = 0.61, sigma_start = 2.47, gamma_start = 0.61, sigma_lookup = 1:3))
  expect_equal(unlist(got[c("sigma_V_default", "gamma_V_default", "sigma_start", "gamma_start")], use.names = FALSE), c(2.678, 0.61, 2.47, 0.61))
  expect_identical(got$min_exporters, 2L); expect_null(got$sigma_lookup)        # the base config otherwise; no lookup table rides along
  none <- e$stage2_summary_cfg(base, NULL)                                    # a table loaded from a file
  expect_true(all(is.na(unlist(none[c("sigma_V_default", "gamma_V_default", "sigma_start", "gamma_start")]))))
  part <- e$stage2_summary_cfg(base, list(sigma_V_default = 3))               # a stage config without a field
  expect_equal(part$sigma_V_default, 3); expect_true(is.na(part$gamma_V_default))
  run <- paste(readLines(file.path(.a63_root(), "scripts", "run_estimation.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(run, "write_estimation_summary(regional_results, summary_cfg_regional, out_base_regional", fixed = TRUE)
  expect_match(run, "write_estimation_summary(country_results, summary_cfg_country, out_base_country", fixed = TRUE)
  expect_match(run, "summary_cfg_regional <- stage2_summary_cfg(config, config_2a)", fixed = TRUE)
  expect_match(run, "summary_cfg_country <- stage2_summary_cfg(config, config_2b)", fixed = TRUE)
  expect_false(grepl("write_estimation_summary(country_results, config,", run, fixed = TRUE))
  smy <- paste(readLines(file.path(.a63_root(), "R", "summary.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(smy, "not recorded", fixed = TRUE)
})

test_that("paired_gain_cluster_boot: the gain, reproducible draws, and goods that do not agree", {
  e <- .a63_env("R/utils_general.R")
  set.seed(3)
  # 20 goods x 60 cells; predictor b is closer in 12 goods and farther in 8, by the same amount
  good <- rep(sprintf("%04d", 1:20), each = 60L)
  shift <- rep(c(rep(0.2, 12), rep(-0.2, 8)), each = 60L)
  d_b <- rep(1, length(good)); d_a <- 1 + shift + rnorm(length(good), 0, 0.01)
  byg <- e$paired_gain_cluster_boot(d_a, d_b, cluster = good, B = 800L, seed = 7L)
  byc <- e$paired_gain_cluster_boot(d_a, d_b, cluster = seq_along(good), B = 800L, seed = 7L)
  expect_equal(byg$gain, stats::median(d_a) - stats::median(d_b)); expect_equal(byc$gain, byg$gain)
  expect_identical(byg$clusters, 20L); expect_identical(byc$clusters, length(good))
  expect_gt(byc$lo, 0)                       # cells drawn one by one: the majority sign looks certain
  expect_lt(byg$lo, 0)                       # goods drawn: 8 of 20 goods go the other way, and the interval says so
  expect_gt(byg$hi - byg$lo, 3 * (byc$hi - byc$lo))
  expect_gt(byg$share_le_0, 0.05); expect_lt(byc$share_le_0, 0.01)
  again <- e$paired_gain_cluster_boot(d_a, d_b, cluster = good, B = 800L, seed = 7L)
  expect_identical(again[c("lo", "hi", "share_le_0")], byg[c("lo", "hi", "share_le_0")])
  one <- e$paired_gain_cluster_boot(d_a, d_b, cluster = rep("0101", length(good)))
  expect_true(is.na(one$lo) && is.na(one$hi)); expect_identical(one$clusters, 1L)
  expect_error(e$paired_gain_cluster_boot(1:3, 1:2, 1:3), "same length")
  # the window census resamples goods and keeps both directions of a cell together
  cen <- paste(readLines(file.path(.a63_root(), "analysis", "sigma_update_window_census.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(cen, "paired_gain_cluster_boot(pr$d_lev, pr$d_shr, cluster = rep(cu$good, 2L)", fixed = TRUE)
  expect_match(cen, "robust <- isTRUE(gb$lo > 0)", fixed = TRUE)
})

test_that("md_table_cell_mismatches: an unescaped bar in a cell is caught, and the generated README has none", {
  mm <- .a63_script_fn("scripts/build_readme.R", "md_table_cell_mismatches")
  ok <- c("text", "| Column | Meaning |", "|---|---|", "| `a` | plain |", "| `b` | escaped \\|x\\| stays one cell |", "", "after")
  expect_identical(mm(ok), integer(0))
  bad <- ok; bad[5L] <- "| `b` | the median |x| splits the cell and the rest is dropped |"
  expect_identical(mm(bad), 5L)
  expect_identical(mm(c("| a | b | c |", "|:--|--:|---|", "| 1 | 2 | 3 |", "| 1 | 2 |")), 4L)     # too few cells is a mismatch too
  expect_identical(mm(c("no table here", "| a line that starts with a bar but is not a table |")), integer(0))
  root <- .a63_root()
  for (f in c("README.md", file.path("docs", "known_limitations_record.md"))) {
    lines <- readLines(file.path(root, f), warn = FALSE, encoding = "UTF-8")
    expect_identical(mm(lines), integer(0), info = f)
  }
  readme <- readLines(file.path(root, "README.md"), warn = FALSE, encoding = "UTF-8")
  sig <- grep("^\\| `sigma` \\|", readme, value = TRUE)
  expect_length(sig, 1L)
  expect_match(sig, "likely overstated by 5\u20139% on average", fixed = TRUE)     # the sentence GitHub did not show in v0.12.0's row
  expect_false(grepl("(median |", sig, fixed = TRUE))
  # the builder refuses to write such a row: the template with the sigma row's bars unescaped again -- as v0.12.0
  # had them -- stops the build with status 3 and writes nothing
  skip_if_not_installed("glue"); skip_if_not_installed("jsonlite")
  tpl <- paste(readLines(file.path(root, "README.template.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  esc <- "(median \\|\u0394 ln(\u03c3 \u2212 1)\\| 0.97, r 0.04)"
  expect_true(grepl(esc, tpl, fixed = TRUE))
  bad_tpl <- sub(esc, "(median |\u0394 ln(\u03c3 \u2212 1)| 0.97, r 0.04)", tpl, fixed = TRUE)
  td <- tempfile("te_0163_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  for (d in c("scripts", "results", "data", "docs")) dir.create(file.path(td, d))
  file.copy(file.path(root, "scripts", "build_readme.R"), file.path(td, "scripts"))
  file.copy(list.files(file.path(root, "results"), pattern = "\\.json$", full.names = TRUE), file.path(td, "results"))
  file.copy(file.path(root, "data", "manifest.csv"), file.path(td, "data"))
  file.copy(file.path(root, "docs", "known_limitations_record.template.md"), file.path(td, "docs"))
  con <- file(file.path(td, "README.template.md"), open = "wb", encoding = "UTF-8"); writeLines(enc2utf8(bad_tpl), con, useBytes = TRUE); close(con)
  out_md <- file.path(td, "R.md")
  prev <- Sys.getenv(c("README_BUILD_OUTPUT", "README_RECORD_BUILD_OUTPUT"), unset = NA)
  Sys.setenv(README_BUILD_OUTPUT = out_md, README_RECORD_BUILD_OUTPUT = file.path(td, "K.md"))
  on.exit(for (nm in names(prev)) if (is.na(prev[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, stats::setNames(list(prev[[nm]]), nm)), add = TRUE)
  owd <- setwd(td); on.exit(setwd(owd), add = TRUE)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), shQuote(file.path("scripts", "build_readme.R")), stdout = TRUE, stderr = TRUE))
  setwd(owd)
  expect_identical(attr(out, "status"), 3L, info = paste(utils::tail(out, 5), collapse = "\n"))
  expect_true(any(grepl("table row(s) whose cell count differs", out, fixed = TRUE)))
  expect_false(file.exists(out_md))
})

test_that("the generated documents say what the v0.12.0 table holds", {
  root <- .a63_root()
  txt <- generated_docs_text(root)                                            # README.md + the long-form record
  readme <- paste(readLines(file.path(root, "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  s2b <- jsonlite::fromJSON(file.path(root, "results", "stage2b_summary.json"), simplifyVector = FALSE)
  if (isTRUE(s2b$sigma_update$present) && identical(as.numeric(s2b$sigma_robust$robust), 0)) {
    # gamma_se_total is written only where sigma_robust is TRUE: with no such row the column is NA throughout
    expect_match(readme, "which no row of this release is", fixed = TRUE)
    expect_match(readme, "so it is `NA` throughout", fixed = TRUE)
    expect_match(readme, "No row of this release is `TRUE`, so the column cannot serve as a filter here", fixed = TRUE)
    expect_false(grepl("which leaves it populated only among", txt, fixed = TRUE))
    expect_false(grepl("only on the rows that\n  keep a Stage-1", txt, fixed = TRUE))
    expect_match(txt, "since v0.12.0 on no row", fixed = TRUE)
    # the level sigma: who carries it since the update
    expect_match(readme, "every cell with import rows is profiled whatever its Stage-1 status", fixed = TRUE)
    expect_false(grepl("takes the global fallback \u03c3", readme, fixed = TRUE))
  }
  expect_match(readme, "| `gamma_exposure` | Number of moment rows that involve the row's \u03b3", fixed = TRUE)
  expect_false(grepl("Number of exporters in the estimating set for the cell", readme, fixed = TRUE))
  expect_match(readme, "carried over from the \u03b3_V-final table", fixed = TRUE)
  expect_match(readme, "has not been measured", fixed = TRUE)                    # the update's sensitivity to the unit-value trim
  expect_match(readme, "resamples cell-directions", fixed = TRUE)
  expect_false(grepl("small, robust margin", readme, fixed = TRUE))
  # the product table's sigma: near the level, not on it, once the census shows a spread
  ps <- jsonlite::fromJSON(file.path(root, "results", "product_summary_census.json"), simplifyVector = FALSE)
  d <- ps$distribution$sigma_median; lvl <- as.numeric(s2b$sigma_provenance$fallback_value)
  if (!is.null(d) && (abs(as.numeric(d$p10) - lvl) > 5e-4 || abs(as.numeric(d$p90) - lvl) > 5e-4)) {
    expect_match(readme, "A product's median \u03c3 stays close to the level", fixed = TRUE)
    expect_false(grepl("for nearly every product", readme, fixed = TRUE))
  }
  # the card carries the corrections, and the legacy filter section of the methodology note is marked
  card <- paste(readLines(file.path(root, "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(card, "**Corrections (2026-11-09, patch 0163; no estimate changes).**", fixed = TRUE)
  expect_match(card, "It is populated on\nno row", fixed = TRUE)
  expect_match(card, "Addendum 2026-11-09 (patch 0163)", fixed = TRUE)
  meth <- paste(readLines(file.path(root, "docs", "methodology", "stage2_country.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(meth, "do not\n> apply it to a published table", fixed = TRUE)
  q <- paste(readLines(file.path(root, "docs", "next_session_queue.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("No change is queued.", q, fixed = TRUE))
})
