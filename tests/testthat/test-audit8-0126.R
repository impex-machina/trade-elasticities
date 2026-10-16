# ============================================================================
# test-audit8-0126.R  (patch 0126, audit #8: the download timeout, records)
#
#   1. load_outputs(): the download runs with a timeout of at least an hour
#      (R's 60-second default truncated the 262 MB Stage-2b table at ~3 MB/s)
#      and the caller's timeout is restored; a failed download names the file
#      and leaves no temp file; the move into place is checked;
#   2. the reference-exporter and region-map readings are recorded, and the
#      card carries the hub-file gate check.
# ============================================================================

.a26_root <- function() dirname(locate_source_dir())

test_that("load_outputs(): an hour-long timeout for the download, the caller's restored", {
  skip_if_not_installed("openssl")
  root <- .a26_root()                                   # before setwd(): the root is found from the working directory
  source(file.path(root, "R", "load_outputs.R"), local = TRUE)
  d <- tempfile("dl26_"); dir.create(d)
  old_wd <- setwd(d); old_to <- options(timeout = 60)
  on.exit({ setwd(old_wd); options(old_to); unlink(d, recursive = TRUE) }, add = TRUE)
  src <- file.path(d, "src.rds"); saveRDS(1:10, src)
  con <- file(src, "rb"); sha <- tolower(unclass(as.character(openssl::sha256(con)))); close(con)
  m <- data.table::data.table(local_path = "data/derived/x.rds",
                              hf_url = "https://huggingface.co/datasets/o/r/resolve/v1/x.rds",
                              sha256 = sha, size_bytes = file.size(src), produced_by = "t", pillar = 1L, description = "d")
  data.table::fwrite(m, "m.csv", quote = TRUE)
  seen <- NA_real_
  fake <- function(url, destfile, mode, quiet) { seen <<- getOption("timeout"); file.copy(src, destfile, overwrite = TRUE); 0L }
  expect_message(load_outputs(force = TRUE, manifest_path = "m.csv", downloader = fake), "downloaded and verified")
  expect_gte(seen, 3600)
  expect_identical(getOption("timeout"), 60)
  expect_identical(readRDS("data/derived/x.rds"), 1:10)
  # a failed download names the file, keeps the local copy, leaves no temp file
  saveRDS("local", "data/derived/x.rds")
  n_tmp <- length(list.files(tempdir()))
  broken <- function(url, destfile, mode, quiet) { writeLines("partial", destfile); stop("downloaded length 187122255 != reported length 262541019") }
  expect_error(load_outputs(force = TRUE, manifest_path = "m.csv", downloader = broken), "download of data/derived/x.rds failed")
  expect_identical(readRDS("data/derived/x.rds"), "local")
  expect_identical(length(list.files(tempdir())), n_tmp)
  expect_identical(getOption("timeout"), 60)
  src_txt <- paste(readLines(file.path(root, "R", "load_outputs.R"), warn = FALSE), collapse = "\n")
  expect_match(src_txt, "if (!suppressWarnings(file.rename(tmp, local))) {", fixed = TRUE)
  expect_match(src_txt, "if (!file.copy(tmp, local, overwrite = TRUE))", fixed = TRUE)
})

test_that("the 0125 readings are recorded and the card carries the hub check", {
  doc <- paste(readLines(file.path(.a26_root(), "docs", "methodology", "stage2_country.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(doc, "raw cache, 113.8 million rows, 1995\u20132024): closed, both rules stay.**", fixed = TRUE)
  rm_src <- paste(readLines(file.path(.a26_root(), "R", "region_map.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(rm_src, "0.0060% of trade value as importers", fixed = TRUE)
  card <- paste(readLines(file.path(.a26_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(card, "patches 0122\u2013012", fixed = TRUE)   # 0126; 0128 extended the range
  expect_match(card, "(`docs/results/gate_hub_v0110.md`)", fixed = TRUE)
  rc <- jsonlite::fromJSON(file.path(.a26_root(), "results", "reference_exporter_census.json"))
  expect_identical(rc$reading, "closed")
  expect_identical(jsonlite::fromJSON(file.path(.a26_root(), "results", "region_map_census.json"))$reading, "negligible")
})
