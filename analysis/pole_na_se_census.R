#!/usr/bin/env Rscript
# ============================================================================
# analysis/pole_na_se_census.R  (patch 0116, fresh-eyes audit #7, item A3)
#
# The sigma-pole rule (apply_sigma_pole_rule(), v0.10.0 default c = 1) drops a
# Stage-1 cell from the Stage-2 clean set when sigma - 1 < c * sigma_se, and
# KEEPS every cell whose sigma_se is not finite: such a cell cannot be
# assessed. The pole problem is about sigma's value (Eq. (10)'s 1/(sigma - 1)
# coefficients), so a missing SE is not evidence of distance from 1. From the
# shipped stage1_summary.json at most ~440 ok cells are in this position
# (omega-edge boundary optima whose projected edge SE failed). This census
# sizes them on the tables themselves, before any rule changes:
#   - the clean set as Stage 2 builds it (stage2_sigma_clean(), shipped rules),
#     and the cells in it with a non-finite sigma_se, by route / edge / SE
#     status, with their sigma distribution and boundary_corner flag;
#   - how many of them the rule WOULD drop if their SE were the median
#     relative SE (sigma_se / sigma) of assessed clean cells on the same route
#     and edge -- a sizing device, not a proposed rule;
#   - their Stage-2b rows (published): count, Tier mix, sigma_robust, gamma.
# No estimation; seconds on the shipped tables.
#
# Usage (repo root):
#   Rscript analysis/pole_na_se_census.R --stage1 PATH --stage2b PATH
#       [--pole-se 1] [--label v0110] [--out results/pole_na_se_census_v0110.json]
#       [--md docs/results/pole_na_se_census_v0110.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.sha256_file <- function(p) {
  con <- file(p, "rb"); on.exit(close(con), add = TRUE)
  tolower(unclass(as.character(openssl::sha256(con))))
}
q <- function(x, p = c(.1, .25, .5, .75, .9)) { x <- x[is.finite(x)]; if (!length(x)) return(NULL); as.list(setNames(round(quantile(x, p), 6), paste0("p", 100 * p))) }

pole_na_se_census <- function(s1, s2b, pole_c = 1) {
  s1 <- as.data.table(s1); s2b <- as.data.table(s2b)
  for (k in c("importer", "good")) { set(s1, j = k, value = as.character(s1[[k]])); set(s2b, j = k, value = as.character(s2b[[k]])) }
  if (!"convergence" %in% names(s1)) s1[, convergence := fifelse(status == "ok", 0L, -99L)]
  sc <- stage2_sigma_clean(s1, edge_rule = "fallback", pole_rule = "fallback", pole_c = pole_c)
  cl <- copy(sc$clean)
  col_or_na <- function(nm, na) if (nm %in% names(cl)) cl[[nm]] else rep(na, nrow(cl))
  cl[, `:=`(route = col_or_na("final_source", NA_character_), edge = col_or_na("hliml_boundary_edge", NA_character_),
            se_status = col_or_na("edge_se_status", NA_character_), corner = col_or_na("boundary_corner", NA) %in% TRUE)]
  cl[, unassessed := !is.finite(sigma_se)]
  cl[, grp := paste(route, fifelse(is.na(edge), "-", edge))]
  rel <- cl[!unassessed & is.finite(sigma) & sigma > 0, .(rel_se_med = median(sigma_se / sigma)), by = grp]
  cl <- rel[cl, on = "grp"]
  ua <- cl[unassessed == TRUE]
  ua[, would_drop := is.finite(rel_se_med) & (sigma - 1) < pole_c * rel_se_med * sigma]
  tab <- function(x) { if (!length(x)) return(list()); t <- table(x, useNA = "ifany"); as.list(setNames(as.integer(t), ifelse(is.na(names(t)), "NA", names(t)))) }
  key_ua <- paste(ua$importer, ua$good, sep = "\r")
  pub <- if ("trim_reason" %in% names(s2b)) s2b[is.na(trim_reason)] else s2b
  rows <- pub[paste(importer, good, sep = "\r") %in% key_ua]
  est  <- function(x) x[is_estimated_row(tier, convergence) & is.finite(gamma) & gamma > 0]
  list(
    clean_cells = nrow(cl), dropped_edge = sc$n_edge_dropped, dropped_pole = sc$n_pole_dropped,
    unassessed_cells = nrow(ua),
    unassessed_by_route = tab(ua$route), unassessed_by_edge = tab(ua$edge), unassessed_by_se_status = tab(ua$se_status),
    unassessed_boundary_corner = sum(ua$corner),
    unassessed_sigma_quantiles = q(ua$sigma),
    unassessed_sigma_lt = list(`1.2` = sum(ua$sigma < 1.2), `1.5` = sum(ua$sigma < 1.5), `2` = sum(ua$sigma < 2)),
    would_drop_at_route_median_rel_se = sum(ua$would_drop),
    route_median_rel_se = setNames(as.list(round(rel$rel_se_med, 6)), rel$grp),
    stage2b_rows = nrow(rows), stage2b_rows_tier3 = sum(rows$tier %in% 3L),
    stage2b_sigma_robust_true = sum(rows$sigma_robust %in% TRUE),
    stage2b_gamma_median_these = if (nrow(est(rows))) median(est(rows)$gamma) else NA_real_,
    stage2b_gamma_median_all_estimated = median(est(pub)$gamma),
    cells = ua[, .(importer, good, sigma, route, edge, se_status, corner, would_drop)]
  )
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) {
    w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
  }
  s1_path  <- get_arg("--stage1",  "data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds")
  s2b_path <- get_arg("--stage2b", "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
  pole_c   <- as.numeric(get_arg("--pole-se", "1"))
  label    <- get_arg("--label", "run")
  out_json <- get_arg("--out", sprintf("results/pole_na_se_census_%s.json", label))
  out_md   <- get_arg("--md",  sprintf("docs/results/pole_na_se_census_%s.md", label))
  for (p in c(s1_path, s2b_path)) if (!file.exists(p)) stop("not found: ", p)

  .this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                        error = function(e) "analysis")
  .root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
  source(file.path(.root, "R", "utils_general.R")); source(file.path(.root, "R", "iteration_helpers.R"))
  s1 <- readRDS(s1_path); s2b <- readRDS(s2b_path)
  res <- pole_na_se_census(s1, s2b, pole_c)
  cells <- res$cells; res$cells <- NULL
  out <- list(meta = list(stage1 = s1_path, stage1_sha256 = .sha256_file(s1_path), stage2b = s2b_path,
                          stage2b_sha256 = .sha256_file(s2b_path), label = label, pole_c = pole_c,
                          git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1],
                                             error = function(e) NA_character_),
                          timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
              census = res)
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
  fi <- function(x) format(x, big.mark = ",", scientific = FALSE)
  kv <- function(l) if (!length(l)) "none" else paste(sprintf("%s %s", names(l), fi(unlist(l))), collapse = ", ")
  qs <- res$unassessed_sigma_quantiles
  md <- c(sprintf("# Clean-set cells the sigma-pole rule cannot assess (%s)", label), "",
          sprintf("Stage 1 `%s`, Stage 2b `%s` (rev %s, %s). Rules as shipped: edge fallback, pole fallback at c = %s.",
                  basename(s1_path), basename(s2b_path), out$meta$git_rev, out$meta$timestamp, pole_c), "",
          sprintf("- Clean set: %s cells (edge rule dropped %s, pole rule %s).", fi(res$clean_cells), fi(res$dropped_edge), fi(res$dropped_pole)),
          sprintf("- Kept without a finite sigma_se (the pole test cannot run): **%s cells**.", fi(res$unassessed_cells)),
          sprintf("- By route: %s. By edge: %s. Edge-SE status: %s. boundary_corner: %s.", kv(res$unassessed_by_route), kv(res$unassessed_by_edge),
                  kv(res$unassessed_by_se_status), fi(res$unassessed_boundary_corner)),
          if (is.null(qs)) "- Their sigma: none." else sprintf("- Their sigma: p10 %.3f, p25 %.3f, median %.3f, p75 %.3f, p90 %.3f; below 1.2: %s, below 1.5: %s, below 2: %s.",
                                                            qs$p10, qs$p25, qs$p50, qs$p75, qs$p90, fi(res$unassessed_sigma_lt$`1.2`), fi(res$unassessed_sigma_lt$`1.5`), fi(res$unassessed_sigma_lt$`2`)),
          sprintf("- With their route's median relative SE in place of the missing SE, the rule would drop %s of them (sizing only).", fi(res$would_drop_at_route_median_rel_se)),
          sprintf("- Stage-2b published rows in these cells: %s (Tier 3 %s); sigma_robust TRUE on %s (expected 0: no finite SE); gamma median of their directly estimated rows %.3f vs %.3f over all directly estimated rows.",
                  fi(res$stage2b_rows), fi(res$stage2b_rows_tier3), fi(res$stage2b_sigma_robust_true), res$stage2b_gamma_median_these, res$stage2b_gamma_median_all_estimated), "")
  writeLines(md, out_md)
  fwrite(cells, sub("\\.json$", "_cells.csv", out_json))
  cat(paste(md, collapse = "\n"), "\n")
  cat(sprintf("pole_na_se_census: wrote %s, %s and the per-cell CSV\n", out_json, out_md))
}
