#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_sigma_update.R  (prototype, patch 0150 follow-up)
#
# The sigma-update pass, measured at known truth before it is built.
#
# Stage 1 estimates sigma under gamma_j = gamma_k; Stage 2 estimates the
# gamma_j conditional on that sigma. validation/known_truth_stage1_heterogeneity.R
# shows the Stage-1 sigma is biased upward in proportion to the within-cell
# gamma heterogeneity. The remedy the paper's joint NLSUR implies is a sigma
# update: hold the Stage-2b gammas fixed and re-solve sigma per cell from the
# full Eq. (10)+(11) objective -- block coordinate descent on the paper's
# estimand. This script runs that one update on a synthetic world and
# compares, cell by cell, the truth with
#   (a) the sigma Stage 2b used (the Stage-1 sigma, or the fallback),
#   (b) the profile sigma at the Stage-2b gamma-hats, and
#   (c) the profile sigma at the TRUE gammas (the oracle: does the system
#       identify sigma once the heterogeneity is accounted for?).
# The moments, weights, sigma_V / gamma_V lookups and the objective are the
# pipeline's own: the cell estimator's body is reused up to its optimizer call.
#
# Usage (the runner's own CLI; the script sources scripts/run_estimation.R,
# which runs or loads Stage 2b and leaves its session behind):
#   KT_SEED=20261015 KT_WITHIN_SD=0.7 KT_GOODS=12 [KT_SIDE=both|import|export] [KT_ORACLE_V=1] \
#   Rscript validation/known_truth_sigma_update.R --data <world>/BACI_HS92_V202601 \
#           --out-dir <world>/out --ncores 1 --stage all
# (PowerShell: $env:KT_SEED = "20261015" etc. before the call.)
# <world> is a directory validation/synthetic_baci.R (or the heterogeneity
# harness) generated with that seed / within_sd / goods. The truth is
# regenerated from the seed INTO A TEMP DIRECTORY -- the world's own files are
# never touched. KT_SIDE restricts the profile to one block of the objective;
# KT_ORACLE_V=1 evaluates Eq. (11) at the TRUE sigma_V and gamma_V.
# Writes <out-dir>/sigma_update_profile_<side>[_oracleV].rds / .csv.
# ===========================================================================

kt_seed  <- as.integer(Sys.getenv("KT_SEED", "20261015"))
kt_wsd   <- as.numeric(Sys.getenv("KT_WITHIN_SD", "0.7"))
kt_goods <- as.integer(Sys.getenv("KT_GOODS", "12"))
kt_side  <- Sys.getenv("KT_SIDE", "both")   # both | import | export
kt_oracle_v <- identical(Sys.getenv("KT_ORACLE_V", "0"), "1")   # 1: Eq. (11) at the TRUE sigma_V and gamma_V
if (!kt_side %in% c("both", "import", "export")) stop("KT_SIDE must be both, import or export; got ", kt_side)

.this_dir <- function() {
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else normalizePath(".")
}
.root <- normalizePath(file.path(.this_dir(), ".."))

# ---- 1. Stage 2b through the runner (its globals stay in this session) -----
source(file.path(.root, "scripts", "run_estimation.R"))
stopifnot(exists("dt_country"), exists("paths"))
# Under --stage all with the Stage-2b table already on disk the runner loads it
# and never builds config_2b; rebuild it exactly as the runner's else-branch
# does (the pass-3 exporter-specific gamma_V comes from the pass-2 table).
if (!exists("config_2b")) {
  config_2b <- config_country
  .lk <- stage2b_sigma_lookups(sigma_clean)
  config_2b$sigma_lookup <- .lk$sigma_lookup; config_2b$sigma_se_lookup <- .lk$sigma_se_lookup
  config_2b$sigma_adjust_lookup <- .lk$sigma_adjust_lookup; config_2b$sigma_V_lookup <- .lk$sigma_V_lookup
  config_2b$sigma_fallback <- sigma_fallback; config_2b$shrinkage_priors <- country_priors
  config_2b$shrinkage_lambda <- config$shrinkage_lambda
  config_2b$tier1_min_periods <- config$tier1_min_periods; config_2b$tier1_min_dests <- config$tier1_min_dests
  config_2b$tier2_min_periods <- config$tier2_min_periods
  config_2b$sigma_V_default <- sigma_fallback; config_2b$gamma_V_default <- exp(median(country_priors$ln_gamma_prior))
  config_2b$sigma_start <- sigma_fallback; config_2b$gamma_start <- config_2b$gamma_V_default
  .rmap <- build_region_map(); .cc <- unique(as.integer(dt_country$importer))
  .c2r <- data.table::data.table(cty_code = .cc, region = assign_regions(.cc, .rmap))
  .gvc <- merge(.c2r, s2b_priors$gam_V_regional, by = "region", allow.cartesian = TRUE)
  config_2b$gamma_V_lookup <- .gvc[, .(importer = as.character(cty_code), good, gamma)]
  .p2 <- paste0(out_base_country, "_fixed_sigma_pass2.rds")
  if (file.exists(.p2)) {
    .prev <- readRDS(.p2); data.table::setDT(.prev)
    config_2b$gamma_V_exporter_lookup <- .prev[is_estimated_row(tier, convergence) & convergence == 0L & is.finite(gamma) & gamma > 0 & is_published_row(.prev),
                                               .(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good), gamma)]
  }
  config_2b <- init_from_regional(config_2b, regional_handoff)
  cat("  config_2b rebuilt from the loaded Stage-2b run\n")
}

cat("\n\n========== SIGMA UPDATE PROFILE (prototype) ==========\n")
cat(sprintf("world: seed %d, within_sd %g, %d goods | side: %s%s\n", kt_seed, kt_wsd, kt_goods, kt_side,
            if (kt_oracle_v) " (oracle sigma_V, gamma_V)" else ""))

# ---- 2. truth, regenerated from the seed into a temp directory ---------------
# (same seed, same parameters => the same world; the --data directory is not
# rewritten, so a sync client or a lock on its files cannot interfere)
sb <- new.env(); sys.source(file.path(.root, "validation", "synthetic_baci.R"), envir = sb)
.tmp_world <- file.path(tempdir(), sprintf("kt_truth_w%g_s%d", kt_wsd, kt_seed), "BACI_HS92_V202601")
truth <- sb$make_synthetic_baci_dir(.tmp_world, n_goods = kt_goods, seed = kt_seed, within_sd = kt_wsd,
                                    good_sd = 0, importer_sd = 0)
unlink(dirname(.tmp_world), recursive = TRUE)
tr_sig <- data.table::copy(truth$sigma)[, `:=`(importer = as.character(importer), good = as.character(good))]
tr_gam <- data.table::copy(truth$gamma)[, `:=`(importer = as.character(importer), exporter = as.character(exporter),
                                               good = as.character(good))]
cat(sprintf("  truth regenerated: %d (importer, good) sigmas, %d (importer, exporter, good) gammas\n", nrow(tr_sig), nrow(tr_gam)))

# ---- 3. the Stage-2b gammas (every row, trimmed rows included) ---------------
s2b <- readRDS(paths$country_file); data.table::setDT(s2b)
gamma_tbl <- merge(s2b[, .(importer = as.character(importer), exporter = as.character(exporter),
                           good = as.character(good), gamma_est = gamma, tier)],
                   tr_gam, by = c("importer", "exporter", "good"), all.x = TRUE)
cat(sprintf("  Stage-2b table: %d rows, %d without a true gamma (should be 0)\n", nrow(gamma_tbl), sum(is.na(gamma_tbl$gamma_true))))

# ---- 3b. export-side oracle: the reference destination's sigma_V and gamma_V from the truth ---
if (kt_oracle_v) {
  config_2b$sigma_V_lookup <- tr_sig[, .(importer, good, sigma = sigma_true)]
  config_2b$gamma_V_exporter_lookup <- tr_gam[, .(importer, exporter, good, gamma = gamma_true)]
  cat("  export-side oracle: sigma_V and gamma_V taken from the truth\n")
}

# ---- 4. the cell estimator up to its optimizer call, then the sigma profile ---
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
    keys <- c(ref_exporter, exporter_order)                      # d order: gamma_k, gamma_1..gamma_J
    mi <- match(paste(as.character(focal_importer), as.character(keys)),
                paste(gamma_tbl$importer, gamma_tbl$exporter))
    g_est  <- gamma_tbl$gamma_est[mi]
    g_true <- gamma_tbl$gamma_true[mi]
    prof <- function(dvec) {
      if (any(!is.finite(dvec)) || any(dvec <= 0)) return(c(NA_real_, NA_real_, NA_real_))
      obj <- function(s) het_obj_fixed_sigma(d = dvec, sigma = s, imp_Y = imp_Y_vec, imp_X = imp_X_mat,
                                             exp_Y = exp_mom$exp_Y, exp_X = exp_mom$exp_X, exp_jmap = exp_mom$jmap,
                                             exp_sig_V = exp_mom$sig_V, exp_gam_V = exp_mom$gam_V,
                                             wt_imp = wt_imp_vec, wt_exp = exp_mom$wt_exp,
                                             ln_gamma_prior = ln_gamma_prior, shrinkage_lambda = 0,
                                             paper_exact_eq11 = pe11, ridge_all_coords = ridge_all,
                                             prior_form = prior_code, import_constant = imp_const, prior_eps = prior_eps)
      grid <- exp(seq(log(1.02), log(60), length.out = 240L))
      q <- vapply(grid, obj, numeric(1))
      if (!any(is.finite(q))) return(c(NA_real_, NA_real_, NA_real_))
      i <- which.min(q)
      pol <- tryCatch(optimize(obj, c(grid[max(1L, i - 1L)], grid[min(length(grid), i + 1L)]), tol = 1e-8),
                      error = function(e) list(minimum = grid[i], objective = q[i]))
      if (!is.finite(pol$objective) || pol$objective > q[i]) pol <- list(minimum = grid[i], objective = q[i])
      c(pol$minimum, pol$objective, obj(sigma_val))
    }
    pe <- prof(g_est); pt <- prof(g_true)
    data.table::data.table(importer = as.character(focal_importer), good = as.character(g_code),
                           sigma_used = sigma_val, sigma_is_fallback = sigma_is_fallback,
                           J = J, M = exp_mom$M, n_tier1 = N_tier1,
                           sigma_prof_est = pe[1], obj_prof_est = pe[2], obj_used_est = pe[3],
                           sigma_prof_true = pt[1], obj_prof_true = pt[2], obj_used_true = pt[3])
  })
  g <- f
  body(g) <- as.call(c(b[seq_len(idx - 1L)], as.list(tail)[-1L]))
  formals(g) <- c(formals(f), alist(gamma_tbl = ))
  g
}
profile_cell <- .build_profile_fn()

# ---- 5. drive it the way estimate_product_fixed_sigma() does -----------------
out <- list(); n_fail <- 0L; n_early <- 0L; first_err <- NA_character_
goods <- unique(dt_country$good)
cat(sprintf("  profiling %d goods ...\n", length(goods)))
for (g in goods) {
  dt_g <- dt_country[good == g]
  exporter_dests <- compute_exporter_dest_counts(dt_g)
  exp_lookup <- compute_exporter_lookup(dt_g)
  cfg_g <- config_2b
  if (!is.null(cfg_g$gamma_V_exporter_lookup)) {
    gvt <- cfg_g$gamma_V_exporter_lookup[good == as.character(g)]
    data.table::setkeyv(gvt, c("importer", "exporter")); cfg_g$gamma_V_exporter_lookup <- gvt
  }
  imp_stats <- dt_g[, .(n_exp = uniqueN(exporter), max_pd = max(period_count)), by = importer]
  viable <- imp_stats[n_exp >= cfg_g$min_exporters & max_pd >= cfg_g$min_periods, importer]
  gt_g <- gamma_tbl[good == as.character(g)]
  for (imp in viable) {
    r <- tryCatch(profile_cell(dt_g, imp, dt_g, cfg_g, exporter_dests = exporter_dests, exp_lookup = exp_lookup,
                               gamma_tbl = gt_g),
                  error = function(e) { n_fail <<- n_fail + 1L
                                        if (is.na(first_err)) first_err <<- conditionMessage(e); NULL })
    if (data.table::is.data.table(r) && "sigma_prof_est" %in% names(r)) out[[length(out) + 1L]] <- r
    else if (!is.null(r)) n_early <- n_early + 1L   # a cell_failure or the all-Tier-3 early return
  }
}
cat(sprintf("  cells profiled %d | cell errors %d | early returns (cell_failure / all-Tier-3) %d\n", length(out), n_fail, n_early))
if (!is.na(first_err)) cat(sprintf("  first cell error: %s\n", first_err))
if (length(out) == 0L) stop("no cell was profiled; see the first cell error above")
res <- data.table::rbindlist(out)
res <- merge(res, tr_sig, by = c("importer", "good"))
tag <- sprintf("%s%s", kt_side, if (kt_oracle_v) "_oracleV" else "")
data.table::fwrite(res, file.path(opts$out_dir, sprintf("sigma_update_profile_%s.csv", tag)))
saveRDS(res, file.path(opts$out_dir, sprintf("sigma_update_profile_%s.rds", tag)))

lr <- function(s) log((s - 1) / (res$sigma_true - 1))
res[, `:=`(lr_used = lr(sigma_used), lr_est = lr(sigma_prof_est), lr_true = lr(sigma_prof_true))]
summ <- function(x, lab) cat(sprintf("  %-38s n=%3d  median lr %+.3f  mean lr %+.3f  median |lr| %.3f  share |lr|<0.2 %.3f\n",
                                     lab, sum(is.finite(x)), median(x, na.rm = TRUE), mean(x, na.rm = TRUE),
                                     median(abs(x), na.rm = TRUE), mean(abs(x) < 0.2, na.rm = TRUE)))
cat(sprintf("\n=== %d cells, %d with the fallback sigma (lr = ln((sigma - 1) / (sigma_true - 1))) ===\n",
            nrow(res), sum(res$sigma_is_fallback)))
own <- res[sigma_is_fallback == FALSE]
summ(own$lr_used,  "(a) sigma Stage 2b used (own Stage-1 sigma)")
summ(own$lr_est,   "(b) profile at Stage-2b gamma-hats")
summ(own$lr_true,  "(c) profile at TRUE gammas (oracle)")
summ(res$lr_est,   "(b) incl. fallback-sigma cells")
summ(res$lr_true,  "(c) incl. fallback-sigma cells")
cat("\n=== by export-side richness (cells with own sigma) ===\n")
own[, m_bin := cut(M, c(-1, 1, 3, 6, 100), labels = c("M<=1", "2-3", "4-6", "7+"))]
print(own[, .(cells = .N, med_lr_used = round(median(lr_used), 3), med_lr_est = round(median(lr_est), 3),
              med_lr_true = round(median(lr_true), 3), med_abs_used = round(median(abs(lr_used)), 3),
              med_abs_est = round(median(abs(lr_est)), 3), med_abs_true = round(median(abs(lr_true)), 3)), by = m_bin][order(m_bin)])
cat("\n=== objective check: profile objective <= objective at the sigma used (share of cells) ===\n")
cat(sprintf("  at gamma-hats %.3f | at true gammas %.3f\n",
            mean(res$obj_prof_est <= res$obj_used_est + 1e-12, na.rm = TRUE),
            mean(res$obj_prof_true <= res$obj_used_true + 1e-12, na.rm = TRUE)))
cat("\nWritten:", file.path(opts$out_dir, sprintf("sigma_update_profile_%s.rds", tag)), "\n")
