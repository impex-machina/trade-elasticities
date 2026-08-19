#!/usr/bin/env Rscript
# =============================================================================
# analysis/hs4_hliml_closed_form_census.R   (patch 0025, v0.6.0-rc)
#
# Tabulates, from a Stage-1 run made with `--stage1-hliml both`, how the
# HLIML closed form (hliml_closed_form(), the HLIM eigenvector) would re-route
# cells relative to the shipped wall-BFGS path, WITHOUT changing any shipped
# number: "both" routes exactly as v0.5.x and carries the closed form in the
# *_cf columns alongside.
#
# Usage:
#   Rscript analysis/hs4_hliml_closed_form_census.R \
#       --liml <path to *_feenstra_sigma_liml.rds from a 'both' run> \
#       [--out results/hliml_closed_form_census.json] [--md docs/results/hliml_closed_form_census.md]
#
# Reads only the Stage-1 table (no raw cache needed), so it runs on the box in
# seconds once the EC2 'both' run's LIML intermediate has been pulled.
#
# Questions answered (the v0.6.0 go/no-go inputs):
#   Q1  Of the cells that reached Step 3, how many does the closed form
#       classify as admissible-interior vs the BFGS path? (cross-tab)
#   Q2  Re-routes: BFGS-failed/inadmissible but cf-admissible (would become
#       HLIML-interior under 'closed'), split by where they sit today
#       (step2_clean, capped, all_inversions_failed); and the reverse.
#   Q3  Where both are admissible: |delta sigma|, share within 1%, and the
#       share where Q_cf <= Q_bfgs (closed form is the global minimiser, so
#       this should be ~100%; any exception is an eigen/inversion edge case).
#   Q4  Projected Stage-1 composition under 'closed' routing (approximation:
#       cf-admissible -> hliml_interior; else unchanged) and the change in the
#       number of sigma-bearing cells (the Stage-2 fallback denominator).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L]
}
liml_path <- get_arg("--liml")
out_json  <- get_arg("--out", "results/hliml_closed_form_census.json")
out_md    <- get_arg("--md",  "docs/results/hliml_closed_form_census.md")
if (is.null(liml_path) || !file.exists(liml_path))
  stop("--liml <path to *_feenstra_sigma_liml.rds from a --stage1-hliml both run> is required")

d <- as.data.table(readRDS(liml_path))
need <- c("status", "hliml_status", "hliml_cf_status", "hliml_cf_admissible",
          "sigma_hliml", "sigma_hliml_cf", "hliml_Q", "hliml_Q_cf", "adjust")
miss <- setdiff(need, names(d))
if (length(miss))
  stop("input lacks columns ", paste(miss, collapse = ", "),
       " -- was the run made with --stage1-hliml both?")
if ("hliml_method" %in% names(d) &&
    !all(d$hliml_method[!is.na(d$hliml_status)] %in% "both"))
  warning("hliml_method is not 'both' for every Step-3 row; census semantics assume the BFGS routing")

N <- nrow(d)
reached3 <- d[!is.na(hliml_status)]                 # cells that reached Step 3
bfgs_ok  <- reached3[hliml_status == "ok"]
cf_adm   <- reached3[hliml_cf_admissible %in% TRUE]

# Q1 cross-tab ----------------------------------------------------------------
reached3[, bfgs_class := fifelse(hliml_status == "ok", "bfgs_ok",
                          fifelse(hliml_status == "hliml_fail_no_convergence", "bfgs_noconv",
                                  "bfgs_other_fail"))]
reached3[, cf_class := fifelse(is.na(hliml_cf_status), "cf_NA",
                        fifelse(hliml_cf_status != "ok", "cf_fail",
                                fifelse(hliml_cf_admissible %in% TRUE, "cf_admissible", "cf_inadmissible")))]
xt <- reached3[, .N, by = .(bfgs_class, cf_class)][order(bfgs_class, cf_class)]

# Q2 re-routes ------------------------------------------------------------------
# shipped destination of each cell (final routing)
reached3[, shipped_dest := fifelse(status != "ok", status,
                            fifelse(adjust == 0L, "hliml_interior",
                             fifelse(adjust == 1L, "step2_clean",
                              fifelse(adjust %in% c(4L, 5L), "capped",
                               fifelse(adjust %in% c(2L, 3L), "omega_floored_or_fallback",
                                       paste0("adjust_", adjust))))))]
reroute_in  <- reached3[bfgs_class != "bfgs_ok" & cf_class == "cf_admissible",
                        .N, by = shipped_dest][order(-N)]
reroute_out <- reached3[bfgs_class == "bfgs_ok" & cf_class != "cf_admissible",
                        .N, by = cf_class][order(-N)]

# Q3 agreement where both admissible --------------------------------------------
both <- reached3[bfgs_class == "bfgs_ok" & cf_class == "cf_admissible" &
                 is.finite(sigma_hliml) & is.finite(sigma_hliml_cf)]
both[, rel_d := abs(sigma_hliml - sigma_hliml_cf) / sigma_hliml_cf]
q3 <- list(
  n_both = nrow(both),
  median_abs_delta_sigma = if (nrow(both)) median(abs(both$sigma_hliml - both$sigma_hliml_cf)) else NA,
  share_within_1pct = if (nrow(both)) mean(both$rel_d <= 0.01) else NA,
  share_within_10pct = if (nrow(both)) mean(both$rel_d <= 0.10) else NA,
  share_Qcf_le_Qbfgs = if (nrow(both)) mean(both$hliml_Q_cf <= both$hliml_Q + 1e-12, na.rm = TRUE) else NA,
  median_sigma_bfgs = if (nrow(both)) median(both$sigma_hliml) else NA,
  median_sigma_cf   = if (nrow(both)) median(both$sigma_hliml_cf) else NA
)

# Q4 projected composition under 'closed' routing -------------------------------
proj <- copy(reached3)
proj[, proj_dest := fifelse(cf_class == "cf_admissible", "hliml_interior", shipped_dest)]
comp <- merge(reached3[, .(shipped = .N), by = .(dest = shipped_dest)],
              proj[, .(projected = .N), by = .(dest = proj_dest)],
              by = "dest", all = TRUE)
comp[is.na(shipped), shipped := 0L][is.na(projected), projected := 0L]
setorder(comp, -shipped)
n_sigma_shipped   <- d[status == "ok", .N]
n_sigma_projected <- n_sigma_shipped + reached3[status != "ok" & cf_class == "cf_admissible", .N]

# Q5 boundary (hybrid) rescue among closed-form-inadmissible cells (patch 0027) --
has_bd <- all(c("hliml_bd_edge", "hliml_bd_usable", "sigma_hliml_bd") %in% names(reached3))
if (has_bd) {
  inadm <- reached3[cf_class %in% c("cf_inadmissible", "cf_fail")]
  bd_by_edge <- inadm[, .N, by = .(edge = fifelse(is.na(hliml_bd_edge), "bd_NA", hliml_bd_edge))][order(-N)]
  bd_rescue <- inadm[hliml_bd_usable %in% TRUE, .N, by = shipped_dest][order(-N)]
  rescued_aif <- inadm[hliml_bd_usable %in% TRUE & shipped_dest == "all_inversions_failed"]
  q5 <- list(n_cf_inadmissible = nrow(inadm), by_edge = bd_by_edge, usable_by_shipped_dest = bd_rescue,
             rescued_all_inversions_failed = nrow(rescued_aif),
             rescued_aif_sigma_median = if (nrow(rescued_aif)) median(rescued_aif$sigma_hliml_bd) else NA,
             rescued_aif_share_at_sigma_cap = if (nrow(rescued_aif)) mean(rescued_aif$sigma_hliml_bd >= 10 - 1e-6) else NA,
             rescued_aif_share_omega_floor = if (nrow(rescued_aif)) mean(rescued_aif$hliml_bd_edge == "omega_floor") else NA)
} else q5 <- NULL

res <- list(
  input = basename(liml_path), n_cells = N, n_reached_step3 = nrow(reached3),
  n_bfgs_ok = nrow(bfgs_ok), n_cf_admissible = nrow(cf_adm),
  crosstab = xt, reroute_in_by_shipped_dest = reroute_in,
  reroute_out_by_cf_class = reroute_out, agreement = q3,
  composition = comp,
  sigma_bearing_cells = list(shipped = n_sigma_shipped, projected = n_sigma_projected,
                             delta = n_sigma_projected - n_sigma_shipped),
  boundary = q5,
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(res, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

fmt_tab <- function(dt) {
  hdr <- paste0("| ", paste(names(dt), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(dt)), collapse = "|"), "|")
  rows <- apply(dt, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  c(hdr, sep, rows)
}
md <- c(
  "# HLIML closed-form census (v0.6.0-rc A/B input)", "",
  sprintf("Input: `%s` (%s cells; %s reached Step 3). Generated %s.",
          basename(liml_path), format(N, big.mark = ","),
          format(nrow(reached3), big.mark = ","), res$generated), "",
  "## Q1 BFGS path x closed form (cells reaching Step 3)", "", fmt_tab(xt), "",
  "## Q2 Re-routes: BFGS failed/inadmissible but closed form admissible, by shipped destination", "",
  fmt_tab(reroute_in), "",
  "Reverse (BFGS ok, closed form not admissible):", "", fmt_tab(reroute_out), "",
  "## Q3 Agreement where both admissible", "",
  sprintf("- n = %s; median |delta sigma| = %.4f; within 1%%: %.1f%%; within 10%%: %.1f%%",
          format(q3$n_both, big.mark = ","), q3$median_abs_delta_sigma,
          100 * q3$share_within_1pct, 100 * q3$share_within_10pct),
  sprintf("- Q_cf <= Q_bfgs in %.2f%% of cells (closed form is the global minimiser; exceptions are eigen/inversion edge cases)",
          100 * q3$share_Qcf_le_Qbfgs),
  sprintf("- median sigma: BFGS %.3f vs closed form %.3f", q3$median_sigma_bfgs, q3$median_sigma_cf), "",
  "## Q4 Projected Stage-1 composition under 'closed' routing", "", fmt_tab(comp), "",
  sprintf("sigma-bearing cells (Stage-2 fallback denominator): shipped %s -> projected %s (%+d)",
          format(n_sigma_shipped, big.mark = ","), format(n_sigma_projected, big.mark = ","),
          n_sigma_projected - n_sigma_shipped), "",
  if (!is.null(q5)) c(
    "## Q5 Boundary (hybrid) search among closed-form-inadmissible cells", "",
    sprintf("- closed-form-inadmissible cells reaching Step 3: %s", format(q5$n_cf_inadmissible, big.mark = ",")), "",
    "Best edge:", "", fmt_tab(q5$by_edge), "",
    "Usable boundary estimate (omega_floor / omega_cap / sigma_cap) by shipped destination:", "",
    fmt_tab(q5$usable_by_shipped_dest), "",
    sprintf("- all_inversions_failed cells with a usable boundary estimate: %s (median sigma %.3f; at sigma cap %.1f%%; on the omega floor %.1f%%)",
            format(q5$rescued_all_inversions_failed, big.mark = ","), q5$rescued_aif_sigma_median,
            100 * q5$rescued_aif_share_at_sigma_cap, 100 * q5$rescued_aif_share_omega_floor), ""
  ) else "(no boundary columns in input -- run made before patch 0027)"
)
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(paste(md, collapse = "\n"), "\n")
cat(sprintf("\nwrote %s and %s\n", out_json, out_md))
