#' R/quality_log.R
#'
#' Data quality tracker: a lightweight running log of cell drops and
#' data-quality events through the preparation pipeline.
#' Extracted from feen94_het_baci.R (lines 341-421) at refactor step 3;
#' content identical to the original, only sectioned.
#'
#' Exported functions:
#'   new_quality_log()        — create an empty quality log
#'   print_quality_log(qlog)  — print a quality log
#'
#' Depends on: none

# ===========================================================================
#  DATA QUALITY TRACKER
# ===========================================================================

new_quality_log <- function() {
  env <- new.env(parent = emptyenv())
  env$steps <- list()
  env$add <- function(stage, n_obs, n_dropped = NA_integer_,
                      trade_value = NA_real_, detail = "") {
    entry <- list(stage = stage, n_obs = n_obs,
                  n_dropped = n_dropped, trade_value = trade_value,
                  detail = detail)
    env$steps[[length(env$steps) + 1L]] <- entry
    invisible(NULL)
  }
  env
}

print_quality_log <- function(qlog) {
  cat("\n")
  cat("=====================================================================\n")
  cat("  DATA QUALITY REPORT\n")
  cat("=====================================================================\n\n")

  has_tv <- any(sapply(qlog$steps, function(s) !is.na(s$trade_value)))

  if (has_tv) {
    cat(sprintf("  %-40s %12s %12s %16s\n", "Stage", "Obs", "Dropped", "Trade Val ($B)"))
    cat(sprintf("  %-40s %12s %12s %16s\n",
                paste(rep("-", 40), collapse = ""),
                paste(rep("-", 12), collapse = ""),
                paste(rep("-", 12), collapse = ""),
                paste(rep("-", 16), collapse = "")))
  } else {
    cat(sprintf("  %-45s %12s %12s\n", "Stage", "Obs", "Dropped"))
    cat(sprintf("  %-45s %12s %12s\n",
                paste(rep("-", 45), collapse = ""),
                paste(rep("-", 12), collapse = ""),
                paste(rep("-", 12), collapse = "")))
  }

  for (s in qlog$steps) {
    n_str <- format(s$n_obs, big.mark = ",")
    d_str <- if (is.na(s$n_dropped)) "" else format(s$n_dropped, big.mark = ",")
    if (has_tv) {
      tv_str <- if (is.na(s$trade_value)) "" else sprintf("%.1f", s$trade_value / 1e6)
      cat(sprintf("  %-40s %12s %12s %16s\n", s$stage, n_str, d_str, tv_str))
    } else {
      cat(sprintf("  %-45s %12s %12s\n", s$stage, n_str, d_str))
    }
    if (nchar(s$detail) > 0) {
      cat(sprintf("    %s\n", s$detail))
    }
  }

  # Overall retention
  n_start <- qlog$steps[[1]]$n_obs
  n_end   <- qlog$steps[[length(qlog$steps)]]$n_obs
  pct <- round(100 * n_end / n_start, 1)
  cat(sprintf("\n  Overall retention: %s / %s (%.1f%%)\n",
              format(n_end, big.mark = ","),
              format(n_start, big.mark = ","), pct))

  if (has_tv) {
    tv_start <- qlog$steps[[1]]$trade_value
    tv_end   <- qlog$steps[[length(qlog$steps)]]$trade_value
    if (!is.na(tv_start) && !is.na(tv_end) && tv_start > 0) {
      cat(sprintf("  Trade value retention: $%.1fB / $%.1fB (%.1f%%)\n",
                  tv_end / 1e6, tv_start / 1e6, 100 * tv_end / tv_start))
    }
  }
  cat("=====================================================================\n\n")
}


# ===========================================================================
#  HELPER FUNCTIONS
# ===========================================================================

#' Choose reference exporter within an import market.
#' Selects the largest, most persistent exporter.
