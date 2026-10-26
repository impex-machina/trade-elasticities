#!/usr/bin/env Rscript
# scripts/build_readme.R
#
# Generate README.md from README.template.md and the JSON files in results/.
# Run from the repo root.
#
# The drift lock has two layers (post-v0.4.1 audit -- before then, this
# header claimed CI enforcement that did not exist; only the opt-in local
# hook did):
#   1. CI (.github/workflows/test.yml, "Verify README.md matches its build
#      inputs"): rebuilds to a temp file and fails the workflow on any
#      difference from the committed README.md. This is the enforced gate.
#   2. The optional local pre-commit hook (scripts/hooks/pre-commit;
#      install with `git config core.hooksPath scripts/hooks`), which runs
#      the same check at commit time and soft-skips if Rscript is absent.
# See docs/methodology/build_readme.md (forthcoming) for the full
# architecture.
#
# Inputs
#   results/stage1_summary.json     (emitted by analysis/00_setup.R)
#   results/stage2b_summary.json    (emitted by analysis/00_setup.R)
#   README.template.md              (this directory's sibling at repo root)
#
# Output
#   README.md                       (overwritten; override with the
#                                    README_BUILD_OUTPUT env var, e.g. to
#                                    build to a temp file for diff-checking
#                                    without touching the committed README)
#
# Exit codes
#   0  success
#   1  template referenced a field not in any results/*.json
#   2  rendered output still contains "{{" or "}}" (placeholder leak)
#   3  template or results/ files missing
#
# Encoding: every read and write is explicit UTF-8. The README contains
# Greek letters (sigma, gamma) and an em-dash; on Windows, R's default
# encoding is the system code page (commonly cp1252), which would corrupt
# them silently. Explicit UTF-8 makes the round-trip robust across
# Windows local dev and Linux CI.

suppressPackageStartupMessages({
  library(jsonlite)
  library(glue)
})

# --- I/O setup -------------------------------------------------------------

TEMPLATE_PATH <- "README.template.md"
# Output path defaults to README.md but can be redirected via the
# README_BUILD_OUTPUT env var. The pre-commit hook (scripts/hooks/pre-commit)
# sets this to a temp file so it can diff the regenerated README against the
# committed one without modifying the working tree.
OUTPUT_PATH   <- Sys.getenv("README_BUILD_OUTPUT", unset = "README.md")
RESULTS_DIR   <- "results"

if (!file.exists(TEMPLATE_PATH)) {
  message(sprintf("FATAL: template not found at %s (run from repo root)", TEMPLATE_PATH))
  quit(status = 3L)
}
if (!dir.exists(RESULTS_DIR)) {
  message(sprintf("FATAL: results/ not found (run analysis/00_setup.R first)"))
  quit(status = 3L)
}

# --- Load every results/*.json into a single nested list `r` ---------------
# r$stage1, r$stage2b, etc. The naming convention strips "_summary.json" so
# the template references {{r$stage1$n_cells}}, not {{r$stage1_summary$n_cells}}.
# Future emits (pillar2_synthetic.json, pillar3_se_calib.json) get picked
# up automatically without touching this script.

json_files <- list.files(RESULTS_DIR, pattern = "\\.json$", full.names = TRUE)
if (length(json_files) == 0L) {
  message("FATAL: no JSON files in results/")
  quit(status = 3L)
}

r <- list()
for (path in json_files) {
  key <- sub("_summary$", "", tools::file_path_sans_ext(basename(path)))
  r[[key]] <- fromJSON(path, simplifyVector = FALSE)
}
message(sprintf("build_readme.R: loaded %d JSON file(s) into r$%s",
                length(r), paste(names(r), collapse = ", r$")))

# --- Manifest file count ---------------------------------------------------
# The repo-structure tree quotes how many published files the manifest
# lists. Derive it from data/manifest.csv rather than hardcoding: a
# hardcoded count in the template is exactly the drift class this
# architecture exists to kill. (Pre-audit, the template said "12" while
# the manifest held 11 rows; the hub's twelfth object is the unmanifested
# zero-byte data/derived/.gitkeep, a git empty-dir placeholder.)

MANIFEST_PATH <- "data/manifest.csv"
if (!file.exists(MANIFEST_PATH)) {
  message(sprintf("FATAL: manifest not found at %s (run from repo root)",
                  MANIFEST_PATH))
  quit(status = 3L)
}
manifest_n_files <- nrow(utils::read.csv(MANIFEST_PATH,
                                         stringsAsFactors = FALSE))

# --- Required-key wrapper: loud failure on NULL/NA -------------------------
# Templates access fields via req() to get an informative error if a key is
# missing or NA. Bare `r$stage1$nonexistent` silently returns NULL and would
# stringify to "" -- which is exactly the drift the architecture is meant to
# kill. Wrapping every access is verbose but is the safety property the
# brief requires.
#
# Usage in template:  {{req(r$stage1, "n_cells")}}
#                     {{req(r$stage1$provenance_rates$interior_full_universe, "numerator")}}

req <- function(obj, key) {
  if (is.null(obj)) {
    stop(sprintf("req(): parent object is NULL; cannot fetch '%s'", key),
         call. = FALSE)
  }
  val <- obj[[key]]
  if (is.null(val)) {
    # Build a path hint by walking the call stack for context
    stop(sprintf("README needs '%s', not found in results/*.json", key),
         call. = FALSE)
  }
  if (length(val) == 1L && is.na(val)) {
    stop(sprintf("README needs '%s', present but NA in results/*.json", key),
         call. = FALSE)
  }
  val
}

# --- Display formatters ----------------------------------------------------
# Formatting lives here, not in the template. Display precision is a one-
# line code change; template doesn't need to know about big.mark or sprintf.

# Integer with thousands separator: 8128124 -> "8,128,124"
format_int <- function(x) formatC(as.integer(x), big.mark = ",", format = "d")

# Percentage to 1 decimal: 0.4067 -> "40.7%"
format_pct <- function(num, den) sprintf("%.1f%%", 100 * num / den)

# Proportion-to-percentage: 0.375 -> "37.5%". Distinct from format_pct,
# which takes numerator+denominator (and is right when CI should detect
# drift in either part). Use format_prop_pct when the JSON already stores
# a proportion as a single scalar (e.g. pillar2_summary success rates).
format_prop_pct <- function(p) sprintf("%.1f%%", 100 * p)

# Generic numeric to N significant figures (default 3): 2.875208 -> "2.875"
format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")

# --- Freshness helpers (patch 0109) ------------------------------------------
# A census describes the shipped table only if it was computed ON the shipped
# table. From patch 0109 the census scripts record the sha256 of the Stage-2b
# table they read (meta$stage2b_sha256); data/manifest.csv holds the shipped
# table's. pick_census() looks at the release-tagged files of a census
# (results/<prefix>_v<digits>.json, e.g. _v090 = v0.9.0, _v0101 = v0.10.1, plus
# an untagged file with a declared vintage), returns the one computed on the
# shipped table if there is one and otherwise the newest, and stale_note() then
# says in the README which table the numbers come from. Through patch 0108 the
# template named one census by release (`_v090`) and kept quoting it as the
# shipped table's after v0.10.0 changed every gamma; a stale census now reads
# as dated rather than as current.
.nz <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
MANIFEST <- utils::read.csv(MANIFEST_PATH, stringsAsFactors = FALSE)
shipped_sha256 <- function(table = "stage2b") {
  pat <- switch(table,
                stage2b = "^data/derived/stage2b/.*_fixed_sigma\\.rds$",
                stage2a = "^data/derived/stage2a/.*_fixed_sigma\\.rds$",
                stage1  = "^data/derived/stage1/.*_feenstra_sigma\\.rds$",
                stop("shipped_sha256(): unknown table ", table, call. = FALSE))
  v <- MANIFEST$sha256[grepl(pat, MANIFEST$local_path)]
  if (length(v) != 1L) stop(sprintf("shipped_sha256(): expected one manifest row for %s, found %d", table, length(v)), call. = FALSE)
  tolower(v)
}
release_of_suffix <- function(s) {          # "v090" -> "v0.9.0", "v0101" -> "v0.10.1"
  d <- sub("^v", "", s)
  if (nchar(d) == 3L) return(sprintf("v%s.%s.%s", substr(d, 1, 1), substr(d, 2, 2), substr(d, 3, 3)))
  if (nchar(d) == 4L) return(sprintf("v%s.%s.%s", substr(d, 1, 1), substr(d, 2, 3), substr(d, 4, 4)))
  s
}
pick_census <- function(prefix, legacy = character(0), table = "stage2b", res = r) {
  keys <- grep(sprintf("^%s_v[0-9]{3,4}$", prefix), names(res), value = TRUE)
  cand <- c(stats::setNames(vapply(sub(paste0("^", prefix, "_"), "", keys), release_of_suffix, ""), keys), legacy)
  cand <- cand[names(cand) %in% names(res) & !duplicated(names(cand))]
  if (!length(cand)) stop(sprintf("README needs a %s census in results/", prefix), call. = FALSE)
  ver <- function(v) sum(as.numeric(strsplit(sub("^v", "", v), ".", fixed = TRUE)[[1]]) * c(1e6, 1e3, 1))
  cand <- cand[order(-vapply(cand, ver, 0))]
  sha <- shipped_sha256(table)
  fresh <- vapply(names(cand), function(k) identical(tolower(.nz(res[[k]]$meta[[paste0(table, "_sha256")]], "")), sha), TRUE)
  k <- if (any(fresh)) names(cand)[which(fresh)[1L]] else names(cand)[1L]
  list(data = res[[k]], key = k, vintage = cand[[k]], fresh = any(fresh))
}
stale_note <- function(p, open = " (", close = ")") {
  if (isTRUE(p$fresh)) return("")
  sprintf("%scensus of the %s table, not yet re-run on the shipped table%s", open, p$vintage, close)
}
spearman_brown <- function(r1) 2 * r1 / (1 + r1)
# Pillar 2's sigma cap. Captures through patch 0108 carry no cap field: they ran
# estimate_cell_liml()'s library default (10). The shipped cap comes from
# stage1_summary.json (00_setup.R emits it from patch 0109; 50 since v0.9.0).
pillar2_cap_note <- function(p2, s1) {
  cap <- .nz(p2[["sigma_cap"]], 10)
  shipped <- .nz(s1[["sigma_cap"]], 50)
  if (isTRUE(all.equal(as.numeric(cap), as.numeric(shipped)))) return("")
  sprintf(" (captured at a \u03c3 cap of %s, the estimator's library default, while the shipped Stage 1 uses %s)",
          format(cap), format(shipped))
}
# (patch 0112) The shipped Stage-2 SEs are the sandwich form (v0.7.4+), whose
# shrink weight is the half-curvature share: data share = 1 - gamma_shrink_wt.
# A census run with --shrink-wt-def legacy reports 2(1-s)/(2-s) instead -- the
# first v0.10.2 README quoted one (corrected in b98134f) -- so the build refuses it.
shrink_census_ok <- function(p) identical(p$data$meta$shrink_wt_def, "half")
# (patch 0113) whether Pillar 3 concentrated the import-side constant out as the
# shipped estimator does (captures from patch 0113 record it; earlier ones did not).
pillar3_constant_clause <- function(p3) {
  if (isTRUE(p3[["import_constant"]])) return("with the import-side constant concentrated out as the shipped estimator does")
  "that does not include the import-side constant concentrated out since v0.8.0"
}
# (patch 0116) a census pick that may legitimately be absent: NULL when no
# release-tagged file exists yet, so a template clause reading it renders
# empty and the README lock holds until the census is committed.
pick_census_opt <- function(prefix, table = "stage2b", res = r) {
  if (!length(grep(sprintf("^%s_v[0-9]{3,4}$", prefix), names(res)))) return(NULL)
  pick_census(prefix, table = table, res = res)
}
# --- end freshness helpers (patch 0109) --------------------------------------

# --- patch 0116 phrases (fresh-eyes audit #7) ---------------------------------
# A1: the provenance bullet. Through patch 0115 it read "the rest fall to the
# Step 2 fallback", written before boundary routing (v0.6.0): 71% of the
# universe outside the interior is Step 2 (16%), boundary optima (20%) and
# cells with no estimate (35%).
provenance_lead <- function(s1) {
  rs <- req(s1, "routing_summary"); n <- req(s1, "n_cells")
  sprintf("On the full universe, %s of\n  (importer, HS4) cells are identified at the HLIML interior and %s (%s cells) by the\n  Step 2 (Fuller LIML) fallback, of which %s of the full universe (%s cells)\n  are clamped at the \u03c3/\u03c9 caps and report the cap, not an estimate",
          format_pct(req(rs, "hliml_interior"), n), format_pct(req(rs, "step2_total"), n), format_int(req(rs, "step2_total")),
          format_pct(req(rs, "clamped_total"), n), format_int(req(rs, "clamped_total")))
}
provenance_tail <- function(s1) {
  rs <- req(s1, "routing_summary"); n <- req(s1, "n_cells")
  sprintf("; the remaining %s (%s cells) return no estimate (thin or short panels, too few exporters, a singular first step, or no admissible point on any route)",
          format_pct(req(rs, "pre_discard"), n), format_int(req(rs, "pre_discard")))
}
# A8: the headline sigma. On a table where the fallback sigma covers the row
# median, the "median" is the fallback itself; say so.
headline_sigma_note <- function(s2b) {
  sp <- s2b[["sigma_provenance"]]
  if (is.null(sp) || is.null(sp[["fallback_value"]]) || !isTRUE(abs(req(s2b, "sigma_median") - sp[["fallback_value"]]) < 1e-9)) return("")
  sprintf(" \u2014 the fallback \u03c3 itself: %s of rows carry it, so the row-level median falls on that mass. The fallback is the median of the cell-specific estimates (one per importer \u00d7 HS4 cell in the clean set); filter `sigma_source == \"estimated\"` for the estimates' own distribution",
          format_pct(req(sp, "n_fallback"), req(sp, "denominator")))
}
# A7: the optimizer's own non-convergence, from analysis/stage2b_convergence_census.R
# (empty until a census is committed). (patch 0118) The Nelder-Mead restart runs
# for EVERY cell whose L-BFGS-B fit did not converge, not only at the iteration
# cap: on the v0.11.0 table 93% of the non-converged rows carry code 52 (a failed
# line search) and 7% code 1 (the cap). The 0116 wording said "at the iteration
# cap"; the split is now read from the census. (patch 0121) A published code 1
# is the cap of whichever optimizer's point was published: L-BFGS-B reached its
# cap on 7 cells of the v0.11.0 run (the fallback census), which hold at most
# ~1,270 of the 2,397 code-1 rows -- the rest are Nelder-Mead restarts
# published at their own cap.
convergence_clause <- function(p) {
  if (is.null(p)) return("")
  cc <- req(p$data, "census")
  codes <- cc[["codes_estimated"]]
  cnt <- function(k) if (is.null(codes[[k]])) 0 else as.numeric(codes[[k]])
  nn <- as.numeric(req(cc, "n_nonconverged"))
  split <- if (nn > 0 && cnt("52") + cnt("1") > 0)
    sprintf("; a failed L-BFGS-B line search on %s of those rows and an iteration cap on %s \u2014 L-BFGS-B's, or the Nelder\u2013Mead restart's where its point was published", format_pct(cnt("52"), nn), format_pct(cnt("1"), nn)) else ""
  sprintf(" The cell optimizer did not converge on %s of directly estimated rows (%s of %s fitted cells%s%s): those cells publish the better of the L-BFGS-B point and the Nelder\u2013Mead restart, with `gamma_se_status` `non_converged` and no SE (`docs/results/%s.md`).",
          format_pct(nn, req(cc, "n_estimated")), format_int(req(cc, "n_cells_nonconverged")),
          format_int(req(cc, "n_cells_estimated")), split, stale_note(p, "; ", ""), p$key)
}
# (patch 0118) M1 recorded: the sigma-pole rule at known truth
# (validation/pole_rule_accuracy.R -> results/pole_rule_accuracy.json; synthetic,
# so no table hash). Empty until the JSON is committed.
pole_accuracy_clause <- function(pa) {
  if (is.null(pa) || is.null(pa[["by_sigma"]])) return("")
  bs <- pa[["by_sigma"]]
  g <- function(k) vapply(bs, function(x) as.numeric(x[[k]]), 0)
  s <- g("sigma_true"); e1 <- g("tariff_err_P1"); e2 <- g("tariff_err_P2"); dr <- g("pole_drop_share_of_usable")
  fmt <- function(v) if (length(v)) paste(as.character(v), collapse = ", ") else "none"   # per value: format() pads 8 to 8.0 beside 1.2
  hi <- s >= 3
  sprintf(" At known truth the rule does not make the tariff its \u03c3 implies more accurate (patch 0117: Pillar 2's simulator at \u03c3 = %s): the median tariff error is higher with the rule at \u03c3 = %s and lower at \u03c3 = %s, and at \u03c3 \u2265 3 the rule drops %s\u2013%s of usable fits \u2014 cells far from the pole whose standard errors are large. Its measured benefit is the stability above (`docs/results/pole_rule_accuracy.md`).",
          fmt(s), fmt(s[e2 > e1]), fmt(s[e2 < e1]),
          if (any(hi)) format_prop_pct(min(dr[hi])) else "NA", if (any(hi)) format_prop_pct(max(dr[hi])) else "NA")
}
# (patch 0118) M2 recorded: a product-level sigma fallback, sized
# (analysis/sigma_fallback_hierarchy_census.R). Empty until the census is committed.
fallback_hierarchy_clause <- function(p) {
  if (is.null(p)) return("")
  cc <- req(p$data, "census"); lo <- req(cc, "loo")
  sprintf(" One global value is kept because the product does not predict \u03c3: across the cells with an estimate the good explains %s of the variance of ln(\u03c3 \u2212 1), and a fallback built from good and region \u00d7 good medians predicts held-out estimates no better than the global median (median error %s against %s%s; `docs/results/%s.md`).",
          format_prop_pct(req(cc, "r2_good")), format_num(req(lo, "err_ladder")), format_num(req(lo, "err_global")),
          stale_note(p, "; ", ""), p$key)
}
# M4: Pillar 2's sigma coverage, the grid points below 80% and the grid's floor.
pillar2_coverage_clause <- function(p2) {
  t1a <- req(p2, "tier1a")
  cov <- vapply(t1a, function(x) as.numeric(x[["sigma_cov"]]), 0)
  st  <- vapply(t1a, function(x) as.numeric(x[["sigma_true"]]), 0)
  ot  <- vapply(t1a, function(x) as.numeric(x[["omega_true"]]), 0)
  hl  <- vapply(t1a, function(x) if (is.null(x[["sigma_cov_hliml"]])) NA_real_ else as.numeric(x[["sigma_cov_hliml"]]), 0)
  low <- order(cov); low <- low[cov[low] < 0.8]
  one_omega <- length(low) > 0L && all(ot[low] == max(ot))
  pts <- vapply(seq_along(low), function(i) {
    k <- low[i]
    sprintf("%s at \u03c3 = %s%s%s", format_prop_pct(cov[k]), format(st[k]),
            if (one_omega) "" else sprintf(", \u03c9 = %s", format(ot[k])),
            if (i == 1L && is.finite(hl[k]) && hl[k] < cov[k]) sprintf(" (%s on interior-HLIML fits)", format_prop_pct(hl[k])) else "")
  }, "")
  where <- if (!length(low)) "" else sprintf(", but below 80%% at %d of %d points%s: %s",
                                             length(low), length(cov),
                                             if (one_omega) sprintf(", %s at the grid's largest \u03c9 (%s)", if (length(low) == 2L) "both" else if (length(low) > 2L) "all" else "that one", format(max(ot))) else "",
                                             paste(pts, collapse = " and "))
  sprintf(" The nominal 95%% interval for \u03c3 covers the truth in a median %s of replications across the grid%s. The grid's smallest \u03c3 is %s, so these figures do not describe cells near the \u03c3 = 1 pole, where the \u03c3-pole rule acts.",
          format_prop_pct(stats::median(cov)), where, format(min(st)))
}

# (patch 0120) M3 recorded: the window censuses of patch 0119, run on the 2%
# product subsample (no table hash: the newest release-tagged file is used).
pick_latest <- function(prefix, res = r) {
  keys <- grep(sprintf("^%s_v[0-9]{3,4}$", prefix), names(res), value = TRUE)
  if (!length(keys)) return(NULL)
  ver <- function(k) { v <- release_of_suffix(sub(paste0("^", prefix, "_"), "", k)); sum(as.numeric(strsplit(sub("^v", "", v), ".", fixed = TRUE)[[1]]) * c(1e6, 1e3, 1)) }
  k <- keys[which.max(vapply(keys, ver, 0))]
  list(data = res[[k]], key = k)
}
window_drift_clause <- function(p) {
  if (is.null(p)) return("")
  z <- req(req(p$data, "quantities"), "cell_tariff")
  ratio <- as.numeric(req(z, "ratio_robust"))
  reading <- if (ratio > 2) "above the factor of 2 at which a 2010\u20132024 estimate describes current conditions better than the full-panel average"
             else if (ratio < 1.5) "below 1.5, so the full-panel average describes current conditions as well as a 2010\u20132024 estimate would, and none is published"
             else "between 1.5 and 2, short of the factor of 2 at which a 2010\u20132024 estimate would describe current conditions better than the full-panel average"
  sprintf(" Whether that drift calls for a recent-window estimate was measured as well (patch 0119): on the same subsample the cell's log `opt_tariff` differs between 1995\u20132009 and 2010\u20132024 by %s times the variance of its odd/even-year difference, %s (`docs/results/%s.md`).",
          format_num(ratio, 2L), reading, p$key)
}
sigma_window_clause <- function(p) {
  if (is.null(p)) return("")
  el <- req(p$data, "early_vs_late")
  rho <- as.numeric(req(el, "rho"))
  if (rho >= 0.3)
    return(sprintf(" On the 2%% subsample, \u03c3 estimated on 1995\u20132009 and on 2010\u20132024 ranks the cells clean in both alike (rank \u03c1 %s on ln(\u03c3 \u2212 1); `docs/results/%s.md`).", format_num(rho, 2L), p$key))
  sprintf(" Cell-level \u03c3 is weakly reproducible across periods: on the 2%% subsample, \u03c3 estimated on 1995\u20132009 and on 2010\u20132024 ranks the %s cells clean in both almost independently (rank \u03c1 %s on ln(\u03c3 \u2212 1)); \u03c3 \u2212 1 differs by more than a factor of 2 in %s of them, with no shift in level, while only %s of the changes exceed 1.96 combined standard errors inflated 1.5\u00d7 \u2014 the standard errors are as wide as the disagreement. A 15-year panel does not pin down how \u03c3 varies across importers within a product, and the full panel only doubles it: read cell-level \u03c3, and the \u03b3 and `opt_tariff` built on it, as weakly identified in that dimension (`docs/results/%s.md`).",
          format_int(req(el, "cells")), format_num(rho, 2L), format_prop_pct(req(el, "share_change_gt_x2")),
          format_prop_pct(req(req(el, "share_z"), "se_x1.5")), p$key)
}

# (patch 0123) Known truth (validation/known_truth_stage2.R, patch 0122's grid)
# and the sigma EB period census. NULL-tolerant: without the JSONs the README
# keeps the patch-0120 sentences.
kt_row <- function(kt, arm, scale) {
  rows <- Filter(function(x) identical(x$arm_name, arm) && isTRUE(all.equal(as.numeric(x$scale), scale)) &&
                   (is.null(x$structure) || identical(x$structure, "none")), req(kt, "summary"))
  if (!length(rows)) stop(sprintf("README needs the known-truth summary row (arm %s, shock scale %s) in results/known_truth_stage2.json", arm, format(scale)), call. = FALSE)
  rows[[1]]
}
kt_not_recovered <- function(kt) !is.null(kt) && identical(kt$readings$R1_within_cell_gamma$verdict, "not recovered")
known_truth_title_tail <- function(kt) if (kt_not_recovered(kt)) ", and it is not recovered at known truth" else ""
within_signal_phrase <- function(kt) {
  if (kt_not_recovered(kt)) "reproducible within a period and period-specific"
  else "about half the within-cell heterogeneity is signal, and it is period-specific"
}
known_truth_order_sentence <- function(kt) {
  if (!kt_not_recovered(kt))
    return("Read the ordering of exporters within a cell as the data's; read the spread of their \u03b3's as conditional on the shipped \u03bb = 0.1, which sits in the middle of that plateau.")
  sprintf("The ordering is stable across \u03bb, but at known truth it does not follow the true ordering (within-cell rank correlation %s at baseline shock volatility and %s at three times it, shipped configuration; next bullet): read neither the ordering nor the spread of exporters' \u03b3's within a cell as exporter-level information. The spread is in addition conditional on the shipped \u03bb = 0.1, which sits in the middle of that plateau.",
          format_num(as.numeric(req(kt_row(kt, "shipped", 1), "within_rank_r")), 2L), format_num(as.numeric(req(kt_row(kt, "shipped", 3), "within_rank_r")), 2L))
}
known_truth_within_clause <- function(kt) {
  if (is.null(kt)) return("")
  meta <- req(kt, "meta"); yrs <- as.integer(strsplit(as.character(req(meta, "years")), ":", fixed = TRUE)[[1]])
  n_years <- if (length(yrs) == 2L) yrs[2] - yrs[1] + 1L else NA_integer_
  sh1 <- kt_row(kt, "shipped", 1); sh3 <- kt_row(kt, "shipped", 3); t1 <- kt_row(kt, "truesigma0", 1); t3 <- kt_row(kt, "truesigma0", 3)
  verdict <- if (kt_not_recovered(kt)) " The within-cell spread of the published \u03b3 is not exporter-level supply information even when every assumption holds" else ""
  sprintf(" Reproducible is not the same as recovered (patch 0122): on synthetic panels built to the estimator's own assumptions \u2014 Soderbery's model with known \u03c3 and \u03b3, %s years, no unit-value measurement error, %d seeds (`validation/known_truth_stage2.R`) \u2014 the shipped pipeline's within-cell deviations correlate with the true ones at r = %s at baseline shock volatility and %s at three times it, and only at %s and %s with the true \u03c3 and no shrinkage, while the ridge holds the published \u03b3 near the good-level prior (median shrink weight %s and %s).%s (`docs/results/known_truth_stage2.md`).",
          if (is.na(n_years)) "multi-year" else as.character(n_years), length(req(meta, "seeds")),
          format_num(as.numeric(req(sh1, "within_r")), 2L), format_num(as.numeric(req(sh3, "within_r")), 2L),
          format_num(as.numeric(req(t1, "within_r")), 2L), format_num(as.numeric(req(t3, "within_r")), 2L),
          format_num(as.numeric(req(sh1, "shrink_wt_median")), 3L), format_num(as.numeric(req(sh3, "shrink_wt_median")), 3L), verdict)
}
sigma_eb_period_clause <- function(p, kt) {
  if (is.null(p)) return("")
  el <- req(p$data, "early_to_late"); le <- req(p$data, "late_to_early")
  mae <- function(x, k) as.numeric(req(req(x, k), "median_abs_err"))
  const_best <- all(vapply(list(el, le), function(x) mae(x, "constant") < min(mae(x, "published"), mae(x, "eb")), TRUE))
  core <- sprintf("one global \u03c3 (each period's fallback) predicts a cell's estimate in the other period with a median absolute error in ln(\u03c3 \u2212 1) of %s (1995\u20132009 \u2192 2010\u20132024) and %s (the reverse), against %s and %s for the cell's own published \u03c3 and %s and %s for its empirical-Bayes posterior",
                  format_num(mae(el, "constant"), 2L), format_num(mae(le, "constant"), 2L), format_num(mae(el, "published"), 2L),
                  format_num(mae(le, "published"), 2L), format_num(mae(el, "eb"), 2L), format_num(mae(le, "eb"), 2L))
  out <- if (const_best) sprintf(" Out of sample the global value does better still (patch 0122): %s \u2014 cell-level differences in \u03c3 do not carry from one period to the other (`docs/results/%s.md`).", core, p$key)
         else sprintf(" Out of sample (patch 0122): %s (`docs/results/%s.md`).", core, p$key)
  r3 <- if (is.null(kt)) NULL else kt$readings$R3_sigma_eb
  if (!is.null(r3) && identical(r3$verdict, "closed at known truth") && !is.null(r3$worlds))
    out <- paste0(out, sprintf(" Empirical-Bayes shrinkage of \u03c3 is not adopted: at known truth it lowered the \u03c3 error by 10%% or more in %d of %d worlds (`docs/results/known_truth_stage2.md`)%s.",
                               as.integer(r3$worlds_sigma_err_down_10pct), as.integer(r3$worlds),
                               if (const_best) ", and on this split it is beaten by the constant it shrinks toward" else ""))
  out
}

# (patch 0124) Reading R4: the structured known-truth grid of patch 0123
# (results/known_truth_structured.json). NULL-tolerant.
kts_row <- function(kts, structure, scale) {
  rows <- Filter(function(x) identical(x$structure, structure) && identical(x$arm_name, "shipped") &&
                   isTRUE(all.equal(as.numeric(x$scale), scale)), req(kts, "summary"))
  if (!length(rows)) stop(sprintf("README needs the structured known-truth row (%s, shock scale %s) in results/known_truth_structured.json", structure, format(scale)), call. = FALSE)
  rows[[1]]
}
.kt_pair <- function(x1, x3, f) { a <- f(as.numeric(x1)); b <- f(as.numeric(x3)); if (identical(a, b)) a else sprintf("%s and %s", a, b) }
.kt_by_scale <- function(lst, f = function(v) format_num(v, 2L)) .kt_pair(req(lst, "x1"), req(lst, "x3"), f)
.kt_pct <- function(v) sprintf("%.0f%%", 100 * v)
known_truth_overview <- function(kt, kts) {
  if (is.null(kt) || is.null(kts)) return("")
  a <- req(req(kts, "readings"), "R4a_between_goods"); b <- req(req(kts, "readings"), "R4b_within_goods")
  verb_a <- switch(a$verdict, recovered = "track true differences between products", partial = "track true differences between products only in part",
                   "do not track true differences between products")
  verb_b <- switch(b$verdict, recovered = "track differences between importers within a product", partial = "track differences between importers within a product only weakly",
                   "do not track differences between importers within a product")
  verb_c <- if (kt_not_recovered(kt)) "do not recover differences between exporters within a cell" else "recover differences between exporters within a cell only in part"
  sprintf("\n\nChecked against known truth (`validation/known_truth_stage2.R`): on synthetic panels built to the estimator's own assumptions, the published \u03b3 and `opt_tariff` %s (correlation %s for the products' median \u03b3 and %s for their `opt_tariff`, at baseline and triple shock volatility), %s (%s, keeping %s of the true spread), and %s (%s). See Known limitations.",
          verb_a, .kt_by_scale(req(a, "gamma_r_by_scale")), .kt_by_scale(req(a, "tariff_r_by_scale")), verb_b,
          .kt_by_scale(req(b, "gamma_r_by_scale")), .kt_by_scale(req(b, "gamma_sd_ratio_by_scale"), .kt_pct), verb_c,
          .kt_pair(req(kt_row(kt, "shipped", 1), "within_r"), req(kt_row(kt, "shipped", 3), "within_r"), function(v) format_num(v, 2L)))
}
known_truth_structured_bullet <- function(kts) {
  if (is.null(kts)) return("")
  meta <- req(kts, "meta"); a <- req(req(kts, "readings"), "R4a_between_goods"); b <- req(req(kts, "readings"), "R4b_within_goods")
  gi1 <- kts_row(kts, "good_importer", 1); gi3 <- kts_row(kts, "good_importer", 3)
  two <- function(k, rows = list(gi1, gi3)) .kt_pair(req(rows[[1]], k), req(rows[[2]], k), function(v) format_num(v, 2L))
  sprintf("\n- **What the published \u03b3 and `opt_tariff` track at known truth.** On synthetic panels whose ln \u03b3 differs by product (s.d. 0.7 between %s products, 0.35 within; `validation/known_truth_stage2.R --structures good,good_importer`, %d seeds), the products' median published \u03b3 correlates with the true one at %s and their mean ln `opt_tariff` at %s (baseline and triple shock volatility): product differences pass from the Stage-1 \u03c9 through the Stage-2a priors into Stage 2b. With an importer effect added (s.d. 0.5), the cell mean ln \u03b3 tracks the importer differences within a product at r = %s, keeping %s of their true spread, and the cell's `opt_tariff` at r = %s: the Stage-2b prior is one value per product, so with shrink weights near 1 importer differences survive only where the data outweigh it. Across all cells the `opt_tariff` correlates with the truth at %s and the composite \u03b3/((1+\u03b3)(\u03c3\u22121)) at %s. By reading R4 (fixed in patch 0123) that is \"%s\" between products and \"%s\" within them (`docs/results/known_truth_structured.md`).",
          format(req(meta, "goods")), length(req(meta, "seeds")), .kt_by_scale(req(a, "gamma_r_by_scale")), .kt_by_scale(req(a, "tariff_r_by_scale")),
          .kt_by_scale(req(b, "gamma_r_by_scale")), .kt_by_scale(req(b, "gamma_sd_ratio_by_scale"), .kt_pct), .kt_by_scale(req(b, "tariff_r_by_scale")),
          two("opt_tariff_r"), two("composite_r"), req(a, "verdict"), req(b, "verdict"))
}

# (patch 0128) The product-level companion table (analysis/product_summary.R;
# results/product_summary_census.json) and the Stage-1 routing check at known
# truth (validation/known_truth_routing.R; results/known_truth_routing.json).
# NULL-tolerant; the level-gap sentence appears once the census carries it.
product_table_section <- function(ps, sigma_fallback, pw = NULL) {
  # (patch 0130) The odd/even and period halves of patch 0127's census re-ran
  # Stage 2b only, with the full-panel Stage 1 and Stage-2a priors: they show
  # that a product's median barely depends on which half of the Stage-2b data
  # is used, given those priors -- not that product differences reproduce in
  # independent data. Through 0129 this section called them "independent
  # halves" and the gap "the table's error scale". The independent test is
  # results/product_window_census.json (`pw`): Stage 1, 2a and 2b estimated
  # separately on 1995-2009 and 2010-2024.
  if (is.null(ps)) return("")
  oe <- req(ps, "odd_even"); el <- ps$early_late
  sp <- function(x, k) format_num(as.numeric(req(req(x, k), "spearman")), 2L)
  # (patch 0131) the shared-prior halves' level gap (0.2%) is no longer quoted
  # here: it measured how little the Stage-2b data move a product's median given
  # the priors, which is no guide to the table's uncertainty. The independent
  # periods' gap below is.
  gap <- ""
  across <- if (is.null(el)) "" else sprintf(" (%s and %s between 1995\u20132009 and 2010\u20132024)", sp(el, "gamma_median"), sp(el, "opt_tariff_median"))
  indep <- " A test on independently estimated periods is pending."
  if (!is.null(pw)) {
    r <- req(pw, "reproducibility")
    indep <- sprintf(" Estimated independently on 1995\u20132009 and on 2010\u20132024 -- each period's own Stage 1, Stage 2a and Stage 2b, on the same %d products -- product medians correlate at %s for \u03b3 and %s for `opt_tariff`; by the rule fixed in patch 0130 that is \"%s\" (`docs/results/product_window_census.md`).",
                     as.integer(req(req(r, "gamma_median"), "products")), sp(r, "gamma_median"), sp(r, "opt_tariff_median"), req(pw, "reading"))
    # (patch 0131) the independent periods' level gap: the scale of uncertainty for the table's values
    gg <- r$gamma_median$gap_median; g9 <- r$gamma_median$gap_p90; og <- r$opt_tariff_median$gap_median; o9 <- r$opt_tariff_median$gap_p90
    if (!is.null(gg) && !is.null(g9) && !is.null(og) && !is.null(o9)) {
      pc <- function(v) sprintf("%.1f%%", 100 * (exp(as.numeric(v)) - 1))
      indep <- paste0(indep, sprintf(" Between those periods a product's median \u03b3 differs by a median of %s (%s at the 90th percentile) and its median `opt_tariff` by %s (%s). Part of that is change over time, but it is the scale of uncertainty to read the table's values with: its ranking of products is better supported than its levels.",
                                     pc(gg), pc(g9), pc(og), pc(o9)))
    }
  }
  sprintf(paste0("\n\n### The product-level table (since v0.11.1)\n\n",
                 "`data/derived/product/baci_hs92_v202601_elast_hs4_product_summary.csv` has one row per HS4 product (%s), built from the table above by ",
                 "`analysis/product_summary.R`: `gamma_median` (the median \u03b3 over directly estimated rows), `opt_tariff_median` (the median over the ",
                 "product's (importer, product) cells), `opt_tariff_total_median` (since v0.11.3, the same for `opt_tariff_total`), ",
                 "`sigma_median`, `share_cells_own_sigma`, and the counts `n_cells`, `n_rows`, `n_rows_estimated` and ",
                 "`trade` (the sum of `avg_trade`). It is the level the estimates support: at known truth the pipeline recovers differences between products, ",
                 "weakly those between importers within a product, and not those between exporters within a cell (Known limitations). ",
                 "On a 2%% product subsample (%d products) the product medians hardly depend on which half of the Stage-2b data is used -- Spearman %s for ",
                 "\u03b3 and %s for `opt_tariff` between odd and even years%s%s -- but those halves share the full-panel Stage 1 (the odd/even halves also its ",
                 "Stage-2a priors), from which a product's median is mostly built, so they do not show that product differences reproduce in independent data ",
                 "(`docs/results/product_summary_census.md`; a hash check in `docs/results/product_window_census.md`).%s ",
                 "\u03c3 is the global value (%s) for nearly every product. Read `good` as character; the table carries no interval columns, because ",
                 "resampling importers leaves the product prior -- a product's main source of uncertainty -- untouched."),
          format_int(as.integer(req(req(ps, "meta"), "products"))), as.integer(req(req(oe, "gamma_median"), "products")),
          sp(oe, "gamma_median"), sp(oe, "opt_tariff_median"), across, gap, indep, format_num(sigma_fallback, 3L))
}
routing_bullet <- function(kr, ab = NULL) {
  if (is.null(kr)) return("")
  bs <- req(kr, "by_scale"); ov <- req(kr, "overall"); real <- kr$real_routes
  pick <- function(rows, route, scale = NULL) {
    x <- Filter(function(z) identical(z$route, route) && (is.null(scale) || isTRUE(all.equal(as.numeric(z$scale), scale))), rows)
    if (!length(x)) stop(sprintf("README needs the routing row %s%s", route, if (is.null(scale)) "" else paste0(" at scale ", scale)), call. = FALSE)
    x[[1]]
  }
  f <- function(v) formatC(exp(as.numeric(v)), digits = 2, format = "f")
  s1 <- pick(bs, "step2_weighted", 1); s3 <- pick(bs, "step2_weighted", 3); h1 <- pick(bs, "hliml", 1); h3 <- pick(bs, "hliml", 3)
  so <- pick(ov, "step2_weighted")
  real_txt <- ""
  if (!is.null(real)) {
    r2 <- Filter(function(z) identical(z$route, "step2_weighted"), real)
    if (length(r2)) real_txt <- sprintf(" In the shipped Stage 1 the Step-2 route carries %s cells (%s of the cells with an estimate), %s of them in the set whose median is the fallback \u03c3.",
                                        format_int(as.integer(r2[[1]]$cells)), sprintf("%.1f%%", 100 * as.numeric(r2[[1]]$share_of_estimated)), format_int(as.integer(r2[[1]]$clean)))
  }
  verdict <- if (identical(kr$reading$verdict, "biased")) " By the rule fixed in patch 0127 that is \"biased\"." else ""
  # (patch 0130) the A/B of patch 0129 (results/routing_ab.json, `ab`)
  if (!is.null(ab)) {
    ov <- req(req(ab, "known_truth"), "overall")[[1]]; pr <- req(ab, "period"); sh <- req(ab, "shipped")
    verdict <- paste0(verdict, sprintf(
      " The alternative, the boundary search, is usable on %s of those cells (patch 0129): at known truth it is less biased (%s against %s) but noisier (median error %s against %s), and on the real 1995\u20132009 / 2010\u20132024 split it predicts the other period's \u03c3 worse (median error %s and %s against %s and %s). By the rule fixed in patch 0129 that is \"%s\"; switching would move the fallback \u03c3 only from %s to %s (`docs/results/routing_ab.md`).",
      format_int(as.integer(req(sh, "with_usable_boundary"))), sprintf("%+.2f", as.numeric(ov$bias_bd)), sprintf("%+.2f", as.numeric(ov$bias_s2)),
      format_num(as.numeric(ov$error_bd), 2L), format_num(as.numeric(ov$error_s2), 2L),
      format_num(as.numeric(pr$early_to_late$mae_bd), 2L), format_num(as.numeric(pr$late_to_early$mae_bd), 2L),
      format_num(as.numeric(pr$early_to_late$mae_s2), 2L), format_num(as.numeric(pr$late_to_early$mae_s2), 2L),
      req(req(ab, "reading"), "verdict"), format_num(as.numeric(req(sh, "fallback_now")), 3L), format_num(as.numeric(req(sh, "fallback_after")), 3L)))
  }
  sprintf("\n- **Stage 1's Step-2 route overstates \u03c3 at known truth.** On the known-truth worlds (`validation/known_truth_routing.R`, %d worlds), cells whose closed form is inadmissible and that Stage 1 routes through the Step-2 cascade carry \u03c3 \u2212 1 overstated by a median factor of %s and %s at baseline and triple shock volatility, against %s and %s on the closed form's cells; after the edge and pole rules the published factor is %s (`docs/results/known_truth_routing.md`).%s%s",
          length(req(req(kr, "meta"), "worlds")), f(s1$bias_raw), f(s3$bias_raw), f(h1$bias_raw), f(h3$bias_raw), f(so$bias_pub), real_txt, verdict)
}

# (patch 0135) The precision-scaled ridge experiment (patches 0132-0135):
# readings R5 and R6 of validation/known_truth_stage2.R, the empirical-Bayes
# tau^2 and the adoption and tariff checks (analysis/ridge_tau2_eb.R).
# NULL-tolerant: the bullet appears once R5 is committed, and each later
# sentence once its JSON is.
ridge_experiment_bullet <- function(kr5, keb, eb, ck, tc = NULL) {
  if (is.null(kr5)) return("")
  r5 <- req(req(kr5, "readings"), "R5_ridge_scale")
  arm <- function(a) { x <- Filter(function(z) identical(z$arm, a), req(r5, "per_arm")); if (!length(x)) stop("README needs R5 arm ", a, call. = FALSE); x[[1]] }
  sh <- arm("shipped"); t1 <- arm("ridge_t01")
  f2 <- function(v) format_num(as.numeric(v), 2L)
  # (patch 0136) the title follows the outcome: closed once the tariff check
  # (or the adoption reading) says no
  closed <- (!is.null(tc) && !identical(tc$reading, "proceed to a release")) || (!is.null(ck) && !identical(ck$reading, "adopt-candidate"))
  title <- if (closed) "A ridge that does not scale with price volatility was tested and not adopted (patches 0132\u20130136)."
           else "A ridge that does not scale with price volatility is being tested (patches 0132\u20130135; not in the published data)."
  out <- sprintf(paste0("\n- **", title, "** ",
                        "Under `--stage2-ridge-scale cell` each cell's Stage-2b data term is divided by its own noise variance and \u03bb becomes the prior precision ",
                        "1/\u03c4\u00b2 of ln \u03b3 around the product prior. At known truth it recovers importer differences within a product at r %s / %s (\u03c4\u00b2 = 0.1) ",
                        "against %s / %s under the shipped ridge, keeping the product-level signal (reading R5: \"%s\"; `docs/results/known_truth_ridge.md`); ",
                        "exporter differences within a cell stay unrecovered."),
                 f2(t1$within_good_gamma_r[[1]]), f2(t1$within_good_gamma_r[[2]]), f2(sh$within_good_gamma_r[[1]]), f2(sh$within_good_gamma_r[[2]]), req(r5, "verdict"))
  if (!is.null(keb)) {
    r6 <- req(req(keb, "readings"), "R6_eb"); pw <- req(r6, "per_world")
    ratio <- stats::median(vapply(pw, function(z) as.numeric(z$tau2_eb) / as.numeric(z$true_var), 0))
    out <- paste0(out, sprintf(paste0(" \u03c4\u00b2 is set by empirical Bayes from two halves of the years (alternate four-year blocks, so that no year's level enters both): ",
                                      "at known truth the estimate lands in the useful range in %s of the six worlds (reading R6: \"%s\"), overstating the true variance by a median %s%%."),
                               sprintf("%.0f%%", 100 * as.numeric(req(r6, "share_in_range"))), req(r6, "verdict"), sprintf("%.0f", 100 * (ratio - 1))))
  }
  if (!is.null(eb) && !is.null(ck)) {
    out <- paste0(out, sprintf(paste0(" On the 2%% product subsample it gives \u03c4\u00b2 = %s; there, importer differences within a product reproduce across the halves at %s ",
                                      "against %s under the shipped ridge, and product medians move by a median %s%% (adoption reading: \"%s\"; `docs/results/ridge_tau2_check.md`)."),
                               format_num(as.numeric(req(req(eb, "tau2"), "tau2_eb")), 2L), format_num(as.numeric(req(req(ck, "candidate"), "pearson")), 3L),
                               format_num(as.numeric(req(req(ck, "shipped"), "pearson")), 3L), sprintf("%.0f", 100 * (exp(as.numeric(req(ck, "product_median_shift"))) - 1)),
                               req(ck, "reading")))
  }
  if (!is.null(tc)) {
    out <- paste0(out, sprintf(" Cell-level `opt_tariff` reproduces across the halves at %s against %s under the shipped ridge (rule fixed in patch 0135: no more than 0.02 below; \"%s\"; `docs/results/ridge_tariff_check.md`).",
                               format_num(as.numeric(req(tc, "tariff_candidate")), 3L), format_num(as.numeric(req(tc, "tariff_shipped")), 3L), req(tc, "reading")))
    if (!is.null(tc$gamma_candidate) && !is.null(tc$gamma_shipped))
      out <- paste0(out, sprintf(" Row-level ln \u03b3 reproduces at %s against %s.", format_num(as.numeric(tc$gamma_candidate), 3L), format_num(as.numeric(tc$gamma_shipped), 3L)))
  }
  if (closed)
    out <- paste0(out, " At this \u03c4\u00b2 the looser shrinkage admits more noise than signal in the published columns, so the shipped ridge stays; the flags remain in the code, off by default (`docs/methodology/stage2_country.md`).")
  out
}

# (patch 0139) How much the weighting moves the cell tariff, from
# results/tariff_weight_census.json (patch 0138). NULL-tolerant.
tariff_weight_note <- function(tw) {
  if (is.null(tw)) return("")
  pc <- function(x) sprintf("%.1f%%", 100 * as.numeric(x))
  sprintf(paste0(" The choice matters: against `opt_tariff`, the cell value moves by a median %s and by more than 10%% in %s of cells, ",
                 "and product medians move by a median %s (`docs/results/tariff_weight_census.md`)."),
          pc(req(req(tw, "cell_change"), "p50")), pc(req(tw, "share_cells_over_10pct")), pc(req(req(tw, "product_change"), "p50")))
}

# --- Stage-2 DGP harness line (G4, v0.4.1) ---------------------------------
# One rendered sentence for the validation section, built from
# results/stage2_dgp_summary.json. NULL-tolerant on the fields added in
# v0.4.1 (test_D / test_E) so the README builds against both the v0.4.0
# import-only artifact and the extended import+export one.

dgp_harness_line <- function(dgp) {
  if (is.null(dgp)) {
    return(paste0("not yet run -- generate with ",
                  "`Rscript validation/stage2_structural_dgp.R`."))
  }
  verdict  <- if (isTRUE(req(dgp, "overall_pass"))) "**PASS**" else "**FAIL**"
  meta     <- req(dgp, "meta")
  coverage <- if (!is.null(dgp$test_D))
    "import + export sides, Eqs. (10) and (11) with the G1 sign correction"
  else
    "import side only, Eq. (10)"
  quick_note <- if (isTRUE(meta$quick)) " QUICK run -- not release grade;" else ""
  # (patch 0110) Test F: the export side against the model's primitives
  if (!is.null(dgp$test_F)) {
    fg <- dgp$test_F$grid
    sh <- max(vapply(fg, function(x) if (!isTRUE(all.equal(x$gam_I, x$gam_V))) x$resid_ratio_share else 0, 0))
    va <- max(vapply(fg, function(x) x$resid_ratio_value, 0))
    coverage <- sprintf("%s; Test F, the export side against the primitives: exact on export values, the form shipped since v0.11.0 (residual at the truth at most %.1f%% of the outcome), while the share form of the printed Eq. (8) misses by up to %.1f%% when \u03b3_I \u2260 \u03b3_V", coverage, 100 * va, 100 * sh)
  }
  sprintf("%s at rev `%s`, %s (%s%s; seed %s). Regenerate with `Rscript validation/stage2_structural_dgp.R`.",
          verdict, req(meta, "git_rev"),
          substr(req(meta, "timestamp"), 1, 10),
          quick_note, coverage, req(meta, "seed"))
}

# --- Asymmetry conditional -------------------------------------------------
# stage2b$n_importers_asymmetry_vs_stage1 = stage1.n_importers - stage2b.n_importers.
# Currently 1. Prose has to change shape on 0 and >1; the helper encapsulates
# all three branches so the template stays readable.

# Pillar-2 direction phrases (v0.5.1): the README used to hard-code
# "yield declining as sample size grows" and "predominantly downward". Both
# were artifacts of the pre-0020 harness (row/label misalignment); the wording
# is now derived from the JSON so the sentence cannot contradict the numbers.
yield_direction_phrase <- function(t1b) {
  lo <- req(t1b, "success_rate_at_smallest_n")
  hi <- req(t1b, "success_rate_at_largest_n")
  if (hi > lo + 0.02) "rises" else if (hi < lo - 0.02) "falls" else "is flat"
}
sigma_bias_sign_phrase <- function(t1a) {
  b <- sapply(t1a, function(x) x$sigma_bias)
  n_neg <- sum(b < 0); n <- length(b)
  sprintf("negative at %d of %d grid points", n_neg, n)
}

# v0.6.0 (patch 0031): boundary-HLIML cells (adjust 6/7/8, routed only where
# the closed form and Step 2 both failed). Silent when the run has none
# (v0.5.x tables), so the sentence is unchanged for legacy JSONs.
# (patch 0051) SE clause for the boundary sentence, driven by the run's own
# edge_se block (absent on pre-v0.7.1 JSONs -> the old "no SE" reading).
edge_se_clause <- function(es) {
  if (is.null(es) || !identical(es[["method"]], "hncs")) return(", no SE")
  n_se <- es[["n_boundary_with_se"]]
  if (is.null(n_se)) n_se <- es[["n_boundary_with_sigma_se"]]   # pre-0055 JSON
  sprintf("; SEs from the HNCS sandwich projected onto the edge on %s of them (\u03c3 on the \u03c9 edges, \u03c9 on the \u03c3-cap edge); `edge_se_status` names the %s where the projected curvature was not usable",
          format_int(n_se + 0L), format_int(es[["n_boundary_status_fail"]] + 0L))
}

# (patch 0064) Step-2 VCE clause for the Standard-errors bullet, driven by
# the run's own step2_vce block (absent, or rule "legacy", on tables shipped
# before v0.7.3 -> empty, so the bullet is byte-identical on old JSONs).
step2_vce_clause <- function(sv) {
  if (is.null(sv) || !identical(sv[["method"]], "kclass")) return("")
  f2 <- function(x) sprintf("%.2f", x)
  sprintf(" Stage-1 `sigma_se` on the %s Step-2 (Fuller LIML fallback) cells uses the k-class sandwich from v0.7.3; through v0.7.2 an OLS meat overstated it several-fold. Median relative SE (`sigma_se`/`sigma`): %s on Step-2 cells, %s on interior HLIML cells, %s on boundary cells.",
          format_int(sv[["n_step2"]] + 0L), f2(sv[["rel_se_median_step2"]]),
          f2(sv[["rel_se_median_hliml"]]), f2(sv[["rel_se_median_boundary"]]))
}

# (patch 0064) Exporter-cluster bootstrap clause, driven by
# results/bootstrap_se_summary.json (emitted by 00_setup.R only from a
# branch-tagged per-cell file; absent -> empty). Greek/symbols as Unicode
# escapes to keep this file ASCII-clean (see asymmetry_phrase).
bootstrap_clause <- function(bs) {
  if (is.null(bs) || is.null(bs[["by_route"]])) return("")
  br <- bs[["by_route"]]
  g <- function(route, key) br[[route]][[key]]
  f2 <- function(x) sprintf("%.2f", x)
  pc <- function(x) sprintf("%.0f%%", 100 * x)
  s2f <- bs[["step2_by_f"]]
  f7 <- if (!is.null(s2f) && !is.null(s2f[["F>=7"]])) s2f[["F>=7"]][["ratio_mad_same_median"]] else NA_real_
  # (patch 0065) the medians are over the core cells -- three-exporter cells
  # resample to near-degenerate panels and F-undefined cells barely
  # bootstrap; say so, and say how many, rather than imply all cells.
  n_core <- bs[["n_cells_core"]]
  core_phrase <- if (!is.null(n_core) && n_core < bs[["n_cells"]])
    sprintf("; medians over the %s cells with at least four exporters and a defined weak-instrument F", format_int(n_core + 0L)) else ""
  paste0(
    sprintf(" An exporter-cluster bootstrap (%s cells \u00d7 %s replicates, branch-tagged; `validation/bootstrap_se_cells.csv`%s) puts the robust (MAD) dispersion of the replicates that stay on a cell's own branch at %s\u00d7 the analytic SE for interior HLIML cells, %s\u00d7 for boundary cells and %s\u00d7 for Step-2 cells, with %s, %s and %s of replicates staying on the published branch; the unconditional SD-based ratios are %s\u00d7, %s\u00d7 and %s\u00d7, the difference being branch switching and heavy tails.",
            format_int(bs[["n_cells"]] + 0L), format_int(bs[["B"]] + 0L), core_phrase,
            f2(g("hliml", "ratio_mad_same_median")), f2(g("hliml_boundary", "ratio_mad_same_median")), f2(g("step2_weighted", "ratio_mad_same_median")),
            pc(g("hliml", "share_same_route_median")), pc(g("hliml_boundary", "share_same_route_median")), pc(g("step2_weighted", "share_same_route_median")),
            f2(g("hliml", "ratio_sd_median")), f2(g("hliml_boundary", "ratio_sd_median")), f2(g("step2_weighted", "ratio_sd_median"))),
    if (is.finite(f7)) sprintf(" Step-2 cells with strong instruments (Kleibergen-Paap F \u2265 7) sit at %s\u00d7 within their own branch: their \u03c3 depends on which exporters the cell contains, so read Step-2 `sigma_se` as a composition-conditional lower bound and consult the per-cell bootstrap dispersion alongside it.", f2(f7)) else ""
  )
}

# (patch 0080) Optimizer-fallback clause for the gamma-heterogeneity bullet,
# driven by results/stage2_fallback_census.json (emitted by
# analysis/stage2_fallback_census.R from the rc run's universe fallback table);
# empty when the JSON is absent, so the README is byte-identical at apply.
# The template reads it with r[["stage2_fallback_census"]] (exact): r$... would
# partial-match any other results/*.json whose name extends it.
fallback_clause <- function(p) {
  # (patch 0109) p is a pick_census() result: "On the shipped table" only when
  # the census was computed on it, otherwise the table it was computed on.
  fc <- p$data
  if (is.null(fc) || is.null(fc[["n_cells"]])) return("")
  pc <- function(x) sprintf("%.0f%%", 100 * x)
  where <- if (isTRUE(p$fresh)) "On the shipped table" else
    sprintf("On the %s table (the census has not been re-run on the shipped table)", p$vintage)
  # (patch 0118) "reached that cap" -> "did not converge": the restart runs for every
  # cell whose L-BFGS-B fit did not converge, mostly a failed line search (code 52).
  codes <- fc[["lbfgsb_codes"]]
  cs <- if (is.null(codes)) "" else sprintf(" (code 52, a failed line search, on %s; code 1, the iteration cap, on %s)",
                                            format_int(.nz(codes[["52"]], 0) + 0L), format_int(.nz(codes[["1"]], 0) + 0L))
  sprintf(" %s the L-BFGS-B fit did not converge on %s cells%s and the restart ran; its objective was higher than the discarded point on %s of them (%s), and it had reported convergence on %s, rows that v0.8.2 labelled `ok` at a stalled point (`docs/results/%s.md`).",
          where, format_int(fc[["n_cells"]] + 0L), cs, format_int(fc[["n_nm_worse"]] + 0L), pc(fc[["share_nm_worse"]]),
          format_int(fc[["n_nm_converged"]] + 0L), p$key)
}

boundary_phrase <- function(rs, n_cells, es = NULL) {
  bt <- rs[["boundary_total"]]
  if (is.null(bt) || !is.finite(bt) || bt == 0) return("")
  # \u03c9 / \u03c3 = omega / sigma, written as Unicode escapes so this file
  # stays ASCII-clean (see asymmetry_phrase); the literal Greek letters used
  # here before patch 0045 rendered as raw bytes under a non-UTF-8 locale and
  # broke the README lock check there.
  sprintf("; a further %s (%s cells) are constrained boundary HLIML optima -- %s on the \u03c9 floor, %s at the \u03c3 cap, %s at the \u03c9 cap -- routed where the closed-form HLIML point was inadmissible and Step 2 supplied no admissible \u03c9 (`final_source == \"hliml_boundary\"`%s)",
          format_pct(bt, n_cells), format_int(bt),
          format_int(rs[["boundary_omega_floor"]]), format_int(rs[["boundary_sigma_cap"]]),
          format_int(rs[["boundary_omega_cap"]]), edge_se_clause(es))
}

# beyond_inf_phrase (patch 0047): quantifies the v0.6.1 defect from the
# run's own table when the run still carries it (rule "floor"), and is
# silent under reject, where the count is zero by construction. The README
# never states a number the current data cannot reproduce.
beyond_inf_phrase <- function(no) {
  n <- no[["n_cf_beyond_inf_interior"]]
  if (is.null(n) || is.na(n) || n == 0) return("")
  sprintf(" (%s cells, %s of the universe, in this table)", format_int(n),
          format_pct(n, no[["denominator"]]))
}

asymmetry_phrase <- function(n_asym) {
  if (n_asym == 0L) {
    return("")  # no parenthetical at all
  } else if (n_asym == 1L) {
    return(" (one importer present at Stage 1 has no country-pair \u03b3 at Stage 2b after the minimum-destinations filter)")
  } else {
    return(sprintf(" (%s importers present at Stage 1 have no country-pair \u03b3 at Stage 2b after the minimum-destinations filter)",
                   format_int(n_asym)))
  }
}
# Note: \u03b3 is the Greek lowercase gamma. Written as a Unicode escape
# rather than the literal character so this file stays ASCII-clean and
# diffs trivially against any editor / git config. R unescapes \uXXXX in
# string literals regardless of source-file encoding.

# --- Render ----------------------------------------------------------------

template <- readLines(TEMPLATE_PATH, encoding = "UTF-8", warn = FALSE)
template_text <- paste(template, collapse = "\n")

# glue with double-brace delimiters. .envir provides r, req, and formatters
# to the template's expressions. .trim = FALSE preserves leading whitespace
# in multi-line expressions.
render_env <- new.env(parent = baseenv())
render_env$r <- r
render_env$req <- req
render_env$format_int <- format_int
render_env$format_pct <- format_pct
render_env$format_prop_pct <- format_prop_pct
render_env$dgp_harness_line <- dgp_harness_line
render_env$format_num <- format_num
render_env$asymmetry_phrase <- asymmetry_phrase
render_env$yield_direction_phrase <- yield_direction_phrase
render_env$boundary_phrase <- boundary_phrase
render_env$beyond_inf_phrase <- beyond_inf_phrase
render_env$sigma_bias_sign_phrase <- sigma_bias_sign_phrase
render_env$step2_vce_clause <- step2_vce_clause        # patch 0064
render_env$bootstrap_clause <- bootstrap_clause        # patch 0064
render_env$fallback_clause <- fallback_clause          # patch 0080
render_env$manifest_n_files <- manifest_n_files
# (patch 0109) census picks for the template: the shipped table's census if
# one exists, else the newest with its vintage stated (stale_note()).
render_env$SHRINK   <- pick_census("stage2_shrinkage_census")
if (!shrink_census_ok(render_env$SHRINK))
  stop(sprintf("README: %s was computed with --shrink-wt-def %s; the shipped table's sandwich SEs need 'half' (data share = 1 - gamma_shrink_wt). Re-run analysis/stage2_shrinkage_census.R with --shrink-wt-def half.",
               render_env$SHRINK$key, .nz(render_env$SHRINK$data$meta$shrink_wt_def, "<unrecorded>")), call. = FALSE)
render_env$FALLBACK <- pick_census("stage2_fallback_census", legacy = c(stage2_fallback_census = "v0.9.0"))
render_env$stale_note <- stale_note
render_env$spearman_brown <- spearman_brown
render_env$pillar2_cap_note <- pillar2_cap_note
render_env$pillar3_constant_clause <- pillar3_constant_clause   # patch 0113
render_env$provenance_lead <- provenance_lead                   # patch 0116
render_env$provenance_tail <- provenance_tail                   # patch 0116
render_env$headline_sigma_note <- headline_sigma_note           # patch 0116
render_env$convergence_clause <- convergence_clause             # patch 0116
render_env$pillar2_coverage_clause <- pillar2_coverage_clause   # patch 0116
render_env$CONV <- pick_census_opt("stage2b_convergence_census")   # patch 0116: NULL until committed
render_env$pole_accuracy_clause <- pole_accuracy_clause           # patch 0118
render_env$fallback_hierarchy_clause <- fallback_hierarchy_clause # patch 0118
render_env$HIER <- pick_census_opt("sigma_fallback_hierarchy_census")   # patch 0118: NULL until committed
render_env$window_drift_clause <- window_drift_clause   # patch 0120
render_env$sigma_window_clause <- sigma_window_clause   # patch 0120
render_env$WDRIFT <- pick_latest("window_drift_census")  # patch 0120: the 2% subsample census of patch 0119
render_env$SWIN <- pick_latest("sigma_window_census")    # patch 0120
render_env$known_truth_title_tail <- known_truth_title_tail           # patch 0123
render_env$within_signal_phrase <- within_signal_phrase               # patch 0123
render_env$known_truth_order_sentence <- known_truth_order_sentence   # patch 0123
render_env$known_truth_within_clause <- known_truth_within_clause     # patch 0123
render_env$sigma_eb_period_clause <- sigma_eb_period_clause           # patch 0123
render_env$KT <- r[["known_truth_stage2"]]                             # patch 0123: NULL until committed
render_env$SEB <- pick_latest("sigma_eb_period_census")                # patch 0123
render_env$known_truth_overview <- known_truth_overview                 # patch 0124
render_env$known_truth_structured_bullet <- known_truth_structured_bullet   # patch 0124
render_env$KTS <- r[["known_truth_structured"]]                         # patch 0124: NULL until committed
render_env$product_table_section <- product_table_section             # patch 0128
render_env$routing_bullet <- routing_bullet                           # patch 0128
render_env$PS <- r[["product_summary_census"]]                          # patch 0128
render_env$KR <- r[["known_truth_routing"]]                             # patch 0128
render_env$AB <- r[["routing_ab"]]                                      # patch 0130
render_env$PW <- r[["product_window_census"]]                           # patch 0130: NULL until committed
render_env$ridge_experiment_bullet <- ridge_experiment_bullet           # patch 0135
render_env$tariff_weight_note <- tariff_weight_note; render_env$TW <- r[["tariff_weight_census"]]   # patch 0139
render_env$KR5 <- r[["known_truth_ridge"]]; render_env$KEB <- r[["known_truth_eb"]]     # patch 0135
render_env$EB <- r[["ridge_tau2_eb"]]; render_env$CK <- r[["ridge_tau2_check"]]; render_env$TC <- r[["ridge_tariff_check"]]

rendered <- tryCatch(
  glue::glue(template_text,
             .open = "{{", .close = "}}",
             .envir = render_env,
             .trim = FALSE),
  error = function(e) {
    message("FATAL during template render: ", conditionMessage(e))
    quit(status = 1L)
  }
)

# --- Post-render sanity check ----------------------------------------------
# Any remaining "{{" or "}}" in the rendered output means a placeholder
# wasn't substituted (typo in key name, double-brace literal that should
# have been escaped, etc.). Bail loudly rather than committing a broken
# README.

if (grepl("\\{\\{|\\}\\}", rendered)) {
  message("FATAL: rendered output contains leftover placeholders ({{ or }}).")
  message("       Likely template typo. Search the output for '{{' to find it.")
  # Write the broken output (next to the intended output path) for inspection
  broken_path <- paste0(OUTPUT_PATH, ".broken")
  writeLines(as.character(rendered), con = file(broken_path,
                                                  encoding = "UTF-8"))
  message(sprintf("       Wrote broken output to %s for inspection.", broken_path))
  quit(status = 2L)
}

# --- Write the output ------------------------------------------------------
# Explicit UTF-8 connection. writeLines with a connection avoids the default
# system-encoding behavior on Windows.

con <- file(OUTPUT_PATH, open = "wb", encoding = "UTF-8")
writeLines(as.character(rendered), con = con, useBytes = TRUE)
close(con)

message(sprintf("build_readme.R: wrote %s (%d bytes)",
                OUTPUT_PATH, file.info(OUTPUT_PATH)$size))
