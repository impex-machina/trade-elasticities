#' analysis/07_pillar4_hliml_vs_gmm.R
#' Pillar 4: HLIML vs Feenstra GMM comparison (Tier 4).
#'
#' RERUN_PILLARS branch as in 05_*.R. NB: re-running Tier 4 needs the BACI
#' cache + GMM archive on disk (EC2-class inputs); the default read-published
#' path is the norm for a laptop. Reads RERUN_PILLARS, DERIVED_VAL.
#'
#' SCAFFOLD (N+10): branch final; figure code pending Section 10.

if (isTRUE(RERUN_PILLARS)) {
  message("07_pillar4: RERUN_PILLARS -> sourcing validation/capture_tier4_validation.R")
  message("  (requires BACI cache + Feenstra GMM archive on disk; see header)")
  source("validation/capture_tier4_validation.R")
  tier4 <- data.table::fread("docs/methodology/tier4_comp.csv")
} else {
  tier4 <- data.table::fread(file.path(DERIVED_VAL, "tier4_comp.csv"))
}

# Also load the adjust-joined comparison for stratification (memory #17).
if (!isTRUE(RERUN_PILLARS)) {
  tier4_adj <- data.table::fread(
    file.path(DERIVED_VAL, "tier4_comp_with_adjust.csv"))
} else {
  tier4_adj <- data.table::fread("docs/methodology/tier4_comp_with_adjust.csv")
}

# --- HLIML vs GMM scatter --------------------------------------------------
# tier4: cell_id, sigma_new (GMM), omega_new, sigma_stage1 (HLIML).
# Structural rank correlation ~0.20 across all subsettings (memory #17).
rho_all <- suppressWarnings(
  cor(tier4$sigma_stage1, tier4$sigma_new, method = "spearman",
      use = "complete.obs"))

fig <- ggplot(tier4[is.finite(sigma_stage1) & is.finite(sigma_new)],
              aes(x = sigma_stage1, y = sigma_new)) +
  geom_point(alpha = 0.4, size = 1) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed",
              colour = "grey50") +
  coord_cartesian(xlim = c(0, 15), ylim = c(0, 15)) +
  labs(title = "Tier 4: HLIML vs Feenstra GMM sigma",
       subtitle = sprintf("Spearman rho = %.2f (structural)", rho_all),
       x = expression(sigma[HLIML]), y = expression(sigma[GMM])) +
  theme_paper()
save_figure(fig, "07_pillar4_hliml_vs_gmm")

# --- Stratified by adjust flag (interior vs Step 2 fallback) ---------------
# adjust 0 = HLIML interior, 1 = Step 2 fallback (memory #17).
strat <- tier4_adj[adjust %in% c(0L, 1L) &
                   is.finite(sigma_stage1) & is.finite(sigma_new),
  .(n = .N,
    med_ratio = median(sigma_new / sigma_stage1),
    spearman  = cor(sigma_stage1, sigma_new, method = "spearman")),
  by = .(adjust_class = data.table::fifelse(
    adjust == 0L, "HLIML interior", "Step 2 fallback"))]
save_table(strat, "07_pillar4_stratified_by_adjust")
save_table(tier4, "07_pillar4_comp")

message("07_pillar4_hliml_vs_gmm.R: overall Spearman = ", round(rho_all, 3),
        " (n = ", nrow(tier4), ")")
