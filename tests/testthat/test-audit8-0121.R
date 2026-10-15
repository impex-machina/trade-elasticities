# ============================================================================
# test-audit8-0121.R  (patch 0121, fresh-eyes audit #8: records and wording)
#
# Locks for the identities in 0121 (no estimate changes):
#   1. validation/synthetic_baci.R is deterministic given its seed and writes
#      BACI's layout (t, i, j, k, v, q) with HS6 codes missing their leading zero;
#   2. the README's tier thresholds are the ones build_config() ships;
#   3. each committed shrinkage-census markdown names the data-share formula its
#      JSON says it used (through 0120 the header always printed the legacy one);
#   4. the undated Pillar-3 per-param twin in docs/methodology is the newest
#      dated capture, and master.R --rerun-pillars refreshes it;
#   5. 00_setup.R counts fallback rows from sigma_source where the table has it.
# The behaviour behind 5 is exercised end to end in test-runner-e2e-smoke.R.
# ============================================================================

.a21_root <- function() dirname(locate_source_dir())
.a21_lines <- function(...) readLines(file.path(.a21_root(), ...), warn = FALSE, encoding = "UTF-8")

test_that("synthetic BACI generator: deterministic, BACI layout, truth returned", {
  sb <- new.env(); sys.source(file.path(.a21_root(), "validation", "synthetic_baci.R"), envir = sb)
  d1 <- tempfile("sb1_"); d2 <- tempfile("sb2_"); on.exit(unlink(c(d1, d2), recursive = TRUE), add = TRUE)
  args <- list(n_goods = 2L, countries = c(842L, 276L, 392L, 156L, 251L, 826L), years = 2001:2010, seed = 7L)
  t1 <- do.call(sb$make_synthetic_baci_dir, c(list(out_dir = d1), args))
  t2 <- do.call(sb$make_synthetic_baci_dir, c(list(out_dir = d2), args))
  f1 <- sort(list.files(d1, full.names = TRUE)); f2 <- sort(list.files(d2, full.names = TRUE))
  expect_length(f1, 10L)
  expect_identical(unname(tools::md5sum(f1)), unname(tools::md5sum(f2)))
  expect_identical(t1$gamma, t2$gamma)
  x <- data.table::fread(f1[1], colClasses = list(character = "k"))
  expect_identical(names(x), c("t", "i", "j", "k", "v", "q"))
  expect_true(any(nchar(x$k) == 5L))                         # "0101xx" written as "101xx", as BACI does
  expect_true(all(t1$sigma$sigma_true > 1) && all(t1$gamma$gamma_true > 0))
  expect_true(all(x$i != x$j))
})

test_that("README tier thresholds are build_config()'s", {
  cfg <- .a21_lines("R", "build_config.R")
  expect_true(any(grepl("tier1_min_periods = 3L", cfg, fixed = TRUE)))
  expect_true(any(grepl("tier1_min_dests   = 2L", cfg, fixed = TRUE)))
  expect_true(any(grepl("tier2_min_periods = 3L", cfg, fixed = TRUE)))
  tpl <- paste(.a21_lines("README.template.md"), collapse = "\n")
  expect_match(tpl, "at least 3 differenced years shared with the reference exporter in this market and at least 2 other destinations for the good", fixed = TRUE)
  expect_match(tpl, "trade being the pair's mean annual customs value over its years in the estimation panel", fixed = TRUE)
})

test_that("shrinkage-census markdown headers name the formula their JSON used", {
  js <- list.files(file.path(.a21_root(), "results"), pattern = "^stage2_shrinkage_census.*\\.json$", full.names = TRUE)
  expect_gt(length(js), 5L)
  for (j in js) {
    md <- file.path(.a21_root(), "docs", "results", sub("\\.json$", ".md", basename(j)))
    if (!file.exists(md)) next
    def <- jsonlite::fromJSON(j)$meta$shrink_wt_def
    want <- if (identical(def, "half")) "d = 1 - s" else "d = 2(1-s)/(2-s)"
    hdr <- grep("^## Q1 gamma_shrink_wt", readLines(md, warn = FALSE, encoding = "UTF-8"), value = TRUE)
    expect_length(hdr, 1L)
    expect_true(endsWith(hdr, want), info = basename(md))
  }
  src <- paste(.a21_lines("analysis", "stage2_shrinkage_census.R"), collapse = "\n")
  expect_match(src, 'if (identical(res$meta$shrink_wt_def, "legacy")) "2(1-s)/(2-s)" else "1 - s"', fixed = TRUE)
})

test_that("the undated Pillar-3 per-param twin is the newest dated capture", {
  meth <- file.path(.a21_root(), "docs", "methodology")
  dated <- sort(list.files(meth, pattern = "^se_calibration_mc_per_param_\\d{8}\\.csv$", full.names = TRUE), decreasing = TRUE)
  skip_if(length(dated) == 0L)
  norm <- function(p) sub("\r$", "", readLines(p, warn = FALSE))
  expect_identical(norm(file.path(meth, "se_calibration_mc_per_param.csv")), norm(dated[1]))
  ma <- paste(.a21_lines("analysis", "master.R"), collapse = "\n")
  expect_match(ma, 'file.copy(pp[1], file.path("docs/methodology", "se_calibration_mc_per_param.csv"),', fixed = TRUE)
})

test_that("00_setup.R counts fallback rows from sigma_source", {
  s <- paste(.a21_lines("analysis", "00_setup.R"), collapse = "\n")
  expect_match(s, 'sum(stage2b_dt$sigma_source != "estimated")', fixed = TRUE)
  expect_match(s, "n_fallback     = .n_fb,", fixed = TRUE)
})
