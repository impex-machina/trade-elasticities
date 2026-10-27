#!/usr/bin/env Rscript
# ============================================================================
# scripts/rebuild_stage2b_summary.R  (patch 0147)
#
# Rebuilds the Stage-2b summary (<prefix>_summary.rds / _summary.txt, the two
# summary files the hub ships) from the shipped Stage-2b table, with the
# patch-0147 summary: Table 2, the within-pair statistics and the variance
# decomposition over the directly estimated rows. Through patch 0146 they
# included the Tier-3 rows, which carry the good-level prior (one value per
# good) and hold no exporter information, while the text compared them with
# Soderbery's estimates. The direction of the distortion depends on where the
# prior sits; the compare mode measures it on the shipped table.
#
# Nothing is re-estimated. The run metadata (timing, quality log, trim
# bounds) and the provenance are taken from the shipped summary RDS, which
# carries them as its sidecar, so a rebuilt file differs from the shipped one
# only where patch 0147 changed what is computed.
#
# Usage (repo root):
#   Rscript scripts/rebuild_stage2b_summary.R [--table PATH] [--summary PATH] [--write PREFIX]
#     --table PATH     the Stage-2b table; default: the manifest's
#                      data/derived/stage2b/..._fixed_sigma.rds, sha256-checked
#     --summary PATH   the summary RDS shipped with it; default: the manifest's
#                      data/derived/stage2b/..._summary.rds, sha256-checked
#     --write PREFIX   also write PREFIX_summary.rds and PREFIX_summary.txt
#                      (default: compare only; nothing is written)
# Exit status: 0 done; 1 an input is missing, differs from the manifest, or a
# section that patch 0147 does not touch came out different.
# ============================================================================

suppressPackageStartupMessages(library(data.table))
for (f in c("utils_general.R", "iteration_helpers.R", "output_paths.R", "summary.R")) source(file.path("R", f))

# --- rebuild helpers (patch 0147) --------------------------------------------
parse_rebuild_args <- function(args) {
  opt <- list(table = NULL, summary = NULL, write = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (!a %in% c("--table", "--summary", "--write")) stop("unknown argument: ", a, call. = FALSE)
    if (i == length(args) || startsWith(args[i + 1L], "--")) stop(a, " needs a value", call. = FALSE)
    opt[[sub("^--", "", a)]] <- args[i + 1L]
    i <- i + 2L
  }
  opt
}

# the config fields build_summary() reads, from the shipped summary's provenance
cfg_from_provenance <- function(pv) {
  if (is.null(pv)) stop("the summary RDS carries no provenance block", call. = FALSE)
  list(filepath = pv$filepath, agg_level = pv$agg_level, minyear = pv$minyear, maxyear = pv$maxyear,
       min_exporters = pv$min_exporters, min_destinations = pv$min_destinations, min_periods = pv$min_periods,
       uv_outlier_threshold = pv$uv_outlier_thresh, tail_trim_pct = pv$tail_trim_pct,
       sigma_V_default = pv$sigma_V_default, gamma_V_default = pv$gamma_V_default,
       sigma_start = pv$sigma_start, gamma_start = pv$gamma_start,
       use_regions = identical(pv$scope, "regional"))
}

# the sections patch 0147 does not change must come out identical
untouched_sections_differ <- function(old, new) {
  keys <- c("provenance", "performance", "quality", "failures")
  g_old <- old$global; g_new <- new$global
  g_new <- g_new[setdiff(names(g_new), c("n_estimated", "n_imputed", "gamma_median_estimated"))]
  bad <- keys[!vapply(keys, function(k) isTRUE(all.equal(old[[k]], new[[k]], check.attributes = FALSE)), TRUE)]
  if (!isTRUE(all.equal(g_old[names(g_new)], g_new, check.attributes = FALSE))) bad <- c(bad, "global")
  bad
}

# old vs new for every number patch 0147 moves
compare_lines <- function(old, new) {
  f <- function(x) if (is.null(x) || length(x) == 0L || is.na(x)) "-" else if (abs(x - round(x)) < 1e-9 && abs(x) >= 1) format(round(x), big.mark = ",") else sprintf("%.4f", x)
  w_old <- old$table2[importer == "World"]; w_new <- new$table2[importer == "World"]
  rows <- list(
    c("published rows (unchanged)", f(old$global$n_estimates), f(new$global$n_estimates)),
    c("  of which directly estimated", "-", f(new$global$n_estimated)),
    c("  of which Tier 3 at the prior", "-", f(new$global$n_imputed)),
    c("gamma median, directly estimated rows", "-", f(new$global$gamma_median_estimated)),
    c("Table 2 World: obs", f(w_old$obs), f(w_new$obs)),
    c("Table 2 World: gamma median", f(w_old$gamma_median), f(w_new$gamma_median)),
    c("Table 2 World: gamma MAD", f(w_old$gamma_mad), f(w_new$gamma_mad)),
    c("within-pair: pairs with 2+ exporters", f(old$within_het$n_pairs), f(new$within_het$n_pairs)),
    c("within-pair: median gamma", f(old$within_het$median_of_within_med), f(new$within_het$median_of_within_med)),
    c("within-pair: median SD (Soderbery 0.625)", f(old$within_het$median_of_within_sd), f(new$within_het$median_of_within_sd)),
    c("within-pair: median MAD (Soderbery 0.125)", f(old$within_het$median_of_within_mad), f(new$within_het$median_of_within_mad)),
    c("variance decomposition: R2 (Soderbery 0.72)", f(old$var_decomp$r_squared), f(new$var_decomp$r_squared)),
    c("variance decomposition: observations", f(old$var_decomp$n_obs), f(new$var_decomp$n_obs)))
  vapply(rows, function(r) sprintf("  %-46s %14s %14s", r[1], r[2], r[3]), "")
}
# --- end rebuild helpers (patch 0147) ----------------------------------------

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opt <- parse_rebuild_args(args)
  defaults <- is.null(opt$table) || is.null(opt$summary)
  if (defaults) {
    if (!file.exists("data/manifest.csv")) stop("run from the repository root (data/manifest.csv not found)", call. = FALSE)
    man <- utils::read.csv("data/manifest.csv", stringsAsFactors = FALSE)
    pick <- function(pat) { i <- grep(pat, man$local_path); if (length(i) != 1L) stop("manifest: expected one ", pat, call. = FALSE); man[i, ] }
    t_row <- pick("^data/derived/stage2b/.*_fixed_sigma\\.rds$"); s_row <- pick("^data/derived/stage2b/.*_summary\\.rds$")
    if (is.null(opt$table))   opt$table   <- t_row$local_path
    if (is.null(opt$summary)) opt$summary <- s_row$local_path
    for (r in list(t_row, s_row)) {
      if (!file.exists(r$local_path)) { cat("MISSING:", r$local_path, "-- fetch with Rscript scripts/download_outputs.R\n"); quit(status = 1L) }
      # (patch 0148) unclass(): openssl's hash string keeps class c("hash", "sha256"),
      # and identical() against the manifest's plain string was FALSE on every file
      con <- file(r$local_path, "rb"); h <- tolower(unclass(as.character(openssl::sha256(con)))); close(con)
      if (!identical(h, tolower(r$sha256))) { cat("DIFFERS FROM THE MANIFEST:", r$local_path, "-- Rscript scripts/download_outputs.R --force\n"); quit(status = 1L) }
    }
    cat("inputs match the manifest's sha256\n")
  }
  tab <- as.data.table(readRDS(opt$table))
  old <- readRDS(opt$summary)
  cfg <- cfg_from_provenance(old$provenance)
  data.table::setattr(tab, "run_meta", old$run_meta)
  new <- build_summary(tab, cfg, step1_results = NULL, scope = old$provenance$scope)
  cat(sprintf("\nStage-2b summary: shipped (%s) against patch 0147\n\n", basename(opt$summary)))
  cat(sprintf("  %-46s %14s %14s\n", "", "shipped", "patch 0147"))
  cat(compare_lines(old, new), sep = "\n"); cat("\n")
  bad <- untouched_sections_differ(old, new)
  if (length(bad)) {
    cat("\nSECTIONS THAT SHOULD NOT MOVE DID:", paste(bad, collapse = ", "), "-- nothing written; report this\n")
    quit(status = 1L)
  }
  cat("\nprovenance, performance, quality, failures and the global block are unchanged\n")
  if (!is.null(opt$write)) {
    dir.create(dirname(opt$write), showWarnings = FALSE, recursive = TRUE)
    new$run_meta <- old$run_meta
    saveRDS(new, paste0(opt$write, "_summary.rds"))
    write_summary_text(new, paste0(opt$write, "_summary.txt"))
    cat(sprintf("wrote %s_summary.rds and %s_summary.txt\n", opt$write, opt$write))
  } else cat("compare only: nothing written (add --write PREFIX to write the rebuilt files)\n")
  invisible(new)
}

main()
