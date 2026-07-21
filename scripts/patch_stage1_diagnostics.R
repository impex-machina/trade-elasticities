#!/usr/bin/env Rscript
#' scripts/patch_stage1_diagnostics.R
#'
#' G3 (v0.4.1) post-hoc diagnostics patch. Recomputes the Stage-1
#' overidentification and weak-instrument screens from columns already
#' stored in a Stage-1 LIML output RDS, WITHOUT re-running estimation.
#' Point estimates are untouched -- the G3 corrections change only the
#' diagnostic bookkeeping.
#'
#' What is recomputed exactly (from stored jstat / jstat_h / n_exporters):
#'   jstat_pval     -- Sargan p at the corrected dof (n_exporters - 3);
#'                     NA for just-identified 3-exporter cells.
#'   sargan_pass    -- jstat_pval > 0.2.
#'   jstat_h_pval_gs, sargan_pass_gs
#'                  -- G&S-protocol screen: HLIML Hausman-Newey J at
#'                     chi-square dof (total suppliers - 3) =
#'                     (n_exporters + 1) - 3, CDF < 0.8 rule.
#'
#' What is recomputed APPROXIMATELY (flagged sy_rowfix_approx = TRUE):
#'   stockyogo_pass / _cv          -- stored fstat_kp against the CV at the
#'                                    corrected row (n_exporters - 1).
#'   stockyogo_pass_gs25 / _cv_gs25 -- stored fstat_kp against the CV at
#'                                    G&S's row convention (n_exporters + 1).
#'   gs_pass_both                  -- gs25 (approx) AND sargan_pass_gs.
#' The stored fstat_kp itself was computed pre-G3 (no constant partialling,
#' divided by the raw dummy count), so these row-shifted screens are an
#' approximation; an exact refresh requires a Stage-1 re-run.
#'
#' Usage:
#'   Rscript scripts/patch_stage1_diagnostics.R --in <stage1.rds> --out <patched.rds>

suppressMessages(library(data.table))

# ---- arg parsing (no optparse dependency) --------------------------------
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  i <- which(args == flag)
  if (length(i) == 1L && i < length(args)) args[i + 1L] else NA_character_
}
in_path  <- get_arg("--in")
out_path <- get_arg("--out")
if (is.na(in_path) || is.na(out_path))
  stop("Usage: Rscript scripts/patch_stage1_diagnostics.R --in <stage1.rds> --out <patched.rds>")
if (!file.exists(in_path)) stop("Input not found: ", in_path)

# Stock-Yogo table lives in the estimator module.
script_dir <- {
  fa <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(fa)) dirname(normalizePath(sub("^--file=", "", fa))) else "."
}
source(file.path(script_dir, "..", "R", "hs_codes.R"))
source(file.path(script_dir, "..", "R", "liml_estimator.R"))

dt <- setDT(readRDS(in_path))
need <- c("jstat", "jstat_h", "n_exporters", "fstat_kp")
miss <- setdiff(need, names(dt))
if (length(miss))
  stop("Input lacks required columns (schema too old?): ", paste(miss, collapse = ", "))

old_sargan <- dt$sargan_pass
old_gsboth <- if ("gs_pass_both" %in% names(dt)) dt$gs_pass_both else rep(NA, nrow(dt))
old_sy     <- if ("stockyogo_pass" %in% names(dt)) dt$stockyogo_pass else rep(NA, nrow(dt))

sy_cv <- function(rows, threshold) {
  vapply(rows, function(r) {
    if (is.na(r)) return(NA_real_)
    s <- stockyogo_pass(NA_real_, n_excluded_instruments = r,
                        size_threshold = threshold)
    if (is.null(s) || length(s) == 1L && is.na(s)) NA_real_ else s$cv
  }, numeric(1))
}

# ---- exact recomputations ------------------------------------------------
dt[, `:=`(
  jstat_pval = fifelse(n_exporters - 3L > 0L & is.finite(jstat),
                       1 - pchisq(jstat, df = pmax(n_exporters - 3L, 1L)),
                       NA_real_)
)]
dt[, sargan_pass := fifelse(is.na(jstat_pval), NA, jstat_pval > 0.2)]
dt[, jstat_h_pval_gs := fifelse((n_exporters + 1L) - 3L > 0L & is.finite(jstat_h),
                                1 - pchisq(jstat_h, df = pmax(n_exporters - 2L, 1L)),
                                NA_real_)]
dt[, sargan_pass_gs := fifelse(is.na(jstat_h_pval_gs), NA, jstat_h_pval_gs > 0.2)]

# ---- approximate row-shifted SY screens ----------------------------------
dt[, stockyogo_cv      := sy_cv(n_exporters - 1L, 0.10)]
dt[, stockyogo_pass    := fifelse(is.finite(fstat_kp) & is.finite(stockyogo_cv),
                                  fstat_kp > stockyogo_cv, NA)]
dt[, stockyogo_cv_gs25   := sy_cv(n_exporters + 1L, 0.25)]
dt[, stockyogo_pass_gs25 := fifelse(is.finite(fstat_kp) & is.finite(stockyogo_cv_gs25),
                                    fstat_kp > stockyogo_cv_gs25, NA)]
dt[, gs_pass_both := fifelse(is.na(stockyogo_pass_gs25) | is.na(sargan_pass_gs), NA,
                             stockyogo_pass_gs25 & sargan_pass_gs)]
dt[, sy_rowfix_approx := TRUE]

saveRDS(dt, out_path)

rate <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
cat(sprintf("patch_stage1_diagnostics: %s rows -> %s\n",
            format(nrow(dt), big.mark = ","), out_path))
cat(sprintf("  sargan_pass:    %.1f%% -> %.1f%%  (NA share %.1f%% -> %.1f%%)\n",
            100 * rate(old_sargan), 100 * rate(dt$sargan_pass),
            100 * mean(is.na(old_sargan)), 100 * mean(is.na(dt$sargan_pass))))
cat(sprintf("  stockyogo_pass: %.1f%% -> %.1f%%  [row-shift approx]\n",
            100 * rate(old_sy), 100 * rate(dt$stockyogo_pass)))
cat(sprintf("  gs_pass_both:   %.1f%% -> %.1f%%  [now G&S-protocol pair]\n",
            100 * rate(old_gsboth), 100 * rate(dt$gs_pass_both)))
cat("  NOTE: fstat_kp itself is the pre-G3 statistic; SY screens here are\n")
cat("  row-shift approximations. Re-run Stage 1 for exact F diagnostics.\n")
