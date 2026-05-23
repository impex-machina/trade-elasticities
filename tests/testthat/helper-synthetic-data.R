# ============================================================================
# helper-synthetic-data.R
#
# Generates a tiny synthetic trade panel matching the schema that
# prepare_data() produces. By feeding this through estimate_all_fixed_sigma()
# via the `prepared_dt` argument, the test bypasses BACI loading entirely
# and runs in seconds.
#
# The shape is sized to:
#   - have at least one importer/product cell that qualifies for Tier-1
#     classification under the test config (lowered thresholds)
#   - produce enough first-differenced periods for the optimizer to find
#     a non-degenerate gamma estimate (so SE computation actually fires)
#   - stay under 60s wall time on a Windows laptop with ncores=1
# ============================================================================

#' Build a synthetic prepared_dt for Stage 2b end-to-end testing.
#'
#' Schema matches the data.table returned by prepare_data() — see
#' feen94_het_baci.R lines 1122-1140. By bypassing prepare_data() we
#' skip BACI file loading, regional aggregation, HS6->HS4 collapse,
#' and unit-value outlier filtering.
#'
#' DGP: log-prices follow a random walk; market shares respond to prices
#' with an approximate elasticity matching sigma ~ 4, gamma ~ 1. Exact
#' parameter recovery isn't the goal — the optimizer just needs enough
#' identification to converge in `ok` status.
#'
#' Importer codes use real ISO numeric strings ("840"=USA, "276"=DEU,
#' "392"=JPN); exporter codes use distinct numeric strings. Goods use
#' real HS4 codes ("8501"=electric motors, "8504"=transformers) — harmless,
#' but makes log output legible if you ever debug by eye.
#'
#' @param seed RNG seed (default 42 — keeps the test bit-for-bit
#'   reproducible run-to-run on the same R version).
#' @return data.table with columns matching prepare_data() output.
make_synthetic_baci <- function(seed = 42L) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("data.table required for make_synthetic_baci()")
  }
  set.seed(seed)
  
  importers <- c("840", "276", "392")
  exporters <- c("156", "410", "036", "076", "356")  # CHN, KOR, AUS, BRA, IND
  goods     <- c("8501", "8504")
  years     <- 2015:2024  # 10 years -> 9 first-differenced periods
  
  grid <- data.table::CJ(
    year     = years,
    good     = goods,
    importer = importers,
    exporter = exporters,
    sorted   = FALSE
  )
  
  # Drop self-trade: an exporter doesn't import from itself. We don't
  # actually have overlap here (importers and exporters are disjoint
  # numeric codes), but the guard makes the helper robust if you ever
  # expand the country sets.
  grid <- grid[importer != exporter]
  
  # --- DGP --------------------------------------------------------------
  # Each (importer, exporter, good) panel gets a starting log-price drawn
  # from N(0, 1), then evolves as a random walk with small drift. Quantity
  # responds to price with approximate elasticity 4 in *levels*, plus
  # exporter-quality and importer-demand fixed effects, plus i.i.d. noise.
  #
  # The point isn't to recover sigma=4 / gamma=1 precisely — Stage 2b
  # extracts them from first-differenced cross-product structure that
  # this simple DGP isn't designed to satisfy exactly. The point is that
  # the optimizer finds a finite, non-degenerate gamma for enough cells
  # that SE computation runs on at least one of them.
  data.table::setorder(grid, importer, exporter, good, year)
  
  # Assign a per-row panel id. data.table's .GRP inside an `:=` with `by`
  # gives each row the integer index of its group; that's exactly the
  # vector we want for indexing into per-panel parameter draws below.
  grid[, panel_id := .GRP, by = .(importer, exporter, good)]
  
  # Per-panel starting log price + drift
  n_panels <- data.table::uniqueN(grid$panel_id)
  lp_start <- stats::rnorm(n_panels, mean = 1.0, sd = 0.5)
  lp_drift <- stats::rnorm(n_panels, mean = 0.0, sd = 0.05)
  
  # Random walk log-prices
  grid[, year_idx := year - min(year)]
  grid[, lp := lp_start[panel_id] + lp_drift[panel_id] * year_idx +
         stats::rnorm(.N, 0, 0.15)]
  
  # Quantity: respond to price with elasticity ~ -4 (so sigma ~ 4)
  # plus exporter-quality fixed effect (correlates with prices a bit)
  # plus importer-demand level
  exp_fe <- stats::setNames(stats::rnorm(length(exporters), 0, 0.3), exporters)
  imp_fe <- stats::setNames(stats::rnorm(length(importers), 5, 0.5), importers)
  
  grid[, lq := imp_fe[importer] + exp_fe[exporter] - 4.0 * lp +
         stats::rnorm(.N, 0, 0.2)]
  
  grid[, `:=`(cusval   = exp(lp + lq),  # value = price * quantity
              quantity = exp(lq))]
  
  # Sanity: drop any non-finite rows from the DGP (shouldn't happen)
  grid <- grid[is.finite(cusval) & is.finite(quantity) &
                 cusval > 0 & quantity > 0]
  
  # --- Replicate prepare_data() transformations ------------------------
  # See feen94_het_baci.R lines 1122-1140.
  
  # Set t (1-indexed time within the sample, used by all moment construction)
  minyear <- min(grid$year)
  grid[, t := as.integer(year - minyear + 1L)]
  
  # Recompute log price from value/quantity (mirrors prepare_data)
  grid[, lp := log(cusval / quantity)]
  
  # Import-side shares: share of (t, importer, good) total going to each exporter
  grid[, imp_total := sum(cusval), by = .(t, importer, good)]
  grid[, `:=`(s_imp  = cusval / imp_total,
              ls_imp = log(cusval / imp_total))]
  
  # Export-side shares: share of (t, exporter, good) total going to each importer
  grid[, exp_total := sum(cusval), by = .(t, exporter, good)]
  grid[, `:=`(s_exp  = cusval / exp_total,
              ls_exp = log(cusval / exp_total))]
  
  # First differences within (importer, exporter, good) panels
  data.table::setorder(grid, importer, exporter, good, t)
  grid[, `:=`(lp_dif     = lp     - data.table::shift(lp,     1L),
              ls_imp_dif = ls_imp - data.table::shift(ls_imp, 1L),
              ls_exp_dif = ls_exp - data.table::shift(ls_exp, 1L),
              period_count = .N),
       by = .(importer, exporter, good)]
  
  # Drop the first observation per panel (NA lp_dif)
  grid <- grid[!is.na(lp_dif)]
  
  # Drop the helper columns we added during DGP (not in prepare_data output)
  grid[, c("year_idx", "lq", "panel_id") := NULL]
  
  grid[]
}


#' Build the minimal cfg list for Stage 2b on synthetic data.
#'
#' Lowers tier thresholds so that the small synthetic fixture (3 importers,
#' 5 exporters, 9 first-differenced periods) actually produces Tier-1
#' classifications. Default tier1_min_dests=3 would push all exporters to
#' Tier 3 since each ships to only 2 non-focal importers in the fixture.
#'
#' @return A cfg list satisfying validate_config() requirements plus the
#'   Stage 2b-specific fields (sigma_lookup, shrinkage_priors, etc.).
make_synthetic_cfg <- function() {
  # The 6 (importer x good) cells we'll see in the synthetic data
  importers <- c("840", "276", "392")
  goods     <- c("8501", "8504")
  
  sigma_lookup <- data.table::CJ(importer = importers, good = goods)
  sigma_lookup[, sigma := 4.0]  # plausible value; Stage 2b just uses it as fixed
  
  shrinkage_priors <- data.table::data.table(
    good = goods,
    ln_gamma_prior = c(0.0, 0.0)  # prior gamma = exp(0) = 1
  )
  
  cfg <- list(
    # required by validate_config (filepath is checked by file.exists)
    filepath          = tempdir(),
    value             = "v",
    quan              = "q",
    good              = "hs4",
    importer          = "i",
    exporter          = "j",
    time              = "year",
    minyear           = 2015L,
    maxyear           = 2024L,
    agg_level         = "hs4",
    use_regions       = FALSE,
    min_exporters     = 2L,
    min_destinations  = 1L,
    min_periods       = 3L,
    sigma_start       = 4.0,
    gamma_start       = 1.0,
    sigma_V_default   = 4.0,
    gamma_V_default   = 1.0,
    tail_trim_pct     = NA_real_,  # no trimming on tiny sample
    
    # Stage 2b specific
    sigma_lookup      = sigma_lookup,
    sigma_fallback    = 4.0,
    shrinkage_priors  = shrinkage_priors,
    shrinkage_lambda  = 0.05,
    
    # Tier thresholds — lowered for the fixture
    # Default tier1_min_dests=3 won't classify any exporter in a
    # 3-importer fixture as Tier 1. Lower it to 1 so that exporters
    # shipping to >= 1 non-focal importer qualify.
    tier1_min_periods = 3L,
    tier1_min_dests   = 1L,
    tier2_min_periods = 2L,
    
    # Unit-value outlier filter: NA disables (we already produce clean data)
    uv_outlier_threshold = NA_real_
  )
  
  cfg
}