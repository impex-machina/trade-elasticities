#!/usr/bin/env Rscript
# ============================================================================
# analysis/sigma_eb_period_census.R  (patch 0122, audit #8)
#
# The real-data test of empirical-Bayes sigma shrinkage (R/sigma_eb.R), the
# second step after validation/known_truth_stage2.R's R3 reading. Inputs: the
# two Stage-1 tables of the 2% product subsample estimated on 1995-2009 and on
# 2010-2024 (patch 0119's M3 sizing; independent data), as
# analysis/sigma_window_census.R reads them.
#
# Question: which sigma, built from one period, best predicts the other
# period's own estimate? Targets are the cells with an estimate in the target
# period (converged, sigma > 1, finite SE, not on a box edge), on
# z = ln(sigma - 1); predictors are built from the other period for every
# such cell:
#   published  the cell's own sigma if it is in that period's clean set
#              (stage2_sigma_clean(): edge and pole rules as shipped), else
#              that period's fallback (the clean-set median) -- the shipped rule;
#   eb         the empirical-Bayes posterior median (global prior);
#   eb_good    the same with one prior per good (global where a good has
#              fewer than 10 cells);
#   constant   the fallback for every cell.
# Scores, both directions (early -> late, late -> early): the median absolute
# error and the precision-weighted mean squared error (weights 1 / s_target^2,
# s the delta-method SE of the target z, so noisy targets count less). The
# target's own noise is common to every predictor, so differences between
# predictors are differences in how well they track the target's true value.
#
# Reading (fixed in patch 0122): EB passes the real-data test if, in BOTH
# directions, its weighted MSE is at least 5% below the published rule's and
# its median absolute error is not higher. EB becomes a candidate for a
# batched Stage-2 session only if it passes here AND known-truth reading R3
# says "qualifies".
#
# Usage (repo root; local, seconds):
#   Rscript analysis/sigma_eb_period_census.R --early E.rds --late L.rds
#       [--label v0110] [--out results/sigma_eb_period_census_v0110.json]
#       [--md docs/results/sigma_eb_period_census_v0110.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.eb_s1 <- function(x) {
  x <- data.table::copy(data.table::as.data.table(x))
  for (k in c("importer", "good")) data.table::set(x, j = k, value = as.character(x[[k]]))
  if (!"convergence" %in% names(x)) x[, convergence := fifelse(status == "ok", 0L, -99L)]
  x
}

#' Predictors from one period's Stage-1 table, for every cell of `cells`.
eb_predictors <- function(s1, cells) {
  s1 <- .eb_s1(s1)
  sc <- stage2_sigma_clean(s1); fb <- median(sc$clean$sigma)
  eb  <- sigma_eb_shrink(s1)
  ebg <- sigma_eb_shrink(s1, group = "good")
  out <- data.table::copy(cells)
  out <- merge(out, sc$clean[, .(importer, good, s_pub = sigma)], by = c("importer", "good"), all.x = TRUE)
  out[is.na(s_pub), s_pub := fb]
  out <- merge(out, eb[, .(importer, good, s_eb = sigma_eb)], by = c("importer", "good"), all.x = TRUE)
  out[is.na(s_eb), s_eb := 1 + exp(attr(eb, "eb_mu"))]
  out <- merge(out, ebg[, .(importer, good, s_ebg = sigma_eb)], by = c("importer", "good"), all.x = TRUE)
  out[is.na(s_ebg), s_ebg := 1 + exp(attr(eb, "eb_mu"))]
  out[, s_const := fb]
  data.table::setattr(out, "fit", list(fallback = fb, eb_mu = attr(eb, "eb_mu"), eb_tau2 = attr(eb, "eb_tau2"), eb_n = attr(eb, "eb_n"),
                                       eb_good_own_priors = sum(attr(ebg, "eb_groups")$own)))
  out
}

#' Targets: one period's own estimates, on z = ln(sigma - 1), with their SEs.
eb_targets <- function(s1) {
  s1 <- .eb_s1(s1)
  edge <- if ("sigma_capped" %in% names(s1)) s1$sigma_capped %in% TRUE else rep(FALSE, nrow(s1))
  t <- s1[convergence == 0L & is.finite(sigma) & sigma > 1 & is.finite(sigma_se) & sigma_se > 0 & !edge,
          .(importer, good, z = log(sigma - 1), s = sigma_se / (sigma - 1))]
  t
}

#' Score the predictors from `from` against the targets in `to`.
eb_score <- function(from, to) {
  tg <- eb_targets(to)
  goods <- intersect(unique(.eb_s1(from)$good), unique(tg$good))
  tg <- tg[good %in% goods]
  p <- eb_predictors(.eb_s1(from)[good %in% goods], tg[, .(importer, good)])
  m <- merge(tg, p, by = c("importer", "good"))
  w <- 1 / m$s^2
  sc <- function(col) { e <- m$z - log(m[[col]] - 1); list(median_abs_err = median(abs(e)), wmse = sum(w * e^2) / sum(w)) }
  c(list(targets = nrow(m), goods = length(goods)), list(fit = attr(p, "fit")),
    list(published = sc("s_pub"), eb = sc("s_eb"), eb_good = sc("s_ebg"), constant = sc("s_const")))
}

sigma_eb_period_census <- function(early, late) {
  el <- eb_score(early, late); le <- eb_score(late, early)
  pass_dir <- function(x) x$eb$wmse <= 0.95 * x$published$wmse && x$eb$median_abs_err <= x$published$median_abs_err
  list(early_to_late = el, late_to_early = le,
       reading = list(rule = "EB weighted MSE >= 5% below the published rule's and median |error| not higher, in both directions",
                      early_to_late = pass_dir(el), late_to_early = pass_dir(le),
                      verdict = if (pass_dir(el) && pass_dir(le)) "passes" else "fails"))
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "R/sigma_eb.R")) source(f)
  ep <- get_arg("--early", NA_character_); lp <- get_arg("--late", NA_character_)
  if (is.na(ep) || is.na(lp)) stop("usage: Rscript analysis/sigma_eb_period_census.R --early E.rds --late L.rds [--label L] [--out F.json] [--md F.md]")
  label <- get_arg("--label", "v0110")
  out <- get_arg("--out", sprintf("results/sigma_eb_period_census_%s.json", label))
  md  <- get_arg("--md", sprintf("docs/results/sigma_eb_period_census_%s.md", label))
  res <- sigma_eb_period_census(readRDS(ep), readRDS(lp))
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  res$meta <- list(early = ep, late = lp, label = label, git_rev = rev, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  jsonlite::write_json(res, out, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f <- function(x) formatC(x, digits = 4, format = "f")
  row <- function(nm, d) sprintf("| %s | %s | %s |", nm, f(d$median_abs_err), f(d$wmse))
  blk <- function(title, x) c(sprintf("### %s (%s target cells, %s goods)", title, format(x$targets, big.mark = ","), x$goods), "",
                              sprintf("Source-period fit: fallback sigma %s; EB prior mu %s, tau^2 %s on %s cells; %s goods with their own prior.",
                                      f(x$fit$fallback), f(x$fit$eb_mu), f(x$fit$eb_tau2), format(x$fit$eb_n, big.mark = ","), x$fit$eb_good_own_priors), "",
                              "| predictor | median abs error | weighted MSE |", "|---|---|---|",
                              row("published rule", x$published), row("EB (global prior)", x$eb), row("EB (prior per good)", x$eb_good), row("constant (fallback)", x$constant), "")
  writeLines(enc2utf8(c(sprintf("# EB sigma shrinkage on the period split (%s)", label), "",
                        sprintf("Inputs: `%s` (1995-2009) and `%s` (2010-2024); rev %s, %s. Errors on z = ln(sigma - 1) against the other period's own estimate.",
                                ep, lp, res$meta$git_rev, res$meta$timestamp), "",
                        blk("Early predicts late", res$early_to_late), blk("Late predicts early", res$late_to_early),
                        sprintf("**Reading (fixed in patch 0122): %s** -- %s; early -> late %s, late -> early %s.", res$reading$verdict, res$reading$rule,
                                res$reading$early_to_late, res$reading$late_to_early))), md, useBytes = TRUE)
  cat(sprintf("sigma EB period census: %s (early->late %s, late->early %s) -> %s, %s\n", res$reading$verdict,
              res$reading$early_to_late, res$reading$late_to_early, out, md))
}
