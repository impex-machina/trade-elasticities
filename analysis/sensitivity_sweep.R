# analysis/sensitivity_sweep.R
# Sensitivity of the sigma_robust screen to its two thresholds, K_POLE and
# INFL_THRESH. Recomputes the CELL-LEVEL flag exactly as the pipeline does
# (assess_sigma_robust, grouped by importer x good), row-weighted to match the
# reported robust fraction, with a sanity check that the recompute reproduces
# the stored flag at the production defaults (K_POLE = 2.5, INFL_THRESH = 2.0).
#
# Standalone: needs only the Stage-2b output. master.R does NOT source this --
# its loader globs analysis/^\d+_.*\.R and this file is intentionally unnumbered,
# so it never runs as part of the figure path. Run it directly:
#   Rscript analysis/sensitivity_sweep.R
# It reads the Stage-2b table that scripts/download_outputs.R places under
# data/derived/stage2b/, falling back to an ad-hoc copy in ~/Downloads.

suppressMessages(library(data.table))

## ---- Stage-2b output: repo path first, ~/Downloads fallback ----
f <- "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"
if (!file.exists(f)) {
  f <- file.path(Sys.getenv("USERPROFILE"), "Downloads",
                 "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
}
if (!file.exists(f)) {
  stop("Stage-2b file not found. Run scripts/download_outputs.R, or stage it ",
       "into data/derived/stage2b/.", call. = FALSE)
}

b2  <- readRDS(f); setDT(b2)
eps <- 1e-6

# Estimated cells only: the screen was applied where sigma_robust is not NA.
# NA = Tier-3 imputed cells, which never had per-cell SEs.
est <- b2[!is.na(sigma_robust)]
est[, se_cond  := gamma_se]
est[, se_prop  := abs(dgamma_dsigma) * sigma_se]
est[, infl_row := fifelse(is.finite(se_cond) & se_cond > 0 & is.finite(se_prop),
                          sqrt(se_cond^2 + se_prop^2) / se_cond, NA_real_)]

# Collapse to the cell (importer x good). sigma & sigma_se are cell-constant.
# clamp uses sigma >= 9.999 as the adjust-in-{4,5} proxy (adjust is not in the
# Stage-2b schema); clamped cells also carry NA sigma_se, so no_se catches them too.
cell <- est[, .(
  n_rows      = .N,
  sigma       = sigma[1],
  sigma_se    = sigma_se[1],
  clamp       = sigma[1] >= 9.999,
  no_se       = !is.finite(sigma_se[1]),
  pole_margin = (sigma[1] - 1 - eps) / sigma_se[1],   # band reaches pole when K_POLE >= this
  max_infl    = suppressWarnings(max(infl_row, na.rm = TRUE)),
  stored_sr   = sigma_robust[1]
), by = .(importer, good)]
cell[!is.finite(max_infl), max_infl := NA_real_]      # all-NA-inflation cells -> NA
N <- sum(cell$n_rows)                                 # total estimated estimate-rows

# Exact transcription of assess_sigma_robust, vectorised over cells.
robust_of <- function(K, INFL) !(
  cell$clamp | cell$no_se |
  (is.finite(cell$pole_margin) & K >= cell$pole_margin) |
  (is.finite(cell$max_infl)    & cell$max_infl > INFL))

# ---- sanity: recompute at production defaults must reproduce the stored flag ----
chk <- robust_of(2.5, 2.0)
cat(sprintf("cells: %s | estimate-rows: %s\n",
            format(nrow(cell), big.mark = ","), format(N, big.mark = ",")))
cat(sprintf("sanity @ (K_POLE=2.5, INFL_THRESH=2.0): recomputed == stored on %.3f%% of cells\n",
            100 * mean(chk == cell$stored_sr)))
cat(sprintf("  row-weighted robust: recomputed %.1f%%  vs  stored %.1f%%  (of estimated rows)\n\n",
            100 * sum(cell$n_rows[chk]) / N,
            100 * sum(cell$n_rows[cell$stored_sr]) / N))

# ---- sweep: row-weighted robust % of estimated rows over the threshold grid ----
Ks <- c(1.5, 2.0, 2.5, 3.0)   # smaller K_POLE -> narrower band -> fewer pole flags -> more robust
Is <- c(1.5, 2.0, 3.0, 5.0)   # larger INFL_THRESH -> fewer inflation flags -> more robust
g  <- CJ(K_POLE = Ks, INFL_THRESH = Is)
g[, robust_pct := vapply(seq_len(.N), function(i)
     round(100 * sum(cell$n_rows[robust_of(K_POLE[i], INFL_THRESH[i])]) / N, 1), numeric(1))]

cat("Robust % of ESTIMATED estimate-rows  (production screen = K_POLE 2.5, INFL_THRESH 2.0):\n")
print(dcast(g, K_POLE ~ INFL_THRESH, value.var = "robust_pct"))
cat(sprintf("\n(Multiply by N/nrow(b2) = %.3f to convert to '%% of ALL rows incl. Tier-3 imputed'\n",
            N / nrow(b2)))
cat(" -- i.e. the defaults map to the ~16.5%% headline.)\n")
