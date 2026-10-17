# ============================================================================
# test-known-truth-0124.R  (patch 0124, audit #8: reading R4 recorded)
#
#   1. scripts/build_readme.R: the overview sentence and the Known-limitations
#      bullet built from results/known_truth_structured.json follow R4's
#      verdicts (between products "recovered", within them "partial") and are
#      empty without the JSON;
#   2. README and card carry them;
#   3. the harness titles each report with the patch whose readings it holds.
# ============================================================================

.k24_root <- function() dirname(locate_source_dir())
.k24_fns <- function() {
  bf <- readLines(file.path(.k24_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^kt_row <- function", bf); i1 <- grep("^# --- Stage-2 DGP harness line", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  eval(parse(text = bf[i0:i1]), envir = env)
  env
}
.k24_json <- function(f) jsonlite::fromJSON(file.path(.k24_root(), "results", f), simplifyVector = FALSE)

test_that("R4 clauses follow the verdicts and are empty without the JSON", {
  e <- .k24_fns()
  kt <- .k24_json("known_truth_stage2.json"); kts <- .k24_json("known_truth_structured.json")
  expect_identical(e$known_truth_overview(NULL, kts), "")
  expect_identical(e$known_truth_overview(kt, NULL), "")
  expect_identical(e$known_truth_structured_bullet(NULL), "")
  ov <- e$known_truth_overview(kt, kts)
  expect_identical(kts$readings$R4a_between_goods$verdict, "recovered")
  expect_identical(kts$readings$R4b_within_goods$verdict, "partial")
  expect_match(ov, "track true differences between products (correlation", fixed = TRUE)
  expect_match(ov, "track differences between importers within a product only weakly", fixed = TRUE)
  expect_match(ov, "do not recover differences between exporters within a cell", fixed = TRUE)
  bl <- e$known_truth_structured_bullet(kts)
  expect_match(bl, "^\n- \\*\\*What the published")
  expect_match(bl, "that is \"recovered\" between products and \"partial\" within them", fixed = TRUE)
  # a different verdict changes the words
  kts2 <- kts; kts2$readings$R4b_within_goods$verdict <- "not recovered"
  expect_match(e$known_truth_overview(kt, kts2), "do not track differences between importers within a product", fixed = TRUE)
})

test_that("README and card carry the R4 record", {
  readme <- paste(readLines(file.path(.k24_root(), "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(readme, "Checked against known truth (`validation/known_truth_stage2.R`)", fixed = TRUE)
  expect_match(readme, "- **What the published \u03b3 and `opt_tariff` track at known truth.**", fixed = TRUE)
  card <- paste(readLines(file.path(.k24_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(card, "patches 0122\u20130", fixed = TRUE)   # 0124; 0126 extended the range
  expect_match(card, "Differences between products are recovered; differences\nbetween importers within a product weakly", fixed = TRUE)
  expect_false(grepl("is\nbeing measured on structured synthetic panels", card, fixed = TRUE))
})

test_that("each known-truth report is titled with its own patch", {
  t22 <- readLines(file.path(.k24_root(), "docs", "results", "known_truth_stage2.md"), n = 1L, warn = FALSE, encoding = "UTF-8")
  t23 <- readLines(file.path(.k24_root(), "docs", "results", "known_truth_structured.md"), n = 1L, warn = FALSE, encoding = "UTF-8")
  expect_identical(sub("\r$", "", t22), "# Known-truth recovery of the shipped pipeline (patch 0122)")
  expect_identical(sub("\r$", "", t23), "# Known-truth recovery of the shipped pipeline (patch 0123)")
  src <- paste(readLines(file.path(.k24_root(), "validation", "known_truth_stage2.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(src, 'sprintf("# Known-truth recovery of the shipped pipeline (patch %s)", if (is.null(meta$patch)) "0122" else meta$patch)', fixed = TRUE)
})
