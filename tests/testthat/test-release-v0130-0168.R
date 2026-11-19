# ============================================================================
# test-release-v0130-0168.R  (patch 0168, release v0.13.0: the Stage-2b
# re-estimation under the configuration of patches 0165-0167, two gamma_V
# refreshes)
#
# Locks:
#   1. the CLI: two gamma_V refreshes by default (one in patch 0167), the
#      runner's echo of an absent option says the same;
#   2. analysis/00_setup.R's refresh block: the run's _gamma_v_refresh.csv and
#      gamma_v_resid over the published rows, and the pass-log columns of
#      patches 0161 and 0167 in the sigma_update block;
#   3. analysis/sigma_update_sensitivity_census.R on a two-refresh run: the
#      adoption rule read on the first refresh, the second-refresh rule of
#      patch 0167 on the second, every step in the record;
#   4. analysis/product_summary.R: a carry of a carry keeps the measurement's
#      date and rev, and --carried-release names the configuration the rows
#      were measured on and says they were not re-measured;
#   5. scripts/build_readme.R's v0.13.0 phrases: the v0.13.0 wording on a
#      summary with the new fields, the v0.12.x wording without them;
#   6. the card: v0.13.0 on top, <fill> before the upload and the hub oid after,
#      v0.12.1 pinned; the manifest ships the refresh log; one tag.
# ============================================================================

.r130_root <- function() dirname(locate_source_dir())
.r130_run <- function(args) {
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), args, stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}
# every top-level function of a script, defined in one environment (nothing else of the script runs)
.r130_fns <- function(script) {
  ex <- parse(file.path(.r130_root(), script), keep.source = FALSE)
  env <- new.env(parent = globalenv())
  for (x in ex)
    if (is.call(x) && identical(x[[1L]], as.name("<-")) && is.name(x[[2L]]) && is.call(x[[3L]]) && identical(x[[3L]][[1L]], as.name("function")))
      eval(x, envir = env)
  env
}
.r130_rd <- function(...) paste(readLines(file.path(.r130_root(), ...), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

test_that("CLI: two gamma_V refreshes by default; the runner's absent defaults agree", {
  src_dir <- locate_source_dir(); source(file.path(src_dir, "parse_cli.R"), local = TRUE)
  td <- tempfile("te_r130c_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  base <- c("--data", td, "--out-dir", td)
  expect_identical(parse_cli(args = base)$stage2_gamma_v_refresh, 2L)
  expect_identical(parse_cli(args = c(base, "--stage2-gamma-v-refresh", "1"))$stage2_gamma_v_refresh, 1L)
  expect_identical(parse_cli(args = c(base, "--stage2-gamma-v-refresh", "0"))$stage2_gamma_v_refresh, 0L)
  run <- .r130_rd("scripts", "run_estimation.R")
  expect_match(run, "gvr_n <- as.integer(opts$stage2_gamma_v_refresh %||% 2L)", fixed = TRUE)
  expect_match(run, 'if (is.null(opts$stage2_gamma_v_refresh)) 2L else as.integer(opts$stage2_gamma_v_refresh)', fixed = TRUE)
  expect_match(run, 'if (is.null(opts$stage2_sigma_profile)) "closed" else opts$stage2_sigma_profile', fixed = TRUE)
  cli <- .r130_rd("R", "parse_cli.R")
  expect_match(cli, '.gvr <- if (is.null(opts$stage2_gamma_v_refresh)) 2L else opts$stage2_gamma_v_refresh', fixed = TRUE)
})

test_that("00_setup.R: the refresh block reads the refresh log and gamma_v_resid; the pass-log rules reach the summary", {
  suppressPackageStartupMessages(library(data.table))
  src <- readLines(file.path(.r130_root(), "analysis", "00_setup.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^\\.su_src <- ", src); i1 <- grep("^rm\\(\\.gr_log, \\.gr, \\.gr_num", src)
  expect_length(i0, 1L); expect_length(i1, 1L)
  td <- tempfile("te_r130s_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  C <- "baci_hs92_v202601_elast_country_hs4"
  fwrite(data.table(update_pass = 1L, cells_profiled = 10L, cells_updated = 9L, at_floor = 0L, at_cap = 1L, level_sigma = 2.678,
                    shrink_b_half = 0.146, shrink_b_full = 0.2548, scope = "2a2b", prior_median_before = 0.753, prior_median_after = 0.770,
                    stage2a_rows = 40L, unprofiled = "level", cells_unprofiled_level = 3L, trim_sigma_tail = FALSE),
         file.path(td, paste0(C, "_sigma_update_passes.csv")))
  fwrite(data.table(refresh = 1:2, usable_rows = 9L, tier1_rows = 8L, tier1_abs_dlng_p90 = 0.1, rows = c(100L, 101L),
                    abs_dlng_p50 = c(6.7e-4, 8.6e-5), abs_dlng_p90 = c(0.026, 0.0041), abs_dlng_p99 = c(0.29, 0.088), abs_dlng_max = c(5, 4.6),
                    share_rows_gt_1pct = c(0.179, 0.058), cells = c(40L, 40L), share_cells_tariff_gt_1pct = c(0.403, 0.137), tariff_abs_dln_p50 = 1e-3),
         file.path(td, paste0(C, "_gamma_v_refresh.csv")))
  env <- new.env(parent = globalenv())
  env$DERIVED_S2B <- td
  env$stage2b_summary <- list()
  env$stage2b_dt <- data.table(sigma_source = c(rep("updated_import_shrunk", 6), "updated_level", "fallback_no_estimate"),
                               gamma_v_resid = c(1e-4, 2e-3, 0.02, NA, 5e-5, 1e-3, NA, NA))
  eval(parse(text = src[i0:i1]), envir = env)
  su <- env$stage2b_summary$sigma_update; gr <- env$stage2b_summary$gamma_v_refresh
  expect_identical(su$scope, "2a2b"); expect_identical(su$unprofiled, "level"); expect_identical(su$trim_sigma_tail, "FALSE")
  expect_equal(su$cells_unprofiled_level, 3); expect_equal(su$prior_median_after, 0.770); expect_identical(su$n_stage1, 0L)
  expect_true(gr$present); expect_identical(gr$n_refresh, 2L)
  expect_equal(gr$steps[[2]]$share_rows_gt_1pct, 0.058); expect_equal(gr$steps[[1]]$share_cells_tariff_gt_1pct, 0.403)
  expect_identical(gr$resid$n_filled, 5L); expect_identical(gr$resid$denominator, 8L); expect_equal(gr$resid$share_lt_1e2, 0.8)
  # a release without the refresh log: no steps, the resid still read from the table
  unlink(file.path(td, paste0(C, "_gamma_v_refresh.csv")))
  env$stage2b_summary <- list(); eval(parse(text = src[i0:i1]), envir = env)
  expect_false(env$stage2b_summary$gamma_v_refresh$present); expect_length(env$stage2b_summary$gamma_v_refresh$steps, 0L)
})

test_that("sensitivity census on a two-refresh run: ADOPT on the first, the 0167 rule on the second, both steps recorded", {
  suppressPackageStartupMessages(library(data.table))
  td <- normalizePath(tempfile("te_r130g_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  rf <- data.table(refresh = 1:2, usable_rows = 9L, tier1_rows = 8L, tier1_abs_dlng_p90 = 0.1, rows = c(4991241L, 4992802L),
                   abs_dlng_p50 = c(6.68e-4, 8.55e-5), abs_dlng_p90 = c(0.0257, 0.00413), abs_dlng_p99 = c(0.288, 0.0875), abs_dlng_max = c(5, 4.6),
                   share_rows_gt_1pct = c(0.179, 0.058), cells = c(211104L, 211113L), share_cells_tariff_gt_1pct = c(0.403, 0.137), tariff_abs_dln_p50 = 1e-3)
  fwrite(rf, file.path(td, "baci_hs92_v202601_elast_country_hs4_gamma_v_refresh.csv"))
  r <- .r130_run(c(shQuote(file.path(.r130_root(), "analysis", "sigma_update_sensitivity_census.R")), "--run", shQuote(td),
                   "--md", shQuote(file.path(td, "s.md")), "--json", shQuote(file.path(td, "s.json"))))
  expect_identical(r$status, 0L, info = r$out)
  j <- jsonlite::fromJSON(file.path(td, "s.json"), simplifyVector = FALSE)
  expect_identical(j$gamma_v_refresh$reading, "ADOPT"); expect_identical(j$gamma_v_refresh$refresh, 1L)
  expect_identical(j$gamma_v_refresh$second$reading, "TWO SHIP"); expect_identical(j$gamma_v_refresh$n_refresh, 2L)
  expect_length(j$gamma_v_refresh$steps, 2L)
  md <- paste(readLines(file.path(td, "s.md"), warn = FALSE), collapse = "\n")
  expect_match(md, "**Reading (the first refresh): ADOPT.**", fixed = TRUE)
  expect_match(md, "**Reading (the second refresh, rule of patch 0167): TWO SHIP.**", fixed = TRUE)
  expect_match(md, "| 2 | 4,992,802 | 8.55e-05 | 4.13e-03 | 8.75e-02 | 5.8% | 211,113 | 13.7% |", fixed = TRUE)
  e <- .r130_fns("analysis/sigma_update_sensitivity_census.R")
  low <- copy(rf)[2L, `:=`(share_rows_gt_1pct = 0.004, share_cells_tariff_gt_1pct = 0.009)]
  expect_identical(e$refresh_reading(low)$second$reading, "ONE SHIPS")
  expect_null(e$refresh_reading(rf[1L])$second)
  expect_identical(e$refresh_reading(rf[2:1])$refresh, 1L)                     # read in refresh order, whatever the file's
})

test_that("product table: a carry of a carry keeps the measurement; --carried-release says the rows were not re-measured", {
  skip_if_not_installed("jsonlite"); skip_if_not_installed("data.table")
  td <- normalizePath(tempfile("r130p_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  for (d in c("R", "analysis")) dir.create(file.path(td, d))
  file.copy(file.path(.r130_root(), "R", "utils_general.R"), file.path(td, "R"))
  file.copy(file.path(.r130_root(), "analysis", "product_summary.R"), file.path(td, "analysis"))
  s2b <- data.table::data.table(importer = rep(1:4, each = 2), exporter = rep(11:12, 4), good = rep(c("0101", "0202"), each = 4),
                                gamma = seq(0.5, 1.2, length.out = 8), tier = rep(c(0L, 1L), 4), convergence = 0L, avg_trade = 1,
                                sigma = 2.7, sigma_source = "updated_import_shrunk", opt_tariff = 0.8, trim_reason = NA_character_)
  saveRDS(s2b, file.path(td, "s2b.rds"))
  blk <- function(r1) list(paths = c("odd.rds", "even.rds"), gamma_median = list(products = 25, spearman = r1, lo = 0.9, hi = 1, gap_median = 0.002, gap_p90 = 0.007),
                           opt_tariff_median = list(products = 25, spearman = 0.97, lo = 0.88, hi = 0.99, gap_median = 0.03, gap_p90 = 0.117))
  # the v0.12.1 census: itself a carry of the 2026-11-08 measurement
  v121 <- list(meta = list(timestamp = "2026-11-10 22:01:11 EST", git_rev = "19a0fe5",
                           reproducibility_carried_from = list(timestamp = "2026-11-08 01:47:56 EST", git_rev = "2eae5c4")),
               reading = "publish", distribution = list(), odd_even = blk(1), early_late = blk(0.63))
  jsonlite::write_json(v121, file.path(td, "ps.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
  od <- setwd(td); on.exit(setwd(od), add = TRUE)
  base <- c(shQuote("analysis/product_summary.R"), "--stage2b", "s2b.rds", "--table", "ps.csv", "--json", "ps.json", "--md", "ps.md")
  r <- .r130_run(c(base, "--carry-reproducibility", "--carried-release", "v0.12.0"))
  expect_identical(r$status, 0L, info = r$out)
  j <- jsonlite::fromJSON("ps.json", simplifyVector = FALSE)
  expect_identical(j$meta$reproducibility_carried_from$git_rev, "2eae5c4")
  expect_identical(j$meta$reproducibility_carried_from$timestamp, "2026-11-08 01:47:56 EST")
  expect_identical(j$meta$reproducibility_carried_from$release, "v0.12.0")
  expect_identical(j$reading, "publish"); expect_equal(j$odd_even$gamma_median$spearman, 1)
  md <- paste(readLines("ps.md", warn = FALSE), collapse = "\n")
  expect_match(md, "carried from the census of 2026-11-08 01:47:56 EST (rev 2eae5c4), measured on the 2% subsample runs of the v0.12.0 configuration", fixed = TRUE)
  expect_match(md, "not re-measured on its configuration", fixed = TRUE)
  expect_false(grepl("which this rebuild does not change", md, fixed = TRUE))
  # a further carry without the flag keeps the release recorded before
  r2 <- .r130_run(c(base, "--carry-reproducibility"))
  expect_identical(r2$status, 0L, info = r2$out)
  expect_identical(jsonlite::fromJSON("ps.json", simplifyVector = FALSE)$meta$reproducibility_carried_from$release, "v0.12.0")
  # refused: --carried-release without --carry-reproducibility, or not a release tag
  expect_false(identical(.r130_run(c(base, "--carried-release", "v0.12.0"))$status, 0L))
  expect_false(identical(.r130_run(c(base, "--carry-reproducibility", "--carried-release", "0.12"))$status, 0L))
})

test_that("README phrases: the v0.13.0 wording on a summary with the new fields, the v0.12.x wording without", {
  skip_if_not_installed("jsonlite")
  e <- .r130_fns("scripts/build_readme.R")
  prov <- list(fallback_value = 2.6779, n_fallback = 56071, n_cap = 0, denominator = 6841382)
  su12 <- list(present = TRUE, n_shrunk = 6621807, n_unshrunk = 0, n_level = 147071, n_stage1 = 4646, n_fallback = 56071, denominator = 6829595,
               cells_profiled = 211313, cells_updated = 199857, at_floor = 61, at_cap = 11395, level_sigma = 2.6779, shrink_b_half = 0.146, shrink_b_full = 0.2548)
  su13 <- modifyList(su12, list(n_shrunk = 6630683, n_level = 154628, n_stage1 = 0, denominator = 6841382, cells_updated = 199888, at_floor = 42, at_cap = 11383,
                                scope = "2a2b", unprofiled = "level", cells_unprofiled_level = 1545, trim_sigma_tail = "FALSE", prior_median_after = 0.770))
  gvr <- list(present = TRUE, n_refresh = 2, steps = list(list(refresh = 1, share_rows_gt_1pct = 0.179, share_cells_tariff_gt_1pct = 0.403),
                                                          list(refresh = 2, share_rows_gt_1pct = 0.058, share_cells_tariff_gt_1pct = 0.137)),
              resid = list(n_filled = 4992802, denominator = 6841382, p50 = 8.56e-05, p90 = 0.00413, p99 = 0.0876, share_lt_1e2 = 0.942))
  s12 <- list(sigma_provenance = prov, sigma_update = su12, sigma_robust = list(robust = 0))
  s13 <- list(sigma_provenance = prov, sigma_update = su13, gamma_v_refresh = gvr, sigma_robust = list(robust = 0))
  # v0.13.0
  expect_match(e$overview_update_tail(s13), "since v0.13.0 Stage 2a is re-run at that σ and Stage 2b then runs at it three times, the last two", fixed = TRUE)
  expect_match(e$overview_2a_tail(s13), "the published Stage 2a is re-estimated at the region medians of the updated σ", fixed = TRUE)
  rows13 <- e$sigma_rows_sentence(s13)
  expect_match(rows13, "the 1,545 cells with a Stage-1 σ and no fitted exporter", fixed = TRUE)
  expect_match(rows13, "so no row keeps a Stage-1 σ.", fixed = TRUE)
  expect_match(rows13, "(11,383 and 42 of 211,313 profiled cells)", fixed = TRUE)
  g13 <- e$gvr_row_tail(s13)
  expect_match(g13, "the last of two γ_V refreshes", fixed = TRUE)
  expect_match(g13, "filled on 4,992,802 rows, median 8.6e-05, p90 0.0041, p99 0.088, below 0.01 on 94.2%", fixed = TRUE)
  expect_match(g13, "the first moved 17.9% of directly estimated rows by more than 1% and the `opt_tariff` of 40.3% of cells, the second 5.8% and 13.7%", fixed = TRUE)
  expect_match(e$trim_sigma_tail_sentence(s13, list(sigma_cap = 50)), "lies in [1.54, 4.96] by construction", fixed = TRUE)
  expect_match(e$estimated_gloss(s13), "no row of this release is `estimated`", fixed = TRUE)
  expect_match(e$updated_level_gloss(s13), "since v0.13.0", fixed = TRUE)
  expect_match(e$se_total_scope(s13, "bullet"), "since v0.13.0 no row keeps a Stage-1 σ", fixed = TRUE)
  expect_match(e$se_total_row_tail(s13), "since v0.13.0 no row keeps a Stage-1 σ", fixed = TRUE)
  expect_match(e$level_sigma_sentence(s13), "since v0.13.0 also to the 1,545 cells", fixed = TRUE)
  expect_match(e$sigma_row_pass_tail(s13), "followed by two γ_V refreshes; see `gamma_v_resid`", fixed = TRUE)
  # v0.12.x: the earlier wording, nothing about v0.13.0
  for (f in c("overview_update_tail", "overview_2a_tail", "sigma_rows_sentence", "gvr_row_tail", "estimated_gloss", "updated_level_gloss", "sigma_row_pass_tail"))
    expect_false(grepl("v0.13.0", e[[f]](s12), fixed = TRUE), info = f)
  expect_identical(e$trim_sigma_tail_sentence(s12, list(sigma_cap = 50)), "")
  expect_match(e$sigma_rows_sentence(s12), "and 0.1% keep a Stage-1 σ (cells with a Stage-1 σ and no fitted exporter", fixed = TRUE)
  expect_match(e$se_total_row_tail(s12), "the 0.1% of rows that keep a Stage-1 σ", fixed = TRUE)
  # the threshold phrase: the full-data census when there is one, the 2% one otherwise
  sub <- list(trim_grid = list(curve = list(list(threshold = "1.5", median_sigma = 3.2149), list(threshold = "2", median_sigma = 2.7479),
                                            list(threshold = "3", median_sigma = 2.4988), list(threshold = "off", median_sigma = 2.2860)),
                               between_1.5_and_3 = list(level_gap = 0.39, spearman = 0.59)))
  full <- list(key = "sigma_update_sensitivity_census_v0130",
               data = list(trim_grid = list(curve = list(list(threshold = "1.5", median_sigma = 3.2501), list(threshold = "2", median_sigma = 2.7351),
                                                         list(threshold = "3", median_sigma = 2.4791), list(threshold = "off", median_sigma = 2.2891)),
                                            between_1.5_and_3 = list(level_gap = 0.42, spearman = 0.61))))
  ph <- e$uv_threshold_phrase(full, sub)
  expect_match(ph, "on the full panel (the v0.13.0 run's diagnostic)", fixed = TRUE)
  expect_match(ph, "2.29 untrimmed, 2.48 at 3, 2.74 at the shipped 2 and 3.25 at 1.5", fixed = TRUE)
  expect_match(ph, "(the 2% subsample: 2.29 / 2.50 / 2.75 / 3.21; `docs/results/sigma_update_sensitivity_census_v0130.md`)", fixed = TRUE)
  expect_match(e$uv_threshold_phrase(full, sub, detail = TRUE), "0.42 apart between 1.5 and 3, with a Spearman correlation of 0.61", fixed = TRUE)
  ph2 <- e$uv_threshold_phrase(NULL, sub)
  expect_match(ph2, "on the 2% subsample, with γ held at its final values, the median updated σ is 2.29 untrimmed, 2.50 at 3, 2.75 at the shipped 2 and 3.21 at 1.5", fixed = TRUE)
  expect_match(ph2, "(`docs/results/sigma_update_sensitivity_census.md`)", fixed = TRUE)
  # the template calls the phrases
  tpl <- .r130_rd("README.template.md")
  for (s in c("{{overview_2a_tail(r$stage2b)}}", "{{overview_update_tail(r$stage2b)}}", "{{sigma_rows_sentence(r$stage2b)}}", "{{gvr_row_tail(r$stage2b)}}",
              "{{trim_sigma_tail_sentence(r$stage2b, r$stage1)}}", "{{updated_level_gloss(r$stage2b)}}", "{{estimated_gloss(r$stage2b)}}",
              "{{profile_method_phrase(SUSC)}}", "{{uv_threshold_phrase(SUSC_FULL, SUSC)}}"))
    expect_true(grepl(s, tpl, fixed = TRUE), info = s)
  expect_true(grepl("{{uv_threshold_phrase(SUSC_FULL, SUSC, detail = TRUE)}}", .r130_rd("docs", "known_limitations_record.template.md"), fixed = TRUE))
})

test_that("the card: v0.13.0 on top with the release numbers, v0.12.1 pinned, only the top entry may lack its revision", {
  card <- readLines(file.path(.r130_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  hi <- grep("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+ \\(", card)
  expect_match(card[hi[1]], "^> \\*\\*v0\\.13\\.0 \\(2026-11-(19|2[0-9])\\)\\.\\*\\*")
  entry <- paste(sub("^> ?", "", card[hi[1]:(hi[2] - 1L)]), collapse = " ")
  for (s in c("6,829,595 → 6,841,382", "0.8219 → 0.8262", "0.8976 → 0.8983", "17.9%", "40.3%", "5.8% and 13.7%",
              "`--stage2-gamma-v-refresh 2`", "0.753 → 0.770", "1,545", "`sigma_lo`", "[1.54, 4.96]", "_gamma_v_refresh.csv",
              "gate_v0130.md", "sigma_update_sensitivity_census_v0130.md", "646 → 678", "carried and not re-measured"))
    expect_true(grepl(s, entry, fixed = TRUE), info = s)
  expect_match(entry, "Data revision: `(<fill>|[0-9a-f]{40})`. \\*\\*v0\\.12\\.1 remains available pinned at revision `4c20c839c20ae0457c6f44146278a97fa1f3b29c`\\.\\*\\*")
  fills <- grep("Data revision: `<fill>`", card)
  expect_lte(length(fills), 1L)
  if (length(fills)) expect_true(fills > hi[1] && fills < hi[2], info = "a <fill> outside the top entry")
})

test_that("the manifest ships the refresh log beside the Stage-2b table, at one release tag", {
  man <- utils::read.csv(file.path(.r130_root(), "data", "manifest.csv"), stringsAsFactors = FALSE)
  tags <- unique(sub("^.*/resolve/([^/]+)/.*$", "\\1", man$hf_url))
  expect_length(tags, 1L); expect_match(tags, "^v[0-9]+\\.[0-9]+\\.[0-9]+$")
  # the release train registers the log when it pins v0.13.0; a tree still pinned to an earlier release
  # (the patch before its release commit) has nothing to check yet
  rel <- sum(as.numeric(strsplit(sub("^v", "", tags[1L]), ".", fixed = TRUE)[[1]]) * c(1e6, 1e3, 1))
  if (rel < 13000) skip(sprintf("the manifest still pins %s; the v0.13.0 release train registers the refresh log", tags[1L]))
  expect_true("data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_gamma_v_refresh.csv" %in% man$local_path)
})

test_that("the queue and the methodology note record v0.13.0", {
  q <- .r130_rd("docs", "next_session_queue.md"); m <- .r130_rd("docs", "methodology", "stage2_country.md")
  expect_match(q, "**Done -- release v0.13.0 (2026-11-19, patch 0168):**", fixed = TRUE)
  expect_match(q, "**Open after v0.13.0 (nothing queued as a default):**", fixed = TRUE)
  expect_match(m, "#### v0.13.0: the configuration as it ships, read on the full data (patches 0165–0168)", fixed = TRUE)
  expect_match(m, "#### The `2a2b` scope (patch 0161, `--stage2-sigma-update-scope 2a2b`; the default since patch 0167, `2b` before)", fixed = TRUE)
})
