#!/usr/bin/env Rscript
# ============================================================================
# analysis/reference_exporter_census.R  (patch 0125, audit #8)
#
# Both stages difference every exporter's log share and log unit value
# against a reference exporter k, chosen by the same rule -- most periods,
# ties by total value -- but each on its own sample:
#   Stage 1 (prepare_cell_moments()): years in LEVELS on the untrimmed panel;
#   Stage 2 (choose_reference(), rule periods_value): retained DIFFERENCED
#     years on the panel after the |d ln p| >= 2 trim.
# In population either stage's estimates are the same for any k, and Stage 2
# takes Stage 1's sigma as a number, not its reference, so nothing requires
# the two references to coincide. What a reference does change in a finite
# sample: an exporter's observation in year t needs k's difference in t, so
# every year k lacks a difference is lost for the whole cell; and k's own
# shocks -- unit-value jumps included -- enter every observation of the cell.
# This census, run on the raw cache and the shipped tables (no estimation):
#   A  how often the two stages' references differ;
#   B  the Stage-1 observations the level-count rule loses: against the
#      counting-basis alternative (most DIFFERENCED years, ties by value) and
#      against the best reference among the cell's five longest differenced
#      series (the one sharing the most years with the others);
#   C  how often the Stage-1 reference's own series has |d ln p| >= 2 years,
#      and the share of the cell's Stage-1 observations they enter;
#   plus a check that the Stage-2 rule, recomputed here, reproduces the
#   published ref_exporter.
#
# Reading (fixed in patch 0125): a local Stage-1 A/B (subsample, no EC2) of a
# reference rule that keeps more observations is worth running if, in at
# least 10% of the Stage-1 cells with an estimate, the current rule loses at
# least 5% of the cell's usable observations against the best of the five
# candidates ("run the A/B"); otherwise the rule stays and the docs say so
# ("closed"). A and C are informational:
# aligning the two stages' references has no population consequence, and
# Stage 1 keeps its jumps by the 2026-09-22 sample decision.
#
# Usage (repo root; local; ~5-15 min and ~10-15 GB of RAM on the full cache):
#   Rscript analysis/reference_exporter_census.R --raw-cache PATH --stage1 S1.rds --stage2b S2B.rds
#       [--out results/reference_exporter_census.json] [--md docs/results/reference_exporter_census.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.pc16 <- vapply(0:65535, function(v) sum(as.integer(intToBits(v))), 0L)
#' Bit count of non-negative integers below 2^31.
popcount <- function(x) .pc16[bitwAnd(x, 65535L) + 1L] + .pc16[bitwShiftR(x, 16L) + 1L]

#' Per (importer, good, exporter): level years, total value, and year masks of
#' valid differences (all; and those with |d ln p| >= jump) -- the inputs of
#' both reference rules, from a raw-cache table.
ref_exporter_panel <- function(raw, jump = 2) {
  x <- data.table::as.data.table(raw)[is.finite(cusval) & is.finite(quantity) & cusval > 0 & quantity > 0,
                                      .(year, good, importer, exporter, cusval, quantity)]
  if (anyDuplicated(x, by = c("importer", "good", "exporter", "year")))
    x <- x[, .(cusval = sum(cusval), quantity = sum(quantity)), by = .(importer, good, exporter, year)]
  y0 <- min(x$year)
  if (max(x$year) - y0 > 30L) stop("ref_exporter_panel(): more than 31 years; the year masks hold 31")
  data.table::setorder(x, importer, good, exporter, year)
  x[, lp := log(cusval / quantity)]
  x[, `:=`(gap = year - data.table::shift(year), dlp = lp - data.table::shift(lp)), by = .(importer, good, exporter)]
  x[, valid := !is.na(gap) & gap == 1L & is.finite(dlp)]
  x[, bit := bitwShiftL(1L, year - y0)]
  p <- x[, .(n_levels = .N, total = sum(cusval),
             n_dif = sum(valid), n_dif_trim = sum(valid & abs(dlp) < jump), total_dif_trim = sum(cusval[valid & abs(dlp) < jump]),
             d_mask = sum(bit[valid]), j_mask = sum(bit[valid & abs(dlp) >= jump])),
         by = .(importer, good, exporter)]
  p[, `:=`(d_mask = as.integer(d_mask), j_mask = as.integer(j_mask))]
  p
}

#' One reference per (importer, good) under a rule on the panel above.
#'   "stage1"     -- most level years, ties by total value (prepare_cell_moments());
#'   "stage2"     -- most retained differenced years, ties by their value
#'                   (choose_reference(), periods_value);
#'   "stage1_dif" -- the counting-basis alternative: most differenced years
#'                   (untrimmed, the observations Stage 1 uses), ties by total value.
#' Exact ties go to the smallest exporter code, as the stages' which.max() on
#' exporter-sorted groups does.
ref_exporter_pick <- function(p, rule) {
  o <- switch(rule,
              stage1 = p[order(importer, good, -n_levels, -total, exporter)],
              stage2 = p[n_dif_trim > 0][order(importer, good, -n_dif_trim, -total_dif_trim, exporter)],
              stage1_dif = p[order(importer, good, -n_dif, -total, exporter)],
              stop("ref_exporter_pick(): unknown rule ", rule))
  o[, .SD[1L], by = .(importer, good)][, .(importer, good, ref = exporter, ref_d = d_mask, ref_j = j_mask)]
}

#' The reference sharing the most differenced years with the cell's other
#' exporters, among its k longest differenced series (ties by differences,
#' then value, then the smallest code).
ref_exporter_best <- function(p, k = 5L) {
  cand <- p[order(importer, good, -n_dif, -total, exporter)][, utils::head(.SD, k), by = .(importer, good)]
  cand <- cand[, .(importer, good, ref = exporter, ref_d = d_mask, ref_j = j_mask, ref_n = n_dif, ref_tot = total)]
  m <- cand[p, on = .(importer, good), allow.cartesian = TRUE, nomatch = NULL][exporter != ref]
  sc <- m[, .(obs = sum(popcount(bitwAnd(d_mask, ref_d)))), by = .(importer, good, ref, ref_d, ref_j, ref_n, ref_tot)]
  sc <- sc[order(importer, good, -obs, -ref_n, -ref_tot, ref)][, .SD[1L], by = .(importer, good)]
  sc[, .(importer, good, ref, ref_d, ref_j)]
}

#' Stage-1 observations under a reference: sum over the cell's other exporters of
#' the years both have a valid difference; and those falling in the reference's
#' jump years.
ref_exporter_obs <- function(p, refs) {
  m <- refs[p, on = .(importer, good), nomatch = NULL][exporter != ref]
  m[, .(obs = sum(popcount(bitwAnd(d_mask, ref_d))), obs_jump = sum(popcount(bitwAnd(d_mask, ref_j))),
        potential = sum(popcount(d_mask))), by = .(importer, good, ref)]
}

#' The census on a raw-cache table and the shipped Stage-1 / Stage-2b tables.
reference_exporter_census <- function(raw, s1, s2b, jump = 2, loss_threshold = 0.05, cell_share_threshold = 0.10) {
  p <- ref_exporter_panel(raw, jump)
  key <- function(d) d[, `:=`(importer = as.integer(importer), good = as.character(good))]
  s1 <- key(data.table::as.data.table(s1)[status == "ok", .(importer, good)])
  pub <- data.table::as.data.table(s2b)
  if ("trim_reason" %in% names(pub)) pub <- pub[is.na(trim_reason)]
  r2_pub <- key(unique(pub[, .(importer, good, ref_pub = as.integer(ref_exporter))]))
  r1 <- ref_exporter_pick(p, "stage1"); r2 <- ref_exporter_pick(p, "stage2"); ra <- ref_exporter_pick(p, "stage1_dif")
  rb <- ref_exporter_best(p)
  # A: the two stages' references, on cells with a Stage-1 estimate and published Stage-2 rows
  a <- merge(merge(s1, r1[, .(importer, good, ref1 = ref)], by = c("importer", "good")), r2_pub, by = c("importer", "good"))
  # replication check of the Stage-2 rule against the published column
  rep <- merge(r2_pub, r2[, .(importer, good, ref2 = ref)], by = c("importer", "good"))
  # B and C: on cells with a Stage-1 estimate
  o1 <- merge(s1, ref_exporter_obs(p, r1), by = c("importer", "good"))
  oa <- merge(s1, ref_exporter_obs(p, ra), by = c("importer", "good"))
  ob <- merge(s1, ref_exporter_obs(p, rb), by = c("importer", "good"))
  b <- merge(merge(o1[, .(importer, good, ref1 = ref, obs1 = obs, jump1 = obs_jump, potential)],
                   oa[, .(importer, good, ref_alt = ref, obs_alt = obs)], by = c("importer", "good")),
             ob[, .(importer, good, ref_best = ref, obs_best = obs)], by = c("importer", "good"))
  b[, excess_loss := fifelse(obs_best > 0, pmax(0, (obs_best - obs1) / obs_best), 0)]
  b[, excess_loss_alt := fifelse(obs_alt > 0, pmax(0, (obs_alt - obs1) / obs_alt), 0)]
  b[, jump_share := fifelse(obs1 > 0, jump1 / obs1, NA_real_)]
  q <- function(v) as.list(stats::setNames(stats::quantile(v, c(0.5, 0.9, 0.99), na.rm = TRUE, names = FALSE), c("p50", "p90", "p99")))
  share_trigger <- mean(b$excess_loss >= loss_threshold)
  list(
    A_stage_references = list(cells = nrow(a), differ = sum(a$ref1 != a$ref_pub), share_differ = mean(a$ref1 != a$ref_pub)),
    stage2_rule_replication = list(cells = nrow(rep), agree = sum(rep$ref_pub == rep$ref2), share_agree = mean(rep$ref_pub == rep$ref2)),
    B_observations = list(cells = nrow(b), alt_differs = sum(b$ref1 != b$ref_alt), share_alt_differs = mean(b$ref1 != b$ref_alt),
                          best_differs = sum(b$ref1 != b$ref_best), share_best_differs = mean(b$ref1 != b$ref_best),
                          obs_current = sum(as.numeric(b$obs1)), obs_alt = sum(as.numeric(b$obs_alt)), obs_best = sum(as.numeric(b$obs_best)),
                          obs_potential = sum(as.numeric(b$potential)),
                          excess_loss = q(b$excess_loss), excess_loss_alt = q(b$excess_loss_alt),
                          share_cells_loss_ge_threshold = share_trigger, share_cells_loss_alt_ge_threshold = mean(b$excess_loss_alt >= loss_threshold),
                          loss_threshold = loss_threshold, cell_share_threshold = cell_share_threshold),
    C_reference_jumps = list(cells = nrow(b), share_ref_with_jump = mean(b$jump1 > 0),
                             jump_share_of_obs_given_jump = q(b$jump_share[b$jump1 > 0]), jump_threshold = jump),
    reading = if (share_trigger >= cell_share_threshold) "run the A/B" else "closed")
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  rc <- get_arg("--raw-cache", NA_character_); s1p <- get_arg("--stage1", NA_character_); s2p <- get_arg("--stage2b", NA_character_)
  if (any(is.na(c(rc, s1p, s2p))) || !all(file.exists(c(rc, s1p, s2p))))
    stop("usage: Rscript analysis/reference_exporter_census.R --raw-cache PATH --stage1 S1.rds --stage2b S2B.rds [--out F.json] [--md F.md]")
  out <- get_arg("--out", "results/reference_exporter_census.json"); md <- get_arg("--md", "docs/results/reference_exporter_census.md")
  t0 <- Sys.time()
  res <- reference_exporter_census(readRDS(rc), readRDS(s1p), readRDS(s2p))
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  res$meta <- list(raw_cache = rc, stage1 = s1p, stage2b = s2p, git_rev = rev, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
                   minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
  jsonlite::write_json(res, out, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  A <- res$A_stage_references; B <- res$B_observations; C <- res$C_reference_jumps; R <- res$stage2_rule_replication
  pct <- function(x) sprintf("%.1f%%", 100 * x); n <- function(x) format(x, big.mark = ",")
  writeLines(enc2utf8(c("# Reference exporters in the two stages (patch 0125)", "",
    sprintf("Raw cache `%s`, Stage 1 `%s`, Stage 2b `%s`; rev %s, %s.", rc, s1p, s2p, rev, res$meta$timestamp), "",
    "Both stages pick the exporter with the most periods (ties by total value): Stage 1 counts years in levels on the untrimmed panel, Stage 2 counts retained differenced years after the |d ln p| >= 2 trim. An exporter's observation in year t needs the reference's difference in t, so each year the reference lacks one is lost for the whole cell; the reference's own shocks enter every observation.", "",
    sprintf("- **A. The two references differ** in %s of the %s cells with a Stage-1 estimate and published Stage-2 rows (%s cells).", pct(A$share_differ), n(A$cells), n(A$differ)),
    sprintf("- **Stage-2 rule recomputed here** reproduces the published `ref_exporter` in %s of %s cells.", pct(R$share_agree), n(R$cells)),
    sprintf("- **B. Observations.** On %s cells with a Stage-1 estimate, Stage-1 observations number %s under the current rule, %s under the counting-basis alternative (most differenced years; another reference in %s of cells), %s under the best of the five longest differenced series (another reference in %s of cells), and %s if the reference had every year. The current rule's loss against the best: median %s, p90 %s, p99 %s of a cell's observations, at least %s in %s of cells (against the simple alternative: at least %s in %s of cells).",
            n(B$cells), n(B$obs_current), n(B$obs_alt), pct(B$share_alt_differs), n(B$obs_best), pct(B$share_best_differs), n(B$obs_potential),
            pct(B$excess_loss$p50), pct(B$excess_loss$p90), pct(B$excess_loss$p99), pct(B$loss_threshold), pct(B$share_cells_loss_ge_threshold),
            pct(B$loss_threshold), pct(B$share_cells_loss_alt_ge_threshold)),
    sprintf("- **C. Jumps.** The Stage-1 reference's own series has at least one |d ln p| >= %s year in %s of cells; in those cells such years enter a median %s of the cell's Stage-1 observations (p90 %s).",
            format(C$jump_threshold), pct(C$share_ref_with_jump), pct(C$jump_share_of_obs_given_jump$p50), pct(C$jump_share_of_obs_given_jump$p90)), "",
    sprintf("**Reading (fixed in patch 0125): %s.** A local Stage-1 A/B of a rule that keeps more observations is worth running if the current rule loses at least %s of a cell's usable observations against the best of the five candidates in at least %s of cells. A and C are informational: aligning the two stages' references has no population consequence, and Stage 1 keeps its jumps by the 2026-09-22 sample decision.",
            res$reading, pct(B$loss_threshold), pct(B$cell_share_threshold)))), md, useBytes = TRUE)
  cat(sprintf("reference exporter census (%.1f min): references differ in %.1f%% of cells; excess loss >= 5%% in %.1f%% of cells -> %s (%s, %s)\n",
              res$meta$minutes, 100 * A$share_differ, 100 * B$share_cells_loss_ge_threshold, res$reading, out, md))
}
