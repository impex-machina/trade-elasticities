#!/usr/bin/env Rscript
# ============================================================================
# analysis/sigma_fallback_hierarchy_census.R  (patch 0117, audit #7, M2)
#
# How much does the product dimension say about sigma, and how far would a
# hierarchical fallback move the cells that now take the one global value?
# Every Stage-2b cell without a usable Stage-1 sigma (no estimate, a box
# edge, or within one SE of the pole) carries the global fallback, the median
# of the clean set (2.4728 in v0.11.0, 41% of published rows), although Stage
# 2a already runs on region x good medians of the same clean set. Measurement
# only, on the shipped tables, no estimation:
#   1. Variance of z = ln(sigma - 1) over the clean cells (one per importer x
#      good), and the share explained by the good and by region x good.
#   2. A leave-one-out test on the cells that HAVE an estimate: predict each
#      cell's sigma from (a) the global median and (b) the ladder region x
#      good -> good -> global (each level used when it holds >= k other clean
#      cells), the cell itself left out; median |ln((sigma_pred - 1) /
#      (sigma - 1))|. This is how much better a good-level fallback predicts a
#      sigma the data identify.
#   3. The ladder's value for every fallback cell of the published table:
#      how far it moves from the global value, by sigma_source and level, in
#      cells and in rows.
# Caveat for 2: fallback cells are not a random sample of cells -- pole cells
# have low estimates by construction -- so the leave-one-out error describes
# the estimated population; validation/pole_rule_accuracy.R's P3 policy is
# the known-truth counterpart.
#
# Usage (repo root):
#   Rscript analysis/sigma_fallback_hierarchy_census.R [--stage1 PATH] [--stage2b PATH]
#       [--min-cells 3] [--label v0110] [--out results/sigma_fallback_hierarchy_census_v0110.json]
#       [--md docs/results/sigma_fallback_hierarchy_census_v0110.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

#' Leave-one-out medians: for each element, the median of the others.
loo_median <- function(v) {
  n <- length(v); if (n < 2L) return(rep(NA_real_, n))
  o <- order(v); s <- v[o]; m <- n - 1L
  pos <- seq_len(n)                                   # sorted position of the left-out element
  at <- function(j, i) ifelse(j < i, s[pmin(j, n)], s[pmin(j + 1L, n)])
  res <- if (m %% 2L == 1L) at((m + 1L) %/% 2L, pos) else (at(m %/% 2L, pos) + at(m %/% 2L + 1L, pos)) / 2
  out <- numeric(n); out[o] <- res; out
}

#' The census. s1: the shipped Stage-1 table; s2b: the Stage-2b table.
sigma_hierarchy_census <- function(s1, s2b, k = 3L, pole_c = 1) {
  s1 <- as.data.table(s1); s2b <- as.data.table(s2b)
  for (nm in c("importer", "good")) { set(s1, j = nm, value = as.character(s1[[nm]])); set(s2b, j = nm, value = as.character(s2b[[nm]])) }
  if (!"convergence" %in% names(s1)) s1[, convergence := fifelse(status == "ok", 0L, -99L)]
  sc <- stage2_sigma_clean(s1, edge_rule = "fallback", pole_rule = "fallback", pole_c = pole_c)
  cl <- sc$clean[, .(importer = as.character(importer), good = as.character(good), sigma)]
  fb_global <- median(cl$sigma)
  cl[, region := assign_regions(as.integer(importer))]
  cl[, z := log(sigma - 1)]
  # 1. variance decomposition of z
  v_tot <- var(cl$z)
  w_good <- cl[, .(ss = sum((z - mean(z))^2), n = .N), by = good]
  w_rg   <- cl[, .(ss = sum((z - mean(z))^2), n = .N), by = .(region, good)]
  r2_good <- 1 - sum(w_good$ss) / sum((cl$z - mean(cl$z))^2)
  r2_rg   <- 1 - sum(w_rg$ss) / sum((cl$z - mean(cl$z))^2)
  # 2. leave-one-out prediction on the estimated cells
  cl[, n_g := .N, by = good]; cl[, n_rg := .N, by = .(region, good)]
  cl[, loo_g := loo_median(sigma), by = good]; cl[, loo_rg := loo_median(sigma), by = .(region, good)]
  cl[, loo_global := loo_median(sigma)]
  cl[, pred_ladder := fifelse(n_rg - 1L >= k, loo_rg, fifelse(n_g - 1L >= k, loo_g, loo_global))]
  cl[, level := fifelse(n_rg - 1L >= k, "region_good", fifelse(n_g - 1L >= k, "good", "global"))]
  err <- function(pred) median(abs(log((pred - 1) / (cl$sigma - 1))), na.rm = TRUE)
  e_global <- err(cl$loo_global); e_ladder <- err(cl$pred_ladder); e_good <- err(fifelse(cl$n_g - 1L >= k, cl$loo_g, cl$loo_global))
  # 3. the ladder for the fallback cells of the published table
  med_rg <- cl[, .(sig_rg = median(sigma), n_rg = .N), by = .(region, good)]
  med_g  <- cl[, .(sig_g = median(sigma), n_g = .N), by = good]
  pub <- if ("trim_reason" %in% names(s2b)) s2b[is.na(trim_reason)] else s2b
  if (!"sigma_source" %in% names(pub)) stop("the Stage-2b table has no sigma_source column (v0.10.1+)")
  fbc <- unique(pub[sigma_source != "estimated", .(importer, good, sigma_source)], by = c("importer", "good"))
  rows <- pub[sigma_source != "estimated", .N, by = .(importer, good)]
  fbc <- rows[fbc, on = c("importer", "good")]
  fbc[, region := assign_regions(as.integer(importer))]
  fbc <- med_rg[fbc, on = c("region", "good")]; fbc <- med_g[fbc, on = "good"]
  fbc[is.na(n_rg), n_rg := 0L]; fbc[is.na(n_g), n_g := 0L]
  fbc[, ladder := fifelse(n_rg >= k, sig_rg, fifelse(n_g >= k, sig_g, fb_global))]
  fbc[, level := fifelse(n_rg >= k, "region_good", fifelse(n_g >= k, "good", "global"))]
  fbc[, move := abs(log((ladder - 1) / (fb_global - 1)))]
  q <- function(x, p = c(.1, .25, .5, .75, .9)) as.list(setNames(round(quantile(x, p, na.rm = TRUE), 4), paste0("p", 100 * p)))
  by_src <- fbc[, .(cells = .N, rows = sum(N), ladder_median = median(ladder), move_median = median(move),
                    cells_move_gt_25pct = sum(move > log(1.25)), rows_move_gt_25pct = sum(N[move > log(1.25)])), by = sigma_source][order(sigma_source)]
  list(
    k = k, clean_cells = nrow(cl), global_fallback = fb_global,
    z_variance = v_tot, r2_good = r2_good, r2_region_good = r2_rg,
    good_sigma_median_quantiles = q(med_g$sig_g[med_g$n_g >= k]),
    loo = list(cells = nrow(cl), err_global = e_global, err_good = e_good, err_ladder = e_ladder,
               ladder_level_share = as.list(prop.table(table(cl$level)))),
    fallback = list(cells = nrow(fbc), rows = sum(fbc$N),
                    level_cells = as.list(table(fbc$level)),
                    ladder_quantiles = q(fbc$ladder),
                    cells_move_gt_25pct = sum(fbc$move > log(1.25)), rows_move_gt_25pct = sum(fbc$N[fbc$move > log(1.25)]),
                    by_source = by_src)
  )
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
  s1_path  <- get_arg("--stage1",  "data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds")
  s2b_path <- get_arg("--stage2b", "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
  k        <- as.integer(get_arg("--min-cells", "3"))
  label    <- get_arg("--label", "run")
  out_json <- get_arg("--out", sprintf("results/sigma_fallback_hierarchy_census_%s.json", label))
  out_md   <- get_arg("--md",  sprintf("docs/results/sigma_fallback_hierarchy_census_%s.md", label))
  for (p in c(s1_path, s2b_path)) if (!file.exists(p)) stop("not found: ", p)
  .this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) "analysis")
  .root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
  for (f in c("utils_general.R", "region_map.R", "iteration_helpers.R")) source(file.path(.root, "R", f))
  sha <- function(p) { con <- file(p, "rb"); on.exit(close(con)); tolower(unclass(as.character(openssl::sha256(con)))) }
  res <- sigma_hierarchy_census(readRDS(s1_path), readRDS(s2b_path), k = k)
  out <- list(meta = list(stage1 = s1_path, stage1_sha256 = sha(s1_path), stage2b = s2b_path, stage2b_sha256 = sha(s2b_path),
                          label = label, min_cells = k,
                          git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
                          timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
              census = res)
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
  fi <- function(x) format(x, big.mark = ",", scientific = FALSE); f3 <- function(x) formatC(x, digits = 3, format = "f")
  fb <- res$fallback; lo <- res$loo; gq <- res$good_sigma_median_quantiles
  md <- c(sprintf("# A hierarchical sigma fallback, sized (%s)", label), "",
          sprintf("Stage 1 `%s`, Stage 2b `%s`; rules as shipped (edge and pole fallback, c = 1); a level is used when it holds >= %d clean cells. Rev %s, %s.",
                  basename(s1_path), basename(s2b_path), k, out$meta$git_rev, out$meta$timestamp), "",
          sprintf("- Clean cells: %s; the global fallback (their median) %.4f.", fi(res$clean_cells), res$global_fallback),
          sprintf("- Share of the variance of ln(sigma - 1) across clean cells explained by the good: %.1f%%; by region x good: %.1f%%.", 100 * res$r2_good, 100 * res$r2_region_good),
          sprintf("- Good-level medians (goods with >= %d clean cells): p10 %s, p25 %s, median %s, p75 %s, p90 %s.", k, f3(gq$p10), f3(gq$p25), f3(gq$p50), f3(gq$p75), f3(gq$p90)),
          sprintf("- Leave-one-out on the estimated cells, median |ln((sigma_pred - 1)/(sigma - 1))|: global %s, good %s, ladder %s (%.0f%% lower than global).",
                  f3(lo$err_global), f3(lo$err_good), f3(lo$err_ladder), 100 * (1 - lo$err_ladder / lo$err_global)),
          sprintf("- Fallback cells in the published table: %s (%s rows). The ladder resolves them at %s.", fi(fb$cells), fi(fb$rows),
                  paste(sprintf("%s %s", names(fb$level_cells), fi(unlist(fb$level_cells))), collapse = ", ")),
          sprintf("- Their ladder sigma: p10 %s, p25 %s, median %s, p75 %s, p90 %s; it moves (sigma - 1) by more than 25%% from the global value on %s cells (%s rows).",
                  f3(fb$ladder_quantiles$p10), f3(fb$ladder_quantiles$p25), f3(fb$ladder_quantiles$p50), f3(fb$ladder_quantiles$p75), f3(fb$ladder_quantiles$p90),
                  fi(fb$cells_move_gt_25pct), fi(fb$rows_move_gt_25pct)), "",
          "| sigma_source | cells | rows | ladder median | median move (log sigma - 1) | cells moved > 25% | rows moved > 25% |", "|---|---|---|---|---|---|---|",
          sprintf("| %s | %s | %s | %s | %s | %s | %s |", fb$by_source$sigma_source, fi(fb$by_source$cells), fi(fb$by_source$rows), f3(fb$by_source$ladder_median),
                  f3(fb$by_source$move_median), fi(fb$by_source$cells_move_gt_25pct), fi(fb$by_source$rows_move_gt_25pct)), "",
          "Reading rule (fixed before the run): docs/methodology/stage2_country.md, \"A hierarchical sigma fallback\".", "")
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n")
  cat(sprintf("sigma_fallback_hierarchy_census: wrote %s and %s\n", out_json, out_md))
}
