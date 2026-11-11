#!/usr/bin/env Rscript
# =============================================================================
# analysis/gate_release.R   (patch 0104)
#
# The release gate, for any Stage-2b table against its predecessor on a given
# Stage-1 table. Replaces the version-specific analysis/gate_v0100.R (kept for
# the v0.10.0 record). Hard checks (any failure -> exit status 1):
#   H1 core schema present;
#   H2 published row count within --max-row-change of the old table's;
#   H3 optimizer non-convergence among directly estimated rows not up by more
#      than 0.1 point -- the optimizer's codes (1 / 10 / 51 / 52) among
#      is_estimated_row() rows, stage2_convergence_census() in
#      R/utils_general.R (patch 0116; through 0115 this counted convergence -1
#      among tier < 3 rows, i.e. the imputed reference rows of all-Tier-3
#      cells, which the report now shows on its own line);
#   H4 the sigma column is the one the rules imply: every cell in the clean
#      set (stage2_sigma_clean() with --edge-rule / --pole-rule / --pole-se)
#      carries its Stage-1 sigma, every other row the fallback (clean-set
#      median, or --fallback-pin);
#   H5 sigma_robust is FALSE on every fallback row;
#   H6 sigma_source, if present, equals the reconstruction;
#   H7 trim_reason, if present, takes only the trim's reason codes;
#   H8 gamma_v_resid, when the pass log shows two or more passes, is filled on
#      more than half the published rows.
# (patch 0157) When the new table carries sigma_source_stage1 -- a run under
# --stage2-sigma-update import, the default since patch 0155 -- H4/H5/H6 read
# the update's rules instead, from --profile (the run's _sigma_update_pass<u>.csv,
# the last pass) and --update-log (its _sigma_update_passes.csv): a profiled cell
# with status ok carries 1 + exp(L + b_full (ln(sigma_update - 1) - L)) (or the
# unshrunk profile when the log's shrink_b_full is NA) and sigma_source
# 'updated_import_shrunk' ('updated_import' unshrunk); any other profiled cell
# the level 1 + exp(L) and 'updated_level'; a cell not profiled keeps its
# Stage-1 sigma if its Stage-1 label is 'estimated', else the level (the
# fallback under the flag; the clean-set median unshrunk); sigma_source_stage1
# equals the Stage-1 reconstruction; sigma_robust is FALSE on every row whose
# sigma_source is not 'estimated'. (patch 0167) When the log's `unprofiled`
# column says 'level' (--stage2-sigma-update-unprofiled level, the default since
# 0167) and the update is shrunk, an unprofiled cell whose Stage-1 label is
# 'estimated' carries the level and 'updated_level' instead; a log without the
# column (v0.12.0-v0.12.1) is read under the old rule. A run with no sigma tail
# in its trim has no 'sigma_lo' rows, which H7 accepts as it is.
# Report: headline medians, fallback sigma and share, |d ln gamma| by sigma
# source on shared directly estimated rows, the pass log.
#
# Usage (repo root):
#   Rscript analysis/gate_release.R --old OLD_2B.rds --new NEW_2B.rds --stage1 STAGE1.rds
#       [--pass-log PASSES.csv] [--edge-rule fallback] [--pole-rule fallback] [--pole-se 1]
#       [--fallback-pin X] [--max-row-change 0.02] [--out docs/results/gate_<label>.md] [--label NAME]
#       [--profile SIGMA_UPDATE_PASS.csv --update-log SIGMA_UPDATE_PASSES.csv]   (the sigma update, patch 0157)
# =============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
old_p <- get_arg("--old", NA_character_); new_p <- get_arg("--new", NA_character_); s1_p <- get_arg("--stage1", NA_character_)
log_p <- get_arg("--pass-log", NA_character_); edge_rule <- get_arg("--edge-rule", "fallback"); pole_rule <- get_arg("--pole-rule", "fallback")
pole_c <- as.numeric(get_arg("--pole-se", "1")); pin <- suppressWarnings(as.numeric(get_arg("--fallback-pin", NA_character_)))
max_rc <- as.numeric(get_arg("--max-row-change", "0.02")); label <- get_arg("--label", "release")
out_p <- get_arg("--out", sprintf("docs/results/gate_%s.md", label))
prof_p <- get_arg("--profile", NA_character_); ulog_p <- get_arg("--update-log", NA_character_)   # patch 0157
if (anyNA(c(old_p, new_p, s1_p))) stop("usage: Rscript analysis/gate_release.R --old OLD.rds --new NEW.rds --stage1 STAGE1.rds [options]")
for (p in c(old_p, new_p, s1_p)) if (!file.exists(p)) stop("not found: ", p)
.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) ".")
sink(tempfile()); source(file.path(normalizePath(file.path(.this_dir, ".."), mustWork = FALSE), "R", "feen94_het_baci.R")); sink()

key <- function(x) { x <- as.data.table(x); for (k in intersect(c("importer", "exporter", "good"), names(x))) set(x, j = k, value = as.character(x[[k]])); x }
old <- key(readRDS(old_p)); new <- key(readRDS(new_p)); s1 <- key(readRDS(s1_p))
pub <- function(x) if ("trim_reason" %in% names(x)) x[is.na(trim_reason)] else x
q <- function(v, p) { v <- v[is.finite(v)]; if (length(v)) unname(quantile(v, p)) else NA_real_ }
fails <- character(0); fail <- function(id, msg) fails <<- c(fails, sprintf("%s %s", id, msg))
oldp <- pub(old); newp <- pub(new)
L <- c(sprintf("# Release gate (%s): %s -> %s", label, basename(old_p), basename(new_p)), "",
       sprintf("Stage 1 `%s`; rules: edge %s, pole %s (c = %s)%s. Generated %s.", basename(s1_p), edge_rule, pole_rule, pole_c,
               if (!is.na(pin)) sprintf(", fallback pinned at %s", pin) else "", format(Sys.time(), "%Y-%m-%d %H:%M %Z")), "")

# H1 schema
core <- c("importer", "exporter", "good", "sigma", "gamma", "gamma_se", "tier", "convergence", "opt_tariff", "sigma_robust")
miss <- setdiff(core, names(new)); if (length(miss)) fail("H1", paste("missing columns:", paste(miss, collapse = ", ")))
# H2 rows
rc <- nrow(newp) / nrow(oldp) - 1
L <- c(L, "## Rows and schema", "", sprintf("- old: %s rows (%s published), %d columns; new: %s rows (%s published), %d columns; published change %+.2f%%.",
       format(nrow(old), big.mark = ","), format(nrow(oldp), big.mark = ","), ncol(old), format(nrow(new), big.mark = ","), format(nrow(newp), big.mark = ","), ncol(new), 100 * rc))
if (abs(rc) > max_rc) fail("H2", sprintf("published rows changed by %+.2f%% (limit %.1f%%)", 100 * rc, 100 * max_rc))
# H3 optimizer non-convergence on directly estimated rows (patch 0116: the
# optimizer's codes; convergence -1 marks imputed rows, never a failed fit)
cco <- stage2_convergence_census(old); ccn <- stage2_convergence_census(new)
nco <- cco$share_nonconverged; ncn <- ccn$share_nonconverged
if (isTRUE(ncn > nco + 0.001)) fail("H3", sprintf("optimizer non-convergence among directly estimated rows rose %.2f%% -> %.2f%%", 100 * nco, 100 * ncn))
# H4 / H5 / H6 sigma reconstruction
sc <- stage2_sigma_clean(s1, edge_rule, pole_rule, pole_c)
fb <- if (!is.na(pin)) pin else median(sc$clean$sigma, na.rm = TRUE)
rec <- attach_sigma_source(copy(new), sc$source)$table   # patch 0116: the returned table (0114's contract), not the side effect
s1k <- s1[, .(k = paste(importer, good, sep = "\r"), s1_sigma = sigma)]
s1_sig <- s1k$s1_sigma[match(paste(rec$importer, rec$good, sep = "\r"), s1k$k)]
close <- function(a, b) is.finite(a) & is.finite(b) & abs(a - b) <= 1e-9 * pmax(abs(b), 1)
update_mode <- "sigma_source_stage1" %in% names(new)   # patch 0157: a run under --stage2-sigma-update import
if (!update_mode) {
  is_est <- rec$sigma_source == "estimated"
  bad4 <- sum(is_est & !close(rec$sigma, s1_sig)) + sum(!is_est & !close(rec$sigma, fb))
  if (bad4 > 0L) fail("H4", sprintf("%s rows carry a sigma the rules do not imply (estimated cells must carry their Stage-1 sigma, the rest the fallback %.6f)", format(bad4, big.mark = ","), fb))
  bad5 <- sum(!is_est & rec$sigma_robust %in% TRUE)
  if (bad5 > 0L) fail("H5", sprintf("%s fallback-sigma rows publish sigma_robust TRUE", format(bad5, big.mark = ",")))
  if ("sigma_source" %in% names(new)) { bad6 <- sum(new$sigma_source != rec$sigma_source); if (bad6 > 0L) fail("H6", sprintf("sigma_source differs from the reconstruction on %s rows", format(bad6, big.mark = ","))) }
  srcp <- rec[is.na(if ("trim_reason" %in% names(rec)) rec$trim_reason else rep(NA, nrow(rec)))]
  L <- c(L, "", "## Sigma", "", sprintf("- fallback sigma %.4f on %.1f%% of published rows (old table: %.4f on %.1f%%).", fb, 100 * mean(srcp$sigma_source != "estimated"),
         as.numeric(names(which.max(table(oldp$sigma)))), 100 * max(table(oldp$sigma)) / nrow(oldp)),
         sprintf("- published rows by source: %s.", paste(sprintf("%s %s", names(table(srcp$sigma_source)), format(as.integer(table(srcp$sigma_source)), big.mark = ",")), collapse = ", ")))
} else {
  # ---- the sigma update's rules (patch 0157) ----
  if (is.na(prof_p) || !file.exists(prof_p) || is.na(ulog_p) || !file.exists(ulog_p))
    fail("H4", "the new table carries sigma_source_stage1 (a sigma-update run) but --profile / --update-log were not given or do not exist")
  else {
    prof <- fread(prof_p, colClasses = list(character = c("importer", "good"))); ulog <- fread(ulog_p); ul <- ulog[which.max(update_pass)]
    b_full <- if ("shrink_b_full" %in% names(ul)) ul$shrink_b_full else NA_real_
    level <- if ("level_sigma" %in% names(ul)) ul$level_sigma else NA_real_
    kp <- paste(prof$importer, prof$good, sep = "\r"); kr <- paste(rec$importer, rec$good, sep = "\r")
    mp <- match(kr, kp); st <- prof$status[mp]; su <- prof$sigma[mp]
    shrunk <- is.finite(b_full)
    Lv <- if (shrunk) log(level - 1) else NA_real_
    exp_sigma <- rep(NA_real_, nrow(rec)); exp_src <- rep(NA_character_, nrow(rec))
    ok <- !is.na(mp) & st == "ok"
    exp_sigma[ok] <- if (shrunk) 1 + exp(Lv + b_full * (log(su[ok] - 1) - Lv)) else su[ok]
    exp_src[ok] <- if (shrunk) "updated_import_shrunk" else "updated_import"
    notok <- !is.na(mp) & st != "ok"
    s1_lab <- rec$sigma_source                       # the Stage-1 reconstruction (attach_sigma_source on the Stage-1 rules)
    if (shrunk) { exp_sigma[notok] <- level; exp_src[notok] <- "updated_level" }
    else { exp_sigma[notok] <- ifelse(s1_lab[notok] == "estimated", s1_sig[notok], fb); exp_src[notok] <- s1_lab[notok] }
    np <- is.na(mp)
    exp_sigma[np] <- ifelse(s1_lab[np] == "estimated", s1_sig[np], if (shrunk) level else fb); exp_src[np] <- s1_lab[np]
    unprof_level <- shrunk && "unprofiled" %in% names(ul) && identical(as.character(ul$unprofiled), "level")   # patch 0167
    if (unprof_level) { npe <- np & s1_lab == "estimated"; exp_sigma[npe] <- level; exp_src[npe] <- "updated_level" }
    bad4 <- sum(!close(new$sigma, exp_sigma))
    if (bad4 > 0L) fail("H4", sprintf("%s rows carry a sigma the sigma update's rules do not imply (%s; level %.6f, b_full %s)", format(bad4, big.mark = ","),
                                     if (shrunk) "shrunk profile on ok cells, the level elsewhere" else "the unshrunk profile on ok cells", level, format(b_full)))
    bad5 <- sum(exp_src != "estimated" & new$sigma_robust %in% TRUE)
    if (bad5 > 0L) fail("H5", sprintf("%s rows without a Stage-1 sigma publish sigma_robust TRUE", format(bad5, big.mark = ",")))
    bad6 <- sum(new$sigma_source != exp_src) + sum(new$sigma_source_stage1 != s1_lab)
    if (bad6 > 0L) fail("H6", sprintf("sigma_source / sigma_source_stage1 differ from the reconstruction on %s rows", format(bad6, big.mark = ",")))
    if ("sigma_update" %in% names(new)) { bad6b <- sum(ok & !close(new$sigma_update, su)); if (bad6b > 0L) fail("H6", sprintf("sigma_update differs from the profile on %s rows", format(bad6b, big.mark = ","))) }
  }
  srcp <- new[is.na(if ("trim_reason" %in% names(new)) new$trim_reason else rep(NA, nrow(new)))]
  L <- c(L, "", "## Sigma (the update, patch 0152-0155)", "",
         if (!is.na(ulog_p) && file.exists(ulog_p)) sprintf("- update pass %d: %s cells profiled, %s updated, %d at the floor, %d at the cap; level sigma %s; B %s, b_full %s.", ul$update_pass,
                 format(ul$cells_profiled, big.mark = ","), format(ul$cells_updated, big.mark = ","), ul$at_floor, ul$at_cap, format(ul$level_sigma, digits = 5), format(ul$shrink_b_half), format(ul$shrink_b_full)) else "- no update log given.",
         sprintf("- published rows by source: %s.", paste(sprintf("%s %s", names(table(srcp$sigma_source)), format(as.integer(table(srcp$sigma_source)), big.mark = ",")), collapse = ", ")),
         sprintf("- published rows by Stage-1 source: %s.", paste(sprintf("%s %s", names(table(srcp$sigma_source_stage1)), format(as.integer(table(srcp$sigma_source_stage1)), big.mark = ",")), collapse = ", ")),
         sprintf("- old table: fallback sigma %.4f on %.1f%% of published rows.", as.numeric(names(which.max(table(oldp$sigma)))), 100 * max(table(oldp$sigma)) / nrow(oldp)))
}
# H7 trim reasons
if ("trim_reason" %in% names(new)) { bad7 <- setdiff(unique(na.omit(new$trim_reason)), c("sigma_lo", "gamma_lo", "gamma_hi", "na_sigma_or_gamma")); if (length(bad7)) fail("H7", paste("unknown trim_reason codes:", paste(bad7, collapse = ", "))) }
# H8 gamma_v_resid
passes <- NA_integer_
if (!is.na(log_p) && file.exists(log_p)) { pl <- fread(log_p); passes <- max(pl$pass) }
if (isTRUE(passes >= 2L)) {
  if (!"gamma_v_resid" %in% names(new)) fail("H8", "no gamma_v_resid column although the run made two or more passes")
  else if (mean(is.finite(newp$gamma_v_resid)) <= 0.5) fail("H8", sprintf("gamma_v_resid filled on only %.1f%% of published rows", 100 * mean(is.finite(newp$gamma_v_resid))))
}
# report
est <- function(x) x[!is.na(tier) & tier < 3L & convergence %in% 0L & is.finite(gamma) & gamma > 0]
L <- c(L, "", "## Headline (published rows)", "", "| | old | new |", "|---|---|---|",
       sprintf("| gamma median | %.4f | %.4f |", median(oldp$gamma, na.rm = TRUE), median(newp$gamma, na.rm = TRUE)),
       sprintf("| opt_tariff median | %.4f | %.4f |", median(oldp$opt_tariff, na.rm = TRUE), median(newp$opt_tariff, na.rm = TRUE)),
       sprintf("| sigma median | %.4f | %.4f |", median(oldp$sigma, na.rm = TRUE), median(newp$sigma, na.rm = TRUE)),
       sprintf("| optimizer non-converged (directly estimated rows) | %.2f%% | %.2f%% |", 100 * nco, 100 * ncn),
       sprintf("| optimizer non-converged cells | %s | %s |", format(cco$n_cells_nonconverged, big.mark = ","), format(ccn$n_cells_nonconverged, big.mark = ",")),
       sprintf("| imputed reference rows (all-Tier-3 cells; share of tier < 3 rows) | %.2f%% | %.2f%% |", 100 * cco$share_imputed_reference, 100 * ccn$share_imputed_reference),
       sprintf("| Tier 3 | %.1f%% | %.1f%% |", 100 * mean(oldp$tier %in% 3L), 100 * mean(newp$tier %in% 3L)),
       sprintf("| sigma_robust TRUE | %.1f%% | %.1f%% |", 100 * mean(oldp$sigma_robust %in% TRUE), 100 * mean(newp$sigma_robust %in% TRUE)))
j <- merge(est(oldp)[, .(importer, exporter, good, g_old = gamma)], est(srcp)[, .(importer, exporter, good, g_new = gamma, sigma_source)], by = c("importer", "exporter", "good"))
if (nrow(j)) { j[, d := abs(log(g_new) - log(g_old))]
  st <- j[, .(rows = .N, p50 = q(d, .5), p90 = q(d, .9), p99 = q(d, .99), below = mean(d < 1e-2)), by = sigma_source][order(sigma_source)]
  L <- c(L, "", "## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by sigma source", "", "| source | rows | p50 | p90 | p99 | below 1e-2 |", "|---|---|---|---|---|---|",
         sprintf("| %s | %s | %.2e | %.3f | %.3f | %.1f%% |", st$sigma_source, format(st$rows, big.mark = ","), st$p50, st$p90, st$p99, 100 * st$below)) }
if (!is.na(passes)) L <- c(L, "", "## gamma_V pass log", "", paste0("    ", capture.output(print(pl))))
L <- c(L, "", "## Result", "", if (length(fails)) c("**FAIL**", "", paste0("- ", fails)) else "**PASS**")
dir.create(dirname(out_p), showWarnings = FALSE, recursive = TRUE); writeLines(L, out_p)
cat(paste(L, collapse = "\n"), "\n"); cat(sprintf("gate_release: wrote %s\n", out_p))
if (length(fails)) quit(status = 1L)
