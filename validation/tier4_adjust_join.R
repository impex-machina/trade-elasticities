# =============================================================================
# tier4_adjust_join.R
#
# Post-hoc join: attach production `adjust` flag to the 140 Tier 4 cells.
# Verifies whether the sigma=10 boundary heuristic captured exactly the
# adjust ∈ {4, 5} cells, or whether the picture is more nuanced.
#
# Inputs:
#   docs/methodology/tier4_comp.csv  (cell_id, sigma_new, omega_new, sigma_stage1)
#   refactored_stage1_liml.rds       (importer, good, ..., adjust, ...)
#
# Run from the repo root:
#   library(data.table)
#   source("validation/tier4_adjust_join.R")
# =============================================================================

COMP_PATH <- "docs/methodology/tier4_comp.csv"
# Stage 1 LIML output (the per-cell adjust flags). NOT published in this repo;
# set to your local copy or the TRADE_ELAST_STAGE1 environment variable.
S1_PATH   <- Sys.getenv("TRADE_ELAST_STAGE1",
  "<path-to>/refactored_stage1_liml.rds")

stopifnot(
  "tier4_comp.csv not found" = file.exists(COMP_PATH),
  "Stage 1 RDS not found"    = file.exists(S1_PATH)
)

cmp <- fread(COMP_PATH)
s1  <- as.data.table(readRDS(S1_PATH))

# ---- Parse cell_id into (importer, good) ------------------------------------
# Format observed: "100_7204", "12_2505" — importer is variable-width numeric
# country code, hs4 is 4-char string. Split on first underscore.
cmp[, c("importer", "good") := tstrsplit(cell_id, "_", fixed = TRUE,
                                         keep = c(1, 2))]
cmp[, importer := as.integer(importer)]

cat("=== Parse check ===\n")
cat(sprintf("Rows with parsed importer: %d / %d\n",
            sum(!is.na(cmp$importer)), nrow(cmp)))
cat(sprintf("Rows with parsed good:     %d / %d\n",
            sum(!is.na(cmp$good)),     nrow(cmp)))
cat(sprintf("Good values, nchar range:  [%d, %d]\n",
            min(nchar(cmp$good)), max(nchar(cmp$good))))
print(head(cmp[, .(cell_id, importer, good)]))

# ---- Join against Stage 1 ---------------------------------------------------
# Types: Stage 1 has importer as character (see earlier `str(arch)` output
# style — confirm here). cmp$importer is character from tstrsplit. Should
# match directly.
cat("\n=== Type check ===\n")
cat(sprintf("cmp$importer class: %s\n", class(cmp$importer)))
cat(sprintf("s1$importer class:  %s\n", class(s1$importer)))
cat(sprintf("cmp$good class:     %s\n", class(cmp$good)))
cat(sprintf("s1$good class:      %s\n", class(s1$good)))

j <- s1[cmp, on = .(importer, good),
        .(cell_id, sigma_new, omega_new, sigma_stage1,
          importer, good, adjust, hliml_status, final_source,
          sigma_prod = sigma, omega_prod = omega,
          sigma_hliml_prod = sigma_hliml, omega_hliml_prod = omega_hliml,
          sigma_step2_prod = sigma_step2, omega_step2_prod = omega_step2,
          status_prod = status)]

cat(sprintf("\n=== Join result ===\n"))
cat(sprintf("Rows after join: %d  (expected 140)\n", nrow(j)))
cat(sprintf("Rows with adjust NA after join: %d\n", sum(is.na(j$adjust))))

# ---- Compare Tier 4 sigma_new against production sigma ----------------------
# Tier 4 estimates were computed fresh from BACI; production sigma was
# computed by the full pipeline. They should be EQUAL if the harness's
# estimate_elasticities() function matches the production estimator.
cat("\n=== Tier 4 sigma_new vs production sigma ===\n")
j[, sigma_diff := sigma_new - sigma_prod]
cat(sprintf("Diff median: %.6f\n", median(j$sigma_diff, na.rm = TRUE)))
cat(sprintf("Diff max abs: %.6f\n", max(abs(j$sigma_diff), na.rm = TRUE)))
cat(sprintf("Rows with |diff| > 0.01: %d\n",
            sum(abs(j$sigma_diff) > 0.01, na.rm = TRUE)))

# ---- Cross-tab: heuristic boundary vs production adjust ---------------------
j[, heuristic_boundary := abs(sigma_new - 10.0) < 1e-6]

cat("\n=== Heuristic boundary vs production adjust ===\n")
print(table(j$heuristic_boundary, j$adjust, useNA = "ifany",
            dnn = c("sigma_new=10 (heuristic)", "production adjust")))

cat("\n=== Heuristic boundary vs hliml_status ===\n")
print(table(j$heuristic_boundary, j$hliml_status, useNA = "ifany",
            dnn = c("sigma_new=10 (heuristic)", "hliml_status")))

cat("\n=== Heuristic boundary vs final_source ===\n")
print(table(j$heuristic_boundary, j$final_source, useNA = "ifany",
            dnn = c("sigma_new=10 (heuristic)", "final_source")))

# ---- Inspect mismatch cases ------------------------------------------------
# Heuristic says boundary, production says interior (adjust=0 or 1) — false positives
# Heuristic says interior, production says clamped (adjust=4 or 5) — false negatives
fp <- j[heuristic_boundary == TRUE & adjust %in% c(0L, 1L)]
fn <- j[heuristic_boundary == FALSE & adjust %in% c(4L, 5L)]

cat(sprintf("\n=== Heuristic false positives (sigma_new=10 but adjust∈{0,1}): %d ===\n",
            nrow(fp)))
if (nrow(fp) > 0) {
  print(fp[, .(cell_id, sigma_new, omega_new, adjust, hliml_status,
               sigma_hliml_prod, sigma_step2_prod)])
}

cat(sprintf("\n=== Heuristic false negatives (sigma_new<10 but adjust∈{4,5}): %d ===\n",
            nrow(fn)))
if (nrow(fn) > 0) {
  print(fn[, .(cell_id, sigma_new, omega_new, adjust, hliml_status,
               sigma_hliml_prod, sigma_step2_prod)])
}

# ---- Save augmented comparison frame ----------------------------------------
OUT_PATH <- "docs/methodology/tier4_comp_with_adjust.csv"
write.csv(j, OUT_PATH, row.names = FALSE)
cat(sprintf("\nWrote augmented comparison: %s  (%d rows)\n", OUT_PATH, nrow(j)))

cat("\n=== Done ===\n")
