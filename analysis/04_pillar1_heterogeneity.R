#' analysis/04_pillar1_heterogeneity.R
#' Pillar 1: heterogeneity of gamma -- within an (importer, product) cell
#' across exporters, and across HS chapters. Reads `stage2b` (published rows)
#' from 00_setup.R.
#'
#' gamma is the INVERSE export-supply elasticity (Soderbery's gamma; the
#' supply elasticity is 1 / gamma).
#'
#' (patch 0116, fresh-eyes audit #7) Through patch 0115 the figure was titled
#' "Export-supply elasticity (gamma)", and the within-cell MAD and the chapter
#' boxplots ran over every row, including the Tier-3 rows (26.8% of the
#' shipped table) whose gamma IS the good-level prior: imputed values read as
#' data, deflating within-cell dispersion wherever Tier 3 is common. The MAD
#' and the figure now use the directly estimated rows (tier 0-2, not imputed);
#' the chapter table keeps the all-rows median beside the estimated one.

s2b <- data.table::copy(stage2b)
s2b <- s2b[is.finite(gamma)]
s2b[, est := !is.na(tier) & tier < 3L & !(convergence %in% -1L)]
s2b[, hs_chapter := substr(good, 1, 2)]
s2e <- s2b[est == TRUE & gamma > 0]

# --- Within-cell dispersion (directly estimated exporters) -----------------
within <- s2e[, .(
  n_exp     = .N,
  gamma_mad = median(abs(gamma - median(gamma)))
), by = .(importer, good)][n_exp >= 2]
save_table(within[, .(
  n_cells   = .N,
  mad_med   = median(gamma_mad),
  mad_q75   = quantile(gamma_mad, 0.75)
)], "04_pillar1_within_pair_mad")

# --- By HS chapter ----------------------------------------------------------
by_chap <- s2b[, .(
  gamma_med_estimated = if (any(est)) median(gamma[est]) else NA_real_,
  n_estimated         = sum(est),
  gamma_med_all       = median(gamma),
  n_all               = .N,
  share_tier3         = mean(tier %in% 3L)
), by = hs_chapter][order(hs_chapter)]

fig <- ggplot(s2e[gamma > quantile(gamma, 0.01) & gamma < quantile(gamma, 0.99)],
              aes(x = hs_chapter, y = gamma)) +
  geom_boxplot(outlier.shape = NA, fill = "grey80", linewidth = 0.3) +
  labs(title = "Inverse export-supply elasticity (gamma) by HS chapter",
       subtitle = "Directly estimated rows (Tier 3, the good-level prior, excluded); 1st-99th percentile",
       x = "HS chapter", y = expression(gamma)) +
  theme_paper() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 5))
save_figure(fig, "04_pillar1_heterogeneity", height = 5)
save_table(by_chap, "04_pillar1_gamma_by_hs_chapter")

message("04_pillar1_heterogeneity.R: ", nrow(by_chap), " HS chapters; ",
        nrow(within), " cells with >= 2 directly estimated exporters")
