#' R/load_baci.R
#'
#' BACI data loading. Dispatches on file extension: .csv, .rds, or .dta
#' (.dta requires the optional 'haven' package via a requireNamespace guard).
#' Extracted from feen94_het_baci.R (lines 441-489) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   load_baci(filepath)  — load a BACI file (.csv / .rds / .dta) as a data.table
#'
#' Depends on: none (haven optional, only for .dta)

# ===========================================================================
#  DATA LOADING
# ===========================================================================

#' Load BACI data from either a single CSV/RDS or a directory of per-year CSVs.
#'
#' BACI is distributed as one CSV per year inside a zip archive.
#' This function handles both cases.
load_baci <- function(filepath) {
  if (dir.exists(filepath)) {
    # Match only BACI trade data files (BACI_HS*_Y####_V*.csv),
    # excluding metadata files like country_codes*.csv and product_codes*.csv
    csv_files <- list.files(filepath, pattern = "BACI_HS.*_Y\\d{4}_V.*\\.csv$",
                            full.names = TRUE, recursive = FALSE)
    if (length(csv_files) == 0L) {
      # Fallback: try all CSVs but warn
      csv_files <- list.files(filepath, pattern = "\\.csv$",
                              full.names = TRUE, recursive = FALSE)
      warning("No files matching BACI_HS*_Y*_V*.csv pattern found. ",
              "Loading all ", length(csv_files), " CSV files in directory. ",
              "Remove metadata CSVs (country_codes, product_codes) ",
              "from the directory to avoid errors.")
    }
    if (length(csv_files) == 0L) stop("No CSV files found in: ", filepath)
    cat(sprintf("  Loading %d BACI trade data files from: %s\n",
                length(csv_files), filepath))
    dt_list <- lapply(csv_files, fread, colClasses = list(character = "k"))
    raw <- rbindlist(dt_list)
  } else if (grepl("\\.csv$", filepath, ignore.case = TRUE)) {
    raw <- fread(filepath, colClasses = list(character = "k"))
  } else if (grepl("\\.rds$", filepath, ignore.case = TRUE)) {
    raw <- as.data.table(readRDS(filepath))
  } else if (grepl("\\.dta$", filepath, ignore.case = TRUE)) {
    if (!requireNamespace("haven", quietly = TRUE))
      stop("Package 'haven' required to read .dta files.")
    raw <- as.data.table(haven::read_dta(filepath))
  } else {
    stop("Unsupported file type: ", filepath)
  }
  raw
}


# ===========================================================================
#  ESTIMATE ONE (IMPORTER, PRODUCT) PAIR
# ===========================================================================

#' Lightweight failure indicator for cell-level diagnostics.
#' Returned instead of NULL so that estimate_product can log the reason.
