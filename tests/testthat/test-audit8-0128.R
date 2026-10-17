# ============================================================================
# test-audit8-0128.R  (patch 0128: the product table release, v0.11.1)
#
#   1. analysis/product_summary.R: the reproducibility census reports the level
#      gap between halves;
#   2. scripts/register_manifest_file.R: a new row is appended with its hash,
#      size and hub URL at the revision, the other rows are written back
#      byte for byte, and re-registering updates in place;
#   3. scripts/build_readme.R: the product-table section and the routing
#      bullet follow their JSONs and are empty without them; README carries them;
#   4. the card's top entry is v0.11.1 with no data revision yet (Gate 0 of
#      scripts/hf_upload_release.py lets the upload through), and it discloses
#      the Step-2 route.
# ============================================================================

.a28_root <- function() dirname(locate_source_dir())

test_that("product reproducibility reports the level gap", {
  suppressPackageStartupMessages(library(data.table))
  e <- new.env()
  for (f in c("R/utils_general.R", "analysis/product_summary.R")) sys.source(file.path(.a28_root(), f), envir = e)
  a <- data.table::data.table(good = sprintf("%04d", 1:6), gamma_median = 1:6, opt_tariff_median = (1:6) / 2)
  b <- data.table::copy(a)[, gamma_median := gamma_median * 1.1]
  r <- e$product_reproducibility(a, b, B = 50L)
  expect_equal(r$gamma_median$gap_median, log(1.1)); expect_equal(r$gamma_median$gap_p90, log(1.1))
  expect_equal(r$opt_tariff_median$gap_median, 0)
  expect_equal(r$gamma_median$spearman, 1)
})

test_that("register_manifest_file(): appends with hash and URL, keeps the other rows byte for byte", {
  skip_if_not_installed("openssl")
  root <- .a28_root()
  src <- file.path(root, "data", "manifest.csv"); skip_if_not(file.exists(src))
  e <- new.env(); sys.source(file.path(root, "scripts", "register_manifest_file.R"), envir = e)
  d <- tempfile("reg_"); dir.create(file.path(d, "data", "derived", "product"), recursive = TRUE)
  old <- setwd(d); on.exit({ setwd(old); unlink(d, recursive = TRUE) }, add = TRUE)
  file.copy(src, "data/manifest.csv")
  data.table::fwrite(data.table::data.table(good = c("0101", "0102"), gamma_median = c(0.5, 0.7)), "data/derived/product/p.csv")
  before <- readLines("data/manifest.csv")
  m <- e$register_manifest_file(data.table::fread("data/manifest.csv"), "data/derived/product/p.csv", "v0.11.1",
                                "analysis/product_summary.R", 1, "Product-level (HS4) companion table")
  data.table::fwrite(m, "data/manifest.csv", quote = TRUE)
  after <- readLines("data/manifest.csv")
  expect_identical(length(after), length(before) + 1L)
  expect_identical(after[seq_along(before)], before)
  con <- file("data/derived/product/p.csv", "rb"); sha <- as.vector(unclass(as.character(openssl::sha256(con)))); close(con)
  new <- data.table::fread("data/manifest.csv")[local_path == "data/derived/product/p.csv"]
  expect_identical(new$sha256, sha)
  expect_identical(new$hf_url, "https://huggingface.co/datasets/impex-machina/trade-elasticities/resolve/v0.11.1/product/p.csv")
  expect_identical(as.numeric(new$size_bytes), as.numeric(file.size("data/derived/product/p.csv")))
  expect_true(grepl("[0-9a-f]{64}", after[length(after)]))           # scripts/box/*.sh read one 64-hex value per row
  m2 <- e$register_manifest_file(data.table::fread("data/manifest.csv"), "data/derived/product/p.csv", "v0.11.1", "x", 1, "y")
  expect_identical(nrow(m2), length(before))                         # updated in place, not appended
  expect_error(e$register_manifest_file(m, "elsewhere/p.csv", "v0.11.1", "x", 1, "y"), "under data/derived")
})

test_that("README: the product-table section and the routing bullet", {
  bf <- readLines(file.path(.a28_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^product_table_section <- function", bf); i1 <- grep("^# --- Stage-2 DGP harness line", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  env$format_int <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  eval(parse(text = bf[i0:i1]), envir = env)
  expect_identical(env$product_table_section(NULL, 2.47), "")
  expect_identical(env$routing_bullet(NULL), "")
  ps <- jsonlite::fromJSON(file.path(.a28_root(), "results", "product_summary_census.json"), simplifyVector = FALSE)
  expect_match(env$product_table_section(ps, 2.4728), "### The product-level table (since v0.11.1)", fixed = TRUE)
  ps2 <- ps; ps2$odd_even$gamma_median$gap_median <- log(1.05); ps2$odd_even$gamma_median$gap_p90 <- log(1.2)
  # (patch 0131) the shared-prior halves' gap is no longer quoted (it is no guide to the table's uncertainty)
  expect_false(grepl("moves by a median 5.0%", env$product_table_section(ps2, 2.4728), fixed = TRUE))
  kr <- jsonlite::fromJSON(file.path(.a28_root(), "results", "known_truth_routing.json"), simplifyVector = FALSE)
  rb <- env$routing_bullet(kr)
  expect_match(rb, "Stage 1's Step-2 route overstates \u03c3 at known truth.", fixed = TRUE)
  expect_match(rb, "45,305 cells (24.8% of the cells with an estimate)", fixed = TRUE)
  readme <- paste(readLines(file.path(.a28_root(), "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(readme, "### The product-level table (since v0.11.1)", fixed = TRUE)
  expect_match(readme, "Stage 1's Step-2 route overstates \u03c3 at known truth.", fixed = TRUE)
})

test_that("card: the v0.11.1 entry (placeholder before the upload, its revision after), the Step-2 disclosure", {
  card <- readLines(file.path(.a28_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  starts <- grep("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+", card)
  v0111 <- grep("^> \\*\\*v0\\.11\\.1 ", card)
  expect_length(v0111, 1L)
  nxt <- starts[starts > v0111][1]
  block <- paste(card[v0111:(nxt - 1L)], collapse = "\n")
  # (patch 0130) Gate 0's two states: `<fill>` until the upload, the hub revision after
  # (this test asserted the first state only and failed once v0.11.1 shipped)
  expect_true(grepl("Data revision: `<fill>`", block, fixed = TRUE) ||
                grepl("Data revision:[[:space:]>]*`[0-9a-f]{40}`", block))
  expect_match(block, "product/baci_hs92_v202601_elast_hs4_product_summary.csv", fixed = TRUE)
  txt <- paste(card, collapse = "\n")
  expect_match(txt, "(5) Stage 1 at known truth", fixed = TRUE)
})
