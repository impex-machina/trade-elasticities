#' analysis/02_pillar1_sigma_provenance.R
#' Pillar 1: Stage-1 sigma provenance -- how each (importer, HS4) cell got
#' its sigma, on the full universe and among the cells with an estimate.
#' Reads `stage1` from 00_setup.R.
#'
#' (patch 0116, fresh-eyes audit #7) The classes are the shipped Stage-1
#' routes (status "ok" by adjust; see 01_pillar1_empirical_overview.R):
#' HLIML interior (0), Step 2 (1), Step 2 with sigma or omega clamped at a
#' cap (4 / 5), the three constrained boundary optima (6 / 7 / 8, since
#' v0.6.0), and "No estimate" for every cell without status "ok". Through
#' patch 0115 adjust 6-8 fell into "Not estimated": the full-universe bar
#' read 54.9% not estimated against the true 34.8%, and the conditional table
#' put 30.9% of the cells with an estimate there.

.route_class <- function(status, adjust) {
  ok <- status %in% "ok"
  factor(data.table::fcase(
    ok & adjust %in% 0L, "HLIML interior",
    ok & adjust %in% 1L, "Step 2",
    ok & adjust %in% 4L, "Step 2, sigma clamped",
    ok & adjust %in% 5L, "Step 2, omega clamped",
    ok & adjust %in% 6L, "Boundary: omega floor",
    ok & adjust %in% 7L, "Boundary: sigma cap",
    ok & adjust %in% 8L, "Boundary: omega cap",
    ok,                  "Other (ok)",
    default =            "No estimate"),
    levels = c("HLIML interior", "Step 2", "Step 2, sigma clamped", "Step 2, omega clamped",
               "Boundary: omega floor", "Boundary: sigma cap", "Boundary: omega cap",
               "Other (ok)", "No estimate"))
}

s1 <- data.table::copy(stage1)
s1[, route := .route_class(status, adjust)]

prov <- s1[, .(n = .N), by = route][, pct := 100 * n / sum(n)][order(route)]

# --- Figure: provenance bar (share of universe) ----------------------------
fig <- ggplot(prov, aes(x = route, y = pct, fill = route)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.1f%%", pct)), vjust = -0.3, size = 3) +
  labs(title = "Stage 1 sigma provenance (full universe)",
       x = NULL, y = "% of importer x product cells") +
  theme_paper() +
  theme(axis.text.x = element_text(angle = 25, hjust = 1))
save_figure(fig, "02_pillar1_sigma_provenance")
save_table(prov, "02_pillar1_sigma_provenance")

# conditional on an estimate (status == "ok")
ok <- s1[status %in% "ok", .(n = .N), by = route][, pct := 100 * n / sum(n)][order(route)]
save_table(ok, "02_pillar1_sigma_provenance_conditional_ok")

message(sprintf("02_pillar1_sigma_provenance.R: interior %.1f%%, Step 2 %.1f%%, boundary %.1f%%, no estimate %.1f%% of the universe",
                sum(prov[route == "HLIML interior", pct]), sum(prov[grepl("^Step 2", route), pct]),
                sum(prov[grepl("^Boundary", route), pct]), sum(prov[route == "No estimate", pct])))
