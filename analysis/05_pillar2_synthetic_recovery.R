#' analysis/05_pillar2_synthetic_recovery.R
#' Pillar 2: synthetic recovery of the HLIML estimator (Tier 1a/1b).
#'
#' If RERUN_PILLARS, regenerate by sourcing the validation harness; otherwise
#' read the published CSVs from data/derived/validation/. Reads globals
#' RERUN_PILLARS, DERIVED_VAL from 00_setup.R / master.R.
#'
#' SCAFFOLD (N+10): rerun/read branch is final; figure code pending Section 10.

if (isTRUE(RERUN_PILLARS)) {
  message("05_pillar2: RERUN_PILLARS -> sourcing validation/capture_liml_validation.R")
  source("validation/capture_liml_validation.R")
  tier1a <- data.table::fread("docs/methodology/liml_validation_tier1a.csv")
  tier1b <- data.table::fread("docs/methodology/liml_validation_tier1b.csv")
} else {
  tier1a <- data.table::fread(file.path(DERIVED_VAL, "liml_validation_tier1a.csv"))
  tier1b <- data.table::fread(file.path(DERIVED_VAL, "liml_validation_tier1b.csv"))
}

# --- Tier 1a: recovery across the sigma x omega grid -----------------------
# Columns: sigma_true, omega_true, success_rate, sigma_med, sigma_bias,
#          omega_med, omega_bias, sigma_cov, omega_cov, med_fstat
fig1a <- ggplot(tier1a, aes(x = factor(sigma_true), y = factor(omega_true),
                            fill = success_rate)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.0f%%", 100 * success_rate)), size = 3) +
  scale_fill_gradient(low = "#fee8c8", high = "#e34a33",
                      labels = scales::percent) +
  labs(title = "HLIML synthetic recovery: success rate by sigma x omega",
       x = expression(sigma[true]), y = expression(omega[true]),
       fill = "success") +
  theme_paper()
save_figure(fig1a, "05_pillar2_tier1a_success_grid")
save_table(tier1a, "05_pillar2_tier1a")

# --- Tier 1b: success rate vs sample size ----------------------------------
# Columns: J, T, n_obs, sigma_bias, omega_bias, success_rate
fig1b <- ggplot(tier1b, aes(x = n_obs, y = success_rate)) +
  geom_line(colour = "grey60") +
  geom_point(aes(size = J)) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "HLIML recovery: success rate vs sample size",
       subtitle = "Selection-bias signature as n grows",
       x = "n observations", y = "success rate", size = "J") +
  theme_paper()
save_figure(fig1b, "05_pillar2_tier1b_success_vs_n")
save_table(tier1b, "05_pillar2_tier1b")

message("05_pillar2_synthetic_recovery.R: Tier 1a grid (", nrow(tier1a),
        " cells), Tier 1b trajectory (", nrow(tier1b), " points)")
