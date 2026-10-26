# ============================================================================
# test-audit8-0131.R  (patch 0131: the independent periods' level gap)
#
#   The README's product-table section states the independent periods' level
#   gap (results/product_window_census.json) as the scale of uncertainty for
#   the table's values, no longer quotes the shared-prior halves' 0.2%, and
#   says precisely which inputs those halves shared; the card's v0.11.1
#   correction carries the result.
# ============================================================================

.a31_root <- function() dirname(locate_source_dir())

test_that("README: the independent level gap, the shared-prior gap dropped", {
  bf <- readLines(file.path(.a31_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^product_table_section <- function", bf); i1 <- grep("^routing_bullet <- function", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  env$format_int <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  eval(parse(text = bf[i0:i1]), envir = env)
  ps <- jsonlite::fromJSON(file.path(.a31_root(), "results", "product_summary_census.json"), simplifyVector = FALSE)
  pw <- jsonlite::fromJSON(file.path(.a31_root(), "results", "product_window_census.json"), simplifyVector = FALSE)
  txt <- env$product_table_section(ps, 2.4728, pw)
  expect_match(txt, "a product's median \u03b3 differs by a median of 25.5% (94.9% at the 90th percentile) and its median `opt_tariff` by 16.0% (56.4%)", fixed = TRUE)
  expect_match(txt, "its ranking of products is better supported than its levels", fixed = TRUE)
  expect_false(grepl("moves by a median 0.2%", txt, fixed = TRUE))
  expect_match(txt, "share the full-panel Stage 1 (the odd/even halves also its Stage-2a priors)", fixed = TRUE)
  pw_nogap <- pw; pw_nogap$reproducibility$gamma_median$gap_median <- NULL
  expect_false(grepl("differs by a median of", env$product_table_section(ps, 2.4728, pw_nogap), fixed = TRUE))
  readme <- generated_docs_text(.a31_root())   # patch 0143: README.md + the long-form record
  expect_match(readme, "differs by a median of 25.5%", fixed = TRUE)
})

test_that("card: the v0.11.1 correction carries the independent result", {
  card <- paste(readLines(file.path(.a31_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(card, "product medians correlate at 0.64 for \u03b3\n> and 0.76 for `opt_tariff`", fixed = TRUE)
  expect_match(card, "by a median of 25.5% for \u03b3 (94.9% at the 90th percentile) and 16.0% for `opt_tariff`", fixed = TRUE)
  expect_false(grepl("is reported in the README's product-table section", card, fixed = TRUE))
})
