# ============================================================================
# test-measurements-0166.R  (patch 0166, fresh-eyes audit #11)
#
#   1. The 2% product sample no longer depends on the year window: the raw
#      cache carries the whole panel's products (attr "goods_universe", taken
#      before the window cuts the panel) and the draw uses them, so a window
#      missing one code keeps the other window's products. A cache written
#      before this patch has no attribute and falls back to its own products.
#      (The late window of 2026-11-11 drew from 1,239 of 1,240 codes and shared
#      4 of its 25 products with the early window.)
#   2. The README, the long-form record and the card state what the local
#      measurements of 2026-11-11 found, and the records they cite are in the
#      repo: the shrinkage gain's product-clustered interval, the threshold
#      curve, the effect of one gamma_V refresh, the closed-form profile.
# ============================================================================

.m66_root <- function() dirname(locate_source_dir())

test_that("sample_products_universe: the whole panel's products, whatever the window holds", {
  e <- new.env(); sys.source(file.path(.m66_root(), "R", "utils_general.R"), envir = e)
  suppressPackageStartupMessages(library(data.table))
  goods <- sprintf("%04d", seq(101, 9900, by = 8))                          # 1,225 codes
  full <- data.table(good = rep(goods, each = 2), x = 1)
  data.table::setattr(full, "goods_universe", goods)
  # a later window: one early code has no trade there, so the window's own list is one shorter
  late <- full[good != goods[3]]; data.table::setattr(late, "goods_universe", goods)
  a <- e$sample_products_universe(full, 0.02, 20260926L); b <- e$sample_products_universe(late, 0.02, 20260926L)
  expect_identical(a$keep, b$keep); expect_true(a$from_universe && b$from_universe)
  expect_identical(a$n_universe, length(goods)); expect_identical(b$n_universe, length(goods))
  expect_identical(a$n_absent, 0L); expect_identical(b$n_absent, as.integer(goods[3] %in% a$keep))
  # the bug this replaces: drawing from the window's own products shifts the draw
  old_late <- e$sample_products(late$good, 0.02, 20260926L)
  expect_lt(length(intersect(old_late, a$keep)), length(a$keep))
  # a cache from before this patch: no attribute -> its own products, flagged
  plain <- copy(late); data.table::setattr(plain, "goods_universe", NULL)
  c0 <- e$sample_products_universe(plain, 0.02, 20260926L)
  expect_false(c0$from_universe); expect_identical(c0$keep, old_late)
  # the full-period draw is the draw every earlier 2% run made (same 25 of 1,240 when the cache is the whole panel)
  expect_identical(a$keep, e$sample_products(full$good, 0.02, 20260926L))
})

test_that("prepare_raw_data: the universe is taken before the year window", {
  for (p in c("data.table")) skip_if_not_installed(p)
  root <- .m66_root(); src_dir <- locate_source_dir()
  td <- normalizePath(tempfile("te_m66_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  sb$make_synthetic_baci_dir(baci, n_goods = 4L, countries = c(842L, 276L, 392L, 156L, 251L, 826L), years = 2000:2013, seed = 7L)
  files <- list.files(baci, pattern = "\\.csv$", full.names = TRUE)
  yr <- as.integer(sub(".*_Y(\\d{4})_.*", "\\1", basename(files)))
  first <- data.table::fread(files[1], colClasses = list(character = "k"))
  gone4 <- substr(sort(unique(sprintf("%06d", as.integer(first$k))))[1], 1, 4)   # one HS4 product
  for (f in files[yr >= 2008]) {                                                  # ... with no trade from 2008 on
    d <- data.table::fread(f, colClasses = list(character = "k"))
    d <- d[substr(sprintf("%06d", as.integer(k)), 1, 4) != gone4]
    data.table::fwrite(d, f)
  }
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); if (file.exists(sink_file)) file.remove(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE); source(file.path(src_dir, "build_config.R"), local = FALSE)
  cfg_late <- build_config(list(data = baci, minyear = 2008L, maxyear = 2013L, agg_level = "hs4"))
  cfg_all <- build_config(list(data = baci, minyear = 2000L, maxyear = NA_integer_, agg_level = "hs4"))
  r_late <- prepare_raw_data(cfg_late); r_all <- prepare_raw_data(cfg_all)
  sink()
  expect_false(gone4 %in% r_late$good)                                           # the window has no rows for it ...
  expect_true(gone4 %in% attr(r_late, "goods_universe"))                         # ... but the universe keeps it
  expect_identical(attr(r_late, "goods_universe"), attr(r_all, "goods_universe"))
  expect_identical(attr(r_all, "goods_universe"), sort(unique(as.character(r_all$good))))
  td2 <- tempfile(fileext = ".rds"); saveRDS(r_late, td2)                         # the cache keeps it
  expect_identical(attr(readRDS(td2), "goods_universe"), attr(r_late, "goods_universe"))
  run <- paste(readLines(file.path(root, "scripts", "run_estimation.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(run, ".ps <- sample_products_universe(raw_cache, opts$product_sample, opts$product_seed)", fixed = TRUE)
  expect_false(grepl("sample_products(raw_cache$good", run, fixed = TRUE))
})

test_that("README, record and card state the 2026-11-11 measurements, and cite records that are in the repo", {
  root <- .m66_root()
  rd <- function(...) paste(readLines(file.path(root, ...), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  readme <- rd("README.md"); rec <- rd("docs", "known_limitations_record.md"); card <- rd("docs", "hf_dataset_card.md")
  # the shrinkage gain, product-clustered
  expect_match(readme, "95% interval [0.002, 0.018] with the subsample's 25 products resampled", fixed = TRUE)
  expect_match(readme, "a small margin that holds when the subsample's products are resampled", fixed = TRUE)
  expect_false(grepl("resamples cell-directions", readme, fixed = TRUE))
  expect_false(grepl("its sign is less certain than that interval suggests", readme, fixed = TRUE))
  # the threshold curve
  expect_match(readme, "2.29 untrimmed, 2.50 at 3, 2.75 at the shipped 2 and 3.22 at 1.5", fixed = TRUE)
  expect_false(grepl("has not been measured", readme, fixed = TRUE))
  expect_match(rec, "median 2.29 untrimmed, 2.50 at 3, 2.75 at the\n  shipped 2 and 3.22 at 1.5", fixed = TRUE)
  expect_false(grepl("moves with the threshold has not been measured", rec, fixed = TRUE))
  # the gamma_V refresh
  expect_match(readme, "moves 15.0% of directly estimated rows by more than 1% in γ and the `opt_tariff` of 37.5% of cells", fixed = TRUE)
  # the card
  expect_match(card, "**Measurements (2026-11-11, patches 0165–0166; no estimate changes).**", fixed = TRUE)
  for (s in c("[0.002, 0.018]", "correction (6)\nabove is resolved", "2.29 untrimmed", "15.0% of directly estimated rows", "largest gap 6.8e-7"))
    expect_true(grepl(s, card, fixed = TRUE), info = s)
  # the records the documents cite exist, and say what the documents say
  sens <- file.path(root, "docs", "results", "sigma_update_sensitivity_census.md")
  win <- file.path(root, "docs", "results", "sigma_update_window_census.md")
  expect_true(file.exists(sens)); expect_true(file.exists(win))
  expect_true(file.exists(file.path(root, "results", "sigma_update_sensitivity_census.json")))
  s_txt <- paste(readLines(sens, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  for (s in c("**Reading: ADOPTABLE.**", "**Reading: ADOPT.**", "**Reading: THRESHOLD-DEPENDENT.**", "| off | 4593 | 3930 | 2.286 |", "| 1.5 | 4437 | 4200 | 3.215 |"))
    expect_true(grepl(s, s_txt, fixed = TRUE), info = s)
  w_txt <- paste(readLines(win, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  for (s in c("cells updated in both windows 3390", "goods bootstrap (25 goods, both directions of a cell kept together) 95% CI [0.0018, 0.0177]",
              "**Robust** (read on the goods interval since patch 0163)", "Reliability by cell size (patch 0165", "**Reading (rule fixed in patch 0165): one b stays.**"))
    expect_true(grepl(s, w_txt, fixed = TRUE), info = s)
  sj <- jsonlite::fromJSON(file.path(root, "results", "sigma_update_sensitivity_census.json"), simplifyVector = FALSE)
  expect_identical(sj$profile_methods$reading, "ADOPTABLE"); expect_identical(sj$gamma_v_refresh$reading, "ADOPT")
  expect_identical(sj$trim_grid$reading, "THRESHOLD-DEPENDENT")
})
