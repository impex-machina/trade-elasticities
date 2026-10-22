#!/usr/bin/env Rscript
# ============================================================================
# analysis/ridge_tau2_eb.R  (patch 0133)
#
# Empirical-Bayes calibration of tau^2, the prior variance of ln gamma around
# the product prior under --stage2-ridge-scale cell (patch 0132). Stage 2b is
# estimated on two halves of the years (--t-parity block-a / block-b:
# alternate four-year blocks of levels, the differences that straddle two
# blocks dropped; same Stage 1 and Stage-2a priors) with a weak prior,
# tau^2 = 1. Not odd / even years: a difference uses two adjacent levels, so
# under odd / even every level year enters both halves, and a unit-value
# level's measurement error with it -- shared noise that would read as
# signal. Under the block halves no level year is in both. A row's deviation from its
# product prior in half h is approximately w_h * (theta + noise_h), with w_h
# the data's share of the row's curvature (1 - gamma_shrink_wt under the
# shipped sandwich form) and noise independent across the halves, so
#     tau2_eb = sum(d_odd * d_even) / sum(w_odd * w_even)
# over rows directly estimated in both halves estimates the variance of the
# recoverable signal. That is the EB prior variance. The sum is taken after a
# 2.5% trim: rows whose |d| is above its 97.5th percentile in either half
# leave it. A few half-sample estimates run far from the prior (factors of
# e^4 and more in a known-truth world), and their products dominate the
# untrimmed sum (1.30 there, against a true row variance of 0.42; trimmed,
# 0.61). The trim was chosen after inspecting that one world (seed 20261015,
# shock scale 1), which is also one of reading R6's six; the untrimmed value
# is reported beside it.
#
# --mode estimate   tau2_eb from the two weak-prior halves, plus, for
#                   information only, the split-half correlation of
#                   exporter-product effects (an exporter's mean deviation from
#                   its cells' means across the importers it sells the product
#                   to). It is NOT a test of whether exporter differences are
#                   recoverable: in a known-truth world with no exporter
#                   component these effects reproduced across halves (r 0.49)
#                   while tracking their true counterparts not at all (r -0.15
#                   to 0.02), so something exporter-specific in the data or the
#                   estimator, not gamma, moves an exporter's cells together.
#                   Reading R6 of validation/known_truth_stage2.R records both
#                   numbers per world.
# --mode check      the halves re-estimated at tau2_eb against the shipped
#                   halves. Reading (fixed in patch 0133): "adopt-candidate" if
#                   (1) the known-truth validation (reading R6 of
#                   validation/known_truth_stage2.R) says "EB validated";
#                   (2) tau2_eb lies in [0.02, 2]; (3) the split-half
#                   correlation of the cells' mean deviations from the product
#                   prior (importer differences within a product) is at least
#                   the shipped halves'; and (4) the product medians of gamma
#                   move by a median of at most 0.10 in logs against the
#                   shipped halves; otherwise "keep the shipped ridge".
#
# Usage (repo root; seconds):
#   Rscript analysis/ridge_tau2_eb.R --mode estimate --half-a A.rds --half-b B.rds --regional R.rds
#       [--json results/ridge_tau2_eb.json] [--md docs/results/ridge_tau2_eb.md]
#   Rscript analysis/ridge_tau2_eb.R --mode check --cand-a A --cand-b B --ship-a C --ship-b D
#       --regional R.rds --eb-json results/ridge_tau2_eb.json --kt-json results/known_truth_eb.json
#       [--json results/ridge_tau2_check.json] [--md docs/results/ridge_tau2_check.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

#' The product priors Stage 2b shrinks toward, built from a Stage-2a table as
#' scripts/run_estimation.R builds them (shipped handoff and prior rows).
eb_priors <- function(regional) {
  rh <- stage2a_handoff_rows(data.table::as.data.table(regional), "published")
  rc <- rh[!is.na(sigma) & !is.na(gamma) & gamma > 0]
  p <- stage2b_priors_from_regional(rc, rows = "estimated")$country_priors
  p[, .(good = as.character(good), ln_prior = ln_gamma_prior)]
}

#' A half's directly estimated rows with their deviation from the prior and
#' the data's share of their curvature.
eb_rows <- function(s2b, priors) {
  x <- data.table::as.data.table(s2b)
  if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
  x <- x[is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0]
  x[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]
  x <- merge(x, priors, by = "good")
  x[, `:=`(d = log(gamma) - ln_prior, w = pmin(pmax(1 - gamma_shrink_wt, 0), 1))]
  x[, .(importer, exporter, good, d, w)]
}

#' tau2_eb from two halves (2.5% trim of |d| in each half; untrimmed beside it).
eb_tau2 <- function(odd, even, priors, trim = 0.025) {
  m <- merge(eb_rows(odd, priors), eb_rows(even, priors), by = c("importer", "exporter", "good"), suffixes = c("_o", "_e"))
  m <- m[is.finite(d_o) & is.finite(d_e) & is.finite(w_o) & is.finite(w_e)]
  mom <- function(x) { den <- sum(x$w_o * x$w_e); if (nrow(x) && den > 0) sum(x$d_o * x$d_e) / den else NA_real_ }
  k <- if (nrow(m)) abs(m$d_o) <= stats::quantile(abs(m$d_o), 1 - trim, names = FALSE) &
                    abs(m$d_e) <= stats::quantile(abs(m$d_e), 1 - trim, names = FALSE) else logical(0)
  list(rows = nrow(m), rows_after_trim = sum(k), tau2_eb = mom(m[k]), tau2_eb_untrimmed = mom(m),
       mean_w_odd = mean(m$w_o), mean_w_even = mean(m$w_e),
       row_spearman = if (nrow(m) >= 4L) suppressWarnings(stats::cor(m$d_o, m$d_e, method = "spearman")) else NA_real_)
}

#' Exporter-product effects: an exporter's mean deviation from its cells' mean
#' ln gamma, across the importers it sells the product to (>= min_imp in both
#' halves); their split-half correlation.
eb_exporter_effects <- function(odd, even, min_imp = 3L) {
  eff <- function(s2b) {
    x <- data.table::as.data.table(s2b)
    if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
    x <- x[is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0]
    x[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good), lg = log(gamma))]
    x[, dc := lg - mean(lg), by = .(importer, good)]
    x[, .(e = mean(dc), n_imp = .N), by = .(exporter, good)]
  }
  m <- merge(eff(odd), eff(even), by = c("exporter", "good"), suffixes = c("_o", "_e"))
  m <- m[n_imp_o >= min_imp & n_imp_e >= min_imp]
  list(exporter_goods = nrow(m), pearson = if (nrow(m) >= 10L) suppressWarnings(stats::cor(m$e_o, m$e_e)) else NA_real_,
       spearman = if (nrow(m) >= 10L) suppressWarnings(stats::cor(m$e_o, m$e_e, method = "spearman")) else NA_real_,
       effects = m[, .(exporter, good, e_o, e_e)])
}

#' Importer differences within a product: the split-half correlation of the
#' cells' mean deviation from the product prior.
eb_cell_reliability <- function(odd, even, priors) {
  cm <- function(s2b) eb_rows(s2b, priors)[, .(cd = mean(d)), by = .(importer, good)]
  m <- merge(cm(odd), cm(even), by = c("importer", "good"), suffixes = c("_o", "_e"))
  list(cells = nrow(m), pearson = if (nrow(m) >= 4L) suppressWarnings(stats::cor(m$cd_o, m$cd_e)) else NA_real_)
}

#' Product medians of gamma (directly estimated rows).
eb_product_medians <- function(s2b) {
  x <- data.table::as.data.table(s2b)
  if ("trim_reason" %in% names(x)) x <- x[is.na(trim_reason)]
  x[is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0, .(lm = log(stats::median(gamma))), by = .(good = as.character(good))]
}

eb_check <- function(co, ce, so, se, priors, tau2, kt_verdict) {
  rc <- eb_cell_reliability(co, ce, priors); rs <- eb_cell_reliability(so, se, priors)
  shift <- function(a, b) { m <- merge(eb_product_medians(a), eb_product_medians(b), by = "good"); stats::median(abs(m$lm.x - m$lm.y)) }
  sh <- mean(c(shift(co, so), shift(ce, se)))
  conds <- list(known_truth = identical(kt_verdict, "EB validated"), tau2_in_range = is.finite(tau2) && tau2 >= 0.02 && tau2 <= 2,
                reproducibility = is.finite(rc$pearson) && is.finite(rs$pearson) && rc$pearson >= rs$pearson,
                level_shift = is.finite(sh) && sh <= 0.10)
  list(candidate = rc, shipped = rs, product_median_shift = sh, conditions = conds,
       reading = if (all(unlist(conds))) "adopt-candidate" else "keep the shipped ridge")
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  for (f in c("R/utils_general.R", "R/iteration_helpers.R")) source(f)
  mode <- get_arg("--mode", NA_character_)
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  f3 <- function(x) formatC(x, digits = 3, format = "f")
  if (identical(mode, "estimate")) {
    p <- c(odd = get_arg("--half-a", NA), even = get_arg("--half-b", NA), regional = get_arg("--regional", NA))
    if (anyNA(p) || !all(file.exists(p))) stop("usage: --mode estimate --half-a A.rds --half-b B.rds --regional R.rds")
    json <- get_arg("--json", "results/ridge_tau2_eb.json"); md <- get_arg("--md", "docs/results/ridge_tau2_eb.md")
    pri <- eb_priors(readRDS(p[["regional"]])); o <- readRDS(p[["odd"]]); e <- readRDS(p[["even"]])
    est <- eb_tau2(o, e, pri); ex <- eb_exporter_effects(o, e)
    ex$effects <- NULL
    jsonlite::write_json(list(meta = c(as.list(p), git_rev = rev, timestamp = ts), tau2 = est, exporter_effects = ex),
                         json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
    writeLines(enc2utf8(c("# Empirical-Bayes tau^2 for the precision-scaled ridge (patch 0133)", "",
      sprintf("Half a `%s`, half b `%s` (Stage 2b on alternate four-year blocks at tau^2 = 1, same Stage 1 and Stage-2a priors); rev %s, %s.", p[["odd"]], p[["even"]], rev, ts), "",
      sprintf("- **tau2_eb = %s** (2.5%% trim; %s untrimmed) on %s rows directly estimated in both halves, %s after the trim (mean data share %s / %s; Spearman of the deviations between halves %s).",
              f3(est$tau2_eb), f3(est$tau2_eb_untrimmed), format(est$rows, big.mark = ","), format(est$rows_after_trim, big.mark = ","),
              f3(est$mean_w_odd), f3(est$mean_w_even), f3(est$row_spearman)),
      sprintf("- Exporter-product effects, for information only: split-half correlation %s (Spearman %s) over %s exporter-products seen with at least 3 importers in both halves. At known truth such effects reproduce across halves without tracking any true exporter difference (reading R6 of `docs/results/known_truth_eb.md`), so this number is not evidence that exporter differences within a cell are recoverable.",
              f3(ex$pearson), f3(ex$spearman), format(ex$exporter_goods, big.mark = ",")))), md, useBytes = TRUE)
    cat(sprintf("tau2_eb %.4f (untrimmed %.4f; %d rows); exporter-product effects split-half r %.3f (information only)\n", est$tau2_eb, est$tau2_eb_untrimmed, est$rows, ex$pearson))
  } else if (identical(mode, "check")) {
    p <- c(co = get_arg("--cand-a", NA), ce = get_arg("--cand-b", NA), so = get_arg("--ship-a", NA), se = get_arg("--ship-b", NA),
           regional = get_arg("--regional", NA), eb = get_arg("--eb-json", NA), kt = get_arg("--kt-json", NA))
    if (anyNA(p) || !all(file.exists(p))) stop("usage: --mode check --cand-a A --cand-b B --ship-a C --ship-b D --regional R --eb-json F --kt-json F")
    json <- get_arg("--json", "results/ridge_tau2_check.json"); md <- get_arg("--md", "docs/results/ridge_tau2_check.md")
    tau2 <- jsonlite::fromJSON(p[["eb"]])$tau2$tau2_eb
    kt <- jsonlite::fromJSON(p[["kt"]])$readings$R6_eb$verdict
    res <- eb_check(readRDS(p[["co"]]), readRDS(p[["ce"]]), readRDS(p[["so"]]), readRDS(p[["se"]]), eb_priors(readRDS(p[["regional"]])), tau2, kt)
    jsonlite::write_json(c(list(meta = c(as.list(p), tau2_eb = tau2, git_rev = rev, timestamp = ts)), res), json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
    cd <- res$conditions
    writeLines(enc2utf8(c("# The precision-scaled ridge at the empirical-Bayes tau^2, on real data (patch 0133)", "",
      sprintf("2%% product subsample, alternate four-year blocks; tau2_eb = %s; candidate and shipped halves on the same blocks; rev %s, %s.", f3(tau2), rev, ts), "",
      sprintf("- Importer differences within a product, split-half correlation of the cells' mean deviation from the prior: %s at tau2_eb (%s cells) against %s shipped (%s cells).",
              f3(res$candidate$pearson), format(res$candidate$cells, big.mark = ","), f3(res$shipped$pearson), format(res$shipped$cells, big.mark = ",")),
      sprintf("- Product medians of gamma against the shipped halves: median |difference in logs| %s.", f3(res$product_median_shift)),
      sprintf("- Conditions: known-truth validation %s; tau2 in [0.02, 2] %s; reproducibility at least shipped %s; level shift <= 0.10 %s.",
              cd$known_truth, cd$tau2_in_range, cd$reproducibility, cd$level_shift), "",
      sprintf("**Reading (fixed in patch 0133): %s.**", res$reading))), md, useBytes = TRUE)
    cat(sprintf("ridge check at tau2_eb %.4f: %s\n", tau2, res$reading))
  } else stop("--mode estimate | check")
}
