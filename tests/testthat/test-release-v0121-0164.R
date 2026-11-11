# ============================================================================
# test-release-v0121-0164.R  (patch 0164, release v0.12.1: no re-estimation)
#
# v0.12.1 re-publishes two files that the v0.12.0 train wrote with code from
# before the sigma update: the product table (share_cells_own_sigma, patch
# 0163's definition) and the two Stage-2b summary files (the final pass's own
# structural defaults instead of build_config()'s placeholders). Locks:
#   1. scripts/rebuild_stage2b_summary.R --passes sets the four structural-
#      default fields from the last update pass (the level sigma; the median
#      prior, after the 2a2b rebuild where there was one) and lets nothing else
#      move; the manifest default path picks the pass log up and refuses one
#      that differs from the manifest;
#   2. analysis/product_summary.R --carry-reproducibility rebuilds the table and
#      its distribution and carries the census's odd/even and early/late blocks
#      unchanged; it refuses fresh halves beside them and a census without them;
#   3. analysis/stage2_reliability.R writes its JSON beside the record it is
#      given (results/<md name>.json), so runs that pass only --md no longer
#      overwrite one shared file;
#   4. the card: v0.12.1 on top with its data revision <fill> before the upload
#      and the hub oid after, v0.12.0 pinned at 73cf5702..., and no entry but
#      the top one carrying <fill> (patch 0162's card file had reverted the
#      v0.12.0 entry's revision, and no test caught it).
# ============================================================================

.r121_root <- function() dirname(locate_source_dir())
.r121_rs <- function() file.path(R.home("bin"), "Rscript")
.r121_run <- function(args) {
  out <- suppressWarnings(system2(.r121_rs(), args, stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}

# a scratch repo with the summary code, the rebuild tool, a Stage-2b table, the
# summary the unpatched runner wrote for it (placeholder defaults) and a pass log
.r121_summary_fixture <- function(dir, passes) {
  suppressPackageStartupMessages(library(data.table))
  env <- new.env(parent = globalenv())
  for (f in c("utils_general.R", "iteration_helpers.R", "output_paths.R", "summary.R"))
    sys.source(file.path(.r121_root(), "R", f), envir = env)
  set.seed(11L)
  dt <- rbindlist(lapply(1:9, function(k) data.table(
    importer = sprintf("I%02d", k), good = "0101", exporter = sprintf("E%d", 1:3),
    sigma = 2.678, gamma = exp(rnorm(3, -0.4, 0.6)), tier = c(0L, 1L, 1L), convergence = 0L)))
  dt[, `:=`(trim_reason = NA_character_, opt_tariff = 0.4)]
  setattr(dt, "run_meta", list(timestamp = as.POSIXct("2026-11-07 12:00:00", tz = "UTC")))
  cfg <- list(filepath = "BACI_HS92_V202601/", agg_level = "hs4", minyear = 1995L, maxyear = NA, min_exporters = 2L,
              min_destinations = 2L, min_periods = 3L, uv_outlier_threshold = 2, tail_trim_pct = 0.5,
              sigma_V_default = 2.88, gamma_V_default = 0.69, sigma_start = 2.88, gamma_start = 0.69, use_regions = FALSE)
  old <- env$build_summary(dt, cfg, scope = "country")
  old$run_meta <- attr(dt, "run_meta")
  for (d in c("R", "scripts", "data/derived/stage2b")) dir.create(file.path(dir, d), recursive = TRUE, showWarnings = FALSE)
  for (f in c("utils_general.R", "iteration_helpers.R", "output_paths.R", "summary.R"))
    file.copy(file.path(.r121_root(), "R", f), file.path(dir, "R"))
  file.copy(file.path(.r121_root(), "scripts", "rebuild_stage2b_summary.R"), file.path(dir, "scripts"))
  paths <- c(tab = "data/derived/stage2b/x_fixed_sigma.rds", sum = "data/derived/stage2b/x_summary.rds",
             pas = "data/derived/stage2b/x_sigma_update_passes.csv")
  saveRDS(dt, file.path(dir, paths[["tab"]])); saveRDS(old, file.path(dir, paths[["sum"]]))
  data.table::fwrite(passes, file.path(dir, paths[["pas"]]))
  list(paths = paths, old = old)
}
.r121_manifest <- function(dir, paths) {
  sha <- vapply(file.path(dir, paths), function(p) { con <- file(p, "rb"); on.exit(close(con)); tolower(unclass(as.character(openssl::sha256(con)))) }, "")
  utils::write.csv(data.frame(local_path = unname(paths), sha256 = unname(sha), hf_url = paste0("https://h/d/resolve/v0.12.1/", basename(paths))),
                   file.path(dir, "data", "manifest.csv"), row.names = FALSE)
}

test_that("rebuild --passes: the final pass's structural defaults, nothing else moves", {
  skip_if_not_installed("openssl"); skip_if_not_installed("data.table")
  td <- normalizePath(tempfile("r121_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  log2b <- data.frame(update_pass = 1L, cells_profiled = 27L, level_sigma = 2.678, shrink_b_full = 0.2548, scope = "2b",
                      prior_median_before = 0.6102, prior_median_after = NA_real_)
  fx <- .r121_summary_fixture(td, log2b)
  od <- setwd(td); on.exit(setwd(od), add = TRUE)
  r <- .r121_run(c(shQuote("scripts/rebuild_stage2b_summary.R"), "--table", fx$paths[["tab"]], "--summary", fx$paths[["sum"]],
                   "--passes", fx$paths[["pas"]], "--write", "out/x"))
  expect_identical(r$status, 0L, info = r$out)
  expect_match(r$out, "the provenance moved only in sigma_V_default, gamma_V_default, sigma_start, gamma_start", fixed = TRUE)
  new <- readRDS("out/x_summary.rds")
  expect_equal(new$provenance$sigma_V_default, 2.678); expect_equal(new$provenance$gamma_V_default, 0.6102)
  expect_equal(new$provenance$gamma_start, 0.6102); expect_true(is.na(new$provenance$sigma_start))
  for (k in c("performance", "quality", "failures", "table2", "within_het", "var_decomp"))     # values, not data.table index attributes
    expect_true(isTRUE(all.equal(new[[k]], fx$old[[k]], check.attributes = FALSE)), info = k)
  keep <- setdiff(names(fx$old$provenance), c("sigma_V_default", "gamma_V_default", "sigma_start", "gamma_start"))
  expect_equal(new$provenance[keep], fx$old$provenance[keep])
  txt <- paste(readLines("out/x_summary.txt", warn = FALSE), collapse = "\n")
  expect_match(txt, "Structural defaults:  sigma_V=2.678, gamma_V=0.610", fixed = TRUE)
  expect_match(txt, "Starting value:       gamma=0.610", fixed = TRUE)
  expect_false(grepl("2.880", txt, fixed = TRUE))
  # under the 2a2b scope the final pass ran on the rebuilt priors: prior_median_after
  data.table::fwrite(transform(log2b, scope = "2a2b", prior_median_after = 0.6213), fx$paths[["pas"]])
  r2 <- .r121_run(c(shQuote("scripts/rebuild_stage2b_summary.R"), "--table", fx$paths[["tab"]], "--summary", fx$paths[["sum"]],
                    "--passes", fx$paths[["pas"]], "--write", "out/y"))
  expect_identical(r2$status, 0L, info = r2$out)
  expect_equal(readRDS("out/y_summary.rds")$provenance$gamma_V_default, 0.6213)
  # an unshrunk update records no level: the sigma_V default is "not recorded", not a number the log lacks
  data.table::fwrite(transform(log2b, level_sigma = NA_real_, shrink_b_full = NA_real_), fx$paths[["pas"]])
  r3 <- .r121_run(c(shQuote("scripts/rebuild_stage2b_summary.R"), "--table", fx$paths[["tab"]], "--summary", fx$paths[["sum"]],
                    "--passes", fx$paths[["pas"]], "--write", "out/z"))
  expect_identical(r3$status, 0L, info = r3$out)
  expect_match(paste(readLines("out/z_summary.txt", warn = FALSE), collapse = "\n"), "sigma_V=not recorded, gamma_V=0.610", fixed = TRUE)
  # without --passes nothing in the provenance may move (the v0.11.4 behaviour)
  r4 <- .r121_run(c(shQuote("scripts/rebuild_stage2b_summary.R"), "--table", fx$paths[["tab"]], "--summary", fx$paths[["sum"]]))
  expect_identical(r4$status, 0L, info = r4$out)
  expect_match(r4$out, "provenance, performance, quality, failures and the global block are unchanged", fixed = TRUE)
})

test_that("rebuild, manifest default path: the pass log is picked up and checked against the manifest", {
  skip_if_not_installed("openssl"); skip_if_not_installed("data.table")
  td <- normalizePath(tempfile("r121m_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  fx <- .r121_summary_fixture(td, data.frame(update_pass = 1L, level_sigma = 2.678, scope = "2b", prior_median_before = 0.6102, prior_median_after = NA_real_))
  dir.create(file.path(td, "data"), showWarnings = FALSE)
  .r121_manifest(td, fx$paths)
  od <- setwd(td); on.exit(setwd(od), add = TRUE)
  r <- .r121_run(c(shQuote("scripts/rebuild_stage2b_summary.R"), "--write", "out/m"))
  expect_identical(r$status, 0L, info = r$out)
  expect_match(r$out, "inputs match the manifest's sha256", fixed = TRUE)
  expect_match(r$out, "structural defaults from x_sigma_update_passes.csv", fixed = TRUE)
  expect_equal(readRDS("out/m_summary.rds")$provenance$sigma_V_default, 2.678)
  cat("1,0,0,0\n", file = fx$paths[["pas"]], append = TRUE)                      # the log no longer matches its manifest row
  r2 <- .r121_run(c(shQuote("scripts/rebuild_stage2b_summary.R")))
  expect_identical(r2$status, 1L)
  expect_match(r2$out, "DIFFERS FROM THE MANIFEST: data/derived/stage2b/x_sigma_update_passes.csv", fixed = TRUE)
})

test_that("product table --carry-reproducibility: the table and distribution rebuilt, the census blocks carried", {
  skip_if_not_installed("jsonlite"); skip_if_not_installed("data.table")
  td <- normalizePath(tempfile("r121p_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  for (d in c("R", "analysis")) dir.create(file.path(td, d))
  file.copy(file.path(.r121_root(), "R", "utils_general.R"), file.path(td, "R"))
  file.copy(file.path(.r121_root(), "analysis", "product_summary.R"), file.path(td, "analysis"))
  s2b <- data.table::data.table(importer = rep(1:4, each = 2), exporter = rep(11:12, 4), good = rep(c("0101", "0202"), each = 4),
                                gamma = seq(0.5, 1.2, length.out = 8), tier = rep(c(0L, 1L), 4), convergence = 0L, avg_trade = 1,
                                sigma = rep(c(2.5, 2.9, 2.68, 2.7), each = 2),
                                sigma_source = rep(c("updated_import_shrunk", "updated_import_shrunk", "updated_level", "updated_import_shrunk"), each = 2),
                                opt_tariff = rep(c(0.6, 0.7, 0.8, 0.9), each = 2), trim_reason = NA_character_)
  saveRDS(s2b, file.path(td, "s2b.rds"))
  rep_block <- function(r1, r2) list(paths = c("..\\te_ship\\ship_odd\\x.rds", "..\\te_ship\\ship_even\\x.rds"),
                                     gamma_median = list(products = 25, spearman = r1, lo = r1 - 0.1, hi = r1 + 0.05, gap_median = 0.002, gap_p90 = 0.01),
                                     opt_tariff_median = list(products = 25, spearman = r2, lo = r2 - 0.1, hi = r2 + 0.05, gap_median = 0.003, gap_p90 = 0.02))
  old <- list(meta = list(timestamp = "2026-11-08 01:47:56 EST", git_rev = "2eae5c4"), reading = "publish",
              distribution = list(share_cells_own_sigma = list(p10 = 0, p25 = 0, p50 = 0, p75 = 0.006, p90 = 0.014)),
              odd_even = rep_block(0.93, 0.95), early_late = rep_block(0.63, 0.73))
  jsonlite::write_json(old, file.path(td, "ps.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
  od <- setwd(td); on.exit(setwd(od), add = TRUE)
  base <- c(shQuote("analysis/product_summary.R"), "--stage2b", "s2b.rds", "--table", "ps.csv", "--json", "ps.json", "--md", "ps.md")
  r <- .r121_run(c(base, "--carry-reproducibility"))
  expect_identical(r$status, 0L, info = r$out)
  new <- jsonlite::fromJSON("ps.json", simplifyVector = FALSE)
  expect_equal(new$odd_even, jsonlite::fromJSON(jsonlite::toJSON(old$odd_even, auto_unbox = TRUE, digits = NA), simplifyVector = FALSE))
  expect_equal(new$early_late$gamma_median$spearman, 0.63); expect_identical(new$reading, "publish")
  expect_equal(new$distribution$share_cells_own_sigma$p50, 0.75)               # 0101: both cells own; 0202: one of two
  expect_identical(new$meta$reproducibility_carried_from$git_rev, "2eae5c4")
  tab <- data.table::fread("ps.csv", colClasses = list(character = "good"))
  expect_equal(tab$share_cells_own_sigma, c(1, 0.5))
  md <- paste(readLines("ps.md", warn = FALSE), collapse = "\n")
  expect_match(md, "carried unchanged from the census of 2026-11-08 01:47:56 EST (rev 2eae5c4)", fixed = TRUE)
  expect_match(md, "| odd vs even years (within a period) | 25 | 0.93", fixed = TRUE)
  # refused: fresh halves beside the carried ones; a census with no odd/even block
  expect_false(identical(.r121_run(c(base, "--carry-reproducibility", "--odd", "s2b.rds", "--even", "s2b.rds"))$status, 0L))
  jsonlite::write_json(old[c("meta", "reading", "distribution")], "ps.json", auto_unbox = TRUE)
  expect_false(identical(.r121_run(c(base, "--carry-reproducibility"))$status, 0L))
})

test_that("stage2_reliability.R: the JSON follows the record", {
  e <- new.env(); assign("RELIABILITY_NO_MAIN", TRUE, envir = e)
  sys.source(file.path(.r121_root(), "analysis", "stage2_reliability.R"), envir = e)
  expect_identical(e$reliability_default_out("docs/results/stage2_reliability_ship.md"), "results/stage2_reliability_ship.json")
  expect_identical(e$reliability_default_out(NULL), "results/stage2_reliability.json")
  expect_true(file.exists(file.path(.r121_root(), "results", "stage2_reliability_Q.json")))
  expect_false(file.exists(file.path(.r121_root(), "results", "stage2_reliability.json")))
})

test_that("the card: v0.12.1 on top, v0.12.0 pinned, and only the top entry may lack its data revision", {
  card <- readLines(file.path(.r121_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  hi <- grep("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+ \\(", card)
  expect_match(card[hi[1]], "^> \\*\\*v0\\.12\\.1 \\(2026-11-(09|1[0-2])\\)\\.\\*\\*")
  entry <- paste(sub("^> ?", "", card[hi[1]:(hi[2] - 1L)]), collapse = " ")
  for (s in c("No re-estimation", "share_cells_own_sigma", "median 0, 90th percentile 0.014", "2.880", "0.690", "(2.678)",
              "rebuild_stage2b_summary.R --passes", "product_summary_census.md", "patches 0163\u20130164"))
    expect_true(grepl(s, entry, fixed = TRUE), info = s)
  expect_match(entry, "Data revision: `(<fill>|[0-9a-f]{40})`. \\*\\*v0\\.12\\.0 remains available pinned at revision `73cf5702564820d35260a87974aed2ceed9c4f45`\\.\\*\\*")
  fills <- grep("Data revision: `<fill>`", card)
  expect_lte(length(fills), 1L)
  if (length(fills)) expect_true(fills > hi[1] && fills < hi[2], info = "a <fill> outside the top entry")
  i0 <- grep("^> \\*\\*v0\\.12\\.0 ", card)
  expect_true(any(grepl("Data revision: `73cf5702564820d35260a87974aed2ceed9c4f45`", card[i0:(hi[match(i0, hi) + 1L] - 1L)], fixed = TRUE)))
})
