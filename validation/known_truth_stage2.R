#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_stage2.R  (patch 0122, audit #8)
#
# Does the shipped pipeline recover the parameters that generated the data?
# Pillar 2 tests Stage 1 cell by cell, the structural-DGP harness tests the
# Eq. (10)/(11) moment identities at the truth, and the split-half / period
# reliability measures say how reproducible the published gamma is -- none of
# them compares a published gamma with a known one. Here the whole pipeline
# (scripts/run_estimation.R, production defaults) runs on synthetic BACI
# directories from validation/synthetic_baci.R (Soderbery's model, known sigma
# and gamma, BACI's file layout) and its output is compared with the truth.
#
# Worlds: seeds x shock scales (the volatility of the demand and supply
# shocks; the Stage-2 ridge's weight relative to the data scales with the
# fourth power of it). Arms, each a full Stage 2a + 2b (three gamma_V passes)
# on the world's Stage-1 table:
#   shipped     the published configuration;
#   lambda0     --shrinkage-lambda 0 (Stage 2b unpenalized; 2a keeps 0.05);
#   truesigma   the true sigma written into the Stage-1 table (SE 0.01), lambda 0.1;
#   truesigma0  the true sigma, lambda 0 -- the best case Stage 2 can have;
#   sigma_eb    every cell's sigma replaced by its empirical-Bayes posterior
#               median (R/sigma_eb.R; global prior on ln(sigma - 1)), with the
#               edge and pole rules off (the shrinkage replaces them).
# Metrics per run (published rows; directly estimated rows for gamma):
#   within-cell: r and rank r between estimated and true ln gamma, each
#     demeaned by (importer, good); ratio of their within-cell s.d.;
#   cell level: correlation with the truth and median |log ratio| of the
#     cell mean ln gamma, of the composite gamma/((1+gamma)(sigma-1)) (the
#     quantity the import moments pin) and of opt_tariff (the truth's tariff
#     uses the true gamma and sigma with the published exporters and weights);
#   sigma: median |error| in ln(sigma - 1) of the sigma Stage 2 used, per cell;
#   median gamma_shrink_wt, convergence share, fallback-sigma share.
# Per world, without Stage 2: sigma accuracy of the raw Stage-1 estimates, the
# published rule (own sigma in the clean set, else the fallback) and the EB
# posterior, over every true cell.
#
# READINGS (fixed in patch 0122, before the grid's numbers; medians over seeds,
# per shock scale):
#   R1 within-cell gamma. "recovered" if the shipped arm's within-cell r >= 0.5
#      at every scale; "not recovered" if it is < 0.3 at every scale AND the
#      truesigma0 arm's is < 0.5 at every scale -- then the within-cell spread
#      of the published gamma is not exporter-level information even when every
#      assumption holds, and the README / card / paper say so; otherwise
#      "partial", recorded and decided with the numbers in hand.
#   R2 cell-level opt_tariff (shipped arm). "usable" if the correlation of
#      ln opt_tariff with the truth across cells is >= 0.5 at every scale,
#      "weak" if < 0.3 at every scale, otherwise "partial".
#   R3 sigma EB. "qualifies" (for the real-data period test,
#      analysis/sigma_eb_period_census.R) if, in a majority of worlds, the EB
#      posterior's median |error| in ln(sigma - 1) is at least 10% below the
#      published rule's AND the sigma_eb arm's median |log ratio| of
#      opt_tariff is no more than 5% above the shipped arm's (median over
#      worlds); otherwise "closed at known truth".
# STRUCTURED WORLDS (patch 0123). In the worlds above every pair's gamma is an
# independent draw, so no good has systematically higher gammas and R2 can only
# ask about within-good noise. --structures adds worlds whose ln gamma carries a
# good effect ("good": s.d. 0.7 between goods, 0.35 within) or a good and an
# importer effect ("good_importer": plus s.d. 0.5 between importers); sigma, the
# shocks and the trade pattern are those of the unstructured world of the same
# seed (validation/synthetic_baci.R). Added metrics (all worlds):
#   between goods: correlation across goods of the log median gamma (directly
#     estimated rows) and of the mean ln opt_tariff, estimated vs true;
#   within goods: cell mean ln gamma and ln opt_tariff demeaned by good --
#     their correlation with the truth and the ratio of their s.d.
# READING R4 (fixed in patch 0123, before the structured grid's numbers;
# shipped arm, medians over seeds, per shock scale):
#   R4a between goods ("good" worlds): "recovered" if both between-good
#       correlations are >= 0.7 at every scale; "not recovered" if both are
#       < 0.4 at every scale; otherwise "partial".
#   R4b within goods, across importers ("good_importer" worlds): "not
#       recovered" if the within-good s.d. ratio of the cell mean ln gamma is
#       < 0.1 at every scale (the published gamma carries no importer
#       differences) or its within-good correlation is < 0.2 at every scale;
#       "recovered" if the correlation is >= 0.5 and the s.d. ratio >= 0.5 at
#       every scale; otherwise "partial".
#   If R4a says "recovered" and R4b "not recovered", the README and card
#   describe gamma and opt_tariff as good-level information.
#
# A synthetic world satisfies every assumption the estimator makes and has no
# unit-value measurement error: the most favourable case, not a calibration.
#
# Usage (repo root; local, no EC2; ~1-2 min per arm per world on one core):
#   Rscript validation/known_truth_stage2.R --out DIR
#       [--seeds 20261015,20261016,20261017] [--scales 1,3]
#       [--arms shipped,lambda0,truesigma,truesigma0,sigma_eb]
#       [--goods 5] [--countries 15] [--years 1995:2024] [--ncores 1]
#       [--structures none | good,good_importer]
#       [--json results/known_truth_stage2.json] [--md docs/results/known_truth_stage2.md]
#   With --structures other than none the defaults become --goods 12,
#   --arms shipped, --json results/known_truth_structured.json and --md
#   docs/results/known_truth_structured.md.
#   Outputs of finished runs under DIR are reused; a world directory whose
#   truth.rds was generated with other settings stops the run rather than
#   being reused (delete DIR or choose another --out).
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

KT_ARMS <- list(
  shipped    = list(args = character(), stage1 = "estimated"),
  lambda0    = list(args = c("--shrinkage-lambda", "0"), stage1 = "estimated"),
  truesigma  = list(args = character(), stage1 = "true"),
  truesigma0 = list(args = c("--shrinkage-lambda", "0"), stage1 = "true"),
  sigma_eb   = list(args = c("--stage2-sigma-pole-rule", "none", "--stage2-sigma-edge", "publish"), stage1 = "eb"),
  # (patch 0132) the precision-scaled ridge at three prior variances of ln gamma
  ridge_t002 = list(args = c("--stage2-ridge-scale", "cell", "--stage2-ridge-tau2", "0.02"), stage1 = "estimated"),
  ridge_t01  = list(args = c("--stage2-ridge-scale", "cell", "--stage2-ridge-tau2", "0.1"), stage1 = "estimated"),
  ridge_t05  = list(args = c("--stage2-ridge-scale", "cell", "--stage2-ridge-tau2", "0.5"), stage1 = "estimated")
)
KT_PREFIX <- "baci_hs92_v202601_elast_country_hs4"
# (patch 0123) world structures: the s.d. of the good effect, the importer
# effect and the pair's own deviation in ln gamma (validation/synthetic_baci.R)
KT_STRUCTURES <- list(
  none          = list(good_sd = 0,   importer_sd = 0,   within_sd = 0.7),
  good          = list(good_sd = 0.7, importer_sd = 0,   within_sd = 0.35),
  good_importer = list(good_sd = 0.7, importer_sd = 0.5, within_sd = 0.35)
)

#' A world's directory: the patch-0122 name for unstructured worlds (so their
#' runs are reused), the structure appended otherwise.
kt_world_dir <- function(out, seed, scale, structure = "none") {
  base <- sprintf("w%d_x%s", seed, format(scale))
  file.path(out, if (identical(structure, "none")) base else paste0(base, "_", structure))
}

#' Stop if an existing world was generated with other settings.
kt_check_world <- function(meta, seed, scale, goods, countries, years, st) {
  want <- list(seed = seed, shock_scale = scale, n_goods = goods, n_countries = length(countries),
               years = range(years), good_sd = st$good_sd, importer_sd = st$importer_sd, within_sd = st$within_sd)
  have <- list(seed = meta$seed, shock_scale = meta$shock_scale, n_goods = meta$n_goods, n_countries = length(meta$countries),
               years = meta$years, good_sd = if (is.null(meta$good_sd)) 0 else meta$good_sd,
               importer_sd = if (is.null(meta$importer_sd)) 0 else meta$importer_sd,
               within_sd = if (is.null(meta$within_sd)) 0.7 else meta$within_sd)
  bad <- names(want)[!vapply(names(want), function(k) isTRUE(all.equal(as.numeric(want[[k]]), as.numeric(have[[k]]))), TRUE)]
  if (length(bad)) stop(sprintf("world directory holds a world generated with other settings (%s); delete it or choose another --out",
                                paste(bad, collapse = ", ")), call. = FALSE)
  invisible(TRUE)
}

#' Source the library pieces the harness needs (no Rcpp).
kt_source <- function(root, env = parent.frame()) {
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "R/sigma_eb.R", "validation/synthetic_baci.R"))
    sys.source(file.path(root, f), envir = env)
  invisible(env)
}

#' The Stage-1 table an arm hands to Stage 2.
kt_arm_stage1 <- function(s1, kind, truth_sigma) {
  x <- data.table::copy(data.table::as.data.table(s1))
  if (kind == "estimated") return(x)
  if (kind == "true") {
    key <- paste(as.character(x$importer), as.character(x$good))
    tk <- paste(as.character(truth_sigma$importer), as.character(truth_sigma$good))
    m <- match(key, tk); has <- !is.na(m)
    x[has, `:=`(sigma = truth_sigma$sigma_true[m[has]], sigma_se = 0.01, status = "ok", convergence = 0L)]
    if ("sigma_capped" %in% names(x)) x[has, sigma_capped := FALSE]
    if ("adjust" %in% names(x)) x[has, adjust := 0L]
    if ("final_source" %in% names(x)) x[has, final_source := "hliml"]
    if ("hliml_boundary_edge" %in% names(x)) x[has, hliml_boundary_edge := NA]
    return(x)
  }
  if (kind == "eb") {
    eb <- sigma_eb_shrink(x)
    # sigma_capped stays: under --stage2-sigma-edge publish it no longer moves a
    # cell out of the clean set, and the capped-omega rule keeps such cells'
    # omega out of the Stage-2a priors exactly as in the shipped arm.
    x[, `:=`(sigma = eb$sigma_eb, sigma_se = eb$sigma_eb_se, status = "ok", convergence = 0L)]
    data.table::setattr(x, "eb_mu", attr(eb, "eb_mu")); data.table::setattr(x, "eb_tau2", attr(eb, "eb_tau2"))
    return(x)
  }
  stop("kt_arm_stage1(): unknown kind ", kind)
}

#' Run scripts/run_estimation.R; the log is kept in out_dir/run.log.
kt_run <- function(root, baci_dir, out_dir, args = character(), ncores = 1L) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  rs <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rs, c(shQuote(file.path(root, "scripts", "run_estimation.R")), "--data", shQuote(baci_dir),
                                        "--out-dir", shQuote(out_dir), "--ncores", as.character(ncores), args),
                                  stdout = TRUE, stderr = TRUE))
  writeLines(out, file.path(out_dir, "run.log"))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  if (st != 0L) stop(sprintf("run_estimation.R failed (status %d) in %s; last lines:\n%s", st, out_dir,
                             paste(utils::tail(out, 25), collapse = "\n")))
  invisible(out)
}

#' Sigma accuracy over every true cell: raw estimates, published rule, EB.
kt_sigma_level <- function(s1, truth_sigma) {
  s1 <- data.table::copy(data.table::as.data.table(s1))
  s1[, `:=`(importer = as.character(importer), good = as.character(good))]
  if (!"convergence" %in% names(s1)) s1[, convergence := fifelse(status == "ok", 0L, -99L)]
  ts <- truth_sigma[, .(importer = as.character(importer), good = as.character(good), sigma_true)]
  sc <- stage2_sigma_clean(s1)
  fb <- median(sc$clean$sigma)
  eb <- sigma_eb_shrink(s1)
  m <- merge(ts, s1[, .(importer, good, sigma, convergence)], by = c("importer", "good"), all.x = TRUE)
  m <- merge(m, sc$clean[, .(importer, good, s_pub = sigma)], by = c("importer", "good"), all.x = TRUE)
  m[is.na(s_pub), s_pub := fb]
  m <- merge(m, eb[, .(importer = as.character(importer), good = as.character(good), sigma_eb, eb_weight, eb_data)],
             by = c("importer", "good"), all.x = TRUE)
  m[is.na(sigma_eb), sigma_eb := 1 + exp(attr(eb, "eb_mu"))]
  e <- function(a, t) abs(log(a - 1) - log(t - 1))
  raw <- m[convergence %in% 0L & sigma > 1]
  list(cells = nrow(m), cells_raw = nrow(raw),
       err_raw = median(e(raw$sigma, raw$sigma_true)), err_published = median(e(m$s_pub, m$sigma_true)),
       err_eb = median(e(m$sigma_eb, m$sigma_true)),
       rho_published = suppressWarnings(cor(m$s_pub, m$sigma_true, method = "spearman")),
       rho_eb = suppressWarnings(cor(m$sigma_eb, m$sigma_true, method = "spearman")),
       eb_mu = attr(eb, "eb_mu"), eb_tau2 = attr(eb, "eb_tau2"), eb_weight_median = median(m$eb_weight[m$eb_data %in% TRUE]),
       fallback = fb, share_fallback_cells = mean(!paste(m$importer, m$good) %in% paste(sc$clean$importer, sc$clean$good)))
}

#' Recovery metrics for one finished run.
kt_metrics <- function(out_dir, truth) {
  s2b <- data.table::as.data.table(readRDS(file.path(out_dir, paste0(KT_PREFIX, "_fixed_sigma.rds"))))
  pub <- if ("trim_reason" %in% names(s2b)) s2b[is.na(trim_reason)] else s2b
  for (k in c("importer", "exporter", "good")) data.table::set(pub, j = k, value = as.character(pub[[k]]))
  est <- pub[is_estimated_row(tier, convergence)]
  tg <- truth$gamma[, .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good), gamma_true)]
  ts <- truth$sigma[, .(importer = as.character(importer), good = as.character(good), sigma_true)]
  m <- merge(merge(est, tg, by = c("importer", "exporter", "good")), ts, by = c("importer", "good"))
  m <- m[is.finite(gamma) & gamma > 0]
  m[, n_cell := .N, by = .(importer, good)]
  w <- m[n_cell >= 2L]
  w[, `:=`(de = log(gamma) - mean(log(gamma)), dt = log(gamma_true) - mean(log(gamma_true)),
           re = frank(gamma) - (.N + 1) / 2, rt = frank(gamma_true) - (.N + 1) / 2), by = .(importer, good)]
  cells <- m[, .(mlg = mean(log(gamma)), mlg_t = mean(log(gamma_true)),
                 kap = median(gamma / ((1 + gamma) * (sigma - 1))),
                 kap_t = median(gamma_true / ((1 + gamma_true) * (sigma_true - 1))),
                 ot = opt_tariff[1], ot_t = optimal_tariff(gamma_true, sigma_true[1], avg_trade),
                 sg = sigma[1], sg_t = sigma_true[1]), by = .(importer, good)]
  # correlations are NA (not a warning) where either side has no spread -- e.g. a
  # cell whose every gamma is the prior
  sc <- function(a, b) { ok <- is.finite(a) & is.finite(b); if (sum(ok) < 3L || sd(a[ok]) == 0 || sd(b[ok]) == 0) NA_real_ else cor(a[ok], b[ok]) }
  lc <- function(a, b) { ok <- is.finite(a) & is.finite(b) & a > 0 & b > 0; sc(log(a[ok]), log(b[ok])) }
  lr <- function(a, b) { ok <- is.finite(a) & is.finite(b) & a > 0 & b > 0; median(abs(log(a[ok] / b[ok]))) }
  # (patch 0123) between goods and within goods
  goods <- m[, .(lmg = log(median(gamma)), lmg_t = log(median(gamma_true))), by = good]
  okc <- cells[is.finite(ot) & ot > 0 & is.finite(ot_t) & ot_t > 0]
  gt <- okc[, .(lot = mean(log(ot)), lot_t = mean(log(ot_t))), by = good]
  wg <- data.table::copy(cells)[, `:=`(mw = mlg - mean(mlg), mw_t = mlg_t - mean(mlg_t)), by = good]
  wt <- data.table::copy(okc)[, `:=`(ow = log(ot) - mean(log(ot)), ow_t = log(ot_t) - mean(log(ot_t))), by = good]
  sdr <- function(a, b) { if (length(a) < 3L || sd(b) == 0) NA_real_ else sd(a) / sd(b) }
  list(rows = nrow(m), cells = nrow(cells),
       within_r = sc(w$de, w$dt), within_rank_r = sc(w$re, w$rt),
       within_sd_ratio = if (nrow(w) > 2L) sd(w$de) / sd(w$dt) else NA_real_,
       cell_mean_lngamma_r = sc(cells$mlg, cells$mlg_t),
       composite_r = lc(cells$kap, cells$kap_t), composite_err = lr(cells$kap, cells$kap_t),
       opt_tariff_r = lc(cells$ot, cells$ot_t), opt_tariff_err = lr(cells$ot, cells$ot_t),
       sigma_err = median(abs(log(cells$sg - 1) - log(cells$sg_t - 1))),
       between_good_gamma_r = sc(goods$lmg, goods$lmg_t), between_good_tariff_r = sc(gt$lot, gt$lot_t),
       within_good_gamma_r = sc(wg$mw, wg$mw_t), within_good_gamma_sd_ratio = sdr(wg$mw, wg$mw_t),
       within_good_tariff_r = sc(wt$ow, wt$ow_t), within_good_tariff_sd_ratio = sdr(wt$ow, wt$ow_t),
       shrink_wt_median = suppressWarnings(median(est$gamma_shrink_wt, na.rm = TRUE)),
       converged_share = mean(est$convergence == 0L),
       fallback_sigma_share = if ("sigma_source" %in% names(pub)) mean(pub$sigma_source != "estimated") else NA_real_,
       gamma_median = median(m$gamma), gamma_true_median = median(m$gamma_true))
}

.kt_none <- function(x) if ("structure" %in% names(x)) x[structure == "none"] else x

#' The pre-registered readings R1-R3 (unstructured worlds).
kt_readings <- function(summary, sigma_level, runs) {
  summary <- .kt_none(summary); runs <- .kt_none(runs); sigma_level <- .kt_none(sigma_level)
  if (!nrow(summary)) return(list(R1_within_cell_gamma = list(verdict = "not measured"), R2_cell_opt_tariff = list(verdict = "not measured"),
                                  R3_sigma_eb = list(verdict = "not measured")))
  sc <- sort(unique(summary$scale))
  get <- function(arm, col) vapply(sc, function(x) { v <- summary[arm_name == arm & scale == x][[col]]; if (length(v)) v else NA_real_ }, 0)
  sh_w <- get("shipped", "within_r"); t0_w <- get("truesigma0", "within_r"); sh_ot <- get("shipped", "opt_tariff_r")
  r1 <- if (all(is.finite(sh_w)) && all(sh_w >= 0.5)) "recovered" else
        if (all(is.finite(sh_w)) && all(sh_w < 0.3) && all(is.finite(t0_w)) && all(t0_w < 0.5)) "not recovered" else "partial"
  r2 <- if (all(is.finite(sh_ot)) && all(sh_ot >= 0.5)) "usable" else if (all(is.finite(sh_ot)) && all(sh_ot < 0.3)) "weak" else "partial"
  r3 <- "closed at known truth"; r3_detail <- list()
  if (nrow(sigma_level) && "sigma_eb" %in% runs$arm_name) {
    better <- sigma_level$err_eb <= 0.9 * sigma_level$err_published
    ot_sh <- median(runs[arm_name == "shipped"]$opt_tariff_err, na.rm = TRUE)
    ot_eb <- median(runs[arm_name == "sigma_eb"]$opt_tariff_err, na.rm = TRUE)
    r3_detail <- list(worlds = nrow(sigma_level), worlds_sigma_err_down_10pct = sum(better),
                      opt_tariff_err_shipped = ot_sh, opt_tariff_err_sigma_eb = ot_eb)
    if (sum(better) > nrow(sigma_level) / 2 && is.finite(ot_eb) && is.finite(ot_sh) && ot_eb <= 1.05 * ot_sh) r3 <- "qualifies"
  }
  list(R1_within_cell_gamma = list(verdict = r1, shipped_within_r_by_scale = setNames(as.list(sh_w), paste0("x", sc)),
                                   truesigma0_within_r_by_scale = setNames(as.list(t0_w), paste0("x", sc))),
       R2_cell_opt_tariff = list(verdict = r2, shipped_opt_tariff_r_by_scale = setNames(as.list(sh_ot), paste0("x", sc))),
       R3_sigma_eb = c(list(verdict = r3), r3_detail))
}

#' The pre-registered reading R4 (structured worlds; patch 0123).
kt_readings_r4 <- function(summary) {
  if (!"structure" %in% names(summary)) summary <- data.table::copy(summary)[, structure := "none"]
  pick <- function(st, col) {
    x <- summary[structure == st & arm_name == "shipped"]
    if (!nrow(x)) return(NULL)
    setNames(as.list(x[[col]][order(x$scale)]), paste0("x", sort(x$scale)))
  }
  all_ge <- function(v, t) !is.null(v) && all(is.finite(unlist(v))) && all(unlist(v) >= t)
  all_lt <- function(v, t) !is.null(v) && all(is.finite(unlist(v))) && all(unlist(v) < t)
  bg <- pick("good", "between_good_gamma_r"); bt <- pick("good", "between_good_tariff_r")
  r4a <- if (is.null(bg)) "not measured" else if (all_ge(bg, 0.7) && all_ge(bt, 0.7)) "recovered" else
         if (all_lt(bg, 0.4) && all_lt(bt, 0.4)) "not recovered" else "partial"
  wr <- pick("good_importer", "within_good_gamma_r"); ws <- pick("good_importer", "within_good_gamma_sd_ratio")
  r4b <- if (is.null(ws)) "not measured" else if (all_lt(ws, 0.1) || all_lt(wr, 0.2)) "not recovered" else
         if (all_ge(wr, 0.5) && all_ge(ws, 0.5)) "recovered" else "partial"
  list(R4a_between_goods = list(verdict = r4a, gamma_r_by_scale = bg, tariff_r_by_scale = bt),
       R4b_within_goods = list(verdict = r4b, gamma_r_by_scale = wr, gamma_sd_ratio_by_scale = ws,
                               tariff_r_by_scale = pick("good_importer", "within_good_tariff_r"),
                               between_goods_gamma_r_by_scale = pick("good_importer", "between_good_gamma_r")),
       good_level_reading = identical(r4a, "recovered") && identical(r4b, "not recovered"))
}

#' The pre-registered reading R5 (patch 0132): does the precision-scaled ridge,
#' at any of its prior variances, recover more than the shipped ridge in the
#' good_importer worlds? "calibrate on real data" if some tau2 arm, at every
#' shock scale (medians over seeds), reaches a within-good gamma r >= 0.40 or a
#' within-cell r >= 0.30 while keeping the between-good gamma r >= 0.80;
#' otherwise "closed".
kt_readings_r5 <- function(summary) {
  if (!"structure" %in% names(summary)) return(list(verdict = "not measured"))
  x <- summary[structure == "good_importer"]
  arms <- intersect(c("ridge_t002", "ridge_t01", "ridge_t05"), unique(x$arm_name))
  if (!length(arms)) return(list(verdict = "not measured"))
  per_arm <- lapply(c("shipped", arms), function(a) {
    y <- x[arm_name == a][order(scale)]
    list(arm = a, scales = y$scale, within_good_gamma_r = y$within_good_gamma_r, within_r = y$within_r,
         between_good_gamma_r = y$between_good_gamma_r)
  })
  pass <- vapply(per_arm[-1], function(z) all(is.finite(z$between_good_gamma_r)) && all(z$between_good_gamma_r >= 0.80) &&
                   (all(is.finite(z$within_good_gamma_r) & z$within_good_gamma_r >= 0.40) || all(is.finite(z$within_r) & z$within_r >= 0.30)), TRUE)
  list(verdict = if (any(pass)) "calibrate on real data" else "closed", arms_passing = arms[pass], per_arm = per_arm)
}

#' Run the grid (reusing finished runs) and return the results list.
kt_grid <- function(root, out, seeds, scales, arms, goods = 5L, countries = NULL, years = 1995:2024, ncores = 1L,
                    structures = "none") {
  all_ctys <- c(842L, 276L, 392L, 156L, 251L, 826L, 380L, 124L, 484L, 410L, 528L, 724L, 752L, 32L, 710L)
  ctys <- if (is.null(countries)) all_ctys else all_ctys[seq_len(min(countries, length(all_ctys)))]
  if (length(setdiff(structures, names(KT_STRUCTURES)))) stop("unknown structure(s): ", paste(setdiff(structures, names(KT_STRUCTURES)), collapse = ", "))
  runs <- list(); sig <- list(); worlds <- list()
  for (st_name in structures) for (seed in seeds) for (sc in scales) {
    st <- KT_STRUCTURES[[st_name]]
    tag <- sprintf("world seed %d x%s%s", seed, format(sc), if (st_name == "none") "" else paste0(" ", st_name))
    wdir <- kt_world_dir(out, seed, sc, st_name)
    baci <- file.path(wdir, "BACI_HS92_V202601"); tpath <- file.path(wdir, "truth.rds")
    if (file.exists(tpath) && length(list.files(baci, pattern = "^BACI_HS92_Y\\d{4}_V202601\\.csv$"))) {
      truth <- readRDS(tpath)
      kt_check_world(truth$meta, seed, sc, goods, ctys, years, st)
    } else {
      truth <- make_synthetic_baci_dir(baci, n_goods = goods, countries = ctys, years = years, seed = seed, shock_scale = sc,
                                       good_sd = st$good_sd, importer_sd = st$importer_sd, within_sd = st$within_sd)
      saveRDS(truth, tpath)
    }
    worlds[[length(worlds) + 1L]] <- list(structure = st_name, seed = seed, scale = sc, dir = wdir, hs6_rows = truth$meta$n_hs6_rows,
                                          importer_goods = nrow(truth$sigma), pairs = nrow(truth$gamma))
    shipped_dir <- file.path(wdir, "shipped")
    s1_path <- file.path(shipped_dir, paste0(KT_PREFIX, "_feenstra_sigma.rds"))
    if (!file.exists(file.path(shipped_dir, paste0(KT_PREFIX, "_fixed_sigma.rds")))) {
      cat(sprintf("[%s] %s: shipped (Stage 1 + 2a + 2b)\n", format(Sys.time(), "%H:%M:%S"), tag))
      kt_run(root, baci, shipped_dir, KT_ARMS$shipped$args, ncores)
    }
    s1 <- readRDS(s1_path)
    sl <- kt_sigma_level(s1, truth$sigma)
    sig[[length(sig) + 1L]] <- c(list(structure = st_name, seed = seed, scale = sc), sl)
    for (a in arms) {
      adir <- file.path(wdir, a)
      if (a != "shipped" && !file.exists(file.path(adir, paste0(KT_PREFIX, "_fixed_sigma.rds")))) {
        cat(sprintf("[%s] %s: arm %s\n", format(Sys.time(), "%H:%M:%S"), tag, a))
        dir.create(adir, recursive = TRUE, showWarnings = FALSE)
        file.copy(file.path(shipped_dir, paste0(KT_PREFIX, "_raw_cache.rds")), adir, overwrite = TRUE)
        saveRDS(kt_arm_stage1(s1, KT_ARMS[[a]]$stage1, truth$sigma), file.path(adir, paste0(KT_PREFIX, "_feenstra_sigma.rds")))
        kt_run(root, baci, adir, KT_ARMS[[a]]$args, ncores)
      }
      runs[[length(runs) + 1L]] <- c(list(structure = st_name, seed = seed, scale = sc, arm_name = a), kt_metrics(adir, truth))
    }
  }
  runs <- data.table::rbindlist(runs, fill = TRUE); sigma_level <- data.table::rbindlist(sig, fill = TRUE)
  num <- setdiff(names(runs)[vapply(runs, is.numeric, TRUE)], c("seed", "scale"))
  summary <- runs[, lapply(.SD, function(v) median(v, na.rm = TRUE)), by = .(structure, arm_name, scale), .SDcols = num]
  summary[, n_worlds := runs[, .N, by = .(structure, arm_name, scale)]$N]
  readings <- if ("none" %in% structures) kt_readings(summary, sigma_level, runs) else list()
  if (any(structures != "none")) readings <- c(readings, kt_readings_r4(summary))
  if (any(grepl("^ridge_", arms))) readings$R5_ridge_scale <- kt_readings_r5(summary)   # patch 0132
  list(worlds = worlds, runs = runs, sigma_level = sigma_level, summary = summary, readings = readings)
}

kt_md <- function(res, meta) {
  f <- function(x, d = 3) ifelse(is.na(x), "NA", formatC(x, digits = d, format = "f"))
  s_all <- res$summary
  # (patch 0124) the title names the patch whose readings the file reports (0122 for
  # the unstructured grid, 0123 for the structured one); it read "0122" for both
  out <- c(sprintf("# Known-truth recovery of the shipped pipeline (patch %s)", if (is.null(meta$patch)) "0122" else meta$patch), "",
           sprintf("Synthetic BACI worlds from `validation/synthetic_baci.R` (Soderbery's model, known sigma and gamma; %d goods, %d countries, years %s); seeds %s; shock scales %s; rev %s, %s.",
                   meta$goods, meta$countries, meta$years, paste(meta$seeds, collapse = ", "), paste(meta$scales, collapse = ", "), meta$git_rev, meta$timestamp), "")
  rd <- res$readings
  s <- .kt_none(s_all)
  if (nrow(s)) {
    s <- s[order(scale, match(arm_name, names(KT_ARMS)))]
    rows <- sprintf("| x%s | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |", format(s$scale), s$arm_name, s$n_worlds,
                    f(s$shrink_wt_median), f(s$within_r), f(s$within_rank_r), f(s$within_sd_ratio), f(s$cell_mean_lngamma_r),
                    f(s$composite_r), f(s$opt_tariff_r), f(s$opt_tariff_err), f(s$sigma_err))
    sl <- .kt_none(res$sigma_level)
    srows <- sprintf("| %d | x%s | %d | %s | %s | %s | %s | %s | %s |", sl$seed, format(sl$scale), sl$cells, f(sl$err_raw), f(sl$err_published),
                     f(sl$err_eb), f(sl$eb_tau2), f(sl$eb_weight_median), f(sl$share_fallback_cells))
    out <- c(out,
      "Medians over seeds. Within-cell: estimated vs true ln gamma, each demeaned by (importer, good); cell level: across (importer, good) cells; sigma error: median |error| in ln(sigma - 1) of the sigma Stage 2 used.", "",
      "| scale | arm | worlds | shrink wt | within r | within rank r | within sd ratio | cell mean ln gamma r | composite r | opt_tariff r | opt_tariff \\|log err\\| | sigma \\|err\\| |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|", rows, "",
      "## Sigma without Stage 2 (every true cell)", "",
      "| seed | scale | cells | raw estimates | published rule | EB posterior | EB tau^2 | EB weight (median) | fallback cells |",
      "|---|---|---|---|---|---|---|---|---|", srows, "",
      "## Readings (rules fixed in patch 0122; see the script header)", "",
      sprintf("- **R1 within-cell gamma: %s.** Shipped within-cell r by scale: %s; true sigma at lambda 0: %s.", rd$R1_within_cell_gamma$verdict,
              paste(sprintf("%s %s", names(rd$R1_within_cell_gamma$shipped_within_r_by_scale), f(unlist(rd$R1_within_cell_gamma$shipped_within_r_by_scale))), collapse = ", "),
              paste(sprintf("%s %s", names(rd$R1_within_cell_gamma$truesigma0_within_r_by_scale), f(unlist(rd$R1_within_cell_gamma$truesigma0_within_r_by_scale))), collapse = ", ")),
      sprintf("- **R2 cell-level opt_tariff: %s.** Shipped correlation of ln opt_tariff with the truth by scale: %s.", rd$R2_cell_opt_tariff$verdict,
              paste(sprintf("%s %s", names(rd$R2_cell_opt_tariff$shipped_opt_tariff_r_by_scale), f(unlist(rd$R2_cell_opt_tariff$shipped_opt_tariff_r_by_scale))), collapse = ", ")),
      sprintf("- **R3 sigma EB: %s.**%s", rd$R3_sigma_eb$verdict,
              if (is.null(rd$R3_sigma_eb$worlds)) "" else sprintf(" Sigma error at least 10%% below the published rule's in %d of %d worlds; opt_tariff |log err| shipped %s vs sigma_eb %s.",
                                                                   rd$R3_sigma_eb$worlds_sigma_err_down_10pct, rd$R3_sigma_eb$worlds,
                                                                   f(rd$R3_sigma_eb$opt_tariff_err_shipped), f(rd$R3_sigma_eb$opt_tariff_err_sigma_eb))), "")
  }
  st <- s_all[structure != "none"]
  if (nrow(st)) {
    st <- st[order(structure, scale, match(arm_name, names(KT_ARMS)))]
    sdesc <- vapply(unique(st$structure), function(x) { p <- KT_STRUCTURES[[x]]; sprintf("`%s` (between goods %s, between importers %s, within %s)", x, p$good_sd, p$importer_sd, p$within_sd) }, "")
    srow <- sprintf("| %s | x%s | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s |", st$structure, format(st$scale), st$arm_name, st$n_worlds,
                    f(st$within_r), f(st$between_good_gamma_r), f(st$between_good_tariff_r), f(st$within_good_gamma_r),
                    f(st$within_good_gamma_sd_ratio), f(st$within_good_tariff_r), f(st$opt_tariff_r), f(st$composite_r))
    out <- c(out, "## Structured worlds (patch 0123)", "",
             sprintf("ln gamma carries a good effect, or a good and an importer effect (s.d.): %s. Sigma, shocks and trade pattern as in the unstructured world of the same seed. Medians over seeds.",
                     paste(sdesc, collapse = "; ")), "",
             "| structure | scale | arm | worlds | within-cell r | between-good gamma r | between-good tariff r | within-good gamma r | within-good gamma sd ratio | within-good tariff r | cell opt_tariff r | composite r |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|", srow, "",
             "## Reading R4 (rules fixed in patch 0123; see the script header)", "",
             sprintf("- **R4a between goods: %s.** Between-good correlation of the log median gamma by scale: %s; of the mean ln opt_tariff: %s.",
                     rd$R4a_between_goods$verdict,
                     paste(sprintf("%s %s", names(rd$R4a_between_goods$gamma_r_by_scale), f(unlist(rd$R4a_between_goods$gamma_r_by_scale))), collapse = ", "),
                     paste(sprintf("%s %s", names(rd$R4a_between_goods$tariff_r_by_scale), f(unlist(rd$R4a_between_goods$tariff_r_by_scale))), collapse = ", ")),
             sprintf("- **R4b within goods, across importers: %s.** Within-good correlation of the cell mean ln gamma by scale: %s; s.d. ratio: %s; within-good correlation of ln opt_tariff: %s.",
                     rd$R4b_within_goods$verdict,
                     paste(sprintf("%s %s", names(rd$R4b_within_goods$gamma_r_by_scale), f(unlist(rd$R4b_within_goods$gamma_r_by_scale))), collapse = ", "),
                     paste(sprintf("%s %s", names(rd$R4b_within_goods$gamma_sd_ratio_by_scale), f(unlist(rd$R4b_within_goods$gamma_sd_ratio_by_scale))), collapse = ", "),
                     paste(sprintf("%s %s", names(rd$R4b_within_goods$tariff_r_by_scale), f(unlist(rd$R4b_within_goods$tariff_r_by_scale))), collapse = ", ")),
             sprintf("- **Good-level reading: %s.**", if (isTRUE(rd$good_level_reading)) "yes -- gamma and opt_tariff carry differences between goods, not between importers within a good" else "no"), "")
  }
  if (!is.null(rd$R5_ridge_scale) && !identical(rd$R5_ridge_scale$verdict, "not measured")) {
    pa <- rd$R5_ridge_scale$per_arm
    lines <- vapply(pa, function(z) sprintf("| %s | %s | %s | %s |", z$arm, paste(f(z$within_good_gamma_r), collapse = " / "),
                                            paste(f(z$within_r), collapse = " / "), paste(f(z$between_good_gamma_r), collapse = " / ")), "")
    out <- c(out, "## Reading R5: the precision-scaled ridge (patch 0132; good_importer worlds, shock scales in order)", "",
             "| arm | within-good gamma r | within-cell r | between-good gamma r |", "|---|---|---|---|", lines, "",
             sprintf("- **R5: %s.** Calibrate on real data if some tau2 arm reaches a within-good gamma r >= 0.40 or a within-cell r >= 0.30 at every scale, keeping the between-good gamma r >= 0.80.%s",
                     rd$R5_ridge_scale$verdict, if (length(rd$R5_ridge_scale$arms_passing)) sprintf(" Passing: %s.", paste(rd$R5_ridge_scale$arms_passing, collapse = ", ")) else ""), "")
  }
  c(out, "A synthetic world satisfies every assumption the estimator makes and has no unit-value measurement error: the most favourable case, not a calibration to BACI.")
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  root <- normalizePath(file.path(dirname(file_arg), ".."), winslash = "/")
  kt_source(root, environment())
  out <- get_arg("--out", NA_character_)
  if (is.na(out)) stop("usage: Rscript validation/known_truth_stage2.R --out DIR [--seeds a,b] [--scales 1,3] [--arms ...] [--structures none|good,good_importer] [--json F] [--md F]")
  out <- normalizePath(out, winslash = "/", mustWork = FALSE); dir.create(out, recursive = TRUE, showWarnings = FALSE)
  structures <- strsplit(get_arg("--structures", "none"), ",")[[1]]
  if (length(setdiff(structures, names(KT_STRUCTURES)))) stop("unknown structure(s): ", paste(setdiff(structures, names(KT_STRUCTURES)), collapse = ", "))
  structured <- any(structures != "none")
  seeds  <- as.integer(strsplit(get_arg("--seeds", "20261015,20261016,20261017"), ",")[[1]])
  scales <- as.numeric(strsplit(get_arg("--scales", "1,3"), ",")[[1]])
  # (patch 0132) the default for an unstructured grid stays 0122's five arms; the ridge arms run when named
  arms   <- strsplit(get_arg("--arms", if (structured) "shipped" else paste(setdiff(names(KT_ARMS), grep("^ridge_", names(KT_ARMS), value = TRUE)), collapse = ",")), ",")[[1]]
  if (length(setdiff(arms, names(KT_ARMS)))) stop("unknown arm(s): ", paste(setdiff(arms, names(KT_ARMS)), collapse = ", "))
  arms <- unique(c("shipped", arms))
  goods <- as.integer(get_arg("--goods", if (structured) 12L else 5L)); n_cty <- as.integer(get_arg("--countries", 15L))
  years_s <- get_arg("--years", "1995:2024"); years <- eval(parse(text = years_s))
  ncores <- as.integer(get_arg("--ncores", 1L))
  json <- get_arg("--json", if (structured) "results/known_truth_structured.json" else "results/known_truth_stage2.json")
  md   <- get_arg("--md", if (structured) "docs/results/known_truth_structured.md" else "docs/results/known_truth_stage2.md")
  t0 <- Sys.time()
  res <- kt_grid(root, out, seeds, scales, arms, goods = goods, countries = n_cty, years = years, ncores = ncores, structures = structures)
  rev <- tryCatch(system2("git", c("-C", shQuote(root), "rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(script = "validation/known_truth_stage2.R", patch = if (any(grepl("^ridge_", arms))) "0132" else if (structured) "0123" else "0122", seeds = seeds, scales = scales, arms = arms,
               structures = structures, goods = goods, countries = n_cty, years = years_s, ncores = ncores, out = out, git_rev = rev,
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
  dir.create(dirname(json), recursive = TRUE, showWarnings = FALSE); dir.create(dirname(md), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(list(meta = meta, readings = res$readings, summary = res$summary, sigma_level = res$sigma_level,
                            runs = res$runs, worlds = res$worlds), json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  writeLines(enc2utf8(kt_md(res, meta)), md, useBytes = TRUE)
  cat(sprintf("known-truth grid: %d worlds x %d arms in %.1f min -> %s, %s\n", length(res$worlds), length(arms), meta$minutes, json, md))
  rd <- res$readings
  if (!is.null(rd$R1_within_cell_gamma))
    cat(sprintf("R1 within-cell gamma: %s | R2 cell opt_tariff: %s | R3 sigma EB: %s\n", rd$R1_within_cell_gamma$verdict,
                rd$R2_cell_opt_tariff$verdict, rd$R3_sigma_eb$verdict))
  if (!is.null(rd$R5_ridge_scale))
    cat(sprintf("R5 ridge scale: %s\n", rd$R5_ridge_scale$verdict))
  if (!is.null(rd$R4a_between_goods))
    cat(sprintf("R4a between goods: %s | R4b within goods: %s | good-level reading: %s\n", rd$R4a_between_goods$verdict,
                rd$R4b_within_goods$verdict, if (isTRUE(rd$good_level_reading)) "yes" else "no"))
}
