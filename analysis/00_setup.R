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

# B3 / flooring transparency: share of cells whose export-supply parameter
# omega was clamped to its lower admissibility floor (1e-4) rather than
# estimated at an interior point. invert_structural() floors omega *before* the
# feasibility-adjustment block assigns `adjust`, so floored cells read as
# adjust 0/1 and are invisible in routing_summary above; counting omega at the
# floor is the only way to size it from the current output. (The forthcoming
# omega_floored column makes this directly filterable once the estimator is
# re-run.) Backs the root-README flooring bullet's quantified omega-floor share.
stage1_summary$omega_floor <- list(
  n_floor     = sum(stage1$omega <= 1e-4, na.rm = TRUE),
  denominator = nrow(stage1)
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

# --- Hardened limitation figures -------------------------------------------
# Back specific numbers in the README's `sigma` column note and the
# "Known limitations" bullets. All computed from the published Stage 2b
# table so the prose stays locked to the data via build_readme.R's req().
#
# (a) sigma provenance. Stage 2b assigns each cell either a cell-specific
# sigma from the Stage 1 lookup, or — where Stage 1 produced no admissible
# sigma — the GLOBAL-MEDIAN fallback broadcast as a single constant
# (run_estimation.R: median of sigma over sigma>1 & convergence==0). The
# sigma cap (10) is the other constant. Neither is flagged in the Stage 2b
# schema, so we identify them as the two value spikes: the cap is exactly 10;
# the fallback is the most-common NON-cap sigma (one value shared across a
# large block of cells, where genuine cell-specific estimates do not repeat).
sigma_cap_value <- 10
.sig_spikes <- stage2b_dt[sigma != sigma_cap_value, .N, by = sigma][order(-N)]
sigma_fallback_value <- .sig_spikes$sigma[1]
stopifnot(sigma_fallback_value > 1, sigma_fallback_value < sigma_cap_value)
stage2b_summary$sigma_provenance <- list(
  fallback_value = sigma_fallback_value,
  n_fallback     = sum(stage2b_dt$sigma == sigma_fallback_value),
  n_cap          = sum(stage2b_dt$sigma == sigma_cap_value),
  denominator    = nrow(stage2b_dt)
)
rm(.sig_spikes, sigma_cap_value, sigma_fallback_value)

# (b) published-gamma floor. Stage 2b floors gamma at 0 for both the J
# exporters and the reference exporter (estimate_cell_fixed_sigma.R:
# gamma_j_hat <- pmax(d_hat[2:(J+1)], 0); gamma_k_hat <- max(d_hat[1], 0)),
# so all published gamma >= 0 and the floor is gamma == 0. This is the
# published-side counterpart to the Stage 1 omega flooring; Stage 2 shrinkage
# toward good-level priors lifts most floored mass, so this share is much
# smaller than the Stage 1 omega-floor share documented in
# docs/methodology/stage1_README.md.
stage2b_summary$gamma_floor <- list(
  n_floor     = sum(stage2b_dt$gamma <= 0),
  denominator = nrow(stage2b_dt)
)

# (c) gamma_se status composition. gamma_se is conditional on the fixed sigma.
# Status default is "ok" (a clean, usable SE); it is overridden to
# "boundary"/"plateau" for extreme estimates, set to "non_converged" when the
# fit did not converge, and "tier3_prior" for Tier 3 cells assigned the
# regional prior outright (no cell-specific SE). "other" groups every
# non-ok, non-tier3 state (boundary/plateau/non_converged, plus any rows whose
# gamma_se_status was left NA). Backs the "large share of rows carry no
# usable cell-specific SE" claim.
.ses <- stage2b_dt$gamma_se_status
stage2b_summary$se_status <- list(
  ok          = sum(.ses == "ok", na.rm = TRUE),
  tier3_prior = sum(.ses == "tier3_prior", na.rm = TRUE),
  # "other" = everything not ok and not tier3. %in% maps NA to FALSE, so rows
  # with an unrecorded (NA) gamma_se_status are counted here too; the three
  # buckets stay a clean partition of all rows.
  other       = sum(!(.ses %in% c("ok", "tier3_prior"))),
  total       = length(.ses)
)
stopifnot(with(stage2b_summary$se_status, ok + tier3_prior + other == total))
rm(.ses)

# Sigma-robustness screen (gamma_se_total / sigma_robust columns, present once
# Stage 1 sigma uncertainty is propagated into the gamma SEs). TRUE/FALSE are the
# estimated cells the screen passed/failed; NA are Tier-3 imputed cells with no
# per-cell sigma to screen. n_estimated = robust + not_robust backs the
# "of estimated cells" framing. Requires the patched Stage-2b output.
.sr <- stage2b_dt$sigma_robust
stage2b_summary$sigma_robust <- list(
  robust      = sum(.sr, na.rm = TRUE),
  not_robust  = sum(!.sr, na.rm = TRUE),
  tier3_na    = sum(is.na(.sr)),
  n_estimated = sum(!is.na(.sr)),
  total       = length(.sr)
)
stopifnot(with(stage2b_summary$sigma_robust,
               robust + not_robust + tier3_na == total))
rm(.sr)

# Implied export-supply elasticity (1 - gamma)/gamma; its median backs the
# gamma-row worked-example figure. gamma in (0, 1], so the ratio is finite
# except where gamma was floored to 0 (excluded by is.finite).
.elast <- (1 - stage2b_dt$gamma) / stage2b_dt$gamma
stage2b_summary$elast_median <- median(.elast[is.finite(.elast)], na.rm = TRUE)
rm(.elast)

rm(stage2b_dt)

# Derived: stage1 has one more importer than stage2b. Backs the README claim
# "one importer present at Stage 1 has no country-pair gamma at Stage 2b
# after the minimum-destinations filter." If this drifts to 0 or >1, the
# README prose has to change shape, not just substitute a number — the
# template will branch on this value.
stage2b_summary$n_importers_asymmetry_vs_stage1 <-
  stage1_summary$n_importers - stage2b_summary$n_importers

# --- Pillar 2: synthetic recovery (validate_liml.R Tier 1) ----------------
# Reads two committed CSVs in docs/methodology/. Field names mirror CSV
# column names exactly so the chain "validate_liml.R -> CSV -> JSON ->
# template" has no rename steps. Full tables are emitted for CI-locking;
# templates will normally reference the _summary blocks.
#
# Tier 1a: 4x3 grid of (sigma_true, omega_true) -> recovery diagnostics
#   columns: sigma_true, omega_true, success_rate, sigma_med, sigma_bias,
#            omega_med, omega_bias, sigma_cov, omega_cov, med_fstat
# Tier 1b: sample-size sweep -> bias and success rate as n grows
#   columns: J, T, n_obs, sigma_bias, omega_bias, success_rate
#
# Selection-bias caveat (from memory): tier1b success_rate falls as n grows
# (smaller-n runs that converge are the "easy" cells; harder cells reach
# convergence only with more data, dragging the converged subsample's
# success rate downward). The endpoints expose this in the _summary block.

PILLAR2_TIER1A_CSV <- "docs/methodology/liml_validation_tier1a.csv"
PILLAR2_TIER1B_CSV <- "docs/methodology/liml_validation_tier1b.csv"

tier1a <- data.table::fread(PILLAR2_TIER1A_CSV)
tier1b <- data.table::fread(PILLAR2_TIER1B_CSV)

# Reconciliation: tier1a is a 4x3 grid (12 rows), tier1b is a sample-size
# sweep (9 rows per the captured methodology). Hard-fail on row-count drift
# so a future re-run that changes the experimental design surfaces here.
stopifnot(nrow(tier1a) == 12L)
stopifnot(nrow(tier1b) == 9L)

# Order tier1b by n_obs so first/last are smallest/largest sample size
data.table::setorder(tier1b, n_obs)

pillar2_summary <- list(
  tier1a = lapply(seq_len(nrow(tier1a)), function(i) as.list(tier1a[i])),
  tier1a_summary = list(
    min_success_rate    = min(tier1a$success_rate),
    median_success_rate = median(tier1a$success_rate),
    max_success_rate    = max(tier1a$success_rate),
    min_sigma_cov       = min(tier1a$sigma_cov),
    median_sigma_cov    = median(tier1a$sigma_cov)
  ),
  tier1b = lapply(seq_len(nrow(tier1b)), function(i) as.list(tier1b[i])),
  tier1b_summary = list(
    n_obs_smallest               = tier1b$n_obs[1],
    n_obs_largest                = tier1b$n_obs[nrow(tier1b)],
    success_rate_at_smallest_n   = tier1b$success_rate[1],
    success_rate_at_largest_n    = tier1b$success_rate[nrow(tier1b)]
  )
)
rm(tier1a, tier1b)

# --- Pillar 3: SE calibration (monte_carlo_se.R) --------------------------
# Reads the 4-regime x 3-formula summary CSV. The production formula is
# pen_gn (penalized Gauss-Newton); the methodology claim is that its
# med_ratio sits in [0.93, 1.07] across all 4 regimes (within +/-7%).
# We emit pen_gn's per-regime ratios + min/max across regimes + worst
# pct_err so templates can express the calibration band claim with a
# concrete number rather than a hardcoded "+/-7%".
#
# CSV columns: regime, formula, n_params, med_ratio, mad_ratio, pct_err
# The per-param CSV (44 rows) is intentionally NOT emitted — methodology
# doc and figure code consume it directly from disk; no plausible README
# prose needs per-parameter granularity.

PILLAR3_SUMMARY_CSV <- "docs/methodology/se_calibration_mc_summary.csv"

se_summary <- data.table::fread(PILLAR3_SUMMARY_CSV)

# Reconciliation: 4 regimes x 3 formulas = 12 rows. Loud-fail if the
# experimental design changes.
stopifnot(nrow(se_summary) == 12L)
stopifnot(all(c("unp_gn", "sandwich", "pen_gn") %in% se_summary$formula))

pen_gn <- se_summary[formula == "pen_gn"]
stopifnot(nrow(pen_gn) == 4L)  # one row per regime

pillar3_summary <- list(
  regimes = lapply(seq_len(nrow(se_summary)),
                   function(i) as.list(se_summary[i])),
  pen_gn_summary = list(
    n_regimes               = nrow(pen_gn),
    pen_gn_med_ratio_min    = min(pen_gn$med_ratio),
    pen_gn_med_ratio_max    = max(pen_gn$med_ratio),
    pen_gn_pct_err_min      = min(pen_gn$pct_err),
    pen_gn_pct_err_max      = max(pen_gn$pct_err),
    pen_gn_pct_err_worst_abs = max(abs(pen_gn$pct_err))
  )
)
rm(se_summary, pen_gn)

emit_json(stage1_summary,  "stage1_summary")
emit_json(stage2b_summary, "stage2b_summary")
emit_json(pillar2_summary, "pillar2_summary")
emit_json(pillar3_summary, "pillar3_summary")

message("00_setup.R: emitted results/stage1_summary.json (",
        stage1_summary$n_cells, " cells), ",
        "results/stage2b_summary.json (",
        stage2b_summary$n_cells, " cells), ",
        "results/pillar2_summary.json (Tier 1a 4x3 grid + 1b sweep), ",
        "results/pillar3_summary.json (4-regime SE calibration)")
