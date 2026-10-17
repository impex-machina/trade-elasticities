# ============================================================================
# test-audit8-0130.R  (patch 0130: corrections after v0.11.1, the independent test)
#
#   1. analysis/product_window_census.R: shared-input check by hash, the goods
#      checks, the reading;
#   2. scripts/build_readme.R: the product section no longer calls the halves
#      independent, adds the window test when its JSON exists; the routing
#      bullet carries the 0129 A/B;
#   3. the card's v0.11.1 entry is corrected and point (5) carries the A/B.
# ============================================================================

.a30_root <- function() dirname(locate_source_dir())

test_that("window census: shared inputs by hash, and the reading", {
  skip_if_not_installed("openssl")
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "analysis/product_summary.R", "analysis/product_window_census.R")) sys.source(file.path(.a30_root(), f), envir = e)
  d <- tempfile("pw_"); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  for (x in c("a", "b", "c")) dir.create(file.path(d, x), recursive = TRUE)
  s1n <- paste0(e$PWC_PREFIX, "_country_hs4_feenstra_sigma.rds"); s2an <- paste0(e$PWC_PREFIX, "_regional_hs4_fixed_sigma.rds")
  saveRDS(1:3, file.path(d, "a", s1n)); saveRDS(1:3, file.path(d, "b", s1n)); saveRDS(4:6, file.path(d, "c", s1n))
  saveRDS("x", file.path(d, "a", s2an)); saveRDS("x", file.path(d, "b", s2an))
  sh <- e$pwc_pairs(list(c(file.path(d, "a"), file.path(d, "b")), c(file.path(d, "a"), file.path(d, "c"))))
  expect_identical(c(sh[[1]]$stage1, sh[[1]]$stage2a), c("shared", "shared"))
  expect_identical(c(sh[[2]]$stage1, sh[[2]]$stage2a), c("own", "absent"))
  rep <- function(g, o) list(gamma_median = list(spearman = g), opt_tariff_median = list(spearman = o))
  expect_identical(e$pwc_reading(rep(0.6, 0.7)), "reproduces")
  expect_identical(e$pwc_reading(rep(0.1, 0.2)), "does not reproduce")
  expect_identical(e$pwc_reading(rep(0.6, 0.2)), "partial")
  expect_identical(e$pwc_reading(rep(NA_real_, 0.2)), "not measured")
})

test_that("README: the product section is corrected and the routing bullet carries the A/B", {
  bf <- readLines(file.path(.a30_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^product_table_section <- function", bf); i1 <- grep("^# --- Stage-2 DGP harness line", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  env$format_int <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  eval(parse(text = bf[i0:i1]), envir = env)
  ps <- jsonlite::fromJSON(file.path(.a30_root(), "results", "product_summary_census.json"), simplifyVector = FALSE)
  txt <- env$product_table_section(ps, 2.4728)
  expect_false(grepl("independent halves", txt, fixed = TRUE))
  expect_false(grepl("error scale", txt, fixed = TRUE))
  expect_match(txt, "so they do not show that product differences reproduce in independent data", fixed = TRUE)
  expect_match(txt, "A test on independently estimated periods is pending.", fixed = TRUE)
  pw <- list(reading = "partial", reproducibility = list(gamma_median = list(products = 25L, spearman = 0.42),
                                                         opt_tariff_median = list(products = 25L, spearman = 0.31)))
  txt2 <- env$product_table_section(ps, 2.4728, pw)
  expect_match(txt2, "product medians correlate at 0.42 for \u03b3 and 0.31 for `opt_tariff`; by the rule fixed in patch 0130 that is \"partial\"", fixed = TRUE)
  kr <- jsonlite::fromJSON(file.path(.a30_root(), "results", "known_truth_routing.json"), simplifyVector = FALSE)
  ab <- jsonlite::fromJSON(file.path(.a30_root(), "results", "routing_ab.json"), simplifyVector = FALSE)
  rb <- env$routing_bullet(kr, ab)
  expect_match(rb, "is usable on 23,592 of those cells (patch 0129)", fixed = TRUE)
  expect_match(rb, "that is \"keep Step 2\"; switching would move the fallback \u03c3 only from 2.473 to 2.486", fixed = TRUE)
  expect_false(grepl("is the next measurement", rb, fixed = TRUE))
  readme <- paste(readLines(file.path(.a30_root(), "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("independent halves", readme, fixed = TRUE))
  expect_match(readme, "that is \"keep Step 2\"", fixed = TRUE)
})

test_that("card: the v0.11.1 entry corrected, point (5) carries the A/B", {
  card <- paste(readLines(file.path(.a30_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("product medians reproduce across independent halves", card, fixed = TRUE))
  expect_match(card, "*(Corrected 2026-10-17, patch\n> 0130:", fixed = TRUE)
  expect_match(card, "does not do better (patch 0129, `docs/results/routing_ab.md`)", fixed = TRUE)
  expect_false(grepl("is being measured\n(patch 0129)", card, fixed = TRUE))
})
