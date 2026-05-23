#' R/hs_codes.R
#'
#' HS code utilities: leading-zero-safe HS6 padding and HS6→HS4 rollup.
#' Extracted from feen94_het_baci.R (lines 222-267) at refactor step 3;
#' content identical to the original, only sectioned into its own file.
#'
#' Exported functions:
#'   pad_hs6(k)       — pad HS6 codes to 6-digit strings with leading zeroes
#'   hs6_to_hs4(hs6)  — roll HS6 codes up to HS4
#'
#' Depends on: none

# ===========================================================================
#  HS CODE UTILITIES
# ===========================================================================

#' Pad HS6 codes to ensure 6-digit strings with leading zeroes.
#'
#' BACI's product column (k) may be read as numeric by fread/read.csv,
#' which strips leading zeroes (e.g., 010110 -> 10110). This function
#' detects and fixes the issue.
#'
#' @param k Vector of HS6 codes (character or numeric).
#' @return Character vector of 6-digit zero-padded HS6 codes.
pad_hs6 <- function(k) {
  k <- as.character(k)
  # Detect if padding is needed: any code shorter than 6 digits
  needs_pad <- nchar(k) < 6L
  if (any(needs_pad)) {
    n_padded <- sum(needs_pad)
    cat(sprintf("  [HS6 padding] %s codes shorter than 6 digits; ",
                format(n_padded, big.mark = ",")))
    cat("padding with leading zeroes.\n")
    k <- formatC(as.integer(k), width = 6, format = "d", flag = "0")
  }
  k
}


#' Extract HS4 heading from HS6 codes.
#' @param hs6 Character vector of 6-digit HS6 codes.
#' @return Character vector of 4-digit HS4 codes.
hs6_to_hs4 <- function(hs6) {
  substr(hs6, 1, 4)
}


# ===========================================================================
#  CONFIG VALIDATION
# ===========================================================================

#' Validate config for obvious misconfigurations before expensive operations.
#'
#' Checks that required fields exist, types are correct, and values are
#' logically consistent. Stops with an informative error on failure.
#' Warns on likely-problematic but non-fatal settings.
#'
#' @param cfg Config list.
