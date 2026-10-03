#!/usr/bin/env Rscript
# ============================================================================
# analysis/eb_lambda_census.R  (patch 0082, 2026-10-03)
#
# Empirical-Bayes calibration of the Stage-2b shrinkage lambda, per good,
# from the odd/even calendar-split passes -- a census, not an estimator
# change. The penalised objective sum_r w_r e_r^2 + lambda sum_i (ln g_i -
# ln g_good)^2 is the MAP objective of the hierarchical model
#     ln gamma_i ~ N(ln g_good, tau^2),   sqrt(w_r) e_r ~ N(0, s^2)
# with lambda = s^2 / tau^2. The census estimates tau_g^2 (the signal
# variance of log gamma across the good's (importer, exporter) rows) and
# s_g^2 (the weighted residual variance) from two independent halves of the
# calendar, using the one-dimensional quadratic approximation in which a
# row's penalised estimate is a convex combination of its prior and its
# unpenalised estimate with the stored weight s_i = gamma_shrink_wt:
#     dev_h,i = ln gamma_hat_h,i - ln g_good = (1 - s_i)(delta_i + e_h,i),
#     delta_i ~ N(0, tau^2),  e_h,i ~ N(0, s^2 / c_i),  c_i = lambda (1 - s_i) / s_i
# (c_i is the data curvature in log units, backed out of the shrinkage
# identity s_i = lambda / (lambda + c_i)). The halves share delta_i and have
# independent noise, so within each good
#     E[dev_o dev_e] = (1 - s_o)(1 - s_e) tau^2
#     E[dev_h^2]     = (1 - s_h)^2 tau^2 + (1 - s_h) s_h s^2 / lambda
# which gives the method-of-moments estimates
#     tau_hat^2 = sum dev_o dev_e / sum (1 - s_o)(1 - s_e)
#     s_hat^2   = lambda * sum_h sum_i [dev_h^2 - (1 - s_h)^2 tau_hat^2] / sum_h sum_i (1 - s_h) s_h
#     lambda_g* = s_hat^2 / tau_hat^2            (the half-sample calibration)
# Each half averages the moments over half the years, so its weighted
# residual variance is about twice the full sample's (the exporter weights
# are renormalised to sum to J, so their scale does not change); the
# full-sample calibration is therefore reported as lambda_g* / 2 and marked
# approximate. What the census is for is the DISPERSION of lambda_g* across
# goods and its rough level relative to the fixed 0.1: a tight cluster near
# 0.1 says the constant is defensible and goes in the paper; a spread of
# orders of magnitude says lambda should vary by good (a v0.9 estimator
# change). The quadratic approximation is crude for rows with s near 1
# (no data curvature); rows with s > 0.99 are excluded.
#
# Inputs (the parity grid layout under --grid):
#   <grid>/<config>_odd/ and <grid>/<config>_even/ with
#       baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds
#   <grid>/<stage2a-dir>/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds
#       (the Stage-2a table those passes drew their priors from; the prior
#        is rebuilt here with the rule the passes used: --prior-rows all)
# Usage (repo root):
#   Rscript analysis/eb_lambda_census.R --config shipped_l0.1 --lambda 0.1
#   Rscript analysis/eb_lambda_census.R --config log_l0.01 --lambda 0.01
#   [--grid DIR (default %USERPROFILE%/te_grid)] [--stage2a-dir 2a_log]
#   [--prior-rows all|estimated] [--s-max 0.99] [--out X.json] [--md Y.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
config     <- get_arg("--config", "shipped_l0.1")
lambda     <- as.numeric(get_arg("--lambda", "0.1"))
grid_dir   <- get_arg("--grid", file.path(Sys.getenv("USERPROFILE", unset = Sys.getenv("HOME")), "te_grid"))
s2a_dir    <- get_arg("--stage2a-dir", "2a_log")
prior_rows <- get_arg("--prior-rows", "all")
s_max      <- as.numeric(get_arg("--s-max", "0.99"))
out_json   <- get_arg("--out", sprintf("results/eb_lambda_census_%s.json", gsub("[^A-Za-z0-9_.-]", "_", config)))
out_md     <- get_arg("--md",  sprintf("docs/results/eb_lambda_census_%s.md", gsub("[^A-Za-z0-9_.-]", "_", config)))
stopifnot(is.finite(lambda), lambda > 0, prior_rows %in% c("all", "estimated"))

.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                      error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()

country_name  <- "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"
regional_name <- "baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds"
p_odd  <- file.path(grid_dir, paste0(config, "_odd"),  country_name)
p_even <- file.path(grid_dir, paste0(config, "_even"), country_name)
p_2a   <- file.path(grid_dir, s2a_dir, regional_name)
for (p in c(p_odd, p_even, p_2a)) if (!file.exists(p)) stop("not found: ", p)

read_half <- function(p, tag) {
  x <- readRDS(p); setDT(x)
  x <- x[is_estimated_row(tier, convergence) & convergence == 0L & is.finite(gamma) & gamma > 0 &
         is.finite(gamma_shrink_wt) & gamma_shrink_wt >= 0 & gamma_shrink_wt <= s_max,
         .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good),
           lg = log(gamma), s = gamma_shrink_wt)]
  setnames(x, c("lg", "s"), paste0(c("lg_", "s_"), tag))
  x
}
odd  <- read_half(p_odd, "o")
even <- read_half(p_even, "e")
reg <- readRDS(p_2a); setDT(reg)
regional_clean <- reg[!is.na(sigma) & !is.na(gamma) & gamma > 0]
prior <- stage2b_priors_from_regional(regional_clean, rows = prior_rows)$country_priors
prior[, good := as.character(good)]

m <- merge(odd, even, by = c("importer", "exporter", "good"))
m <- merge(m, prior, by = "good")
m[, `:=`(dev_o = lg_o - ln_gamma_prior, dev_e = lg_e - ln_gamma_prior)]
m <- m[is.finite(dev_o) & is.finite(dev_e)]
if (nrow(m) == 0L) stop("no rows shared by the two halves after filtering")

eb_fit <- function(d) {
  w_cross <- (1 - d$s_o) * (1 - d$s_e)
  tau2 <- sum(d$dev_o * d$dev_e) / sum(w_cross)
  num  <- sum(d$dev_o^2 - (1 - d$s_o)^2 * tau2) + sum(d$dev_e^2 - (1 - d$s_e)^2 * tau2)
  den  <- sum((1 - d$s_o) * d$s_o) + sum((1 - d$s_e) * d$s_e)
  s2   <- lambda * num / den
  r    <- suppressWarnings(cor(d$dev_o, d$dev_e))
  list(n = nrow(d), tau2 = tau2, s2 = s2,
       lambda_half = if (tau2 > 0 && s2 > 0) s2 / tau2 else NA_real_,
       lambda_full = if (tau2 > 0 && s2 > 0) s2 / (2 * tau2) else NA_real_,
       r_parity = r, s_median = median(c(d$s_o, d$s_e)))
}
by_good <- m[, eb_fit(.SD), by = good]
pooled  <- eb_fit(m)

q <- function(x, p = c(.1, .25, .5, .75, .9)) { x <- x[is.finite(x)]; if (!length(x)) return(NULL); as.list(setNames(quantile(x, p), paste0("p", 100 * p))) }
lh <- by_good$lambda_half; lf <- by_good$lambda_full
summ <- list(
  n_goods = nrow(by_good), n_goods_usable = sum(is.finite(lf)),
  n_goods_tau2_nonpositive = sum(!(by_good$tau2 > 0)), n_goods_s2_nonpositive = sum(!(by_good$s2 > 0)),
  n_rows = nrow(m),
  lambda_half_quantiles = q(lh), lambda_full_quantiles = q(lf),
  log10_lambda_full_sd = sd(log10(lf[is.finite(lf)])),
  share_full_within_half_to_double_of_fixed = mean(lf >= lambda / 2 & lf <= 2 * lambda, na.rm = TRUE),
  share_full_within_order_of_magnitude = mean(lf >= lambda / 10 & lf <= 10 * lambda, na.rm = TRUE),
  pooled = pooled, fixed_lambda = lambda, prior_rows = prior_rows, s_max = s_max
)
out <- list(meta = list(config = config, grid = grid_dir, stage2a_dir = s2a_dir,
                        git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
                        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
            summary = summ, by_good = by_good)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

f3 <- function(x) if (is.null(x) || !is.finite(x)) "NA" else formatC(x, format = "g", digits = 3)
pc <- function(x) if (is.na(x)) "NA" else sprintf("%.0f%%", 100 * x)
ql <- function(qq) if (is.null(qq)) "NA" else paste(sapply(qq, f3), collapse = " / ")
md <- c(
  sprintf("# EB calibration of the Stage-2b shrinkage lambda (%s, fixed lambda = %s)", config, f3(lambda)), "",
  sprintf("Passes: `%s_odd` / `%s_even` under `%s`; prior rebuilt from `%s` with rows = %s; rows with gamma_shrink_wt > %s excluded (rev %s, %s).",
          config, config, grid_dir, s2a_dir, prior_rows, f3(s_max), out$meta$git_rev, out$meta$timestamp), "",
  "Method: per good, tau^2 = sum(dev_o dev_e) / sum((1-s_o)(1-s_e)) from the two calendar halves, s^2 from the halves' own dispersion net of tau^2 (see the script header); lambda* = s^2 / tau^2 on the half sample, and lambda* / 2 as the approximate full-sample value (each half averages the moments over half the years).", "",
  sprintf("- %s goods, %s shared rows; usable lambda on %s goods (tau^2 <= 0 on %s, s^2 <= 0 on %s).",
          summ$n_goods, format(summ$n_rows, big.mark = ","), summ$n_goods_usable, summ$n_goods_tau2_nonpositive, summ$n_goods_s2_nonpositive),
  sprintf("- lambda* (half sample) p10 / p25 / p50 / p75 / p90: %s.", ql(summ$lambda_half_quantiles)),
  sprintf("- lambda* (full-sample approx.) p10 / p25 / p50 / p75 / p90: %s; sd of log10 across goods %s.", ql(summ$lambda_full_quantiles), f3(summ$log10_lambda_full_sd)),
  sprintf("- Share of goods whose full-sample lambda* lies within a factor 2 of the fixed %s: %s; within an order of magnitude: %s.",
          f3(lambda), pc(summ$share_full_within_half_to_double_of_fixed), pc(summ$share_full_within_order_of_magnitude)),
  sprintf("- Pooled over all rows: tau^2 %s, s^2 %s, lambda* half %s, full approx. %s, parity correlation of the deviations %s, median shrink_wt %s.",
          f3(pooled$tau2), f3(pooled$s2), f3(pooled$lambda_half), f3(pooled$lambda_full), f3(pooled$r_parity), f3(pooled$s_median)), "",
  "| good | rows | tau^2 | s^2 | lambda* half | lambda* full | r parity | median s |", "|---|---|---|---|---|---|---|---|",
  sprintf("| %s | %d | %s | %s | %s | %s | %s | %s |", by_good$good, by_good$n, sapply(by_good$tau2, f3), sapply(by_good$s2, f3),
          sapply(by_good$lambda_half, f3), sapply(by_good$lambda_full, f3), sapply(by_good$r_parity, f3), sapply(by_good$s_median, f3)), "",
  "Reading: a tight cluster of lambda* near the fixed value says the constant is defensible and the calibration goes in the paper; a spread across orders of magnitude says lambda should vary by good, which is an estimator change (v0.9). The quadratic one-dimensional approximation behind s_i is crude where the data curvature is small, so weight the pooled and median figures over the individual goods."
)
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(sprintf("Wrote %s and %s\n", out_json, out_md))
cat(sprintf("%s: %d goods (%d usable), %s rows | lambda* full-sample approx. p10/p50/p90 = %s / %s / %s vs fixed %s | within x2: %s, within x10: %s | pooled tau2 %s s2 %s lambda* full %s\n",
            config, summ$n_goods, summ$n_goods_usable, format(summ$n_rows, big.mark = ","),
            f3(summ$lambda_full_quantiles$p10), f3(summ$lambda_full_quantiles$p50), f3(summ$lambda_full_quantiles$p90), f3(lambda),
            pc(summ$share_full_within_half_to_double_of_fixed), pc(summ$share_full_within_order_of_magnitude),
            f3(pooled$tau2), f3(pooled$s2), f3(pooled$lambda_full)))
