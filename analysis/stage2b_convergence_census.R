#!/usr/bin/env Rscript
# ============================================================================
# analysis/stage2b_convergence_census.R  (patch 0116, fresh-eyes audit #7)
#
# The optimizer's own convergence record of a Stage-2 table, kept apart from
# the imputed rows. The cell estimator writes optim()'s code on every row of a
# fitted cell (0 converged; 1 iteration cap; 10 Nelder-Mead degeneracy; 51 / 52
# L-BFGS-B warning / error -- 52 is typically a failed line search) and -1 only on imputed rows -- Tier 3, and the
# reference row of a cell whose non-reference exporters are all Tier 3.
# Through patch 0115 the release gates read convergence -1 among tier < 3 rows
# as "optimizer non-convergence"; that is the share of the imputed reference
# rows (0.42% in v0.10.0 and v0.11.0). stage2_convergence_census() in
# R/utils_general.R is the one definition; analysis/gate_release.R uses it.
#
# Usage (repo root):
#   Rscript analysis/stage2b_convergence_census.R --stage2b PATH
#       [--label v0110] [--out results/stage2b_convergence_census_v0110.json]
#       [--md docs/results/stage2b_convergence_census_v0110.md]
# Name the outputs with the release suffix (_vNNN / _vNNNN): build_readme.R
# picks the census computed on the shipped table by the sha256 recorded here.
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default
}
s2b_path <- get_arg("--stage2b", "data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
label    <- get_arg("--label", "run")
out_json <- get_arg("--out", sprintf("results/stage2b_convergence_census_%s.json", label))
out_md   <- get_arg("--md",  sprintf("docs/results/stage2b_convergence_census_%s.md", label))
if (!file.exists(s2b_path)) stop("Stage-2b table not found: ", s2b_path)

.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                      error = function(e) "analysis")
source(file.path(normalizePath(file.path(.this_dir, ".."), mustWork = FALSE), "R", "utils_general.R"))

.sha256_file <- function(p) {
  con <- file(p, "rb"); on.exit(close(con), add = TRUE)
  tolower(unclass(as.character(openssl::sha256(con))))
}

s2b <- readRDS(s2b_path); setDT(s2b)
cc  <- stage2_convergence_census(s2b)
pub <- if ("trim_reason" %in% names(s2b)) s2b[is.na(trim_reason)] else s2b
pub[, est := is_estimated_row(tier, convergence)]
pub[, nc := est & !(convergence %in% 0L)]
by_tier <- pub[!is.na(tier) & tier < 3L, .(rows = .N, estimated = sum(est), non_converged = sum(nc),
                                           imputed = sum(convergence %in% -1L)), by = tier][order(tier)]
st_check <- if (is.na(cc$n_status_non_converged)) NA else identical(as.integer(cc$n_status_non_converged), as.integer(cc$n_nonconverged))
# (patch 0118) cells whose non-converged directly estimated rows were all flagged by the tail trim
allr <- copy(s2b); allr[, est := is_estimated_row(tier, convergence)]
nc_cells_all <- uniqueN(allr[est & !(convergence %in% 0L), paste(importer, good, sep = "\r")])

out <- list(
  meta = list(stage2b = s2b_path, stage2b_sha256 = .sha256_file(s2b_path), label = label,
              git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1],
                                 error = function(e) NA_character_),
              timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  census = cc,
  by_tier = by_tier,
  status_matches_codes = st_check,
  n_cells_nonconverged_incl_flagged = nc_cells_all
)
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")

pc <- function(a, b) sprintf("%.2f%%", 100 * a / b)
fi <- function(x) format(x, big.mark = ",", scientific = FALSE)
codes <- cc$codes_estimated
md <- c(sprintf("# Stage-2b optimizer convergence census (%s)", label), "",
        sprintf("Table `%s` (sha256 %s...; rev %s, %s). Published rows only.", s2b_path, substr(out$meta$stage2b_sha256, 1, 16),
                out$meta$git_rev, out$meta$timestamp), "",
        sprintf("- Directly estimated rows (tier 0-2, fitted): %s of %s published rows.", fi(cc$n_estimated), fi(cc$n_rows)),
        sprintf("- **Optimizer non-convergence**: %s rows (%s of directly estimated rows) in %s of %s fitted cells -- the cells whose published point is not a converged optimum: L-BFGS-B stopped without converging (code 52, typically a failed line search, or 1, the iteration cap) and the Nelder-Mead restart did no better or was published without converging.",
                fi(cc$n_nonconverged), pc(cc$n_nonconverged, cc$n_estimated), fi(cc$n_cells_nonconverged), fi(cc$n_cells_estimated)),
        sprintf("- Codes among directly estimated rows: %s (0 converged; 1 iteration cap; 10 Nelder-Mead degeneracy; 51 L-BFGS-B warning; 52 L-BFGS-B error, typically a failed line search).", paste(sprintf("%s = %s", names(codes), fi(unlist(codes))), collapse = ", ")),
        sprintf("- Counting the rows the tail trim flagged too: %s cells with a non-converged directly estimated row (%s whose non-converged rows were all flagged).", fi(nc_cells_all), fi(nc_cells_all - cc$n_cells_nonconverged)),
        sprintf("- `gamma_se_status == \"non_converged\"` on directly estimated rows: %s (%s the code count).",
                if (is.na(cc$n_status_non_converged)) "column absent" else fi(cc$n_status_non_converged),
                if (isTRUE(st_check)) "equal to" else if (is.na(st_check)) "not compared with" else "DIFFERENT from"),
        sprintf("- Imputed reference rows (tier 0, convergence -1: the reference of a cell whose other exporters are all Tier 3): %s, %s of tier < 3 rows -- the figure the release gates reported as optimizer non-convergence through patch 0115.",
                fi(cc$n_imputed_reference), pc(cc$n_imputed_reference, cc$n_tier_lt3)),
        sprintf("- Tier 3: %s rows (%s of published rows).", fi(cc$n_tier3), pc(cc$n_tier3, cc$n_rows)), "",
        "| tier | rows | directly estimated | optimizer non-converged | imputed (-1) |", "|---|---|---|---|---|",
        sprintf("| %s | %s | %s | %s | %s |", by_tier$tier, fi(by_tier$rows), fi(by_tier$estimated), fi(by_tier$non_converged), fi(by_tier$imputed)), "")
writeLines(md, out_md)
cat(paste(md, collapse = "\n"), "\n")
cat(sprintf("stage2b_convergence_census: wrote %s and %s\n", out_json, out_md))
