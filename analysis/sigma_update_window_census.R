#!/usr/bin/env Rscript
# ===========================================================================
# analysis/sigma_update_window_census.R  (patch 0153)
#
# The acceptance census for --stage2-sigma-update import (patch 0152): two
# window runs of the pipeline on independent data (1995-2009 and 2010-2024,
# the design of analysis/sigma_window_census.R, M3 record), both under the
# flag, and on the cells that have an updated sigma in both windows the
# cross-window reproducibility of three predictors of ln(sigma - 1):
#   stage1   the Stage-1 sigma of the cell (sigma_source_stage1 == "estimated"
#            in both windows; the pipeline's sigma before the update)
#   updated  the updated sigma (sigma_source == "updated_import" in both)
#   global   one number per window: the median of the window's updated sigma
# Readings (fixed before the numbers, patch 0153): for each predictor, the
# median absolute cross-window difference of ln(sigma - 1) and the Pearson r
# across cells; the update ADVANCES if `updated` has a lower median |diff|
# than `stage1` on the common cells AND a lower median |diff| than `global`
# (the M3 census found the Stage-1 sigma loses to the global median), with
# r not lower than stage1's. Also reported: the same on the cells with a
# Stage-1 estimate in both windows (the subset the Stage-1 comparison can
# use), the update's coverage, and the share of profiles at floor / cap.
#
# Shrinkage block (the step after a "does not advance" reading; rule fixed
# before its numbers): each cell-level predictor is re-read as a + b * x --
# x the cell's ln(sigma - 1) in one window, a and b fitted on one random half
# of the cells (seed 20260926) and applied on the other half, both directions
# pooled -- at b fixed to 0 (the target window's level: the global-median
# predictor in the same cross-fit), b fixed to 1 (the cell value, level-
# shifted) and b fitted (the shrunk sigma; b is the reliability ratio). The
# shrunk updated sigma ADVANCES if its out-of-sample median |diff| is lower
# than the level predictor's (b = 0) on the same cells AND lower than the
# shrunk Stage-1 sigma's on the cells with a Stage-1 estimate in both windows.
#
# Robustness of the shrinkage gain (patch 0163). Through patch 0162 the gain's
# interval came from a bootstrap over "cell-directions": the two prediction
# directions of one cell (early -> late, late -> early: the same two numbers
# read both ways) were drawn as independent observations, and so were the
# cells of one good, although the 2% subsample holds 25 goods. That interval
# ([0.0037, 0.0158] on the v0.12.0 census) understates the uncertainty. The
# census now also resamples GOODS, keeping both directions of every cell of a
# drawn good together (paired_gain_cluster_boot(), R/utils_general.R) -- the
# unit analysis/stage2_reliability.R resamples for the gamma A/Bs -- reports
# both intervals, and words its "robust" line on the goods interval. The
# shrinkage RULE above has no significance criterion and is not changed: this
# block only says how sure the sign of the gain is.
#
# Usage (from the repo root; the two --out-dir's of the window runs):
#   Rscript analysis/sigma_update_window_census.R --early <out-dir-1995-2009> --late <out-dir-2010-2024> [--md docs/results/sigma_update_window_census.md]
# Each window run: scripts/run_estimation.R --data <BACI> --out-dir <dir> --product-sample 0.02 --product-seed <s>
#                  --minyear 1995 --maxyear 2009 --stage2-sigma-update import   (and 2010 / 2024 for the late window)
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(optparse) })
source(file.path("R", "utils_general.R"))   # patch 0163: paired_gain_cluster_boot()

opt <- parse_args(OptionParser(option_list = list(
  make_option("--early", type = "character", help = "--out-dir of the early-window run"),
  make_option("--late", type = "character", help = "--out-dir of the late-window run"),
  make_option("--md", type = "character", default = "", help = "optional markdown record to write")
)))
if (is.null(opt$early) || is.null(opt$late)) stop("--early and --late are required")

load_window <- function(dir) {
  f <- list.files(dir, pattern = "_country_hs4_fixed_sigma\\.rds$", full.names = TRUE)
  if (length(f) != 1L) stop("expected one *_country_hs4_fixed_sigma.rds under ", dir, ", found ", length(f))
  t <- readRDS(f); setDT(t)
  if (!"sigma_source_stage1" %in% names(t)) stop(basename(f), " has no sigma_source_stage1 column: run the window under --stage2-sigma-update import")
  p <- list.files(dir, pattern = "_sigma_update_pass1\\.csv$", full.names = TRUE)
  prof <- if (length(p) == 1L) fread(p, colClasses = list(character = c("importer", "good"))) else NULL
  cells <- unique(t[, .(importer = as.character(importer), good = as.character(good), sigma, sigma_source, sigma_source_stage1)])
  # the Stage-1 sigma of the cell: the pass-K table (gamma_V final, before the update) carries it
  k <- list.files(dir, pattern = "_country_hs4_fixed_sigma_pass[0-9]+\\.rds$", full.names = TRUE)
  s1 <- NULL
  if (length(k)) {
    kk <- k[which.max(as.integer(sub("^.*_pass([0-9]+)\\.rds$", "\\1", k)))]
    pk <- readRDS(kk); setDT(pk)
    s1 <- unique(pk[, .(importer = as.character(importer), good = as.character(good), sigma_stage1 = sigma)])
  }
  if (!is.null(s1)) cells <- merge(cells, s1, by = c("importer", "good"), all.x = TRUE)
  list(cells = cells, prof = prof, file = basename(f))
}
E <- load_window(opt$early); L <- load_window(opt$late)
m <- merge(E$cells, L$cells, by = c("importer", "good"), suffixes = c("_e", "_l"))
lr <- function(s) log(s - 1)
rd <- function(label, x, y) { d <- lr(x) - lr(y); data.table(predictor = label, n = sum(is.finite(d)), med_abs = median(abs(d), na.rm = TRUE), r = cor(lr(x), lr(y), use = "complete.obs")) }

# common cells: updated in both windows
cu <- m[sigma_source_e == "updated_import" & sigma_source_l == "updated_import" & sigma_e > 1 & sigma_l > 1]
g_e <- median(cu$sigma_e); g_l <- median(cu$sigma_l)
res <- rbindlist(list(
  rd("updated (cell)", cu$sigma_e, cu$sigma_l),
  data.table(predictor = "global median (window)", n = nrow(cu),
             med_abs = median(abs(lr(cu$sigma_l) - lr(g_e))), r = NA_real_)
))
# the Stage-1 comparison on cells with a Stage-1 estimate in both windows
cs <- cu[sigma_source_stage1_e == "estimated" & sigma_source_stage1_l == "estimated" & is.finite(sigma_stage1_e) & is.finite(sigma_stage1_l) &
         sigma_stage1_e > 1 & sigma_stage1_l > 1]
res_s <- if (nrow(cs)) rbindlist(list(
  rd("stage1 (cell)", cs$sigma_stage1_e, cs$sigma_stage1_l),
  rd("updated (cell), same cells", cs$sigma_e, cs$sigma_l),
  data.table(predictor = "global median (window), same cells", n = nrow(cs), med_abs = median(abs(lr(cs$sigma_l) - lr(g_e))), r = NA_real_)
)) else NULL

cov <- function(W, lab) {
  c1 <- W$cells
  data.table(window = lab, cells = nrow(c1), updated = sum(c1$sigma_source == "updated_import"),
             stage1_estimated = sum(c1$sigma_source_stage1 == "estimated"),
             at_floor = if (!is.null(W$prof)) sum(W$prof$status == "floor") else NA_integer_,
             at_cap = if (!is.null(W$prof)) sum(W$prof$status == "ceiling") else NA_integer_)
}
coverage <- rbind(cov(E, "early"), cov(L, "late"))

cat("\n=== sigma update, cross-window reproducibility of ln(sigma - 1) ===\n")
cat(sprintf("early: %s | late: %s | cells updated in both windows: %d | global medians %.3f / %.3f\n", E$file, L$file, nrow(cu), g_e, g_l))
print(coverage)
cat("\n-- cells updated in both windows --\n"); print(res[, .(predictor, n, med_abs_diff = round(med_abs, 3), r = round(r, 3))])
if (!is.null(res_s)) { cat("\n-- cells with a Stage-1 estimate in both windows --\n"); print(res_s[, .(predictor, n, med_abs_diff = round(med_abs, 3), r = round(r, 3))]) }
verdict <- if (is.null(res_s) || !nrow(cs)) "no cells with a Stage-1 estimate in both windows: no reading" else {
  s1 <- res_s[predictor == "stage1 (cell)"]; up <- res_s[predictor == "updated (cell), same cells"]; gl <- res_s[predictor == "global median (window), same cells"]
  if (up$med_abs < s1$med_abs && up$med_abs < gl$med_abs && up$r >= s1$r) "ADVANCES: the updated sigma reproduces across windows better than the Stage-1 sigma and than the global median"
  else if (up$med_abs < s1$med_abs) "beats the Stage-1 sigma but not the global median (or r lower): does not advance under the rule"
  else "does not beat the Stage-1 sigma: rejected"
}
cat("\nReading (rule, patch 0153):", verdict, "\n")

# ---- the shrinkage block ----
shrink_read <- function(x_e, x_l, label) {
  n <- length(x_e); set.seed(20260926L); fold <- sample(rep(1:2, length.out = n))
  le <- lr(x_e); ll <- lr(x_l); out <- list()
  for (dir in c("early->late", "late->early")) {
    x <- if (dir == "early->late") le else ll; y <- if (dir == "early->late") ll else le
    for (mode in c("level (b = 0)", "cell (b = 1)", "shrunk (b fitted)")) {
      pred <- rep(NA_real_, n); bs <- numeric(2)
      for (f in 1:2) {
        xf <- x[fold == f]; yf <- y[fold == f]
        b <- switch(mode, "level (b = 0)" = 0, "cell (b = 1)" = 1, "shrunk (b fitted)" = unname(coef(lm(yf ~ xf))[2]))
        a <- mean(yf) - b * mean(xf); bs[f] <- b
        pred[fold != f] <- a + b * x[fold != f]
      }
      d <- y - pred
      out[[length(out) + 1L]] <- data.table(predictor = label, mode = mode, direction = dir, n = n,
                                            b = round(mean(bs), 3), med_abs = median(abs(d)), r = if (mode == "level (b = 0)") NA_real_ else cor(pred, y))
    }
  }
  rbindlist(out)
}
pool_dirs <- function(d) d[, .(n = n[1], b = round(mean(b), 3), med_abs = round(mean(med_abs), 3), r = round(mean(r), 3)), by = .(predictor, mode)]
sh_all <- pool_dirs(shrink_read(cu$sigma_e, cu$sigma_l, "updated sigma"))
cat("\n=== shrinkage block: out-of-sample (two-fold, both directions pooled) ===\n")
cat("-- cells updated in both windows --\n"); print(sh_all)
sh_s <- NULL
if (nrow(cs) >= 20L) {
  sh_s <- pool_dirs(rbind(shrink_read(cs$sigma_stage1_e, cs$sigma_stage1_l, "Stage-1 sigma"), shrink_read(cs$sigma_e, cs$sigma_l, "updated sigma, same cells")))
  cat("-- cells with a Stage-1 estimate in both windows --\n"); print(sh_s)
}
verdict_sh <- if (is.null(sh_s)) "too few Stage-1 common cells for the shrinkage reading" else {
  up_sh <- sh_all[predictor == "updated sigma" & mode == "shrunk (b fitted)"]; lev <- sh_all[predictor == "updated sigma" & mode == "level (b = 0)"]
  s1_sh <- sh_s[predictor == "Stage-1 sigma" & mode == "shrunk (b fitted)"]; up_sh_s <- sh_s[predictor == "updated sigma, same cells" & mode == "shrunk (b fitted)"]
  if (up_sh$med_abs < lev$med_abs && up_sh_s$med_abs < s1_sh$med_abs)
    sprintf("ADVANCES: the shrunk updated sigma (b = %.2f) beats the level predictor (%.3f vs %.3f) and the shrunk Stage-1 sigma (%.3f vs %.3f)", up_sh$b, up_sh$med_abs, lev$med_abs, up_sh_s$med_abs, s1_sh$med_abs)
  else sprintf("does not advance: shrunk updated %.3f vs level %.3f (all common cells); shrunk updated %.3f vs shrunk Stage-1 %.3f (Stage-1 common cells)", up_sh$med_abs, lev$med_abs, up_sh_s$med_abs, s1_sh$med_abs)
}
cat("\nReading (shrinkage rule, patch 0153):", verdict_sh, "\n")

# ---- robustness of the shrinkage gain: paired bootstrap over cells, win share, fold-seed sensitivity ----
# (the rule has no significance criterion; this says whether the gain over the level predictor is fold noise)
shrink_pair <- function(x_e, x_l, seed) {
  n <- length(x_e); set.seed(seed); fold <- sample(rep(1:2, length.out = n))
  le <- lr(x_e); ll <- lr(x_l); d_lev <- numeric(0); d_shr <- numeric(0); bs <- numeric(0)
  for (dir in c("early->late", "late->early")) {
    x <- if (dir == "early->late") le else ll; y <- if (dir == "early->late") ll else le
    p_lev <- rep(NA_real_, n); p_shr <- rep(NA_real_, n)
    for (f in 1:2) {
      xf <- x[fold == f]; yf <- y[fold == f]; b <- unname(coef(lm(yf ~ xf))[2]); bs <- c(bs, b)
      p_lev[fold != f] <- mean(yf); p_shr[fold != f] <- mean(yf) - b * mean(xf) + b * x[fold != f]
    }
    d_lev <- c(d_lev, abs(y - p_lev)); d_shr <- c(d_shr, abs(y - p_shr))
  }
  list(d_lev = d_lev, d_shr = d_shr, b = mean(bs))
}
pr <- shrink_pair(cu$sigma_e, cu$sigma_l, 20260926L)
set.seed(1L); m <- length(pr$d_lev)
boot <- replicate(1000L, { i <- sample.int(m, m, replace = TRUE); median(pr$d_lev[i]) - median(pr$d_shr[i]) })
gain <- median(pr$d_lev) - median(pr$d_shr)
win <- mean(pr$d_shr < pr$d_lev)
seeds <- c(20260926L, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L)
sens <- t(vapply(seeds, function(sd) { q <- shrink_pair(cu$sigma_e, cu$sigma_l, sd); c(b = q$b, gain = median(q$d_lev) - median(q$d_shr)) }, numeric(2)))
cat(sprintf("\n=== robustness of the shrinkage gain (updated sigma, %d cells x 2 directions) ===\n", length(cu$sigma_e)))
cat(sprintf("  gain over the level predictor in median |diff|: %.4f | paired bootstrap 95%% CI [%.4f, %.4f] | share of cell-directions where the shrunk sigma is closer: %.3f\n",
            gain, quantile(boot, 0.025), quantile(boot, 0.975), win))
cat(sprintf("  over 10 fold seeds: b %.3f-%.3f | gain %.4f-%.4f (negative in %d of 10)\n", min(sens[, "b"]), max(sens[, "b"]), min(sens[, "gain"]), max(sens[, "gain"]), sum(sens[, "gain"] < 0)))
# (patch 0163) the same gain with GOODS resampled: both directions of every cell of a drawn good stay together
gb <- paired_gain_cluster_boot(pr$d_lev, pr$d_shr, cluster = rep(cu$good, 2L), B = 2000L, seed = 20261015L)
cat(sprintf("  goods bootstrap (%d goods, %d draws; both directions of a cell kept together): 95%% CI [%.4f, %.4f], %.1f%% of draws <= 0\n",
            gb$clusters, gb$draws, gb$lo, gb$hi, 100 * gb$share_le_0))
robust <- isTRUE(gb$lo > 0) && all(sens[, "gain"] > 0)
cat("  Reading: the gain", if (robust) "is robust (goods-bootstrap CI above zero, positive under every fold seed)" else "is NOT robust (goods-bootstrap CI includes zero, or negative under some fold seed)", "\n")

if (nzchar(opt$md)) {
  f <- function(x) sprintf("%.3f", x)
  lines <- c("# The sigma update across windows (patch 0153)", "",
             sprintf("Early `%s`, late `%s`; cells updated in both windows %d; global medians %s / %s.", E$file, L$file, nrow(cu), f(g_e), f(g_l)), "",
             "| window | cells | updated | Stage-1 estimated | at floor | at cap |", "|---|---|---|---|---|---|",
             sprintf("| %s | %d | %d | %d | %s | %s |", coverage$window, coverage$cells, coverage$updated, coverage$stage1_estimated, coverage$at_floor, coverage$at_cap), "",
             "| predictor | cells | median abs cross-window diff of ln(sigma - 1) | r |", "|---|---|---|---|",
             sprintf("| %s | %d | %s | %s |", res$predictor, res$n, f(res$med_abs), ifelse(is.na(res$r), "--", f(res$r))),
             if (!is.null(res_s)) sprintf("| %s | %d | %s | %s |", res_s$predictor, res_s$n, f(res_s$med_abs), ifelse(is.na(res_s$r), "--", f(res_s$r))) else character(),
             "", paste0("**Reading:** ", verdict), "",
             "Shrinkage block (two-fold, both directions pooled; b = reliability ratio):", "",
             "| predictor | mode | cells | b | median abs out-of-sample diff | r |", "|---|---|---|---|---|---|",
             sprintf("| %s | %s | %d | %s | %s | %s |", sh_all$predictor, sh_all$mode, sh_all$n, f(sh_all$b), f(sh_all$med_abs), ifelse(is.na(sh_all$r), "--", f(sh_all$r))),
             if (!is.null(sh_s)) sprintf("| %s | %s | %d | %s | %s | %s |", sh_s$predictor, sh_s$mode, sh_s$n, f(sh_s$b), f(sh_s$med_abs), ifelse(is.na(sh_s$r), "--", f(sh_s$r))) else character(),
             "", paste0("**Reading (shrinkage rule):** ", verdict_sh), "",
             sprintf("Robustness of the shrinkage gain (updated sigma, all common cells): gain over the level predictor %.4f in median |diff|; goods bootstrap (%d goods, both directions of a cell kept together) 95%% CI [%.4f, %.4f], %.1f%% of draws <= 0; the bootstrap over cell-directions used through patch 0162, which treats the two directions of a cell and the cells of a good as independent, [%.4f, %.4f]; shrunk sigma closer in %.1f%% of cell-directions; over 10 fold seeds b %.3f-%.3f, gain %.4f-%.4f (negative in %d of 10). **%s** (read on the goods interval since patch 0163).",
                     gain, gb$clusters, gb$lo, gb$hi, 100 * gb$share_le_0, quantile(boot, 0.025), quantile(boot, 0.975), 100 * win, min(sens[, "b"]), max(sens[, "b"]), min(sens[, "gain"]), max(sens[, "gain"]), sum(sens[, "gain"] < 0),
                     if (robust) "Robust" else "Not robust"))
  writeLines(lines, opt$md); cat("Written:", opt$md, "\n")
}
