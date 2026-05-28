#' analysis/00_setup.R
#'
#' Shared setup for the analysis layer. Sourced into the GLOBAL environment
#' by master.R before any pillar script runs, so the objects and helpers it
#' defines are visible to 01_*.R through 07_*.R.
#'
#' Responsibilities:
#'   - load the published Stage 1 / Stage 2 outputs from data/derived/
#'   - load the published validation CSVs (pillars 2/3/4)
#'   - define a shared ggplot2 theme and the figure/table writers
#'
#' Depends on: R/dependencies.R (sourced by master.R), R/load_outputs.R
#'
#' NB: assumes data/derived/ is already populated (master.R calls
#' verify_manifest_complete() before sourcing this). Run
#' scripts/download_outputs.R first if needed.

library(ggplot2)

# --- shared paths ----------------------------------------------------------
DERIVED      <- "data/derived"
DERIVED_S1   <- file.path(DERIVED, "stage1")
DERIVED_S2A  <- file.path(DERIVED, "stage2a")
DERIVED_S2B  <- file.path(DERIVED, "stage2b")
DERIVED_VAL  <- file.path(DERIVED, "validation")

# OUTPUT_DIR is set by master.R; fall back if 00_setup.R is sourced directly.
if (!exists("OUTPUT_DIR")) OUTPUT_DIR <- "analysis/figures"

# --- shared theme ----------------------------------------------------------
theme_paper <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      plot.title       = element_text(face = "bold"),
      legend.position  = "bottom"
    )
}
theme_set(theme_paper())

# --- figure / table writers ------------------------------------------------
# Every pillar script writes figures and tables through these so paths and
# formats stay consistent and master's run log can find them.
save_figure <- function(plot, name, width = 6.5, height = 4.5) {
  path <- file.path(OUTPUT_DIR, paste0(name, ".pdf"))
  ggplot2::ggsave(path, plot, width = width, height = height)
  invisible(path)
}
save_table <- function(x, name) {
  path <- file.path(OUTPUT_DIR, "tables", paste0(name, ".csv"))
  data.table::fwrite(x, path)
  invisible(path)
}

# --- load published outputs ------------------------------------------------
# Pillar 1 (empirical core). Loaded once; pillar-1 scripts read these objects.
stage1 <- readRDS(file.path(
  DERIVED_S1, "baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds"))
stage2b <- readRDS(file.path(
  DERIVED_S2B, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"))

message("00_setup.R: loaded stage1 (", nrow(stage1), " rows) and ",
        "stage2b (", nrow(stage2b), " rows)")

# --- emit summaries for README build artifact ------------------------------
# Architecture: README.md is a generated build artifact. Numbers flow through
# results/*.json (this script) -> build_readme.R (TODO) -> README.md, with a
# CI diff-check between the regeneration and the committed README as the
# lock that prevents prose drifting from data. Full design doc will live at
# docs/methodology/build_readme.md once build_readme.R lands.
#
# Conventions enforced here:
#   - numbers stored at FULL PRECISION (digits = NA); formatting at render
#   - counts emitted as raw numerator/denominator pairs (not pre-divided
#     rates) so denominators are explicit in the JSON and CI can detect
#     drift in either independently
#
# Stock-Yogo: stockyogo_pass is a per-cell logical in stage1 (TRUE = passes
# weak-IV screen, FALSE = fails, NA = not evaluated). The headline fail rate
# (sy_fails / sy_evaluated) excludes NA-status cells from the denominator.

if (!dir.exists("results")) dir.create("results", recursive = TRUE)

emit_json <- function(obj, name) {
  path <- file.path("results", paste0(name, ".json"))
  jsonlite::write_json(obj, path,
                       auto_unbox = TRUE, pretty = TRUE, digits = NA)
  invisible(path)
}

stage1_summary <- list(
  n_cells      = nrow(stage1),
  n_products   = data.table::uniqueN(stage1$good),
  n_importers  = data.table::uniqueN(stage1$importer),
  sy_fails     = sum(!stage1$stockyogo_pass, na.rm = TRUE),
  sy_evaluated = sum(!is.na(stage1$stockyogo_pass))
)

# adjust x final_source cross-tab is the routing-structure source of truth.
# Empirical finding: adjust == 0 <-> final_source == "hliml" (zero leakage);
# adjust in {1, 4, 5} <-> final_source == "step2_weighted"; NA on both sides
# is the pre-HLIML-discard universe (cells dropped before estimation by
# thin-panel / prep-thin / fail_too_few_exporters / all_inversions_failed
# gates).
#
# Code-to-label mapping (from R/liml_estimator.R lines 1041-1094, the
# feasibility-adjustment block):
#   adjust == 0: HLIML admissible (sigma > 1, omega > 0, both under caps)
#   adjust == 1: HLIML failed, Step 2 sigma admissible
#   adjust == 2: HLIML failed, Step 2 omega admissible but sigma not
#                (zero cells in current data)
#   adjust == 3: omega defensively floored to 0.0001 when < 0
#                (zero cells in current data; comment says "shouldn't reach")
#   adjust == 4: Step 2 sigma exceeded sigma_start_cap, clamped to cap
#   adjust == 5: Step 2 omega exceeded omega_start_cap, clamped to cap
#
# Codes 4 and 5 are SUB-CASES of Step 2 fallback (cells that fell to Step 2
# and then produced a value clamped at a cap, not an estimate). The README
# currently presents Step 2 and clamping as parallel categories ("majority
# Step 2, small share clamped"); the data is hierarchical. routing_summary
# below emits the labeled aggregates so prose can be made precise.
xt <- function(adjust_val, fs_val) {
  adjust_match <- if (is.na(adjust_val)) is.na(stage1$adjust)
                  else !is.na(stage1$adjust) & stage1$adjust == adjust_val
  fs_match     <- if (is.na(fs_val))     is.na(stage1$final_source)
                  else !is.na(stage1$final_source) & stage1$final_source == fs_val
  sum(adjust_match & fs_match)
}
stage1_summary$adjust_x_final_source <- list(
  code_0           = list(hliml = xt(0,  "hliml"),
                          step2_weighted = xt(0,  "step2_weighted"),
                          pre_discard    = xt(0,  NA)),
  code_1           = list(hliml = xt(1,  "hliml"),
                          step2_weighted = xt(1,  "step2_weighted"),
                          pre_discard    = xt(1,  NA)),
  code_4           = list(hliml = xt(4,  "hliml"),
                          step2_weighted = xt(4,  "step2_weighted"),
                          pre_discard    = xt(4,  NA)),
  code_5           = list(hliml = xt(5,  "hliml"),
                          step2_weighted = xt(5,  "step2_weighted"),
                          pre_discard    = xt(5,  NA)),
  code_pre_discard = list(hliml = xt(NA, "hliml"),
                          step2_weighted = xt(NA, "step2_weighted"),
                          pre_discard    = xt(NA, NA))
)
rm(xt)

# routing_summary: labeled aggregates over the adjust codes. The seven
# primary fields are mutually exclusive and sum to nrow(stage1); step2_total
# and clamped_total are derived aggregates over subsets of those primaries.
# Field semantics are pinned in the comment block above; here we just count.
stage1_summary$routing_summary <- list(
  hliml_interior        = sum(stage1$adjust == 0L, na.rm = TRUE),
  step2_clean           = sum(stage1$adjust == 1L, na.rm = TRUE),
  step2_omega_only      = sum(stage1$adjust == 2L, na.rm = TRUE),
  omega_negative_floor  = sum(stage1$adjust == 3L, na.rm = TRUE),
  clamped_at_sigma_cap  = sum(stage1$adjust == 4L, na.rm = TRUE),
  clamped_at_omega_cap  = sum(stage1$adjust == 5L, na.rm = TRUE),
  pre_discard           = sum(is.na(stage1$adjust)),
  # Derived aggregates (sums over subsets of the seven primaries above):
  step2_total           = sum(stage1$adjust %in% c(1L, 2L, 3L, 4L, 5L), na.rm = TRUE),
  clamped_total         = sum(stage1$adjust %in% c(4L, 5L), na.rm = TRUE)
)
# Reconciliation: the seven primary (mutually-exclusive) categories must
# sum to nrow(stage1). Loud-fails if a future estimator run adds a new
# adjust code not covered here.
stopifnot(
  with(stage1_summary$routing_summary,
       hliml_interior + step2_clean + step2_omega_only +
       omega_negative_floor + clamped_at_sigma_cap + clamped_at_omega_cap +
       pre_discard) == nrow(stage1)
)

# status breakdown: five headline categories with prose stakes, plus two
# grouped tails (prep_thin_total, thin_panel_total) covering the long tail
# of pre-HLIML discards. The methodology doc can recover finer granularity
# from the rds; the README never references individual thin_panel codes.
stage1_summary$status_breakdown <- list(
  ok                                        = sum(stage1$status == "ok"),
  all_inversions_failed                     = sum(stage1$status == "all_inversions_failed"),
  fail_too_few_exporters                    = sum(stage1$status == "fail_too_few_exporters"),
  step1_fail_singular_QWW                   = sum(stage1$status == "step1_fail_singular_QWW"),
  step2_fail_singular_QWW_fellback_to_step1 = sum(stage1$status == "step2_fail_singular_QWW_fellback_to_step1"),
  prep_thin_total                           = sum(startsWith(stage1$status, "prep_thin_n")),
  thin_panel_total                          = sum(startsWith(stage1$status, "thin_panel_"))
)
# Reconciliation check (script-side, not asserted): the seven counts above
# must sum to nrow(stage1). Failing this would mean the status column gained
# a category not covered here.
stopifnot(sum(unlist(stage1_summary$status_breakdown)) == nrow(stage1))

# provenance_rates: the specific rates the README quotes (or alludes to),
# each as numerator/denominator so the template can render either as
# percentage or as raw fraction, and CI can detect drift in either.
# Derivations:
#   interior_full_universe        = adjust==0 cells / nrow(stage1)
#                                 = final_source=="hliml" / nrow(stage1)  [equivalent per B3]
#   interior_conditional_on_ok    = same numerator / status=="ok" cells
#   step2_full_universe           = adjust in {1,4,5} / nrow(stage1)
#                                 = final_source=="step2_weighted" / nrow(stage1)
n_interior <- sum(stage1$adjust == 0, na.rm = TRUE)
n_step2    <- sum(stage1$adjust %in% c(1L, 4L, 5L), na.rm = TRUE)
n_status_ok <- stage1_summary$status_breakdown$ok
stage1_summary$provenance_rates <- list(
  interior_full_universe     = list(numerator = n_interior, denominator = nrow(stage1)),
  interior_conditional_on_ok = list(numerator = n_interior, denominator = n_status_ok),
  step2_full_universe        = list(numerator = n_step2,    denominator = nrow(stage1))
)
rm(n_interior, n_step2, n_status_ok)

stage2b_dt <- stage2b[!is.na(sigma) & !is.na(gamma)]
stage2b_summary <- list(
  n_cells      = nrow(stage2b_dt),
  n_importers  = data.table::uniqueN(stage2b_dt$importer),
  n_exporters  = data.table::uniqueN(stage2b_dt$exporter),
  n_sigma      = nrow(unique(stage2b_dt[, .(importer, good)])),
  sigma_median = median(stage2b_dt$sigma),
  sigma_q25    = as.numeric(quantile(stage2b_dt$sigma, 0.25)),
  sigma_q75    = as.numeric(quantile(stage2b_dt$sigma, 0.75)),
  gamma_median = median(stage2b_dt$gamma),
  gamma_q25    = as.numeric(quantile(stage2b_dt$gamma, 0.25)),
  gamma_q75    = as.numeric(quantile(stage2b_dt$gamma, 0.75))
)
rm(stage2b_dt)

# Derived: stage1 has one more importer than stage2b. Backs the README claim
# "one importer present at Stage 1 has no country-pair gamma at Stage 2b
# after the minimum-destinations filter." If this drifts to 0 or >1, the
# README prose has to change shape, not just substitute a number — the
# template will branch on this value.
stage2b_summary$n_importers_asymmetry_vs_stage1 <-
  stage1_summary$n_importers - stage2b_summary$n_importers

emit_json(stage1_summary,  "stage1_summary")
emit_json(stage2b_summary, "stage2b_summary")

message("00_setup.R: emitted results/stage1_summary.json (",
        stage1_summary$n_cells, " cells) and ",
        "results/stage2b_summary.json (",
        stage2b_summary$n_cells, " cells)")
