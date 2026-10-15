# ============================================================================
# test-audit8-0125.R  (patch 0125, audit #8: small fixes and two censuses)
#
#   1. classify_exporter_tiers(): an absent key takes build_config()'s value;
#   2. validate_cli_opts(): the option list is printed at the command line,
#      not under testthat;
#   3. the runner no longer ends by hashing the release files in data/derived;
#   4. analysis/region_map_census.R on a toy table;
#   5. analysis/reference_exporter_census.R: the bit count, the three reference
#      rules on a crafted cell, the observation counts, the Stage-1 rule against
#      prepare_cell_moments() itself on a synthetic world, the reading;
#   6. the methodology note on the two stages' references.
# ============================================================================

.a25_root <- function() dirname(locate_source_dir())

test_that("tier thresholds: an absent key takes the value build_config() ships", {
  suppressPackageStartupMessages(library(data.table))   # the library's functions call data.table verbs unqualified
  for (f in c("R/utils_general.R", "R/estimate_cell_fixed_sigma.R")) source(file.path(.a25_root(), f), local = TRUE)
  dt <- data.table::data.table(exporter = rep(c(1L, 2L, 3L, 4L), times = c(3, 3, 2, 9)), t = c(1:3, 1:3, 1:2, 1:9))
  dests <- data.table::data.table(exporter = 1:4, n_dests_total = c(3L, 2L, 5L, 4L))
  shipped <- list(tier1_min_periods = 3L, tier1_min_dests = 2L, tier2_min_periods = 3L)   # build_config()'s values
  t_ship <- classify_exporter_tiers(dt, dests, shipped)
  t_none <- classify_exporter_tiers(dt, dests, list())
  expect_identical(t_none, t_ship)
  expect_identical(t_ship[order(exporter)]$tier, c(1L, 2L, 3L, 1L))
  cfg <- readLines(file.path(.a25_root(), "R", "build_config.R"), warn = FALSE)
  expect_true(any(grepl("tier1_min_periods = 3L", cfg, fixed = TRUE)) && any(grepl("tier2_min_periods = 3L", cfg, fixed = TRUE)))
})

test_that("validate_cli_opts() prints the option list at the command line, not under testthat", {
  source(file.path(.a25_root(), "R", "parse_cli.R"), local = TRUE)
  parser <- optparse::OptionParser(option_list = list(optparse::make_option("--data", type = "character", default = NULL)))
  old <- Sys.getenv("TESTTHAT")
  on.exit(Sys.setenv(TESTTHAT = old), add = TRUE)
  Sys.setenv(TESTTHAT = "true")
  out_test <- utils::capture.output(try(validate_cli_opts(list(data = ""), parser), silent = TRUE))
  expect_length(out_test, 0L)
  Sys.setenv(TESTTHAT = "")
  out_cli <- utils::capture.output(try(validate_cli_opts(list(data = ""), parser), silent = TRUE))
  expect_true(any(grepl("--data", out_cli, fixed = TRUE)))
})

test_that("the runner no longer hashes the release files at the end of a run", {
  run <- readLines(file.path(.a25_root(), "scripts", "run_estimation.R"), warn = FALSE, encoding = "UTF-8")
  expect_false(any(grepl("openssl::sha256", run, fixed = TRUE)))
  expect_true(any(grepl("(patch 0125) The run no longer ends by hashing the files named in", run, fixed = TRUE)))
})

test_that("region map census: unmapped codes and their shares", {
  e <- new.env(); sys.source(file.path(.a25_root(), "analysis", "region_map_census.R"), envir = e)
  raw <- data.table::data.table(year = 2001L, good = "0101", importer = c(842L, 842L, 999L), exporter = c(276L, 998L, 276L),
                                cusval = c(900, 60, 40), quantity = 1)
  r <- e$region_map_census(raw, region_codes = c(842L, 276L))
  expect_setequal(r$unmapped$code, c(998L, 999L))
  expect_equal(r$unmapped_importer_value_share, 0.04)
  expect_equal(r$unmapped_exporter_value_share, 0.06)
  expect_identical(r$reading, "map them")
  expect_identical(e$region_map_census(raw[1], c(842L, 276L))$reading, "negligible")
})

test_that("reference census: bit count, the three rules, observation counts, reading", {
  e <- new.env(); sys.source(file.path(.a25_root(), "analysis", "reference_exporter_census.R"), envir = e)
  expect_identical(e$popcount(c(0L, 1L, 3L, 1023L, bitwShiftL(1L, 29L), 1073741823L)), c(0L, 1L, 2L, 10L, 1L, 30L))
  # one cell, 2001-2006. Exporter 1: five level years with a gap (2001-2002, 2004-2006) -> 3 differences, most
  # level years; exporter 2: four consecutive years (2003-2006) -> 3 differences, one a x20 unit-value jump;
  # exporter 3: four consecutive years (2001-2004) -> 3 differences, more value than 2.
  raw <- data.table::rbindlist(list(
    data.table::data.table(year = c(2001L, 2002L, 2004L, 2005L, 2006L), exporter = 1L, cusval = 10, quantity = 1),
    data.table::data.table(year = 2003:2006, exporter = 2L, cusval = c(5, 5, 100, 5), quantity = c(1, 1, 0.25, 1)),
    data.table::data.table(year = 2001:2004, exporter = 3L, cusval = 50, quantity = 1)))
  raw[, `:=`(good = "0101", importer = 842L)]
  p <- e$ref_exporter_panel(raw)
  expect_identical(p[order(exporter)]$n_levels, c(5L, 4L, 4L))
  expect_identical(p[order(exporter)]$n_dif, c(3L, 3L, 3L))
  expect_identical(p[order(exporter)]$n_dif_trim, c(3L, 1L, 3L))    # exporter 2's 2004->2005 and 2005->2006 steps jump by ln 80
  expect_identical(e$ref_exporter_pick(p, "stage1")$ref, 1L)       # most level years
  expect_identical(e$ref_exporter_pick(p, "stage2")$ref, 3L)       # 3 retained differences, more value than 1
  expect_identical(e$ref_exporter_pick(p, "stage1_dif")$ref, 3L)   # ties on differences, value decides
  o1 <- e$ref_exporter_obs(p, e$ref_exporter_pick(p, "stage1"))
  # reference 1 has differences in 2002, 2005, 2006; exporter 2 in 2004-2006 (shares 2005, 2006); exporter 3 in 2002-2004 (shares 2002)
  expect_identical(o1$obs, 3L)
  oa <- e$ref_exporter_obs(p, e$ref_exporter_pick(p, "stage1_dif"))
  # reference 3: 2002-2004; exporter 1 shares 2002; exporter 2 shares 2004
  expect_identical(oa$obs, 2L)
  # best of the candidates: references 1 and 2 both share 3 years with the others; 2 has more value
  rb <- e$ref_exporter_best(p)
  expect_identical(rb$ref, 2L)
  expect_identical(e$ref_exporter_obs(p, rb)$obs, 3L)
})

test_that("reference census: the Stage-1 rule is prepare_cell_moments()'s, cell by cell", {
  for (f in c("R/utils_general.R", "R/liml_estimator.R")) source(file.path(.a25_root(), f), local = TRUE)
  sb <- new.env(); sys.source(file.path(.a25_root(), "validation", "synthetic_baci.R"), envir = sb)
  e <- new.env(); sys.source(file.path(.a25_root(), "analysis", "reference_exporter_census.R"), envir = e)
  d <- tempfile("rc_"); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  sb$make_synthetic_baci_dir(d, n_goods = 2L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L), years = 2001:2012, seed = 11L)
  x <- data.table::rbindlist(lapply(list.files(d, full.names = TRUE), data.table::fread, colClasses = list(character = "k")))
  x <- x[!is.na(q) & q > 0 & v > 0][, .(cusval = sum(v), quantity = sum(q)),
                                     by = .(year = t, good = substr(formatC(as.integer(k), width = 6, flag = "0"), 1, 4), importer = j, exporter = i)]
  r1 <- e$ref_exporter_pick(e$ref_exporter_panel(x), "stage1")
  chk <- x[, .(ref_pcm = as.integer(prepare_cell_moments(data.frame(exporter = exporter, t = year, value = cusval, quantity = quantity),
                                                          exporter_col = "exporter", time_col = "t", value_col = "value",
                                                          quantity_col = "quantity")$ref_exporter)), by = .(importer, good)]
  m <- merge(chk[!is.na(ref_pcm)], r1, by = c("importer", "good"))
  expect_gt(nrow(m), 5L)
  expect_identical(m$ref_pcm, m$ref)
})

test_that("reference census reading and the methodology note", {
  e <- new.env(); sys.source(file.path(.a25_root(), "analysis", "reference_exporter_census.R"), envir = e)
  src <- paste(readLines(file.path(.a25_root(), "analysis", "reference_exporter_census.R"), warn = FALSE), collapse = "\n")
  expect_match(src, 'reading = if (share_trigger >= cell_share_threshold) "run the A/B" else "closed")', fixed = TRUE)
  doc <- paste(readLines(file.path(.a25_root(), "docs", "methodology", "stage2_country.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(doc, "### Reference exporters in the two stages (patch 0125)", fixed = TRUE)
})
