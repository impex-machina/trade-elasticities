#!/usr/bin/env Rscript
# ===========================================================================
# validation/synthetic_baci.R  (patch 0121)
#
# A synthetic BACI HS92 directory -- one CSV per year in BACI's own layout
# (t, i, j, k, v, q), HS6 codes written the way BACI writes them (leading
# zero dropped), a few missing quantities, entry / exit and gaps -- generated
# from Soderbery (2018)'s model with KNOWN parameters:
#
#   demand  x_Ijt = b_Ijt * p_Ijt^(-sigma_Ig) * P_It^(sigma_Ig - 1) * E_I   (Eq. 2)
#   supply  p_Ijt = exp(eta_Ijt) * x_Ijt^(gamma_Ijg)                       (Eq. 3)
#
# solved for p given the CES price index P (iterated to a fixed point),
# with ln b and eta random walks whose innovation s.d. differ across pairs
# (the heteroskedasticity the estimator identifies from) and are drawn
# independently (the independence it assumes). Every HS4 flow is split over
# its HS6 lines with fixed-ish shares and line-specific unit values.
#
# Two uses:
#   * tests/testthat/test-runner-e2e-smoke.R runs scripts/run_estimation.R
#     on a small directory, then analysis/master.R and scripts/build_readme.R
#     on its outputs -- the runner, 00_setup.R and the README build have no
#     other test that executes them;
#   * known-truth checks: `truth.rds` beside the directory holds sigma_Ig
#     and gamma_Ijg, so the published estimates can be compared with the
#     parameters that generated the data.
#
# The DGP satisfies every assumption the estimator makes and has no
# unit-value measurement error; it is the most favourable case, not a
# calibration to BACI.
#
# Structure (patch 0123). By default every pair's gamma is an independent
# draw, ln gamma ~ N(ln 0.7, 0.7^2): no good or importer has systematically
# higher gammas, so there is nothing between goods for the pipeline to find.
# good_sd / importer_sd add a good effect and an importer effect,
#   ln gamma_Ijg = ln 0.7 + a_g + b_I + e_Ijg,  a ~ N(0, good_sd^2),
#   b ~ N(0, importer_sd^2), e ~ N(0, within_sd^2),
# drawn from a separate RNG stream (seed + 7919) so that sigma, the shocks
# and the trade pattern are the same as the unstructured world of the same
# seed; with both at 0 the world is the one patch 0121 generated, bit for bit.
#
# CLI:
#   Rscript validation/synthetic_baci.R --out DIR [--seed N] [--shock-scale S]
#           [--goods G] [--countries C] [--years 1995:2024]
#           [--good-sd A] [--importer-sd B] [--within-sd E]
#   DIR is created as DIR/BACI_HS92_V202601 (the runner parses the source
#   tag from the path) with DIR/truth.rds beside it.
# ===========================================================================

suppressPackageStartupMessages(library(data.table))

#' Write a synthetic BACI directory and return the true parameters.
#'
#' @param out_dir directory to hold the BACI_HS92_Y####_V202601.csv files.
#' @param n_goods number of HS4 goods (taken in order from a fixed list).
#' @param countries BACI country codes (real codes, so the region map works).
#' @param years calendar years.
#' @param seed RNG seed.
#' @param shock_scale multiplies every shock innovation s.d. (volatility).
#' @param p_trade probability that an exporter sells a good to an importer.
#' @param good_sd,importer_sd s.d. of the good and importer effects on ln gamma
#'   (patch 0123; 0 = none, the default).
#' @param within_sd s.d. of the pair's own deviation (0.7, the default, is the
#'   unstructured world's whole dispersion).
#' @return invisibly, list(sigma = (importer, good, sigma_true),
#'   gamma = (importer, exporter, good, gamma_true)).
make_synthetic_baci_dir <- function(out_dir,
                                    n_goods = 5L,
                                    countries = c(842L, 276L, 392L, 156L, 251L, 826L, 380L, 124L, 484L,
                                                  410L, 528L, 724L, 752L, 32L, 710L),
                                    years = 1995:2024, seed = 20261015L,
                                    shock_scale = 1, p_trade = 0.75,
                                    good_sd = 0, importer_sd = 0, within_sd = 0.7) {
  set.seed(seed)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  # (patch 0123) seven more goods appended after the original five, so a world
  # of n_goods <= 5 is unchanged
  hs6_all <- data.table(hs4 = c("0101", "0101", "8703", "8703", "2709", "6109", "6109", "8471",
                                "3004", "7208", "9403", "9403", "8517", "0901", "3901", "6403"),
                        hs6 = c("010110", "010190", "870321", "870322", "270900", "610910", "610990", "847130",
                                "300490", "720890", "940360", "940350", "851710", "090111", "390110", "640399"),
                        uv_rel = c(1.0, 0.7, 1.0, 1.4, 1.0, 1.0, 0.8, 1.0, 1.0, 1.0, 1.0, 0.9, 1.0, 1.0, 1.0, 1.0))
  goods <- unique(hs6_all$hs4)[seq_len(min(n_goods, uniqueN(hs6_all$hs4)))]
  hs6 <- hs6_all[hs4 %in% goods]
  TT <- length(years)
  rows <- list(); truth_sig <- list(); truth_gam <- list()
  structured <- good_sd > 0 || importer_sd > 0
  g_eff <- stats::setNames(rep(0, length(goods)), goods)
  i_eff <- stats::setNames(rep(0, length(countries)), as.character(countries))
  if (structured) {                                    # separate stream: the main one is untouched
    main_state <- get(".Random.seed", envir = .GlobalEnv)
    set.seed(seed + 7919L)
    if (good_sd > 0) g_eff[] <- stats::rnorm(length(goods), 0, good_sd)
    if (importer_sd > 0) i_eff[] <- stats::rnorm(length(countries), 0, importer_sd)
    assign(".Random.seed", main_state, envir = .GlobalEnv)
  }
  for (g in goods) {
    for (I in countries) {
      sig <- 1.6 + rlnorm(1, log(1.2), 0.5)            # sigma_Ig > 1
      EI  <- exp(rnorm(1, 8, 1))                        # expenditure on g in I
      ex  <- setdiff(countries, I)
      ex  <- ex[runif(length(ex)) < p_trade]
      if (length(ex) < 3) next
      J <- length(ex)
      gam <- if (structured) exp(log(0.7) + g_eff[[g]] + i_eff[[as.character(I)]] + rnorm(J, 0, within_sd))
             else rlnorm(J, log(0.7), within_sd)        # inverse supply elasticities
      truth_sig[[length(truth_sig) + 1L]] <- data.table(importer = I, good = g, sigma_true = sig)
      truth_gam[[length(truth_gam) + 1L]] <- data.table(importer = I, exporter = ex, good = g, gamma_true = gam)
      sd_b <- shock_scale * runif(J, 0.05, 0.45); sd_e <- shock_scale * runif(J, 0.05, 0.45)
      lb <- matrix(rnorm(J, 0, 1), J, TT); le <- matrix(rnorm(J, 0, 0.5), J, TT)
      for (t in 2:TT) {
        lb[, t] <- lb[, t - 1] + rnorm(J, 0, sd_b)
        le[, t] <- le[, t - 1] + rnorm(J, 0, sd_e)
      }
      active <- matrix(TRUE, J, TT)                     # entry, exit and gaps
      pick <- function(x) x[sample.int(length(x), 1L)]  # sample() on a length-1 x would mean 1:x
      for (j in seq_len(J)) {
        s <- if (runif(1) < 0.3) pick(1:max(1L, min(12L, TT - 3L))) else 1L
        e <- if (runif(1) < 0.2) pick(min(TT, max(18L, s + 5L)):TT) else TT
        active[j, ] <- seq_len(TT) >= s & seq_len(TT) <= e
        if (runif(1) < 0.15) active[j, sample(seq_len(TT), 2)] <- FALSE
      }
      for (t in seq_len(TT)) {
        a <- which(active[, t]); if (!length(a)) next
        lP <- 0
        for (it in 1:60) {                               # fixed point in ln P
          lA <- lb[a, t] + (sig - 1) * lP + log(EI)
          lp <- (le[a, t] + gam[a] * lA) / (1 + sig * gam[a])
          lP_new <- (1 / (1 - sig)) * log(sum(exp(lb[a, t] + (1 - sig) * lp)))
          if (abs(lP_new - lP) < 1e-12) { lP <- lP_new; break }
          lP <- 0.5 * lP + 0.5 * lP_new
        }
        lA <- lb[a, t] + (sig - 1) * lP + log(EI)
        lp <- (le[a, t] + gam[a] * lA) / (1 + sig * gam[a])
        lx <- lA - sig * lp
        rows[[length(rows) + 1L]] <- data.table(t = years[t], i = ex[a], j = I, hs4 = g,
                                                p = exp(lp), x = exp(lx))
      }
    }
  }
  d <- rbindlist(rows)
  d <- hs6[d, on = "hs4", allow.cartesian = TRUE]
  d[, n6 := .N, by = .(t, i, j, hs4)]
  d[, w := ifelse(n6 == 1L, 1, runif(.N, 0.35, 0.65))]
  d[, w := w / sum(w), by = .(t, i, j, hs4)]
  d[, q := round(x * w / uv_rel * 1e3, 3)]
  d[, v := round(p * x * w * 1e3, 3)]
  d <- d[v > 0]
  d[runif(.N) < 0.01, q := NA_real_]                     # a few flows without a quantity
  d[, k := sub("^0", "", hs6)]                            # BACI drops the leading zero
  for (yy in years) {
    data.table::fwrite(d[t == yy, .(t, i, j, k, v, q)],
                       file.path(out_dir, sprintf("BACI_HS92_Y%d_V202601.csv", yy)), na = "")
  }
  truth <- list(sigma = rbindlist(truth_sig), gamma = rbindlist(truth_gam),
                meta = list(seed = seed, shock_scale = shock_scale, n_goods = length(goods),
                            countries = countries, years = range(years), n_hs6_rows = nrow(d),
                            good_sd = good_sd, importer_sd = importer_sd, within_sd = within_sd,
                            good_effects = g_eff, importer_effects = i_eff))
  invisible(truth)
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) {
    i <- match(flag, args)
    if (is.na(i) || i == length(args)) default else args[i + 1L]
  }
  out <- get_arg("--out", NA_character_)
  if (is.na(out)) stop("usage: Rscript validation/synthetic_baci.R --out DIR [--seed N] [--shock-scale S] [--goods G] [--countries C] [--years A:B]")
  yrs <- eval(parse(text = get_arg("--years", "1995:2024")))
  all_ctys <- c(842L, 276L, 392L, 156L, 251L, 826L, 380L, 124L, 484L, 410L, 528L, 724L, 752L, 32L, 710L)
  n_cty <- as.integer(get_arg("--countries", length(all_ctys)))
  baci_dir <- file.path(out, "BACI_HS92_V202601")
  tr <- make_synthetic_baci_dir(baci_dir, n_goods = as.integer(get_arg("--goods", 5L)),
                                countries = all_ctys[seq_len(min(n_cty, length(all_ctys)))], years = yrs,
                                seed = as.integer(get_arg("--seed", 20261015L)),
                                shock_scale = as.numeric(get_arg("--shock-scale", 1)),
                                good_sd = as.numeric(get_arg("--good-sd", 0)),
                                importer_sd = as.numeric(get_arg("--importer-sd", 0)),
                                within_sd = as.numeric(get_arg("--within-sd", 0.7)))
  saveRDS(tr, file.path(out, "truth.rds"))
  cat(sprintf("synthetic BACI: %s HS6 rows, %d goods, %d countries, years %d-%d, shock scale %g -> %s (truth: %s)\n",
              format(tr$meta$n_hs6_rows, big.mark = ","), tr$meta$n_goods, length(tr$meta$countries),
              tr$meta$years[1], tr$meta$years[2], tr$meta$shock_scale, baci_dir, file.path(out, "truth.rds")))
}
