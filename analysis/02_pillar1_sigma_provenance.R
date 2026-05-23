#' analysis/02_pillar1_sigma_provenance.R
#' Pillar 1: sigma-provenance breakdown (HLIML interior / Step 2 fallback /
#' clamped / not estimated). Reads `stage1` from 00_setup.R.
#'
#' Authored N+12 against the real stage1$adjust coding (memory #19):
#'   0 = HLIML interior, 1 = Step 2 fallback, 4 = sigma clamped (cap),
#'   5 = omega clamped, NA = not estimated. Full-universe split is
#'   ~21% / 35% / (4:~6.4% + 5:~2.2%) / 47%.

s1 <- data.table::copy(stage1)
s1[, adjust_class := factor(
  data.table::fcase(
    adjust == 0L, "HLIML interior",
    adjust == 1L, "Step 2 fallback",
    adjust == 4L, "sigma clamped",
    adjust == 5L, "omega clamped",
    default = "Not estimated"
  ),
  levels = c("HLIML interior", "Step 2 fallback", "sigma clamped",
             "omega clamped", "Not estimated"))]

prov <- s1[, .(n = .N), by = adjust_class][
  , pct := 100 * n / sum(n)][order(adjust_class)]

# --- Figure: provenance bar (share of universe) ----------------------------
fig <- ggplot(prov, aes(x = adjust_class, y = pct, fill = adjust_class)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.1f%%", pct)), vjust = -0.3, size = 3) +
  labs(title = "Stage 1 sigma estimation provenance (full universe)",
       x = NULL, y = "% of importer x product cells") +
  theme_paper() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))
save_figure(fig, "02_pillar1_sigma_provenance")
save_table(prov, "02_pillar1_sigma_provenance")

# also report the conditional-on-status=ok rates (the "40%/64%" framing)
ok <- s1[status == "ok", .(n = .N), by = adjust_class][
  , pct := 100 * n / sum(n)][order(adjust_class)]
save_table(ok, "02_pillar1_sigma_provenance_conditional_ok")

message("02_pillar1_sigma_provenance.R: interior = ",
        round(prov[adjust_class == "HLIML interior", pct], 1), "% of universe")
