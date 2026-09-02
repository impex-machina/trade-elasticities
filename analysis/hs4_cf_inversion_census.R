#!/usr/bin/env Rscript
# =============================================================================
# analysis/hs4_cf_inversion_census.R   (patch 0043, 2026-09-01 fresh-eyes audit)
#
# Reads only the shipped Stage-1 table (no raw cache) and tabulates how many
# closed-form HLIML points were routed as INTERIOR estimates after
# invert_structural() clamped a negative algebraic omega up to the 1e-4 floor
# (hliml_cf_inversion == "constraint_violated"). Those points lie past the
# omega = +Inf end of the admissible interval, so the floor (perfectly
# elastic supply) is the opposite reading from what the data say; under
# --stage1-cf-admissibility strict they take the Step-2 -> boundary cascade.
# See hliml_closed_form() in R/liml_estimator.R and
# tests/testthat/test-stage1-cf-admissibility.R.
#
# Usage (either the rich LIML intermediate or the Stage-2 input works --
# both carry the *_cf and *_step2 columns):
#   Rscript analysis/hs4_cf_inversion_census.R \
#       --stage1 data/derived/stage1/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds \
#       [--out results/cf_inversion_census.json] [--md docs/results/cf_inversion_census.md]
#
# Questions:
#   Q1  final_source x closed-form inversion status x omega_floored, all cells.
#   Q2  The interior-HLIML constraint-violated set: size (universe / ok /
#       hliml shares), sigma quantiles, and where the floored mass sits.
#   Q3  Projected re-routing under strict (Step 2 admissible -> step2; else
#       boundary if the closed form existed; else all_inversions_failed) and
#       the sigma-bearing delta. The boundary EDGE needs the raw cache (an
#       EC2 --stage1-cf-admissibility strict rerun); the synthetic DGP put
#       ~96% of such cells on the omega_cap edge.
#   Q4  Geometry sanity: the shipped boundary_omega_floor cells should be
#       dominated by hliml_cf_inversion == "eta1_nonpositive" (the omega -> 0
#       continuation), not "constraint_violated".
#   Q5  Where Step 2 would take over: |sigma_step2 - sigma| on those cells.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L]
}
s1_path <- get_arg("--stage1")
out_json <- get_arg("--out", "results/cf_inversion_census.json")
out_md   <- get_arg("--md",  "docs/results/cf_inversion_census.md")
if (is.null(s1_path) || !file.exists(s1_path))
  stop("--stage1 <path to the Stage-1 rds (feenstra_sigma or feenstra_sigma_liml)> is required")

d <- as.data.table(readRDS(s1_path))
need <- c("status", "final_source", "adjust", "sigma", "omega", "omega_floored",
          "hliml_cf_inversion", "hliml_cf_admissible", "sigma_hliml_cf",
          "sigma_step2", "omega_step2")
miss <- setdiff(need, names(d))
if (length(miss)) stop("input lacks columns ", paste(miss, collapse = ", "),
                       " -- was this produced at v0.6.0 or later?")
N <- nrow(d); n_ok <- d[status == "ok", .N]
inv_lab <- function(x) fifelse(is.na(x), "cf_NA", x)
d[, cf_inv := inv_lab(hliml_cf_inversion)]
d[, dest := fifelse(status != "ok", status, final_source)]

# Q1 ---------------------------------------------------------------------------
q1 <- d[, .N, by = .(dest, cf_inv, floored = omega_floored %in% TRUE)][order(dest, -N)]

# Q2 ---------------------------------------------------------------------------
cv <- d[status == "ok" & final_source == "hliml" & cf_inv == "constraint_violated"]
n_hliml <- d[status == "ok" & final_source == "hliml", .N]
q2 <- list(
  n = nrow(cv),
  share_universe = nrow(cv) / N, share_ok = nrow(cv) / n_ok,
  share_of_hliml_interior = nrow(cv) / n_hliml,
  all_floored = all(cv$omega_floored %in% TRUE),
  sigma_quartiles = if (nrow(cv)) unname(quantile(cv$sigma, c(.25, .5, .75))) else NA,
  sigma_at_cap_share = if (nrow(cv)) mean(cv$sigma >= 10 - 1e-3) else NA,
  n_floored_total = d[omega_floored %in% TRUE, .N],
  n_floored_boundary_edge = d[status == "ok" & final_source == "hliml_boundary" &
                                omega_floored %in% TRUE, .N],
  n_floored_step2 = d[status == "ok" & final_source == "step2_weighted" &
                        omega_floored %in% TRUE, .N],
  n_floored_hliml_interior = d[status == "ok" & final_source == "hliml" &
                                 omega_floored %in% TRUE, .N]
)

# Q3 ---------------------------------------------------------------------------
cv[, s2_ok := !is.na(sigma_step2) & sigma_step2 > 1 & sigma_step2 < 10 &
              !is.na(omega_step2) & omega_step2 >= 0 & omega_step2 <= 10]
cv[, s2_capped := !s2_ok & ((!is.na(sigma_step2) & sigma_step2 >= 10) |
                            (!is.na(omega_step2) & omega_step2 > 10))]
cv[, proj := fifelse(s2_ok, "step2_clean", fifelse(s2_capped, "step2_capped",
                     "boundary_or_failed (edge needs raw data)"))]
q3_tab <- cv[, .N, by = proj][order(-N)]
q3 <- list(projected = q3_tab,
           step2_omega_on_reroutes = if (any(cv$s2_ok))
             unname(quantile(cv[s2_ok == TRUE, omega_step2], c(.25, .5, .75))) else NA,
           step2_omega_floored_share = if (any(cv$s2_ok)) mean(cv[s2_ok == TRUE, omega_step2] <= 1e-4) else NA)

# Q4 ---------------------------------------------------------------------------
q4 <- d[status == "ok" & final_source == "hliml_boundary", .N, by = .(adjust, cf_inv)][order(adjust, -N)]

# Q5 ---------------------------------------------------------------------------
q5 <- if (any(cv$s2_ok)) {
  x <- cv[s2_ok == TRUE, abs(sigma_step2 - sigma) / sigma]
  list(n = length(x), median_rel_dsigma = median(x), p75 = unname(quantile(x, .75)),
       p90 = unname(quantile(x, .9)), share_gt_10pct = mean(x > 0.1))
} else NULL

res <- list(input = basename(s1_path), n_cells = N, n_ok = n_ok, n_hliml_interior = n_hliml,
            q1 = q1, q2 = q2, q3 = q3, q4 = q4, q5 = q5,
            generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(res, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

fmt_tab <- function(dt) {
  hdr <- paste0("| ", paste(names(dt), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(dt)), collapse = "|"), "|")
  rows <- apply(dt, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  c(hdr, sep, rows)
}
pct <- function(x) sprintf("%.1f%%", 100 * x)
md <- c(
  "# Closed-form inversion census (patch 0043 input)", "",
  sprintf("Input: `%s` (%s cells; %s ok). Generated %s.", basename(s1_path),
          format(N, big.mark = ","), format(n_ok, big.mark = ","), res$generated), "",
  "## Q1 final_source x closed-form inversion status x omega_floored", "", fmt_tab(q1), "",
  "## Q2 Interior-HLIML cells whose closed form was constraint_violated (omega clamped from negative)", "",
  sprintf("- n = %s = %s of the universe, %s of ok cells, %s of interior-HLIML cells; all floored: %s",
          format(q2$n, big.mark = ","), pct(q2$share_universe), pct(q2$share_ok),
          pct(q2$share_of_hliml_interior), q2$all_floored),
  sprintf("- sigma quartiles on these cells: %s; share at the sigma cap: %s",
          paste(sprintf("%.3f", q2$sigma_quartiles), collapse = " / "), pct(q2$sigma_at_cap_share)),
  sprintf("- omega_floored cells in total: %s -- interior-HLIML %s, Step-2 %s, boundary omega_floor edge %s",
          format(q2$n_floored_total, big.mark = ","), format(q2$n_floored_hliml_interior, big.mark = ","),
          format(q2$n_floored_step2, big.mark = ","), format(q2$n_floored_boundary_edge, big.mark = ",")), "",
  "## Q3 Projected destination under --stage1-cf-admissibility strict", "", fmt_tab(q3_tab), "",
  sprintf("- Step-2 omega on the step2_clean re-routes: quartiles %s; floored share %s",
          paste(sprintf("%.3f", q3$step2_omega_on_reroutes), collapse = " / "),
          pct(q3$step2_omega_floored_share)), "",
  "## Q4 Geometry sanity: shipped boundary cells by adjust code x inversion status", "", fmt_tab(q4), "",
  "## Q5 sigma movement where Step 2 takes over", "",
  if (!is.null(q5)) sprintf("- n = %s; median |dsigma|/sigma = %.3f (p75 %.3f, p90 %.3f); > 10%%: %s",
                            format(q5$n, big.mark = ","), q5$median_rel_dsigma, q5$p75, q5$p90,
                            pct(q5$share_gt_10pct)) else "- (no step2_clean re-routes)", ""
)
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(paste(md, collapse = "\n"), "\n")
cat(sprintf("\nwrote %s and %s\n", out_json, out_md))
