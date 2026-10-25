#!/usr/bin/env Rscript
# ============================================================================
# scripts/export_parquet.R  (patch 0137, release v0.11.2)
#
# Parquet copies of the published tables, so that Python, DuckDB, Polars and
# the Hugging Face dataset viewer can read them without R. The .rds files (and
# the product CSV) stay the canonical copies; each Parquet file is written
# next to its source with the same base name, then read back and compared with
# the source value for value -- the export stops on the first difference.
#
#   data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds
#   data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds
#   data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds
#   data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv
#
# Types: factors become character; `good` is written as a character HS4 code
# with its leading zero (a CSV reader drops it; Parquet keeps the type).
# Needs the nanoparquet package (CRAN; no system dependencies).
#
# Usage (repo root; about a minute):
#   Rscript scripts/export_parquet.R            write and verify all four
#   Rscript scripts/export_parquet.R --check    verify existing copies only
# ============================================================================

suppressPackageStartupMessages(library(data.table))

PQ_SOURCES <- c(
  "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds",
  "data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds",
  "data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds",
  "data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv")

#' The Parquet path beside a source file.
pq_path <- function(src) sub("\\.(rds|csv)$", ".parquet", src)

#' A source table as a plain data.frame with Parquet-friendly types.
pq_read_source <- function(src) {
  x <- if (grepl("\\.csv$", src)) data.table::fread(src, colClasses = list(character = "good")) else readRDS(src)
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  for (k in names(x)) {
    if (is.factor(x[[k]])) x[[k]] <- as.character(x[[k]])
    if (inherits(x[[k]], "integer64")) x[[k]] <- as.numeric(x[[k]])
  }
  if ("good" %in% names(x) && !is.character(x$good))
    x$good <- formatC(as.integer(x$good), width = 4L, flag = "0")
  attr(x, "sorted") <- NULL
  x
}

#' Compare a Parquet file with its normalized source; returns NULL or a message.
pq_compare <- function(x, pq) {
  y <- as.data.frame(nanoparquet::read_parquet(pq), stringsAsFactors = FALSE)
  if (!identical(names(x), names(y))) return("column names differ")
  if (nrow(x) != nrow(y)) return(sprintf("row counts differ (%d vs %d)", nrow(x), nrow(y)))
  for (k in names(x)) {
    a <- x[[k]]; b <- y[[k]]
    if (is.factor(b)) b <- as.character(b)
    if (inherits(a, "POSIXct")) { a <- as.numeric(a); b <- as.numeric(b) }
    if (inherits(a, "Date")) { a <- as.numeric(a); b <- as.numeric(b) }
    attributes(a) <- NULL; attributes(b) <- NULL
    if (!identical(a, b)) return(sprintf("column %s differs", k))
  }
  NULL
}

#' Write (unless check_only) and verify one table.
pq_export_one <- function(src, check_only = FALSE) {
  if (!file.exists(src)) stop("missing source: ", src, call. = FALSE)
  x <- pq_read_source(src); pq <- pq_path(src)
  if (!check_only) nanoparquet::write_parquet(x, pq, compression = "zstd")
  if (!file.exists(pq)) stop("missing Parquet copy: ", pq, call. = FALSE)
  msg <- pq_compare(x, pq)
  if (!is.null(msg)) stop(sprintf("%s does not match %s: %s", pq, src, msg), call. = FALSE)
  list(source = src, parquet = pq, rows = nrow(x), cols = ncol(x), mb = file.size(pq) / 1e6)
}


if (sys.nframe() == 0L) {
  if (!requireNamespace("nanoparquet", quietly = TRUE))
    stop("scripts/export_parquet.R needs nanoparquet: install.packages(\"nanoparquet\")", call. = FALSE)
  check_only <- "--check" %in% commandArgs(trailingOnly = TRUE)
  for (src in PQ_SOURCES) {
    r <- pq_export_one(src, check_only)
    cat(sprintf("%s %s: %s rows x %d columns, %.1f MB -- matches its source\n", if (check_only) "checked" else "wrote",
                r$parquet, format(r$rows, big.mark = ","), r$cols, r$mb))
  }
}
