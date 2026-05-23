#' analysis/06_pillar3_se_calibration.R
#' Pillar 3: standard-error calibration Monte Carlo (4 regimes x 3 formulas).
#'
#' RERUN_PILLARS branch as in 05_*.R. Reads RERUN_PILLARS, DERIVED_VAL.
#'
#' SCAFFOLD (N+10): branch final; figure code pending Section 10.

if (isTRUE(RERUN_PILLARS)) {
  message("06_pillar3: RERUN_PILLARS -> sourcing validation/monte_carlo_se.R")
  source("validation/monte_carlo_se.R")
  se_summary <- data.table::fread("docs/methodology/se_calibration_mc_summary.csv")
} else {
  se_summary <- data.table::fread(file.path(DERIVED_VAL, "se_calibration_mc_summary.csv"))
}

# --- Calibration ratio by formula x regime ---------------------------------
# Columns: regime, formula, n_params, med_ratio, mad_ratio, pct_err
# med_ratio = median(estimated SE / true SE); 1.0 = perfectly calibrated.
# pen_gn (penalized Gauss-Newton) is the production formula; it should sit
# within +/-7% (med_ratio in [0.93, 1.07]) across all regimes, while
# sandwich under-covers without shrinkage and unp_gn over-covers with it.
se_summary[, formula := factor(formula,
  levels = c("unp_gn", "sandwich", "pen_gn"))]

fig <- ggplot(se_summary, aes(x = regime, y = med_ratio,
                              colour = formula, group = formula)) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "grey50") +
  geom_hline(yintercept = c(0.93, 1.07), linetype = "dotted",
             colour = "grey70") +
  geom_point(size = 2.5) +
  geom_line(alpha = 0.5) +
  labs(title = "SE calibration: median(estimated / true) by formula x regime",
       subtitle = "Dashed = perfect; dotted = +/-7% band",
       x = NULL, y = "median ratio", colour = "SE formula") +
  theme_paper() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))
save_figure(fig, "06_pillar3_se_calibration")
save_table(se_summary, "06_pillar3_se_calibration")

pen <- se_summary[formula == "pen_gn"]
message("06_pillar3_se_calibration.R: pen_gn med_ratio range [",
        round(min(pen$med_ratio), 3), ", ", round(max(pen$med_ratio), 3), "]")
