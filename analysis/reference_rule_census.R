#!/usr/bin/env Rscript
# ============================================================================
# analysis/reference_rule_census.R  (patch 0132)
#
# The real-data test of --stage1-reference-rule stable (R/liml_estimator.R,
# prepare_cell_moments()). The 2% product subsample's Stage 1 is estimated on
# 1995-2009 and on 2010-2024 under each rule (the "levels" windows are patch
# 0119's M3 runs; the "stable" windows are new runs with the same sample and
# year windows). A reference that carries fewer unit-value jumps should make
# a cell's sigma less noisy, so the two periods' estimates should agree more.
# On the cells estimated in both periods under both rules (same cells for the
# two rules):
#   sigma: the median |ln(sigma_early - 1) - ln(sigma_late - 1)| and the
#     Spearman correlation between the periods, per rule;
#   priors: the product-level prior Stage 2a starts from (the median ln omega
#     of the clean cells, as scripts/run_estimation.R builds it), Spearman
#     across products between the periods, per rule.
# Real-data only: the synthetic worlds carry no unit-value measurement error,
# so both rules pick the same reference there.
#
# Reading (fixed in patch 0132, before the numbers): "stable helps" if the
# stable rule's cross-period median |difference| in ln(sigma - 1) is at least
# 5% below the levels rule's AND its product-prior Spearman is no more than
# 0.05 below the levels rule's; otherwise "closed".
#
# Usage (repo root; seconds):
#   Rscript analysis/reference_rule_census.R --levels-early A --levels-late B
#       --stable-early C --stable-late D
#       [--json results/reference_rule_census.json] [--md docs/results/reference_rule_census.md]
#   (each a Stage-1 table, *_feenstra_sigma.rds)
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.rr_s1 <- function(x) {
  x <- data.table::copy(data.table::as.data.table(x))
  for (k in c("importer", "good")) data.table::set(x, j = k, value = as.character(x[[k]]))
  if (!"convergence" %in% names(x)) x[, convergence := fifelse(status == "ok", 0L, -99L)]
  x
}

#' A Stage-1 table's estimated cells (converged, sigma > 1, not on the box edge).
rr_estimated <- function(s1) {
  s1 <- .rr_s1(s1)
  edge <- if ("sigma_capped" %in% names(s1)) s1$sigma_capped %in% TRUE else rep(FALSE, nrow(s1))
  s1[convergence == 0L & is.finite(sigma) & sigma > 1 & !edge, .(importer, good, z = log(sigma - 1))]
}

#' The product-level Stage-2a prior, as scripts/run_estimation.R builds it.
rr_priors <- function(s1) {
  s1 <- .rr_s1(s1)
  cl <- stage2_sigma_clean(s1)$clean
  for (k in c("adjust", "omega_floored", "omega_capped", "sigma_capped")) if (!k %in% names(cl)) cl[, (k) := if (k == "adjust") 0L else FALSE]
  g <- cl[!is.na(gamma) & gamma > 0 & adjust != 5L & !(omega_floored %in% TRUE) & !(omega_capped %in% TRUE) & !(sigma_capped %in% TRUE)]
  g[, .(ln_prior = stats::median(log(gamma), na.rm = TRUE)), by = good]
}

reference_rule_census <- function(le, ll, se, sl) {
  e <- list(levels = list(early = rr_estimated(le), late = rr_estimated(ll)), stable = list(early = rr_estimated(se), late = rr_estimated(sl)))
  key <- function(d) paste(d$importer, d$good)
  common <- Reduce(intersect, list(key(e$levels$early), key(e$levels$late), key(e$stable$early), key(e$stable$late)))
  per_rule <- lapply(c("levels", "stable"), function(r) {
    a <- e[[r]]$early[match(common, key(e[[r]]$early))]; b <- e[[r]]$late[match(common, key(e[[r]]$late))]
    pe <- rr_priors(if (r == "levels") le else se); pl <- rr_priors(if (r == "levels") ll else sl)
    pm <- merge(pe, pl, by = "good", suffixes = c("_e", "_l"))
    list(rule = r, cells = length(common), sigma_mad = stats::median(abs(a$z - b$z)),
         sigma_spearman = suppressWarnings(stats::cor(a$z, b$z, method = "spearman")),
         products = nrow(pm), prior_spearman = if (nrow(pm) >= 4L) suppressWarnings(stats::cor(pm$ln_prior_e, pm$ln_prior_l, method = "spearman")) else NA_real_)
  })
  names(per_rule) <- c("levels", "stable")
  L <- per_rule$levels; S <- per_rule$stable
  helps <- is.finite(S$sigma_mad) && is.finite(L$sigma_mad) && S$sigma_mad <= 0.95 * L$sigma_mad &&
    is.finite(S$prior_spearman) && is.finite(L$prior_spearman) && S$prior_spearman >= L$prior_spearman - 0.05
  list(per_rule = per_rule, reading = if (helps) "stable helps" else "closed")
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  for (f in c("R/utils_general.R", "R/iteration_helpers.R")) source(f)
  p <- c(le = get_arg("--levels-early", NA), ll = get_arg("--levels-late", NA), se = get_arg("--stable-early", NA), sl = get_arg("--stable-late", NA))
  if (anyNA(p) || !all(file.exists(p))) stop("usage: Rscript analysis/reference_rule_census.R --levels-early A --levels-late B --stable-early C --stable-late D [--json F] [--md F]")
  json <- get_arg("--json", "results/reference_rule_census.json"); md <- get_arg("--md", "docs/results/reference_rule_census.md")
  res <- reference_rule_census(readRDS(p[["le"]]), readRDS(p[["ll"]]), readRDS(p[["se"]]), readRDS(p[["sl"]]))
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  res$meta <- c(as.list(p), git_rev = rev, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  jsonlite::write_json(res, json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f3 <- function(x) formatC(x, digits = 3, format = "f")
  row <- function(z) sprintf("| %s | %s | %s | %s | %d |", z$rule, f3(z$sigma_mad), f3(z$sigma_spearman), f3(z$prior_spearman), z$products)
  L <- res$per_rule$levels; S <- res$per_rule$stable
  writeLines(enc2utf8(c("# Stage-1 reference rule: levels against stable, on the period split (patch 0132)", "",
    sprintf("2%% product subsample; Stage 1 on 1995-2009 and 2010-2024 under each rule; %d cells estimated in both periods under both rules; rev %s, %s.",
            L$cells, rev, res$meta$timestamp), "",
    "| rule | sigma: median abs. difference in ln(sigma - 1) between periods | sigma: Spearman between periods | product prior: Spearman between periods | products |",
    "|---|---|---|---|---|", row(L), row(S), "",
    sprintf("**Reading (fixed in patch 0132): %s.** Stable helps if its median difference is at least 5%% below the levels rule's and its product-prior correlation is no more than 0.05 lower.",
            res$reading))), md, useBytes = TRUE)
  cat(sprintf("reference rule census: %s (sigma median |diff| levels %.3f, stable %.3f; prior Spearman %.3f / %.3f)\n",
              res$reading, L$sigma_mad, S$sigma_mad, L$prior_spearman, S$prior_spearman))
}
