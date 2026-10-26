#!/usr/bin/env Rscript
# ============================================================================
# scripts/add_opt_tariff_total.R  (patch 0139, release v0.11.3)
#
# Adds two columns to an existing Stage-2b table without re-estimation:
#
#   total_trade        the pair's total customs value over its years in the
#                      Stage-2 panel (avg_trade is the mean over the same years)
#   opt_tariff_total   the cell's optimal tariff with exporters weighted by
#                      total_trade instead of avg_trade (cell-level, like
#                      opt_tariff; over the published, directly estimated rows)
#
# exactly as the patched estimator computes them natively (patch 0139). The
# pairs' panel years come from the raw cache by the rule the reference-exporter
# census (patch 0125) and the tariff-weight census (0138) showed reproduces the
# Stage-2 panel. Nothing is written unless every check passes:
#
#   - every row's pair is found in the panel;
#   - total_trade / panel years equals the published avg_trade on every row
#     with a positive avg_trade (relative 1e-6);
#   - the avg_trade-weighted tariff recomputed here equals the published
#     opt_tariff in every cell (relative 1e-9).
#
# Rows the Stage-2 trim flagged (trim_reason set) carry the cell's pre-trim
# values in their cell-level columns; opt_tariff_total follows the same rule
# where the pre-trim opt_tariff reproduces exactly on those rows, and is NA on
# them otherwise (the script says which). Every other column is unchanged.
#
# Usage (repo root; ~10 min and up to ~15 GB of RAM on the full cache):
#   Rscript scripts/add_opt_tariff_total.R --raw-cache PATH --in S2B.rds [--out S2B.rds]
# --out defaults to --in (overwrite).
# ============================================================================

suppressPackageStartupMessages(library(data.table))

#' Same value: both NA, or equal to a relative tolerance.
.ott_same <- function(a, b, tol = 1e-9) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= tol * pmax(abs(b), 1))

#' The cell's tariff over its directly estimated rows with weights w.
.ott_cell <- function(gamma, sigma, w, tier, convergence) {
  e <- is_estimated_row(tier, convergence)
  if (any(e)) optimal_tariff(gamma[e], sigma[e][1L], w[e]) else NA_real_
}

#' Attach total_trade and opt_tariff_total; returns list(table, checks).
attach_opt_tariff_total <- function(dt, panel) {
  x <- data.table::copy(data.table::as.data.table(dt))
  orig <- data.table::copy(names(x))   # a copy: data.table extends names(x) by reference as columns are added
  pn <- data.table::as.data.table(panel)[, .(.imp = as.integer(importer), .exp = as.integer(exporter), .good = as.character(good),
                                             .tot = total_dif_trim, .n = n_dif_trim)]
  x[, `:=`(.imp = as.integer(importer), .exp = as.integer(exporter), .good = as.character(good), .row = .I)]
  x[pn, `:=`(total_trade = i..tot, .n = i..n), on = .(.imp, .exp, .good)]
  unmatched <- sum(is.na(x$.n))
  ok_avg <- x[is.finite(avg_trade) & avg_trade > 0, .ott_same(total_trade / .n, avg_trade, 1e-6)]
  pub <- if ("trim_reason" %in% names(x)) is.na(x$trim_reason) else rep(TRUE, nrow(x))
  cv <- x[pub, .(ot_rep = .ott_cell(gamma, sigma, avg_trade, tier, convergence),
                 ott = .ott_cell(gamma, sigma, total_trade, tier, convergence), ot_pub = opt_tariff[1L]), by = .(importer, good)]
  ok_pub <- .ott_same(cv$ot_rep, cv$ot_pub)
  x[cv, opt_tariff_total := i.ott, on = .(importer, good)]
  n_flag <- sum(!pub); ok_flag <- NA; flag_rule <- "none flagged"
  if (n_flag > 0L) {
    pre <- x[, .(ot_pre = .ott_cell(gamma, sigma, avg_trade, tier, convergence),
                 ott_pre = .ott_cell(gamma, sigma, total_trade, tier, convergence)), by = .(importer, good)]
    fl <- x[!pub, .(.row, importer, good, opt_tariff)][pre, on = .(importer, good), nomatch = NULL]
    ok_flag <- mean(.ott_same(fl$ot_pre, fl$opt_tariff))
    if (isTRUE(ok_flag == 1)) {
      x[fl, opt_tariff_total := i.ott_pre, on = ".row"]; flag_rule <- "pre-trim values (reproduced exactly)"
    } else {
      x[!pub, opt_tariff_total := NA_real_]; flag_rule <- "NA (pre-trim opt_tariff not reproduced exactly)"
    }
  }
  x[, c(".imp", ".exp", ".good", ".row", ".n") := NULL]
  lead <- orig[seq_len(match("avg_trade", orig))]
  data.table::setcolorder(x, c(lead, "total_trade"))
  if ("opt_tariff_all" %in% names(x)) data.table::setcolorder(x, c(names(x)[seq_len(match("opt_tariff_all", names(x)))], "opt_tariff_total"))
  unchanged <- isTRUE(all.equal(x[, ..orig], data.table::as.data.table(dt), check.attributes = FALSE))
  list(table = x, checks = list(rows = nrow(x), unmatched = unmatched, rep_avg_trade = mean(ok_avg), cells = nrow(cv),
                                rep_opt_tariff = mean(ok_pub), flagged_rows = n_flag, rep_flagged = ok_flag, flagged_rule = flag_rule,
                                other_columns_unchanged = unchanged))
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  rc <- get_arg("--raw-cache", NA_character_); inp <- get_arg("--in", NA_character_); out <- get_arg("--out", inp)
  if (is.na(rc) || is.na(inp) || !all(file.exists(c(rc, inp))))
    stop("usage: Rscript scripts/add_opt_tariff_total.R --raw-cache PATH --in S2B.rds [--out S2B.rds]")
  source("R/utils_general.R")
  e <- new.env(); sys.source("analysis/reference_exporter_census.R", envir = e)
  t0 <- Sys.time()
  dt <- readRDS(inp)
  if (all(c("total_trade", "opt_tariff_total") %in% names(dt))) stop("the table already has total_trade and opt_tariff_total: ", inp)
  res <- attach_opt_tariff_total(dt, e$ref_exporter_panel(readRDS(rc)))
  ck <- res$checks
  cat(sprintf("rows %s | unmatched pairs %d | avg_trade reproduced %.4f%% | opt_tariff reproduced in %.4f%% of %s cells | flagged rows %s: %s | other columns unchanged: %s\n",
              format(ck$rows, big.mark = ","), ck$unmatched, 100 * ck$rep_avg_trade, 100 * ck$rep_opt_tariff, format(ck$cells, big.mark = ","),
              format(ck$flagged_rows, big.mark = ","), ck$flagged_rule, ck$other_columns_unchanged))
  if (ck$unmatched > 0L || ck$rep_avg_trade < 1 || ck$rep_opt_tariff < 1 || !ck$other_columns_unchanged)
    stop("a check failed -- nothing written", call. = FALSE)
  saveRDS(finalize_saved_output(res$table), out)
  tt <- res$table[is.finite(opt_tariff) & is.finite(opt_tariff_total) & opt_tariff > 0, .(a = opt_tariff[1L], b = opt_tariff_total[1L]), by = .(importer, good)]
  cat(sprintf("wrote %s (%.1f min): %d columns; cells: opt_tariff median %.3f, opt_tariff_total median %.3f\n", out,
              as.numeric(difftime(Sys.time(), t0, units = "mins")), ncol(res$table), stats::median(tt$a), stats::median(tt$b)))
}
