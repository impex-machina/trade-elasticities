#!/usr/bin/env Rscript
# =============================================================================
# analysis/gate_v0100.R   (patch 0101, 2026-10-11)
#
# The v0.10.0 gate: compares the new Stage-2b table (sigma-pole rule c = 1,
# Stage-2a default gamma_V from the priors' rows, trim action flag, native
# gamma_v_resid) with the v0.9.1 table on the same Stage-1 table, by cell
# class, and checks the things the session must have done. Writes a markdown
# report; prints it; exits non-zero on a hard failure.
#
# Usage (repo root, or the box's working copy):
#   Rscript analysis/gate_v0100.R --old OLD_2B.rds --new NEW_2B.rds --stage1 STAGE1.rds \
#       [--pass-log NEW_gamma_v_passes.csv] [--c 1] [--out docs/results/gate_v0100.md]
# =============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
old_p <- get_arg("--old", NA_character_); new_p <- get_arg("--new", NA_character_); s1_p <- get_arg("--stage1", NA_character_)
log_p <- get_arg("--pass-log", NA_character_); cval <- as.numeric(get_arg("--c", "1")); out_p <- get_arg("--out", "docs/results/gate_v0100.md")
if (anyNA(c(old_p, new_p, s1_p))) stop("usage: Rscript analysis/gate_v0100.R --old OLD.rds --new NEW.rds --stage1 STAGE1.rds [--pass-log CSV] [--c 1] [--out MD]")
for (p in c(old_p, new_p, s1_p)) if (!file.exists(p)) stop("not found: ", p)

key <- function(x) { x <- as.data.table(x); for (k in intersect(c("importer", "exporter", "good"), names(x))) data.table::set(x, j = k, value = as.character(x[[k]])); x }
old <- key(readRDS(old_p)); new <- key(readRDS(new_p)); s1 <- key(readRDS(s1_p))
pub <- function(x) if ("trim_reason" %in% names(x)) x[is.na(trim_reason)] else x
est <- function(x) x[!is.na(tier) & tier < 3L & !(convergence %in% -1L) & is.finite(gamma) & gamma > 0]
q <- function(v, p) { v <- v[is.finite(v)]; if (length(v)) unname(quantile(v, p)) else NA_real_ }
fails <- character(0); fail <- function(msg) fails <<- c(fails, msg)
L <- c(sprintf("# v0.10.0 gate: %s -> %s", basename(old_p), basename(new_p)), "", sprintf("Stage 1: `%s`. Generated %s.", basename(s1_p), format(Sys.time(), "%Y-%m-%d %H:%M %Z")), "")

# --- classes on the Stage-1 table
s1[, cls := fifelse(!(status %in% "ok"), "no_estimate",
             fifelse(sigma_capped %in% TRUE, "sigma_edge",
             fifelse(is.finite(sigma_se) & (sigma - 1) < cval * sigma_se, "sigma_pole", "other")))]
cls_tab <- s1[, .N, by = cls][order(cls)]
L <- c(L, "## Stage-1 cell classes", "", "| class | cells |", "|---|---|", sprintf("| %s | %s |", cls_tab$cls, format(cls_tab$N, big.mark = ",")), "")
n_pole <- s1[cls == "sigma_pole", .N]

# --- schema and rows
newp <- pub(new); oldp <- pub(old)
L <- c(L, "## Rows and schema", "",
       sprintf("- old: %s rows (%s published), %d columns; new: %s rows (%s published), %d columns.",
               format(nrow(old), big.mark = ","), format(nrow(oldp), big.mark = ","), ncol(old), format(nrow(new), big.mark = ","), format(nrow(newp), big.mark = ","), ncol(new)))
if (!"trim_reason" %in% names(new)) fail("new table has no trim_reason column")
n_flag <- if ("trim_reason" %in% names(new)) sum(!is.na(new$trim_reason)) else 0L
if (n_flag == 0L) fail("new table carries no flagged trimmed rows (trim action flag expected)")
if (n_flag) L <- c(L, sprintf("- flagged trimmed rows in new: %s (%s).", format(n_flag, big.mark = ","), paste(sprintf("%s %s", names(table(new$trim_reason)), format(as.integer(table(new$trim_reason)), big.mark = ",")), collapse = ", ")))
if (!"gamma_v_resid" %in% names(new)) fail("new table has no gamma_v_resid column") else {
  gv <- new$gamma_v_resid[is.na(new$trim_reason)]
  L <- c(L, sprintf("- gamma_v_resid filled on %s of %s published rows (%.1f%%); p50 %.2e p90 %.3f p99 %.3f.",
                    format(sum(is.finite(gv)), big.mark = ","), format(length(gv), big.mark = ","), 100 * mean(is.finite(gv)), q(gv, .5), q(gv, .9), q(gv, .99)))
  if (mean(is.finite(gv)) < 0.5) fail("gamma_v_resid filled on fewer than half the published rows")
}

# --- fallback sigma
fb <- function(x) { t <- table(x$sigma); v <- as.numeric(names(which.max(t))); list(value = v, share = max(t) / nrow(x)) }
fo <- fb(oldp); fn <- fb(newp)
L <- c(L, "", "## Fallback sigma", "", sprintf("- old: %.4f on %.1f%% of published rows; new: %.4f on %.1f%% of published rows.", fo$value, 100 * fo$share, fn$value, 100 * fn$share))
if (fn$share < 0.25 || fn$share > 0.50) fail(sprintf("new fallback share %.1f%% outside [25%%, 50%%] -- the pole rule did not apply as measured (36.8%% on the subsample)", 100 * fn$share))
pole_cells <- s1[cls == "sigma_pole", paste(importer, good)]
newp[, cell := paste(importer, good)]
pole_rows <- newp[cell %in% pole_cells]
if (nrow(pole_rows)) {
  L <- c(L, sprintf("- sigma-pole cells in new: %s rows; share at the fallback %.1f%%; sigma_robust TRUE on %.1f%%.", format(nrow(pole_rows), big.mark = ","), 100 * mean(abs(pole_rows$sigma - fn$value) < 1e-9), 100 * mean(pole_rows$sigma_robust %in% TRUE)))
  if (mean(abs(pole_rows$sigma - fn$value) < 1e-9) < 0.99) fail("sigma-pole cells are not all at the fallback sigma")
  if (any(pole_rows$sigma_robust %in% TRUE)) fail("a sigma-pole cell publishes sigma_robust TRUE")
}

# --- headline and status
# (patch 0102) non_converged is the optimizer's: convergence -1 among the
# directly estimated rows (tier < 3). Tier-3 rows carry convergence -1 by
# construction, so over all rows the share is ~Tier 3 and moves with the
# published row count -- the v0.10.0 box gate FAILed on exactly that
# (26.73% -> 26.75%) while the optimizer share was 0.42% in both tables.
st <- function(x) { d <- x[!is.na(x$tier) & x$tier < 3L]
  c(ok = mean(x$convergence %in% 0L & !is.na(x$tier) & x$tier < 3L), non_converged = mean(d$convergence %in% -1L),
    tier3 = mean(x$tier %in% 3L), robust = mean(x$sigma_robust %in% TRUE)) }
so <- st(oldp); sn <- st(newp)
L <- c(L, "", "## Headline (published rows)", "", "| | old | new |", "|---|---|---|",
       sprintf("| gamma median | %.4f | %.4f |", median(oldp$gamma, na.rm = TRUE), median(newp$gamma, na.rm = TRUE)),
       sprintf("| opt_tariff median | %.4f | %.4f |", median(oldp$opt_tariff, na.rm = TRUE), median(newp$opt_tariff, na.rm = TRUE)),
       sprintf("| sigma median | %.4f | %.4f |", median(oldp$sigma, na.rm = TRUE), median(newp$sigma, na.rm = TRUE)),
       sprintf("| ok share | %.1f%% | %.1f%% |", 100 * so["ok"], 100 * sn["ok"]), sprintf("| optimizer non-converged (directly estimated rows) | %.2f%% | %.2f%% |", 100 * so["non_converged"], 100 * sn["non_converged"]),
       sprintf("| Tier 3 | %.1f%% | %.1f%% |", 100 * so["tier3"], 100 * sn["tier3"]), sprintf("| sigma_robust TRUE | %.1f%% | %.1f%% |", 100 * so["robust"], 100 * sn["robust"]),
       sprintf("| gamma <= 0.01 (estimated) | %.3f%% | %.3f%% |", 100 * mean(est(oldp)$gamma <= 0.01), 100 * mean(est(newp)$gamma <= 0.01)),
       sprintf("| gamma >= 10 (estimated) | %.3f%% | %.3f%% |", 100 * mean(est(oldp)$gamma >= 10), 100 * mean(est(newp)$gamma >= 10)))
if (sn["non_converged"] > so["non_converged"] + 0.001) fail(sprintf("optimizer non-convergence among directly estimated rows rose by more than 0.1 point (%.2f%% -> %.2f%%)", 100 * so["non_converged"], 100 * sn["non_converged"]))

# --- step by class on shared directly-estimated rows
eo <- est(oldp)[, .(importer, exporter, good, g_old = gamma)]; en <- est(newp)[, .(importer, exporter, good, g_new = gamma)]
j <- merge(eo, en, by = c("importer", "exporter", "good"))
j[, cell := paste(importer, good)]; j <- merge(j, s1[, .(cell = paste(importer, good), cls)], by = "cell", all.x = TRUE)
j[is.na(cls), cls := "not_in_stage1"]; j[, step := abs(log(g_new) - log(g_old))]
stp <- j[, .(rows = .N, p50 = q(step, .5), p90 = q(step, .9), p99 = q(step, .99), below_1e2 = mean(step < 1e-2)), by = cls][order(cls)]
L <- c(L, "", "## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by Stage-1 class", "", "| class | rows | p50 | p90 | p99 | below 1e-2 |", "|---|---|---|---|---|---|",
       sprintf("| %s | %s | %.2e | %.3f | %.3f | %.1f%% |", stp$cls, format(stp$rows, big.mark = ","), stp$p50, stp$p90, stp$p99, 100 * stp$below_1e2))

# --- pass log
if (!is.na(log_p) && file.exists(log_p)) {
  pl <- fread(log_p); L <- c(L, "", "## gamma_V pass log", "", paste0("    ", capture.output(print(pl))))
} else L <- c(L, "", "(no pass log given)")

L <- c(L, "", "## Result", "", if (length(fails)) c("**FAIL**", "", paste0("- ", fails)) else "**PASS**")
dir.create(dirname(out_p), showWarnings = FALSE, recursive = TRUE); writeLines(L, out_p)
cat(paste(L, collapse = "\n"), "\n"); cat(sprintf("gate_v0100: wrote %s\n", out_p))
if (length(fails)) quit(status = 1L)
