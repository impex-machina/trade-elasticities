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
boundary_phrase <- function(rs, n_cells) {
  bt <- rs[["boundary_total"]]
  if (is.null(bt) || !is.finite(bt) || bt == 0) return("")
  # \u03c9 / \u03c3 = omega / sigma, written as Unicode escapes so this file
  # stays ASCII-clean (see asymmetry_phrase); the literal Greek letters used
  # here before patch 0045 rendered as raw bytes under a non-UTF-8 locale and
  # broke the README lock check there.
  sprintf("; a further %s (%s cells) are constrained boundary HLIML optima -- %s on the \u03c9 floor, %s at the \u03c3 cap, %s at the \u03c9 cap -- routed only where both the closed-form HLIML point and Step 2 were inadmissible (`final_source == \"hliml_boundary\"`, no SE)",
          format_pct(bt, n_cells), format_int(bt),
          format_int(rs[["boundary_omega_floor"]]), format_int(rs[["boundary_sigma_cap"]]),
          format_int(rs[["boundary_omega_cap"]]))
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
render_env$sigma_bias_sign_phrase <- sigma_bias_sign_phrase
render_env$manifest_n_files <- manifest_n_files

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
