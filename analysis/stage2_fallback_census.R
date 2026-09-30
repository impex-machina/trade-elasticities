#!/usr/bin/env Rscript
# ============================================================================
# analysis/stage2_fallback_census.R  (patch 0080, 2026-09-29 fresh-eyes audit #4)
#
# Summarises a Stage-2 fallback table (<prefix>_stage2_fallbacks.csv, written
# by estimate_all_fixed_sigma() since patch 0077 beside the checkpoint file):
# one row per cell whose L-BFGS-B fit did not converge and ran the
# Nelder-Mead restart, with both objective values, both convergence codes and
# which point was published. Emits the JSON the README's Known-limitations
# clause reads (results/stage2_fallback_census.json -> build_readme.R's
# fallback_clause()) and a markdown record.
#
# Usage (repo root):
#   Rscript analysis/stage2_fallback_census.R --csv PATH [--label universe|subsample|...]
#                                             [--out results/stage2_fallback_census.json]
#                                             [--md docs/results/stage2_fallback_census.md]
# The default --csv is the country table's file in the working directory; the
# default --out/--md are the UNIVERSE names the README reads -- pass explicit
# names for a subsample census so it cannot overwrite the shipped one.
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
csv_path <- get_arg("--csv", "baci_hs92_v202601_elast_country_hs4_stage2_fallbacks.csv")
label    <- get_arg("--label", "universe")
out_json <- get_arg("--out", "results/stage2_fallback_census.json")
out_md   <- get_arg("--md",  "docs/results/stage2_fallback_census.md")
if (!file.exists(csv_path)) stop("fallback table not found: ", csv_path)

fb <- fread(csv_path)
need <- c("importer", "good", "J", "M", "lbfgsb_convergence", "lbfgsb_value", "nm_convergence", "nm_value", "chosen", "rule")
miss <- setdiff(need, names(fb)); if (length(miss)) stop("fallback table lacks columns: ", paste(miss, collapse = ", "))

cmp <- fb[is.finite(lbfgsb_value) & is.finite(nm_value)]
cmp[, excess := nm_value / lbfgsb_value - 1]
q <- function(x, p = c(.1, .25, .5, .75, .9, .99)) { x <- x[is.finite(x)]; if (!length(x)) return(NULL); as.list(setNames(quantile(x, p), paste0("p", 100 * p))) }
lb_better <- cmp[nm_value > lbfgsb_value]

out <- list(
  meta = list(csv = csv_path, label = label, rules = sort(unique(fb$rule)),
              git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
              timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  n_cells          = nrow(fb),
  n_comparable     = nrow(cmp),
  n_lbfgsb_error   = sum(!is.finite(fb$lbfgsb_value)),
  n_nm_error       = sum(!is.finite(fb$nm_value)),
  n_nm_worse       = nrow(lb_better),
  share_nm_worse   = if (nrow(cmp)) nrow(lb_better) / nrow(cmp) else NA_real_,
  n_nm_better      = nrow(cmp[nm_value < lbfgsb_value]),
  n_tie            = nrow(cmp[nm_value == lbfgsb_value]),
  excess_quantiles = q(cmp$excess),
  excess_quantiles_where_worse = q(lb_better$excess),
  n_nm_converged   = sum(fb$nm_convergence %in% 0L),
  # cells that legacy labelled `ok` at the NM point (NM code 0) but whose
  # L-BFGS-B point is better: under `best` they publish that point with its
  # own code (the cap, 1) and read `non_converged` -- the relabelling
  n_relabel_ok_to_nonconverged = nrow(lb_better[nm_convergence %in% 0L & !(lbfgsb_convergence %in% 0L)]),
  chosen           = as.list(table(factor(fb$chosen, levels = c("lbfgsb", "nelder_mead")))),
  J_quantiles      = q(fb$J, c(.1, .5, .9, 1)),
  M_quantiles      = q(fb$M, c(.1, .5, .9, 1))
)
out$chosen <- lapply(out$chosen, as.integer)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8)

f3 <- function(x) if (is.null(x)) "NA" else formatC(x, format = "f", digits = 3)
pc <- function(x) if (is.na(x)) "NA" else sprintf("%.1f%%", 100 * x)
eq <- out$excess_quantiles
md <- c(
  sprintf("# Stage-2 optimizer fallback census (%s)", label), "",
  sprintf("Table: `%s` (rule%s: %s; rev %s, %s).", csv_path, if (length(out$meta$rules) > 1L) "s" else "", paste(out$meta$rules, collapse = ", "), out$meta$git_rev, out$meta$timestamp), "",
  sprintf("- %s cells reached the L-BFGS-B cap and ran the Nelder-Mead restart (J median %s, p90 %s, max %s).",
          format(out$n_cells, big.mark = ","), out$J_quantiles$p50, out$J_quantiles$p90, out$J_quantiles$p100),
  sprintf("- On the %s cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on %s (%s), lower on %s, tied on %s; L-BFGS-B errored on %s, Nelder-Mead on %s.",
          format(out$n_comparable, big.mark = ","), format(out$n_nm_worse, big.mark = ","), pc(out$share_nm_worse),
          format(out$n_nm_better, big.mark = ","), format(out$n_tie, big.mark = ","), out$n_lbfgsb_error, out$n_nm_error),
  if (!is.null(eq)) sprintf("- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: %s / %s / %s / %s.", f3(eq$p10), f3(eq$p50), f3(eq$p90), f3(eq$p99)) else "- No comparable cells.",
  sprintf("- The restart reported convergence (simplex collapsed, code 0) on %s cells; on %s of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.",
          format(out$n_nm_converged, big.mark = ","), format(out$n_relabel_ok_to_nonconverged, big.mark = ",")),
  sprintf("- Published point: L-BFGS-B on %s cells, Nelder-Mead on %s.", format(out$chosen$lbfgsb, big.mark = ","), format(out$chosen$nelder_mead, big.mark = ",")), "",
  "Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule."
)
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(sprintf("Wrote %s and %s\n", out_json, out_md))
cat(sprintf("%s: %d fallback cells; NM worse on %d of %d comparable (%s); NM code 0 on %d (relabelled under best: %d)\n",
            label, out$n_cells, out$n_nm_worse, out$n_comparable, pc(out$share_nm_worse), out$n_nm_converged, out$n_relabel_ok_to_nonconverged))
