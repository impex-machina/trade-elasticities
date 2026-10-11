#!/usr/bin/env Rscript
# =============================================================================
# analysis/trim_diagnostic.R   (patch 0097, 2026-10-11)
#
# The pre-trim gamma blow-up diagnostic. Reads a run's tail-trim record
# (<prefix>_stage2_trimmed.rds or .csv: full rows + reason since patch 0093,
# the seven-column record of earlier runs is accepted), the published Stage-2b
# table and the Stage-1 table, and characterises the rows the trim removed:
#
#   1. composition -- reason x tier, reason x convergence, cells and goods;
#   2. the sigma behind the gamma tails -- Eq. (10)'s coefficients carry
#      1/(sigma - 1), so a gamma that explodes may be a sigma near the pole;
#      sigma level, provenance (HLIML interior / Step 2 / boundary / fallback)
#      and SE of the trimmed rows' cells against the published rows';
#   3. concentration -- is the blow-up cell-level (many rows of one cell, a
#      bad sigma) or row-level (one exporter in an otherwise ordinary cell)?
#   4. distance from the good-level prior (recovered from the Tier-3 rows,
#      whose gamma IS exp(prior)), and, on a full-row record, the trade size,
#      shrinkage weight and exposure of the trimmed rows;
#   5. the within-good alternative -- what a 0.5%-per-tail rule taken within
#      each good would remove, against what the global rule removed.
#
# Nothing here changes a published number; it is the evidence for keeping,
# tightening or re-scoping the trim. Usage (repo root):
#   Rscript analysis/trim_diagnostic.R --trimmed REC --table TABLE.rds --stage1 STAGE1.rds \
#       [--label NAME] [--out docs/results/trim_diagnostic_NAME.md] [--json results/trim_diagnostic_NAME.json]
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.td_key <- function(x) { x <- as.data.table(x); for (k in intersect(c("importer", "exporter", "good"), names(x))) data.table::set(x, j = k, value = as.character(x[[k]])); x }
.q <- function(v, p) { v <- v[is.finite(v)]; if (length(v)) unname(stats::quantile(v, p)) else NA_real_ }
.share <- function(x) if (length(x)) mean(x, na.rm = TRUE) else NA_real_
.fmt <- function(x, d = 3) ifelse(is.na(x), "NA", formatC(x, digits = d, format = "f"))
.pct <- function(x) ifelse(is.na(x), "NA", sprintf("%.1f%%", 100 * x))
.int <- function(x) format(x, big.mark = ",")

#' Read a trim record (.rds or .csv), keyed on character importer / exporter / good.
read_trim_record <- function(path) {
  rec <- if (grepl("\\.rds$", path, ignore.case = TRUE)) readRDS(path) else
    fread(path, colClasses = list(character = intersect(c("importer", "exporter", "good", "ref_exporter"),
                                                        names(fread(path, nrows = 0L)))))
  .td_key(rec)
}

#' The diagnostic. Returns a list; write_trim_diagnostic() renders it.
trim_diagnostic <- function(trimmed, table, stage1, label = "run", trim_pct = 0.005) {
  tr <- .td_key(trimmed); tb <- .td_key(table); s1 <- .td_key(stage1)
  if (!"reason" %in% names(tr)) stop("trim_diagnostic(): the record needs a 'reason' column")
  full_row <- all(c("gamma_se", "avg_trade", "gamma_shrink_wt") %in% names(tr))
  est <- function(x) x[!is.na(tier) & tier < 3L & !(convergence %in% -1L) & is.finite(gamma) & gamma > 0]
  if ("trim_reason" %in% names(tb)) tb <- tb[is.na(trim_reason)]
  pub <- est(tb)
  tails <- tr[reason %in% c("gamma_lo", "gamma_hi")]

  # ---- 1. composition
  by_reason <- tr[, .N, by = reason][order(-N)]
  by_reason_tier <- tr[, .N, by = .(reason, tier)][order(reason, tier)]
  by_reason_conv <- tr[, .(N = .N, non_converged = sum(convergence %in% -1L)), by = reason][order(reason)]
  cells_tr <- uniqueN(paste(tr$importer, tr$good)); goods_tr <- uniqueN(tr$good)
  top_goods <- tr[, .N, by = good][order(-N)][seq_len(min(10L, .N))]

  # ---- 2. sigma behind the gamma tails (cell-level join to Stage 1)
  s1c <- s1[, .(importer, good, s1_sigma = sigma, s1_status = if ("status" %in% names(s1)) status else NA_character_,
                s1_source = if ("final_source" %in% names(s1)) final_source else NA_character_,
                s1_sigma_se = if ("sigma_se" %in% names(s1)) sigma_se else NA_real_,
                s1_adjust = if ("adjust" %in% names(s1)) adjust else NA_integer_,
                s1_sigma_capped = if ("sigma_capped" %in% names(s1)) sigma_capped %in% TRUE else NA)]
  prov <- function(x) {
    x <- merge(x, s1c, by = c("importer", "good"), all.x = TRUE)
    x[, sigma_provenance := fifelse(is.na(s1_status) | !(s1_status %in% "ok"), "fallback_no_estimate",
                               fifelse(s1_sigma_capped %in% TRUE, "fallback_sigma_edge",
                               fifelse(s1_source %in% "hliml", "hliml_interior",
                               fifelse(s1_source %in% "hliml_boundary", "hliml_boundary",
                               fifelse(s1_source %in% "step2", "step2", "other")))))]
    x
  }
  tails_p <- prov(tails); pub_p <- prov(pub)
  sigma_block <- function(x) list(
    n = nrow(x), sigma_median = .q(x$sigma, .5), sigma_p10 = .q(x$sigma, .1),
    share_sigma_lt_1_5 = .share(x$sigma < 1.5), share_sigma_lt_2 = .share(x$sigma < 2),
    share_sigma_ge_10 = .share(x$sigma >= 10),
    sigma_se_median = .q(x$s1_sigma_se, .5),
    share_sigma_se_gt_sigma_minus_1 = .share(is.finite(x$s1_sigma_se) & x$s1_sigma_se > (x$sigma - 1)),
    provenance = as.list(prop.table(table(x$sigma_provenance))))
  sig_tails <- sigma_block(tails_p); sig_pub <- sigma_block(pub_p)
  sig_hi <- sigma_block(tails_p[reason == "gamma_hi"]); sig_lo <- sigma_block(tails_p[reason == "gamma_lo"])

  # ---- 3. concentration
  pre_cells <- rbindlist(list(pub[, .(importer, good)], tails[, .(importer, good)]))[, .(n_pre = .N), by = .(importer, good)]
  tcell <- tails[, .(n_trim = .N), by = .(importer, good)]
  tcell <- merge(tcell, pre_cells, by = c("importer", "good"), all.x = TRUE)
  tcell[, share_of_cell := n_trim / n_pre]
  conc <- list(n_cells_with_tail_rows = nrow(tcell),
               share_tail_rows_in_cells_ge3 = if (nrow(tails)) sum(tcell$n_trim[tcell$n_trim >= 3L]) / nrow(tails) else NA_real_,
               n_cells_half_or_more_trimmed = sum(tcell$share_of_cell >= 0.5, na.rm = TRUE),
               share_tail_rows_in_cells_half_or_more_trimmed = if (nrow(tails)) sum(tcell$n_trim[tcell$share_of_cell >= 0.5]) / nrow(tails) else NA_real_,
               tail_rows_per_cell_median = .q(tcell$n_trim, .5), tail_rows_per_cell_max = if (nrow(tcell)) max(tcell$n_trim) else NA_real_)

  # ---- 4. prior distance; full-row extras
  prior <- tb[tier == 3L & is.finite(gamma) & gamma > 0, .(ln_prior = log(gamma[1])), by = good]
  if (nrow(prior) == 0L) prior <- pub[, .(ln_prior = log(median(gamma))), by = good]
  dev <- function(x) { x <- merge(x, prior, by = "good", all.x = TRUE); abs(log(x$gamma) - x$ln_prior) }
  d_tails <- dev(tails); d_pub <- dev(pub)
  prior_block <- list(abs_ln_dev_from_prior = list(
    tails_p50 = .q(d_tails, .5), tails_p90 = .q(d_tails, .9), pub_p50 = .q(d_pub, .5), pub_p90 = .q(d_pub, .9)))
  extras <- NULL
  if (full_row) {
    extras <- list(
      avg_trade = list(tails_p50 = .q(tails$avg_trade, .5), pub_p50 = .q(pub$avg_trade, .5),
                       share_tails_below_pub_p10 = .share(tails$avg_trade < .q(pub$avg_trade, .1))),
      gamma_shrink_wt = list(tails_p50 = .q(tails$gamma_shrink_wt, .5), pub_p50 = .q(pub$gamma_shrink_wt, .5)),
      gamma_exposure = list(tails_p50 = .q(tails$gamma_exposure, .5), pub_p50 = .q(pub$gamma_exposure, .5)),
      gamma_se_status = as.list(prop.table(table(tails$gamma_se_status))),
      share_tails_sigma_robust = .share(tails$sigma_robust %in% TRUE))
  }

  # ---- 5. the within-good alternative on the pre-trim union of directly estimated rows
  union <- rbindlist(list(pub[, .(importer, exporter, good, gamma, src = "published")],
                          tails[, .(importer, exporter, good, gamma, src = "trimmed_global")]), use.names = TRUE)
  union[, `:=`(lo = quantile(gamma, trim_pct), hi = quantile(gamma, 1 - trim_pct)), by = good]
  union[, within_good_out := gamma < lo | gamma > hi]
  wg <- list(n_union_rows = nrow(union),
             n_removed_global = sum(union$src == "trimmed_global"),
             n_removed_within_good = sum(union$within_good_out),
             n_both = sum(union$within_good_out & union$src == "trimmed_global"),
             n_within_only = sum(union$within_good_out & union$src == "published"),
             n_global_only = sum(!union$within_good_out & union$src == "trimmed_global"),
             goods_with_any_within_good_removal = uniqueN(union$good[union$within_good_out]),
             share_of_global_removals_also_within_good = if (any(union$src == "trimmed_global"))
               sum(union$within_good_out & union$src == "trimmed_global") / sum(union$src == "trimmed_global") else NA_real_)

  list(label = label, generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), full_row_record = full_row,
       n_trimmed = nrow(tr), n_tail_rows = nrow(tails), n_published_estimated = nrow(pub),
       cells_with_trimmed_rows = cells_tr, goods_with_trimmed_rows = goods_tr,
       by_reason = by_reason, by_reason_tier = by_reason_tier, by_reason_conv = by_reason_conv, top_goods = top_goods,
       sigma = list(tails = sig_tails, gamma_hi = sig_hi, gamma_lo = sig_lo, published = sig_pub),
       concentration = conc, prior = prior_block, extras = extras, within_good = wg)
}

#' Render the diagnostic as markdown (returns the lines; writes when out is given).
write_trim_diagnostic <- function(d, out = NULL) {
  L <- c(sprintf("# Pre-trim gamma blow-up diagnostic: %s", d$label), "",
         sprintf("Generated by `analysis/trim_diagnostic.R` on %s. Record: %s.", d$generated,
                 if (d$full_row_record) "full rows (patch 0093)" else "seven-column record (pre-0093; trade size, shrinkage and exposure of the trimmed rows unavailable)"), "",
         sprintf("Trimmed rows %s (gamma tails %s) from %s cells and %s goods; published directly estimated rows %s.",
                 .int(d$n_trimmed), .int(d$n_tail_rows), .int(d$cells_with_trimmed_rows), .int(d$goods_with_trimmed_rows), .int(d$n_published_estimated)), "",
         "## 1. Composition", "", "| reason | rows |", "|---|---|")
  L <- c(L, sprintf("| %s | %s |", d$by_reason$reason, .int(d$by_reason$N)), "", "| reason | tier | rows |", "|---|---|---|",
         sprintf("| %s | %s | %s |", d$by_reason_tier$reason, d$by_reason_tier$tier, .int(d$by_reason_tier$N)), "",
         "| reason | rows | non-converged |", "|---|---|---|",
         sprintf("| %s | %s | %s |", d$by_reason_conv$reason, .int(d$by_reason_conv$N), .int(d$by_reason_conv$non_converged)), "",
         "Top goods by trimmed rows:", "", "| good | rows |", "|---|---|", sprintf("| %s | %s |", d$top_goods$good, .int(d$top_goods$N)), "")
  sb <- function(name, b) c(sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s |", name, .int(b$n), .fmt(b$sigma_median), .fmt(b$sigma_p10),
                                    .pct(b$share_sigma_lt_1_5), .pct(b$share_sigma_lt_2), .pct(b$share_sigma_ge_10), .fmt(b$sigma_se_median), .pct(b$share_sigma_se_gt_sigma_minus_1)))
  L <- c(L, "## 2. The sigma behind the gamma tails (cell-level, from Stage 1)", "",
         "Eq. (10)'s coefficients carry 1/(sigma - 1): a gamma tail can be a sigma near the pole. `SE > sigma - 1` marks a cell whose sigma is within one SE of the pole.", "",
         "| rows | n | sigma median | sigma p10 | sigma < 1.5 | sigma < 2 | sigma >= 10 | sigma SE median | SE > sigma - 1 |", "|---|---|---|---|---|---|---|---|---|",
         sb("gamma_hi", d$sigma$gamma_hi), sb("gamma_lo", d$sigma$gamma_lo), sb("all gamma tails", d$sigma$tails), sb("published (directly estimated)", d$sigma$published), "",
         "Sigma provenance (share of rows):", "", "| rows | " %+% paste(names(d$sigma$published$provenance), collapse = " | ") %+% " |",
         "|---|" %+% paste(rep("---", length(d$sigma$published$provenance)), collapse = "|") %+% "|")
  prov_line <- function(name, b) { v <- sapply(names(d$sigma$published$provenance), function(k) .pct(if (!is.null(b$provenance[[k]])) b$provenance[[k]] else 0)); sprintf("| %s | %s |", name, paste(v, collapse = " | ")) }
  L <- c(L, prov_line("gamma_hi", d$sigma$gamma_hi), prov_line("gamma_lo", d$sigma$gamma_lo), prov_line("published", d$sigma$published), "")
  cc <- d$concentration
  L <- c(L, "## 3. Concentration", "",
         sprintf("- Cells with gamma-tail rows: %s; tail rows per cell median %s, max %s.", .int(cc$n_cells_with_tail_rows), .fmt(cc$tail_rows_per_cell_median, 1), .int(cc$tail_rows_per_cell_max)),
         sprintf("- Share of tail rows sitting in cells with 3 or more tail rows: %s.", .pct(cc$share_tail_rows_in_cells_ge3)),
         sprintf("- Cells with half or more of their pre-trim estimated rows in the tails: %s, holding %s of tail rows (a cell-level blow-up, i.e. the cell's sigma, rather than one exporter).",
                 .int(cc$n_cells_half_or_more_trimmed), .pct(cc$share_tail_rows_in_cells_half_or_more_trimmed)), "")
  pr <- d$prior$abs_ln_dev_from_prior
  L <- c(L, "## 4. Distance from the good-level prior; trade size", "",
         sprintf("- |ln gamma - ln prior|: tails p50 %s / p90 %s; published p50 %s / p90 %s (prior recovered from the Tier-3 rows).",
                 .fmt(pr$tails_p50), .fmt(pr$tails_p90), .fmt(pr$pub_p50), .fmt(pr$pub_p90)))
  if (!is.null(d$extras)) { e <- d$extras
    L <- c(L, sprintf("- avg_trade median: tails %s vs published %s; %s of tail rows sit below the published p10 of trade size.", .fmt(e$avg_trade$tails_p50, 1), .fmt(e$avg_trade$pub_p50, 1), .pct(e$avg_trade$share_tails_below_pub_p10)),
           sprintf("- gamma_shrink_wt median: tails %s vs published %s; gamma_exposure median: tails %s vs published %s.", .fmt(e$gamma_shrink_wt$tails_p50), .fmt(e$gamma_shrink_wt$pub_p50), .fmt(e$gamma_exposure$tails_p50), .fmt(e$gamma_exposure$pub_p50)),
           sprintf("- gamma_se_status of tail rows: %s; sigma_robust TRUE on %s of them.",
                   paste(sprintf("%s %s", names(e$gamma_se_status), .pct(unlist(e$gamma_se_status))), collapse = ", "), .pct(e$share_tails_sigma_robust))) }
  w <- d$within_good
  L <- c(L, "", "## 5. The within-good alternative", "",
         sprintf("On the pre-trim union of directly estimated rows (%s), a 0.5%%-per-tail rule taken within each good removes %s rows against the global rule's %s: %s rows are removed by both, %s only by the within-good rule (published today), %s only by the global rule; %s of the global removals are also within-good removals; %s goods would lose at least one row.",
                 .int(w$n_union_rows), .int(w$n_removed_within_good), .int(w$n_removed_global), .int(w$n_both), .int(w$n_within_only), .int(w$n_global_only),
                 .pct(w$share_of_global_removals_also_within_good), .int(w$goods_with_any_within_good_removal)), "")
  if (!is.null(out)) { dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE); writeLines(L, out) }
  invisible(L)
}
`%+%` <- function(a, b) paste0(a, b)

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
  tr_path <- get_arg("--trimmed", NA_character_); tb_path <- get_arg("--table", NA_character_); s1_path <- get_arg("--stage1", NA_character_)
  label <- get_arg("--label", "run")
  out_md <- get_arg("--out", sprintf("docs/results/trim_diagnostic_%s.md", label)); out_json <- get_arg("--json", sprintf("results/trim_diagnostic_%s.json", label))
  if (anyNA(c(tr_path, tb_path, s1_path))) stop("usage: Rscript analysis/trim_diagnostic.R --trimmed REC --table TABLE.rds --stage1 STAGE1.rds [--label NAME] [--out MD] [--json JSON]")
  for (p in c(tr_path, tb_path, s1_path)) if (!file.exists(p)) stop("not found: ", p)
  d <- trim_diagnostic(read_trim_record(tr_path), readRDS(tb_path), readRDS(s1_path), label = label)
  write_trim_diagnostic(d, out_md)
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE)
  writeLines(toJSON(d, auto_unbox = TRUE, digits = 8, pretty = TRUE, na = "null"), out_json)
  cat(sprintf("trim_diagnostic: wrote %s and %s\n", out_md, out_json))
  cat(sprintf("  %s trimmed rows (%s gamma tails) | tails sigma<2 %s vs published %s | cells half-or-more trimmed %s (%s of tail rows) | within-good rule: %s removed vs global %s, overlap %s\n",
              .int(d$n_trimmed), .int(d$n_tail_rows), .pct(d$sigma$tails$share_sigma_lt_2), .pct(d$sigma$published$share_sigma_lt_2),
              .int(d$concentration$n_cells_half_or_more_trimmed), .pct(d$concentration$share_tail_rows_in_cells_half_or_more_trimmed),
              .int(d$within_good$n_removed_within_good), .int(d$within_good$n_removed_global), .pct(d$within_good$share_of_global_removals_also_within_good)))
}
