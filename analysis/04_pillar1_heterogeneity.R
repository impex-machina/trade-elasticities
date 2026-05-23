#' analysis/04_pillar1_heterogeneity.R
#' Pillar 1: within-pair dispersion of gamma, and gamma by HS section.
#' Reads `stage2b` from 00_setup.R.
#'
#' Authored N+12. Mirrors docs/audits/heterogeneity_report_legacy.md but
#' driven from the published stage2b output. `good` is the HS4 code stored
#' as a CHARACTER with leading zeros (e.g. "0302"); the HS section is keyed
#' off the leading two digits (HS chapter).

s2b <- data.table::copy(stage2b)
s2b <- s2b[is.finite(gamma)]
# HS chapter = first 2 chars of the zero-padded HS4 code.
s2b[, hs_chapter := substr(good, 1, 2)]

# --- Within-(importer) dispersion of gamma across exporters ----------------
# MAD of gamma within each importer x product cell across exporters.
within <- s2b[, .(
  n_exp   = .N,
  gamma_mad = median(abs(gamma - median(gamma)))
), by = .(importer, good)][n_exp >= 2]
save_table(within[, .(
  n_cells   = .N,
  mad_med   = median(gamma_mad),
  mad_q75   = quantile(gamma_mad, 0.75)
)], "04_pillar1_within_pair_mad")

# --- Figure: gamma distribution by HS chapter (boxplot, trimmed) -----------
by_chap <- s2b[, .(gamma_med = median(gamma), n = .N), by = hs_chapter][
  order(hs_chapter)]
fig <- ggplot(s2b[gamma > quantile(gamma, 0.01) &
                  gamma < quantile(gamma, 0.99)],
              aes(x = hs_chapter, y = gamma)) +
  geom_boxplot(outlier.shape = NA, fill = "grey80", linewidth = 0.3) +
  labs(title = "Export-supply elasticity (gamma) by HS chapter",
       x = "HS chapter", y = expression(gamma)) +
  theme_paper() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 5))
save_figure(fig, "04_pillar1_heterogeneity", height = 5)
save_table(by_chap, "04_pillar1_gamma_by_hs_chapter")

message("04_pillar1_heterogeneity.R: ", nrow(by_chap), " HS chapters; ",
        nrow(within), " multi-exporter cells")
