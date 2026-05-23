#' analysis/00_setup.R
#'
#' Shared setup for the analysis layer. Sourced into the GLOBAL environment
#' by master.R before any pillar script runs, so the objects and helpers it
#' defines are visible to 01_*.R through 07_*.R.
#'
#' Responsibilities:
#'   - load the published Stage 1 / Stage 2 outputs from data/derived/
#'   - load the published validation CSVs (pillars 2/3/4)
#'   - define a shared ggplot2 theme and the figure/table writers
#'
#' Depends on: R/dependencies.R (sourced by master.R), R/load_outputs.R
#'
#' NB: assumes data/derived/ is already populated (master.R calls
#' verify_manifest_complete() before sourcing this). Run
#' scripts/download_outputs.R first if needed.

library(ggplot2)

# --- shared paths ----------------------------------------------------------
DERIVED      <- "data/derived"
DERIVED_S1   <- file.path(DERIVED, "stage1")
DERIVED_S2A  <- file.path(DERIVED, "stage2a")
DERIVED_S2B  <- file.path(DERIVED, "stage2b")
DERIVED_VAL  <- file.path(DERIVED, "validation")

# OUTPUT_DIR is set by master.R; fall back if 00_setup.R is sourced directly.
if (!exists("OUTPUT_DIR")) OUTPUT_DIR <- "analysis/figures"

# --- shared theme ----------------------------------------------------------
theme_paper <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      plot.title       = element_text(face = "bold"),
      legend.position  = "bottom"
    )
}
theme_set(theme_paper())

# --- figure / table writers ------------------------------------------------
# Every pillar script writes figures and tables through these so paths and
# formats stay consistent and master's run log can find them.
save_figure <- function(plot, name, width = 6.5, height = 4.5) {
  path <- file.path(OUTPUT_DIR, paste0(name, ".pdf"))
  ggplot2::ggsave(path, plot, width = width, height = height)
  invisible(path)
}
save_table <- function(x, name) {
  path <- file.path(OUTPUT_DIR, "tables", paste0(name, ".csv"))
  data.table::fwrite(x, path)
  invisible(path)
}

# --- load published outputs ------------------------------------------------
# Pillar 1 (empirical core). Loaded once; pillar-1 scripts read these objects.
stage1 <- readRDS(file.path(
  DERIVED_S1, "baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds"))
stage2b <- readRDS(file.path(
  DERIVED_S2B, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"))

message("00_setup.R: loaded stage1 (", nrow(stage1), " rows) and ",
        "stage2b (", nrow(stage2b), " rows)")
