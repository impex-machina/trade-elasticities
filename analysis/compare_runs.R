#!/usr/bin/env Rscript
# ============================================================================
# compare_runs.R -- v0.2.0 vs v0.3.0 output comparison
#
# Produces a markdown report contrasting two runs of the estimation pipeline:
# the Stage 1 sigma table (*_elast_country_hs4_feenstra_sigma.rds) and the
# Stage 2b country table (*_elast_country_hs4_fixed_sigma.rds). Intended for
# docs/methodology/v020_v030_comparison.md but generic to any pair of runs.
#
# Usage:
#   Rscript analysis/compare_runs.R \
#     --old-stage1  data/derived_v020/stage1/..._feenstra_sigma.rds \
#     --new-stage1  data/derived/stage1/..._feenstra_sigma.rds \
#     --old-stage2b data/derived_v020/stage2b/..._fixed_sigma.rds \
#     --new-stage2b data/derived/stage2b/..._fixed_sigma.rds \
#     --old-label v0.2.0 --new-label v0.3.0 \
#     --out docs/methodology/v020_v030_comparison.md
#
# Stage-1 arguments are optional; if omitted the report covers Stage 2b only.
# Columns absent from either table are skipped row-wise, so the script runs
# against v0.2.0 files that predate sigma_capped / omega_capped / the
# sigma-propagation columns.
# ============================================================================

suppressMessages({
  library(data.table)
  library(optparse)
})

opt_list <- list(
  make_option("--old-stage1",  type = "character", default = NULL,
              dest = "old_stage1"),
  make_option("--new-stage1",  type = "character", default = NULL,
              dest = "new_stage1"),
  make_option("--old-stage2b", type = "character", default = NULL,
              dest = "old_stage2b"),
  make_option("--new-stage2b", type = "character", default = NULL,
              dest = "new_stage2b"),
  make_option("--old-label",   type = "character", default = "v0.2.0",
              dest = "old_label"),
  make_option("--new-label",   type = "character", default = "v0.3.0",
              dest = "new_label"),
  make_option("--out",         type = "character",
              default = "docs/methodology/run_comparison.md")
)
opts <- parse_args(OptionParser(option_list = opt_list))

if (is.null(opts$old_stage2b) || is.null(opts$new_stage2b)) {
  stop("--old-stage2b and --new-stage2b are required.", call. = FALSE)
}

# ---- helpers ---------------------------------------------------------------

read_table <- function(path) {
  if (!file.exists(path)) stop(sprintf("File not found: %s", path), call. = FALSE)
  dt <- readRDS(path)
  setDT(dt)
  dt
}

has_col <- function(dt, col) !is.null(dt) && col %in% names(dt)

med  <- function(x) if (all(is.na(x))) NA_real_ else median(x, na.rm = TRUE)
q    <- function(x, p) if (all(is.na(x))) NA_real_ else
  as.numeric(quantile(x, p, na.rm = TRUE, names = FALSE))
shr_if <- function(dt, col, ok, cond_fun) {
  if (!has_col(dt, col)) return(NA_real_)
  v <- dt[[col]][ok]
  shr(cond_fun(v), rep(TRUE, length(v)))
}

shr  <- function(cond, base) {
  b <- sum(base, na.rm = TRUE)
  if (b == 0) NA_real_ else sum(cond & base, na.rm = TRUE) / b
}

fnum <- function(x, d = 3L) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("--")
  formatC(x, digits = d, format = "f", big.mark = ",")
}
fint <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("--")
  formatC(x, format = "d", big.mark = ",")
}
fpct <- function(x, d = 1L) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("--")
  sprintf(paste0("%.", d, "f%%"), 100 * x)
}

# Change column: absolute delta for medians/quantiles, pp for shares.
chg_num <- function(old, new, d = 3L) {
  if (is.na(old) || is.na(new)) return("--")
  sprintf("%+.*f", d, new - old)
}
chg_pp <- function(old, new, d = 1L) {
  if (is.na(old) || is.na(new)) return("--")
  sprintf("%+.*f pp", d, 100 * (new - old))
}

# Accumulate markdown rows: metric | old | new | change
row_num <- function(rows, label, old, new, d = 3L) {
  c(rows, sprintf("| %s | %s | %s | %s |",
                  label, fnum(old, d), fnum(new, d), chg_num(old, new, d)))
}
row_int <- function(rows, label, old, new) {
  ch <- if (is.na(old) || is.na(new)) "--" else sprintf("%+d", as.integer(new - old))
  c(rows, sprintf("| %s | %s | %s | %s |", label, fint(old), fint(new), ch))
}
row_shr <- function(rows, label, old, new) {
  c(rows, sprintf("| %s | %s | %s | %s |",
                  label, fpct(old), fpct(new), chg_pp(old, new)))
}

table_header <- function(old_label, new_label) {
  c(sprintf("| Metric | %s | %s | Change |", old_label, new_label),
    "|---|---|---|---|")
}

# Distribution block: counts + shares of a categorical column, union of levels.
dist_block <- function(dt_old, dt_new, col, base_old, base_new,
                       old_label, new_label) {
  lv_old <- if (has_col(dt_old, col)) unique(dt_old[[col]][base_old]) else character(0)
  lv_new <- if (has_col(dt_new, col)) unique(dt_new[[col]][base_new]) else character(0)
  levels <- sort(unique(c(as.character(lv_old), as.character(lv_new))), na.last = TRUE)
  if (length(levels) == 0) return(character(0))
  rows <- table_header(old_label, new_label)
  n_old <- sum(base_old, na.rm = TRUE)
  n_new <- sum(base_new, na.rm = TRUE)
  for (lv in levels) {
    so <- if (has_col(dt_old, col) && n_old > 0)
      sum(as.character(dt_old[[col]]) == lv & base_old, na.rm = TRUE) / n_old
    else NA_real_
    sn <- if (has_col(dt_new, col) && n_new > 0)
      sum(as.character(dt_new[[col]]) == lv & base_new, na.rm = TRUE) / n_new
    else NA_real_
    rows <- row_shr(rows, sprintf("`%s = %s`", col, lv), so, sn)
  }
  rows
}

# ---- Stage 2b --------------------------------------------------------------

s2b_old <- read_table(opts$old_stage2b)
s2b_new <- read_table(opts$new_stage2b)

s2b_section <- function(o, n, ol, nl) {
  rows <- table_header(ol, nl)
  rows <- row_int(rows, "Rows (importer, exporter, HS4)", nrow(o), nrow(n))


  g_o <- o$gamma; g_n <- n$gamma
  rows <- row_num(rows, "gamma median",              med(g_o), med(g_n))
  rows <- row_num(rows, "gamma p25",                 q(g_o, .25), q(g_n, .25))
  rows <- row_num(rows, "gamma p75",                 q(g_o, .75), q(g_n, .75))
  rows <- row_num(rows, "gamma p95",                 q(g_o, .95), q(g_n, .95))
  rows <- row_num(rows, "gamma max",                 max(g_o, na.rm = TRUE),
                                                     max(g_n, na.rm = TRUE))
  rows <- row_shr(rows, "share gamma > 1",
                  shr(g_o > 1, !is.na(g_o)), shr(g_n > 1, !is.na(g_n)))
  rows <- row_num(rows, "implied export-supply elasticity, median 1/gamma",
                  med(1 / g_o[is.finite(1 / g_o)]),
                  med(1 / g_n[is.finite(1 / g_n)]))

  rows <- row_num(rows, "sigma median", med(o$sigma), med(n$sigma))
  rows <- row_shr(rows, "share sigma at cap (>= 9.999)",
                  shr(o$sigma >= 9.999, !is.na(o$sigma)),
                  shr(n$sigma >= 9.999, !is.na(n$sigma)))

  se_o <- if (has_col(o, "gamma_se")) o$gamma_se else NA_real_
  se_n <- if (has_col(n, "gamma_se")) n$gamma_se else NA_real_
  rows <- row_num(rows, "gamma_se median (finite)",
                  med(se_o[is.finite(se_o)]), med(se_n[is.finite(se_n)]))
  rows <- row_shr(rows, "share gamma_se finite",
                  shr(is.finite(se_o), rep(TRUE, nrow(o))),
                  shr(is.finite(se_n), rep(TRUE, nrow(n))))

  st_o <- if (has_col(o, "gamma_se_total")) o$gamma_se_total else NA_real_
  st_n <- if (has_col(n, "gamma_se_total")) n$gamma_se_total else NA_real_
  rows <- row_num(rows, "gamma_se_total median (finite)",
                  med(st_o[is.finite(st_o)]), med(st_n[is.finite(st_n)]))

  ss_o <- if (has_col(o, "sigma_se")) o$sigma_se else NA_real_
  ss_n <- if (has_col(n, "sigma_se")) n$sigma_se else NA_real_
  rows <- row_num(rows, "sigma_se median (finite)",
                  med(ss_o[is.finite(ss_o)]), med(ss_n[is.finite(ss_n)]))

  if (has_col(o, "sigma_robust") || has_col(n, "sigma_robust")) {
    sr_all <- function(dt) {
      if (!has_col(dt, "sigma_robust")) return(NA_real_)
      shr(dt$sigma_robust %in% TRUE, rep(TRUE, nrow(dt)))
    }
    sr_nonna <- function(dt) {
      if (!has_col(dt, "sigma_robust")) return(NA_real_)
      shr(dt$sigma_robust %in% TRUE, !is.na(dt$sigma_robust))
    }
    rows <- row_shr(rows, "sigma_robust TRUE (share of all rows)",
                    sr_all(o), sr_all(n))
    rows <- row_shr(rows, "sigma_robust TRUE (share of non-NA)",
                    sr_nonna(o), sr_nonna(n))
  }

  ot_o <- if (has_col(o, "opt_tariff")) o$opt_tariff else NA_real_
  ot_n <- if (has_col(n, "opt_tariff")) n$opt_tariff else NA_real_
  rows <- row_num(rows, "opt_tariff median (finite)",
                  med(ot_o[is.finite(ot_o)]), med(ot_n[is.finite(ot_n)]))
  rows
}

# ---- Stage 1 ---------------------------------------------------------------

s1_section <- NULL
s1_dists <- NULL
if (!is.null(opts$old_stage1) && !is.null(opts$new_stage1)) {
  s1_old <- read_table(opts$old_stage1)
  s1_new <- read_table(opts$new_stage1)

  ok_flag <- function(dt) {
    if (has_col(dt, "status")) dt$status == "ok"
    else if (has_col(dt, "convergence")) dt$convergence == 0L
    else rep(TRUE, nrow(dt))
  }
  ok_o <- ok_flag(s1_old); ok_n <- ok_flag(s1_new)

  rows <- table_header(opts$old_label, opts$new_label)
  rows <- row_int(rows, "Cells attempted", nrow(s1_old), nrow(s1_new))
  rows <- row_shr(rows, "status ok share",
                  mean(ok_o, na.rm = TRUE), mean(ok_n, na.rm = TRUE))

  sig_o <- s1_old$sigma[ok_o]; sig_n <- s1_new$sigma[ok_n]
  rows <- row_num(rows, "sigma median (ok)", med(sig_o), med(sig_n))
  rows <- row_num(rows, "sigma p25 (ok)", q(sig_o, .25), q(sig_n, .25))
  rows <- row_num(rows, "sigma p75 (ok)", q(sig_o, .75), q(sig_n, .75))
  rows <- row_shr(rows, "share sigma at cap (ok, >= 9.999)",
                  shr(sig_o >= 9.999, !is.na(sig_o)),
                  shr(sig_n >= 9.999, !is.na(sig_n)))

  for (cc in c("sigma_se", "omega_se", "rho_se")) {
    v_o <- if (has_col(s1_old, cc)) s1_old[[cc]][ok_o] else NA_real_
    v_n <- if (has_col(s1_new, cc)) s1_new[[cc]][ok_n] else NA_real_
    rows <- row_num(rows, sprintf("%s median (ok, finite)", cc),
                    med(v_o[is.finite(v_o)]), med(v_n[is.finite(v_n)]))
    rows <- row_shr(rows, sprintf("share %s finite (ok)", cc),
                    shr(is.finite(v_o), rep(TRUE, length(v_o))),
                    shr(is.finite(v_n), rep(TRUE, length(v_n))))
  }

  om_o <- s1_old$omega[ok_o]; om_n <- s1_new$omega[ok_n]
  rows <- row_num(rows, "omega median (ok)", med(om_o), med(om_n))
  if (has_col(s1_old, "omega_floored") || has_col(s1_new, "omega_floored")) {
    rows <- row_shr(rows, "omega_floored share (ok)",
                    shr_if(s1_old, "omega_floored", ok_o, function(v) v %in% TRUE),
                    shr_if(s1_new, "omega_floored", ok_n, function(v) v %in% TRUE))
  }
  for (cc in c("sigma_capped", "omega_capped")) {
    if (has_col(s1_old, cc) || has_col(s1_new, cc)) {
      rows <- row_shr(rows, sprintf("%s share (ok)", cc),
                      shr_if(s1_old, cc, ok_o, function(v) v %in% TRUE),
                      shr_if(s1_new, cc, ok_n, function(v) v %in% TRUE))
    }
  }

  fk_o <- if (has_col(s1_old, "fstat_kp")) s1_old$fstat_kp[ok_o] else NA_real_
  fk_n <- if (has_col(s1_new, "fstat_kp")) s1_new$fstat_kp[ok_n] else NA_real_
  rows <- row_num(rows, "fstat_kp median (ok)",
                  med(fk_o[is.finite(fk_o)]), med(fk_n[is.finite(fk_n)]), d = 2L)
  if (has_col(s1_old, "stockyogo_pass") || has_col(s1_new, "stockyogo_pass")) {
    sy_share <- function(dt, ok) {
      if (!has_col(dt, "stockyogo_pass")) return(NA_real_)
      v <- dt$stockyogo_pass[ok]
      shr(v %in% TRUE, !is.na(v))
    }
    rows <- row_shr(rows, "stockyogo_pass share (ok, non-NA)",
                    sy_share(s1_old, ok_o), sy_share(s1_new, ok_n))
  }
  s1_section <- rows

  s1_dists <- c(
    "### Stage 1 `adjust` composition (ok cells)", "",
    dist_block(s1_old, s1_new, "adjust", ok_o, ok_n,
               opts$old_label, opts$new_label), "",
    "### Stage 1 `final_source` composition (ok cells)", "",
    dist_block(s1_old, s1_new, "final_source", ok_o, ok_n,
               opts$old_label, opts$new_label)
  )
}

# ---- Stage 2b distributions ------------------------------------------------

all_o <- rep(TRUE, nrow(s2b_old)); all_n <- rep(TRUE, nrow(s2b_new))
s2b_dists <- c(
  "### Stage 2b `tier` composition", "",
  dist_block(s2b_old, s2b_new, "tier", all_o, all_n,
             opts$old_label, opts$new_label), "",
  "### Stage 2b `gamma_se_status` composition", "",
  dist_block(s2b_old, s2b_new, "gamma_se_status", all_o, all_n,
             opts$old_label, opts$new_label)
)

# ---- Assemble --------------------------------------------------------------

out <- c(
  sprintf("# Run comparison: %s vs %s", opts$old_label, opts$new_label),
  "",
  sprintf("Generated by `analysis/compare_runs.R` on %s.", Sys.Date()),
  "",
  sprintf("- %s Stage 2b: `%s`", opts$old_label, opts$old_stage2b),
  sprintf("- %s Stage 2b: `%s`", opts$new_label, opts$new_stage2b),
  if (!is.null(s1_section)) c(
    sprintf("- %s Stage 1: `%s`", opts$old_label, opts$old_stage1),
    sprintf("- %s Stage 1: `%s`", opts$new_label, opts$new_stage1)
  ) else NULL,
  "",
  if (!is.null(s1_section)) c("## Stage 1 (sigma)", "", s1_section, "",
                              s1_dists, "") else NULL,
  "## Stage 2b (country-level gamma)", "",
  s2b_section(s2b_old, s2b_new, opts$old_label, opts$new_label),
  "",
  s2b_dists,
  ""
)

dir.create(dirname(opts$out), recursive = TRUE, showWarnings = FALSE)
writeLines(out, opts$out)
cat(sprintf("compare_runs.R: wrote %s (%d lines)\n", opts$out, length(out)))
