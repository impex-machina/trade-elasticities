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
# --- end freshness helpers (patch 0109) --------------------------------------

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
    coverage <- sprintf("%s; Test F, the export side against the primitives: exact on export values (residual at the truth at most %.1f%% of the outcome), the shipped share form misses by up to %.1f%% when \u03b3_I \u2260 \u03b3_V", coverage, 100 * va, 100 * sh)
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
  sprintf(" %s %s cells reached that cap; the restart's objective was higher than the discarded point on %s of them (%s), and it had reported convergence on %s, rows that v0.8.2 labelled `ok` at a stalled point (`docs/results/%s.md`).",
          where, format_int(fc[["n_cells"]] + 0L), format_int(fc[["n_nm_worse"]] + 0L), pc(fc[["share_nm_worse"]]),
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
