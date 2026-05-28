#!/usr/bin/env Rscript
# scripts/build_readme.R
#
# Generate README.md from README.template.md and the JSON files in results/.
# Run from the repo root. CI runs this then diffs the output against the
# committed README.md and fails on any difference; that is the lock that
# prevents prose from drifting from data. See docs/methodology/build_readme.md
# (forthcoming) for the full architecture.
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

# Generic numeric to N significant figures (default 3): 2.875208 -> "2.875"
format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")

# --- Asymmetry conditional -------------------------------------------------
# stage2b$n_importers_asymmetry_vs_stage1 = stage1.n_importers - stage2b.n_importers.
# Currently 1. Prose has to change shape on 0 and >1; the helper encapsulates
# all three branches so the template stays readable.

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
render_env$format_num <- format_num
render_env$asymmetry_phrase <- asymmetry_phrase

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
