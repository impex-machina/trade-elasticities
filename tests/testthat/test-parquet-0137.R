# ============================================================================
# test-parquet-0137.R  (patch 0137: Parquet copies, release v0.11.2)
#
#   scripts/export_parquet.R: the source normalization (factors to character,
#   `good` as a zero-padded HS4 string), the Parquet path, a write / read-back
#   round trip and the mismatch check; the card's viewer configs (the product
#   table first, by default) and v0.11.2 entry; the README's Parquet section.
# ============================================================================

.p37_root <- function() dirname(locate_source_dir())

test_that("normalization and the Parquet path", {
  e <- new.env(); sys.source(file.path(.p37_root(), "scripts", "export_parquet.R"), envir = e)
  expect_identical(e$pq_path("data/derived/stage1/x_feenstra_sigma.rds"), "data/derived/stage1/x_feenstra_sigma.parquet")
  expect_identical(e$pq_path("data/derived/product/x_summary.csv"), "data/derived/product/x_summary.parquet")
  d <- tempfile("pq_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "t.rds")
  saveRDS(data.table::data.table(good = c(101L, 8703L), lab = factor(c("a", "b")), v = c(0.5, NA)), f)
  x <- e$pq_read_source(f)
  expect_identical(x$good, c("0101", "8703")); expect_identical(x$lab, c("a", "b")); expect_s3_class(x, "data.frame")
  g <- file.path(d, "p.csv"); data.table::fwrite(data.frame(good = c("0101", "2709"), m = 1:2), g)
  expect_identical(e$pq_read_source(g)$good, c("0101", "2709"))
})

test_that("round trip: write, read back, compare; a changed value is caught", {
  skip_if_not_installed("nanoparquet")
  e <- new.env(); sys.source(file.path(.p37_root(), "scripts", "export_parquet.R"), envir = e)
  d <- tempfile("pq_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "t.rds")
  saveRDS(data.table::data.table(importer = 1:3, good = c("0101", "2709", "8703"), gamma = c(0.1, 1.5, NA),
                                 conv = c(TRUE, FALSE, NA), src = c("estimated", NA, "fallback_sigma_pole")), f)
  r <- e$pq_export_one(f)
  expect_identical(r$rows, 3L); expect_true(file.exists(r$parquet))
  x <- e$pq_read_source(f); x$gamma[2] <- 1.5000001
  expect_match(e$pq_compare(x, r$parquet), "column gamma differs", fixed = TRUE)
  expect_null(e$pq_compare(e$pq_read_source(f), r$parquet))
})

test_that("card configs, the v0.11.2 entry and the README section", {
  card <- readLines(file.path(.p37_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  y <- card[2:(which(card == "---")[2] - 1L)]
  i <- grep("^  - config_name:", y)
  expect_identical(sub("^  - config_name: ", "", y[i[1:4]]), c("product_summary", "stage2b_country", "stage1_country", "stage2a_regional"))
  expect_identical(trimws(y[i[1] + 2L]), "default: true")
  expect_match(y[i[1] + 1L], "product/baci_hs92_v202601_elast_hs4_product_summary.parquet", fixed = TRUE)
  heads <- regmatches(card, regexpr("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+", card))
  expect_identical(heads[1], "> **v0.11.2")
  txt <- paste(card, collapse = "\n")
  expect_match(txt, "Data revision: `<fill>`. **v0.11.1 remains available pinned at revision", fixed = TRUE)
  readme <- paste(readLines(file.path(.p37_root(), "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(readme, "### Parquet copies (since v0.11.2)", fixed = TRUE)
  expect_match(readme, 'filters=[("good", "==", "8703")]', fixed = TRUE)
})
