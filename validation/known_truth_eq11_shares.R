#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_eq11_shares.R  (prototype, patch 0150 follow-up)
#
# Does the export block's sigma bias come from market shares?
#
# known_truth_sigma_update.R found that the Eq. (11) block of the Stage-2
# objective is not minimised at the true sigma even when every parameter --
# the gammas, sigma_V, gamma_V -- is the truth, while the Eq. (10) block is.
# The candidate mechanism: across an exporter's destinations, first- and
# reference-differencing leaves the importer x time aggregates (the CES price
# index P_it, expenditure) in Eq. (9)'s error, and in equilibrium P_it moves
# with the exporter's own price in proportion to its share in i, so
# E[q^J eps^J] != 0. If so, the bias must fall as shares shrink.
#
# This harness needs no estimation: with the parameters at the truth the
# profile depends only on the prepared panel. For each world size it
# generates a world (validation/synthetic_baci.R, the same seed, more
# countries), prepares the panel with prepare_raw_data() / prepare_data(),
# fixes every lookup at the truth, and profiles sigma cell by cell from the
# import block, the export block and both, reusing the cell estimator's own
# moment construction (its body up to the optimizer call).
#
# Usage (from the repo root; ~1-2 min per world size on one core):
#   Rscript validation/known_truth_eq11_shares.R [--sizes 15,30,45] [--goods 4]
#           [--seed 20261015] [--within-sd 0.7] [--out te_kt_shares]
# Prints one table per world size and writes <out>/eq11_shares.rds.
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(optparse) })

.this_dir <- function() {
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else normalizePath(".")
}
root <- normalizePath(file.path(.this_dir(), ".."))

opt <- parse_args(OptionParser(option_list = list(
  make_option("--sizes", type = "character", default = "15,30,45", help = "comma-separated country counts [default %default]"),
  make_option("--goods", type = "integer", default = 4L, help = "HS4 goods per world (max 12) [default %default]"),
  make_option("--seed", type = "integer", default = 20261015L, help = "RNG seed [default %default]"),
  make_option("--within-sd", type = "double", default = 0.7, dest = "within_sd", help = "within-cell s.d. of ln gamma [default %default]"),
  make_option("--out", type = "character", default = "te_kt_shares", help = "output directory [default %default]"),
  make_option("--ref-dest", type = "character", default = "largest", dest = "ref_dest",
              help = "reference destination V for Eq. (11): 'largest' (shipped: largest other market by value) or 'periods' (most differenced periods, ties by value) [default %default]"),
  make_option("--bw-weights", type = "character", default = "fn14", dest = "bw_weights",
              help = "within-row time-average weights: 'fn14' (the shipped T^1.5 (1/x_t + 1/x_t-1)^-0.5) or 'uniform' [default %default]")
)))
sizes <- as.integer(strsplit(opt$sizes, ",")[[1]])
out_root <- normalizePath(opt$out, mustWork = FALSE); dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

# the generator's 15 default codes first, then 30 more real BACI codes
ALL_CTY <- c(842L, 276L, 392L, 156L, 251L, 826L, 380L, 124L, 484L, 410L, 528L, 724L, 752L, 32L, 710L,
             36L, 76L, 152L, 170L, 203L, 208L, 246L, 300L, 348L, 356L, 360L, 372L, 376L, 458L, 554L,
             578L, 586L, 608L, 616L, 620L, 642L, 643L, 682L, 702L, 756L, 764L, 792L, 804L, 704L, 818L)
if (max(sizes) > length(ALL_CTY)) stop("at most ", length(ALL_CTY), " countries")

# the estimation library (every R/ file + the Rcpp objectives)
source(file.path(root, "R", "feen94_het_baci.R"))
source(file.path(root, "R", "build_config.R"))   # the runner sources it beside the library
if (identical(opt$ref_dest, "periods")) {
  # build_export_moments() is looked up at call time: swap its V rule for most-periods, ties by value
  .src <- deparse(build_export_moments)
  .hit <- grep("ref_dest <- dest_stats\\$importer\\[which.max\\(dest_stats\\$dest_val\\)\\]", .src)
  if (length(.hit) != 1L) stop("could not find the V rule in build_export_moments()")
  .src[.hit] <- "    dest_stats <- exp_flows[importer != focal_importer, .(dest_val = sum(cusval, na.rm = TRUE), n_per = sum(is.finite(lp_dif))), by = importer]; data.table::setorder(dest_stats, -n_per, -dest_val); ref_dest <- dest_stats$importer[1L]"
  build_export_moments <- eval(parse(text = .src))
  cat("  reference destination V: most differenced periods, ties by value (build_export_moments() overridden)\n")
}
if (identical(opt$bw_weights, "uniform")) {
  # the cell estimator and build_export_moments() look bw_weight() up at call time
  bw_weight <- function(cusval_t, cusval_lag, T_count) rep(1, length(cusval_t))
  cat("  within-row weights: uniform (bw_weight() overridden)\n")
}
sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)

# the cell estimator up to its optimizer call, then the sigma profile at the
# gammas in `gamma_tbl` (here the truth), for the block named by `kt_side`
.build_profile_fn <- function() {
  f <- estimate_importer_product_fixed_sigma
  b <- as.list(body(f))
  idx <- which(vapply(b, function(s) grepl("^d_start <- rep\\(gam_init", paste(deparse(s), collapse = "")), logical(1)))
  if (length(idx) != 1L) stop("could not find the optimizer call in estimate_importer_product_fixed_sigma()")
  tail <- quote({
    if (identical(kt_side, "import")) {
      exp_mom <- list(exp_Y = numeric(0), exp_X = matrix(numeric(0), nrow = 0, ncol = 9), jmap = integer(0),
                      sig_V = numeric(0), gam_V = numeric(0), wt_exp = numeric(0), M = 0L); imp_const <- FALSE
    } else if (identical(kt_side, "export")) {
      imp_Y_vec <- numeric(0); imp_X_mat <- matrix(numeric(0), nrow = 0, ncol = 5); wt_imp_vec <- numeric(0); imp_const <- FALSE
    }
    keys <- c(ref_exporter, exporter_order)
    mi <- match(paste(as.character(focal_importer), as.character(keys)), paste(gamma_tbl$importer, gamma_tbl$exporter))
    dvec <- gamma_tbl$gamma_true[mi]
    if (any(!is.finite(dvec)) || any(dvec <= 0)) return(cell_failure("no_true_gamma"))
    # residual rows at the truth: Y - pred(sigma_true, true gammas, true sigma_V / gamma_V), one per moment row
    if (identical(kt_side, "exportrows")) {
      if (exp_mom$M == 0L) return(cell_failure("no_export_rows"))
      sig <- sigma_val; sm1 <- sig - 1; X <- exp_mom$exp_X
      gI <- dvec[exp_mom$jmap - 1L]; gV <- exp_mom$gam_V; sV <- exp_mom$sig_V
      pred <- (gI / (1 + gI) / sm1) * X[, 1] + ((gI * (sig - 2) - 1) / (1 + gI) / sm1) * X[, 2] +
              (gV / (1 + gV) / sm1) * X[, 3] + ((1 - gV * (sig - 2)) / (1 + gV) / sm1) * X[, 4] -
              ((1 - gV * (sV - 2)) / (1 + gV) / sm1) * X[, 5] - ((gI * (sV - 2) - 1) / (1 + gI) / sm1) * X[, 6] -
              ((gV * (1 + gI) + gI * (1 + gV)) / ((1 + gI) * (1 + gV) * sm1)) * X[, 7] +
              ((sig - sV) / sm1) * X[, 8] + ((sV - sig) / sm1) * X[, 9]
      sh_i <- dt_g[importer == focal_importer, .(share_i = mean(s_imp)), by = exporter]
      ex <- keys[exp_mom$jmap - 1L]
      return(data.table::data.table(importer = as.character(focal_importer), good = as.character(g_code), block = "export",
                                    exporter = as.character(ex), resid = exp_mom$exp_Y - pred, Y = exp_mom$exp_Y,
                                    w = exp_mom$wt_exp, share_i = sh_i$share_i[match(ex, sh_i$exporter)]))
    }
    if (identical(kt_side, "importrows")) {
      sig <- sigma_val; sm1 <- sig - 1; X <- imp_X_mat; gk <- dvec[1]; gj <- dvec[-1]
      pred <- (gj / (1 + gj) / sm1) * X[, 1] + (gj / (1 + gj)) * X[, 2] + (-1 / sm1) * X[, 3] +
              (gj * (1 + gk) / (gk * (1 + gj) * sm1)) * X[, 4] + ((gj - gk) / (gk * (1 + gj))) * X[, 5]
      sh_i <- dt_g[importer == focal_importer, .(share_i = mean(s_imp)), by = exporter]
      return(data.table::data.table(importer = as.character(focal_importer), good = as.character(g_code), block = "import",
                                    exporter = as.character(exporter_order), resid = imp_Y_vec - pred, Y = imp_Y_vec,
                                    w = wt_imp_vec, share_i = sh_i$share_i[match(exporter_order, sh_i$exporter)]))
    }
    obj <- function(s) het_obj_fixed_sigma(d = dvec, sigma = s, imp_Y = imp_Y_vec, imp_X = imp_X_mat,
                                           exp_Y = exp_mom$exp_Y, exp_X = exp_mom$exp_X, exp_jmap = exp_mom$jmap,
                                           exp_sig_V = exp_mom$sig_V, exp_gam_V = exp_mom$gam_V,
                                           wt_imp = wt_imp_vec, wt_exp = exp_mom$wt_exp,
                                           ln_gamma_prior = NA_real_, shrinkage_lambda = 0,
                                           paper_exact_eq11 = pe11, ridge_all_coords = ridge_all,
                                           prior_form = prior_code, import_constant = imp_const, prior_eps = prior_eps)
    grid <- exp(seq(log(1.02), log(60), length.out = 240L))
    q <- vapply(grid, obj, numeric(1))
    if (!any(is.finite(q))) return(cell_failure("flat_profile"))
    i <- which.min(q)
    pol <- tryCatch(optimize(obj, c(grid[max(1L, i - 1L)], grid[min(length(grid), i + 1L)]), tol = 1e-8),
                    error = function(e) list(minimum = grid[i], objective = q[i]))
    if (!is.finite(pol$objective) || pol$objective > q[i]) pol <- list(minimum = grid[i], objective = q[i])
    data.table::data.table(importer = as.character(focal_importer), good = as.character(g_code), side = kt_side,
                           J = J, M = exp_mom$M, sigma_prof = pol$minimum, obj_prof = pol$objective, obj_true = obj(sigma_val))
  })
  g <- f
  body(g) <- as.call(c(b[seq_len(idx - 1L)], as.list(tail)[-1L]))
  formals(g) <- c(formals(f), alist(gamma_tbl = ))
  g
}
profile_cell <- .build_profile_fn()

all_res <- list(); all_rows <- list()
for (n_cty in sizes) {
  t0 <- Sys.time()
  wdir <- file.path(out_root, sprintf("n%d_s%d", n_cty, opt$seed)); baci <- file.path(wdir, "BACI_HS92_V202601")
  truth <- sb$make_synthetic_baci_dir(baci, n_goods = opt$goods, countries = ALL_CTY[seq_len(n_cty)], seed = opt$seed,
                                      within_sd = opt$within_sd, good_sd = 0, importer_sd = 0)
  tr_sig <- copy(truth$sigma)[, `:=`(importer = as.character(importer), good = as.character(good))]
  tr_gam <- copy(truth$gamma)[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]

  # the pipeline's own panel
  cfg <- build_config(list(data = baci, minyear = 1995L, maxyear = NA_integer_, agg_level = "hs4",
                           shrinkage_lambda = 0, bw_lag = "calendar"))
  cfg$use_regions <- FALSE
  raw <- suppressMessages(prepare_raw_data(cfg))
  dt_country <- prepare_data(cfg, raw_cache = raw)$dt

  # shares, from the panel: the mean over cells of the largest exporter's share and of the HHI
  sh <- dt_country[, .(max_share = max(s_imp), hhi = sum(s_imp^2)), by = .(importer, good, t)][
          , .(max_share = mean(max_share), hhi = mean(hhi)), by = .(importer, good)]
  n_exp_cell <- dt_country[, uniqueN(exporter), by = .(importer, good)]$V1

  # every lookup at the truth
  cfg$sigma_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]
  cfg$sigma_fallback <- median(tr_sig$sigma_true)
  cfg$sigma_V_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]
  cfg$sigma_V_default <- median(tr_sig$sigma_true)
  cfg$gamma_V_exporter_lookup <- tr_gam[, .(importer, exporter, good, gamma = gamma_true)]
  cfg$gamma_V_lookup <- NULL
  cfg$gamma_V_default <- median(tr_gam$gamma_true); cfg$gamma_start <- cfg$gamma_V_default
  cfg$shrinkage_priors <- NULL
  gamma_tbl <- tr_gam

  res <- list(); rows <- list(); n_fail <- 0L; first_err <- NA_character_
  for (g in unique(dt_country$good)) {
    dt_g <- dt_country[good == g]
    exporter_dests <- compute_exporter_dest_counts(dt_g); exp_lookup <- compute_exporter_lookup(dt_g)
    cfg_g <- cfg
    gvt <- cfg_g$gamma_V_exporter_lookup[good == as.character(g)]; setkeyv(gvt, c("importer", "exporter")); cfg_g$gamma_V_exporter_lookup <- gvt
    imp_stats <- dt_g[, .(n_exp = uniqueN(exporter), max_pd = max(period_count)), by = importer]
    viable <- imp_stats[n_exp >= cfg_g$min_exporters & max_pd >= cfg_g$min_periods, importer]
    gt_g <- gamma_tbl[good == as.character(g)]
    for (imp in viable) for (side in c("import", "export", "both", "importrows", "exportrows")) {
      kt_side <<- side
      r <- tryCatch(profile_cell(dt_g, imp, dt_g, cfg_g, exporter_dests = exporter_dests, exp_lookup = exp_lookup, gamma_tbl = gt_g),
                    error = function(e) { n_fail <<- n_fail + 1L; if (is.na(first_err)) first_err <<- conditionMessage(e); NULL })
      if (is.data.table(r) && "sigma_prof" %in% names(r)) res[[length(res) + 1L]] <- r
      if (is.data.table(r) && "resid" %in% names(r)) rows[[length(rows) + 1L]] <- r
    }
  }
  res <- rbindlist(res)
  if (nrow(res) == 0L) stop("no cell profiled at n = ", n_cty, "; first error: ", first_err)
  res <- merge(res, tr_sig, by = c("importer", "good"))
  res[, lr := log((sigma_prof - 1) / (sigma_true - 1))]
  res[, `:=`(n_countries = n_cty, seed = opt$seed, within_sd = opt$within_sd)]
  all_res[[length(all_res) + 1L]] <- res
  rows <- rbindlist(rows); rows[, n_countries := n_cty]
  all_rows[[length(all_rows) + 1L]] <- rows

  cat(sprintf("\n=== %d countries, %d goods, seed %d, within_sd %g | weights %s | V rule %s | cells %d | exporters/cell mean %.1f | mean max share %.3f | mean HHI %.3f | %.0f s%s ===\n",
              n_cty, opt$goods, opt$seed, opt$within_sd, opt$bw_weights, opt$ref_dest, uniqueN(res[, .(importer, good)]), mean(n_exp_cell),
              mean(sh$max_share), mean(sh$hhi), as.numeric(Sys.time() - t0, units = "secs"),
              if (n_fail) sprintf(" | cell errors %d (first: %s)", n_fail, first_err) else ""))
  print(res[, .(cells = .N, med_lr = round(median(lr), 3), mean_lr = round(mean(lr), 3), med_abs_lr = round(median(abs(lr)), 3),
                share_abs_lt_0.2 = round(mean(abs(lr) < 0.2), 3), at_cap = round(mean(sigma_prof > 49), 3)),
            by = side][order(side)])
  # the moment rows at the truth: is E[u] = 0, and does u move with the exporter's share?
  cat("  residual rows at the truth (u = Y - pred; t = mean / s.e.; slope = coefficient of resid on share_i):\n")
  print(rows[, .(rows = .N, mean_u = signif(mean(resid), 3), t_mean = round(mean(resid) / (sd(resid) / sqrt(.N)), 2),
                 mean_u_over_sd_Y = round(mean(resid) / sd(Y), 3), wmean_u_over_sd_Y = round(sum(w * resid) / sum(w) / sd(Y), 3),
                 cor_u_share = round(cor(resid, share_i), 3),
                 slope_on_share = signif(coef(lm(resid ~ share_i))[2], 3)), by = block][order(block)])
}
all <- rbindlist(all_res)
saveRDS(all, file.path(out_root, sprintf("eq11_shares_%s_%s.rds", opt$bw_weights, opt$ref_dest)))
saveRDS(rbindlist(all_rows), file.path(out_root, sprintf("eq11_rows_at_truth_%s_%s.rds", opt$bw_weights, opt$ref_dest)))
cat("\n=== summary: median lr by block and world size ===\n")
print(dcast(all[, .(med_lr = round(median(lr), 3)), by = .(side, n_countries)], side ~ n_countries, value.var = "med_lr"))
cat("\nWritten:", file.path(out_root, sprintf("eq11_shares_%s_%s.rds", opt$bw_weights, opt$ref_dest)), "and", sprintf("eq11_rows_at_truth_%s_%s.rds", opt$bw_weights, opt$ref_dest), "\n")
