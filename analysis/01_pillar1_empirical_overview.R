#' analysis/01_pillar1_empirical_overview.R
#' Pillar 1 (empirical core): headline sigma / gamma distributions.
#' Reads `stage1` and `stage2b` from 00_setup.R. Writes a figure + table.
#'
#' Authored N+12 against the published data/derived/ schema:
#'   stage1:  importer, good, sigma, omega, ..., adjust, final_source,
#'            hliml_status, status (280,649 rows)
#'   stage2b: exporter, importer, good, sigma, gamma, gamma_se,
#'            gamma_se_status, tier, ... (8,128,124 rows)

# adjust class -> readable label (memory #19): 0 HLIML interior,
# 1 Step 2 fallback, 4 sigma clamped, 5 omega clamped, NA = not estimated.
.adjust_label <- function(a) factor(
  data.table::fcase(
    a == 0L, "HLIML interior",
    a == 1L, "Step 2 fallback",
    a %in% c(4L, 5L), "Clamped",
    default = "Not estimated"
  ),
  levels = c("HLIML interior", "Step 2 fallback", "Clamped", "Not estimated")
)

s1 <- data.table::copy(stage1)
s1[, adjust_class := .adjust_label(adjust)]

# --- Figure: sigma density, interior vs fallback (finite, plotted range) ---
s1_plot <- s1[is.finite(sigma) & adjust_class %in%
                c("HLIML interior", "Step 2 fallback")]
fig <- ggplot(s1_plot, aes(x = sigma, fill = adjust_class)) +
  geom_density(alpha = 0.5, colour = NA) +
  coord_cartesian(xlim = c(0, 15)) +
  labs(title = "Import-demand elasticity (sigma) by estimator provenance",
       x = expression(sigma), y = "density", fill = NULL) +
  theme_paper()
save_figure(fig, "01_pillar1_empirical_overview")

# --- Table: headline medians / IQR by adjust class -------------------------
summ <- s1[is.finite(sigma), .(
  n          = .N,
  sigma_med  = median(sigma),
  sigma_q25  = quantile(sigma, 0.25),
  sigma_q75  = quantile(sigma, 0.75)
), by = adjust_class][order(adjust_class)]
# gamma headline from stage2b (country-pair elasticities)
g_med <- stage2b[is.finite(gamma), median(gamma)]
summ[, gamma_med_all := g_med]
save_table(summ, "01_pillar1_empirical_overview")

message("01_pillar1_empirical_overview.R: sigma median (all finite) = ",
        round(s1[is.finite(sigma), median(sigma)], 3),
        "; gamma median = ", round(g_med, 3))
