#!/usr/bin/env Rscript
# =============================================================================
# analysis/handoff_rows_census.R  (patch 0110)
#
# Sizes the Stage-2a -> 2b handoff bug on a shipped Stage-2a table: under
# --stage2-trim-action flag (v0.10.0 default) the table keeps its trimmed rows,
# and run_estimation.R built Stage 2b's good-level priors and regional gamma_V
# from every row (--stage2a-handoff-rows all, every release). Recomputes both
# with stage2b_priors_from_regional() -- the runner's own code path -- from all
# rows and from the published rows (stage2a_handoff_rows(..., "published")) and
# reports how far they move. Reads one table; seconds.
#
# Usage (repo root):
#   Rscript analysis/handoff_rows_census.R \
#     [--stage2a data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds] \
#     [--out results/stage2a_handoff_census.json] [--md docs/results/stage2a_handoff_census.md]
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
source("R/utils_general.R"); source("R/iteration_helpers.R")
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
s2a_path <- get_arg("--stage2a", "data/derived/stage2a/baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds")
out_json <- get_arg("--out", "results/stage2a_handoff_census.json")
out_md   <- get_arg("--md", "docs/results/stage2a_handoff_census.md")
if (!file.exists(s2a_path)) stop("Stage-2a table not found: ", s2a_path)
s2a <- as.data.table(readRDS(s2a_path))
sha <- if (requireNamespace("openssl", quietly = TRUE)) { con <- file(s2a_path, "rb"); on.exit(close(con), add = TRUE)
  tolower(unclass(as.character(openssl::sha256(con)))) } else NA_character_
n_flag <- if ("trim_reason" %in% names(s2a)) sum(!is.na(s2a$trim_reason)) else 0L
pri <- lapply(c(all = "all", published = "published"), function(rl) {
  h <- stage2a_handoff_rows(s2a, rl)
  stage2b_priors_from_regional(h[!is.na(sigma) & !is.na(gamma) & gamma > 0], rows = "estimated")
})
cp <- merge(pri$all$country_priors, pri$published$country_priors, by = "good", suffixes = c(".all", ".pub"), all = TRUE)
d_pr <- abs(cp$ln_gamma_prior.all - cp$ln_gamma_prior.pub)
gv <- merge(pri$all$gam_V_regional, pri$published$gam_V_regional, by = c("region", "good"), suffixes = c(".all", ".pub"), all = TRUE)
d_gv <- abs(log(gv$gamma.all) - log(gv$gamma.pub))
q <- function(x) { x <- x[is.finite(x)]; if (!length(x)) return(NULL)
  as.list(setNames(signif(quantile(x, c(.5, .9, .99, 1)), 6), c("p50", "p90", "p99", "max"))) }
out <- list(
  meta = list(stage2a = s2a_path, stage2a_sha256 = sha, n_rows = nrow(s2a),
              git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
              timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  n_flagged = n_flag,
  flagged_by_reason = if (n_flag) as.list(table(s2a$trim_reason)) else list(),
  n_rows_used = list(all = pri$all$n_rows_used, published = pri$published$n_rows_used),
  prior = list(n_goods = nrow(cp), n_moved = sum(d_pr > 1e-12, na.rm = TRUE), n_missing = sum(!is.finite(d_pr)), abs_dln = q(d_pr)),
  gamma_v_regional = list(n_cells = nrow(gv), n_moved = sum(d_gv > 1e-12, na.rm = TRUE), n_missing = sum(!is.finite(d_gv)), abs_dln = q(d_gv)))
dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
f <- function(x) if (is.null(x)) "--" else sprintf("p50 %.3g / p90 %.3g / p99 %.3g / max %.3g", x$p50, x$p90, x$p99, x$max)
md <- c("# Stage-2a rows handed to Stage 2b: all vs published (patch 0110)", "",
  sprintf("Table: `%s` (%s rows, sha256 %s); generated %s at rev %s.", basename(s2a_path), format(nrow(s2a), big.mark = ","),
          substr(sha, 1, 12), out$meta$timestamp, out$meta$git_rev), "",
  sprintf("Flagged (trimmed) rows in the table: %s%s.", format(n_flag, big.mark = ","),
          if (n_flag) paste0(" (", paste(sprintf("%s %s", names(out$flagged_by_reason), unlist(out$flagged_by_reason)), collapse = ", "), ")") else ""),
  sprintf("Rows behind the priors (directly estimated, gamma > 0): all %s, published %s.",
          format(out$n_rows_used$all, big.mark = ","), format(out$n_rows_used$published, big.mark = ",")), "",
  "| input | units | moved | missing in one | abs d ln |", "|---|---|---|---|---|",
  sprintf("| good-level prior | %s goods | %s | %s | %s |", out$prior$n_goods, out$prior$n_moved, out$prior$n_missing, f(out$prior$abs_dln)),
  sprintf("| regional gamma_V | %s region x good | %s | %s | %s |", out$gamma_v_regional$n_cells, out$gamma_v_regional$n_moved,
          out$gamma_v_regional$n_missing, f(out$gamma_v_regional$abs_dln)), "",
  "Starting values (init_from_regional()) move with the same rows and are not censused; they affect only the optimizer's path.")
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
writeLines(md, out_md)
cat(paste(md, collapse = "\n"), "\n")
