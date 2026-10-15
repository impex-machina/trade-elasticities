#' analysis/01_pillar1_empirical_overview.R
#' Pillar 1 (empirical core): headline sigma / gamma distributions.
#' Reads `stage1` and `stage2b` (published rows) from 00_setup.R. Writes a
#' figure + a table and prints the README's headline sigma.
#'
#' Schema (published data/derived/):
#'   stage1:  importer, good, sigma, omega, ..., adjust, final_source,
#'            status, ... (280,649 rows, one per importer x HS4 cell)
#'   stage2b: exporter, importer, good, sigma, sigma_source, gamma, tier,
#'            convergence, ... (published rows; 00_setup.R sets aside the
#'            rows the tail trim flagged)
#'
#' (patch 0116, fresh-eyes audit #7) Routes follow the shipped Stage-1
#' coding: cells with status "ok" by adjust -- 0 HLIML interior; 1 Step 2;
#' 4 / 5 Step 2 with sigma / omega clamped at a cap; 6 / 7 / 8 constrained
#' boundary HLIML optima on the omega floor / at the sigma cap / at the omega
#' cap (since v0.6.0) -- and every other cell "No estimate". Through patch
#' 0115 this script knew adjust 0 / 1 / 4 / 5 only: the boundary optima (20%
#' of the universe, 31% of the cells with an estimate) were labelled "Not
#' estimated" and left out of the density, and the console line printed the
#' Stage-1 median over every finite sigma while the README said master.R
#' printed the published median.

.route_class <- function(status, adjust) {
  ok <- status %in% "ok"
  factor(data.table::fcase(
    ok & adjust %in% 0L,          "HLIML interior",
    ok & adjust %in% 1L,          "Step 2",
    ok & adjust %in% c(4L, 5L),   "Step 2, clamped at a cap",
    ok & adjust %in% 6L,          "Boundary: omega floor",
    ok & adjust %in% 7L,          "Boundary: sigma cap",
    ok & adjust %in% 8L,          "Boundary: omega cap",
    ok,                           "Other (ok)",
    default =                     "No estimate"),
    levels = c("HLIML interior", "Step 2", "Step 2, clamped at a cap",
               "Boundary: omega floor", "Boundary: sigma cap", "Boundary: omega cap",
               "Other (ok)", "No estimate"))
}

s1 <- data.table::copy(stage1)
s1[, route := .route_class(status, adjust)]

# --- Figure: sigma density on the routes where sigma is free ---------------
# (the clamped Step-2 cells and the sigma-cap boundary sit at the cap itself)
free <- c("HLIML interior", "Step 2", "Boundary: omega floor", "Boundary: omega cap")
s1_plot <- s1[is.finite(sigma) & route %in% free]
s1_plot[, route := droplevels(route)]
fig <- ggplot(s1_plot, aes(x = sigma, fill = route)) +
  geom_density(alpha = 0.45, colour = NA) +
  coord_cartesian(xlim = c(1, 15)) +
  labs(title = "Import-demand elasticity (sigma) by Stage-1 route",
       subtitle = "Cells with an estimate whose sigma is free (clamped and sigma-cap cells omitted)",
       x = expression(sigma), y = "density", fill = NULL) +
  theme_paper()
save_figure(fig, "01_pillar1_empirical_overview")

# --- Table: cells, share of the universe and sigma by route ---------------
summ <- s1[, .(
  n            = .N,
  pct_universe = 100 * .N / nrow(s1),
  sigma_med    = if (any(is.finite(sigma) & status %in% "ok")) median(sigma[is.finite(sigma) & status %in% "ok"]) else NA_real_,
  sigma_q25    = if (any(is.finite(sigma) & status %in% "ok")) unname(quantile(sigma[is.finite(sigma) & status %in% "ok"], 0.25)) else NA_real_,
  sigma_q75    = if (any(is.finite(sigma) & status %in% "ok")) unname(quantile(sigma[is.finite(sigma) & status %in% "ok"], 0.75)) else NA_real_
), by = route][order(route)]

# --- Published Stage-2b sigma and gamma (the README's headline numbers) ----
s2 <- stage2b
is_est <- !is.na(s2$tier) & s2$tier < 3L & !(s2$convergence %in% -1L)
g_med <- median(s2$gamma[is.finite(s2$gamma)])
g_med_est <- median(s2$gamma[is_est & is.finite(s2$gamma)])
summ[, `:=`(gamma_med_published = g_med, gamma_med_directly_estimated = g_med_est)]
save_table(summ, "01_pillar1_empirical_overview")

sig_pub <- median(s2$sigma, na.rm = TRUE)
fb_note <- ""
if ("sigma_source" %in% names(s2)) {
  fb <- !(s2$sigma_source %in% "estimated")
  if (any(fb)) fb_note <- sprintf(" [the fallback sigma %.4f is on %.1f%% of rows; median over rows with a cell-specific sigma %.3f]",
                                  s2$sigma[which(fb)[1]], 100 * mean(fb), median(s2$sigma[!fb], na.rm = TRUE))
}
message(sprintf(paste0("01_pillar1_empirical_overview.R: published sigma median (Stage-2b rows, the README's headline) = %.3f%s; ",
                       "Stage-1 sigma median over cells with an estimate = %.3f; gamma median = %.3f (directly estimated rows %.3f)"),
                sig_pub, fb_note, median(s1$sigma[s1$status %in% "ok" & is.finite(s1$sigma)]), g_med, g_med_est))
