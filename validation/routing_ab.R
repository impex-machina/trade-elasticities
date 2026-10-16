#!/usr/bin/env Rscript
# ===========================================================================
# validation/routing_ab.R  (patch 0129)
#
# The routing comparison patch 0127's reading called for: should a cell
# whose closed form is inadmissible take the boundary search's optimum
# instead of the Step-2 cascade's sigma? estimate_cell_liml() runs the
# boundary search for every such cell and stores its result in the Stage-1
# table (sigma_hliml_bd, hliml_bd_edge, hliml_bd_usable) even when Step 2 is
# routed on, so the comparison needs no re-estimation: on the cells routed
# through Step 2 whose boundary optimum is usable, compare the two sigmas.
#   A. Known truth (the worlds validation/known_truth_stage2.R ran): bias and
#      error of each against the true sigma, on ln(sigma - 1), raw and as
#      published (a boundary optimum on the sigma cap is a box edge and takes
#      the fallback, as the edge rule does; Step 2's published sigma is the
#      shipped one).
#   B. Real data, the 1995-2009 / 2010-2024 Stage-1 windows of the 2% product
#      subsample: for the source period's Step-2 cells with a usable boundary
#      optimum, which sigma better predicts the other period's own estimate
#      (median absolute error on ln(sigma - 1)), both directions.
#   C. The shipped Stage 1: how many Step-2 cells have a usable boundary
#      optimum, where those optima sit, how far sigma would move, and the
#      fallback sigma (the clean-set median) after the switch.
#
# Reading (fixed in patch 0129, before the numbers): "switch" if (A) at every
# shock scale the boundary sigma's raw median |error| is at least 10% below
# Step 2's on the same cells AND its |bias| is smaller, AND (B) its median
# absolute prediction error is no higher than Step 2's in both directions;
# otherwise "keep Step 2". A switch means a Stage-1 routing option and a
# re-estimation of Stage 1 and Stage 2 on the box (roughly $10), batched with
# anything else queued.
#
# Usage (repo root; seconds):
#   Rscript validation/routing_ab.R --worlds DIR --early E.rds --late L.rds --stage1 S1.rds
#       [--json results/routing_ab.json] [--md docs/results/routing_ab.md]
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

RA_PREFIX <- "baci_hs92_v202601_elast_country_hs4"

.ra_s1 <- function(x) {
  x <- data.table::copy(data.table::as.data.table(x))
  for (k in c("importer", "good")) data.table::set(x, j = k, value = as.character(x[[k]]))
  if (!"convergence" %in% names(x)) x[, convergence := fifelse(status == "ok", 0L, -99L)]
  x
}

#' The comparable cells of a Stage-1 table: routed through Step 2, with a
#' usable boundary optimum and both sigmas above 1.
ra_pairs <- function(s1) {
  s1 <- .ra_s1(s1)
  s1[status == "ok" & final_source == "step2_weighted" & hliml_bd_usable %in% TRUE &
       is.finite(sigma) & sigma > 1 & is.finite(sigma_hliml_bd) & sigma_hliml_bd > 1,
     .(importer, good, sigma_s2 = sigma, sigma_bd = sigma_hliml_bd, bd_edge = hliml_bd_edge)]
}

#' A. One known-truth world.
ra_world <- function(wdir) {
  s1 <- .ra_s1(readRDS(file.path(wdir, "shipped", paste0(RA_PREFIX, "_feenstra_sigma.rds"))))
  tr <- readRDS(file.path(wdir, "truth.rds"))
  sc <- stage2_sigma_clean(s1); fb <- stats::median(sc$clean$sigma)
  ck <- paste(sc$clean$importer, sc$clean$good)
  p <- ra_pairs(s1)
  ts <- tr$sigma[, .(importer = as.character(importer), good = as.character(good), sigma_true)]
  p <- merge(p, ts, by = c("importer", "good"))
  if (!nrow(p)) return(NULL)
  p[, `:=`(pub_s2 = fifelse(paste(importer, good) %in% ck, sigma_s2, fb),
           pub_bd = fifelse(bd_edge %in% "sigma_cap", fb, sigma_bd))]
  lr <- function(a) log((a - 1) / (p$sigma_true - 1))
  p[, `:=`(lr_s2 = lr(sigma_s2), lr_bd = lr(sigma_bd), lr_pub_s2 = lr(pub_s2), lr_pub_bd = lr(pub_bd))]
  p[, `:=`(world = basename(wdir), scale = tr$meta$shock_scale)]
  p
}

ra_known_truth <- function(worlds) {
  cells <- data.table::rbindlist(lapply(worlds, ra_world), fill = TRUE)
  f <- function(d) d[, .(cells = .N, bias_s2 = stats::median(lr_s2), bias_bd = stats::median(lr_bd),
                         error_s2 = stats::median(abs(lr_s2)), error_bd = stats::median(abs(lr_bd)),
                         error_pub_s2 = stats::median(abs(lr_pub_s2)), error_pub_bd = stats::median(abs(lr_pub_bd)),
                         share_bd_sigma_cap = mean(bd_edge %in% "sigma_cap"))]
  list(cells = cells, overall = f(cells), by_scale = cells[, f(.SD), by = scale][order(scale)])
}

#' B. One direction of the period test: predictors from `from`, targets in `to`.
ra_period <- function(from, to) {
  p <- ra_pairs(from)
  to <- .ra_s1(to)
  edge <- if ("sigma_capped" %in% names(to)) to$sigma_capped %in% TRUE else rep(FALSE, nrow(to))
  tg <- to[convergence == 0L & is.finite(sigma) & sigma > 1 & !edge, .(importer, good, z = log(sigma - 1))]
  m <- merge(p, tg, by = c("importer", "good"))
  if (!nrow(m)) return(list(cells = 0L, mae_s2 = NA_real_, mae_bd = NA_real_))
  list(cells = nrow(m), mae_s2 = stats::median(abs(m$z - log(m$sigma_s2 - 1))), mae_bd = stats::median(abs(m$z - log(m$sigma_bd - 1))))
}

#' C. The shipped Stage 1.
ra_shipped <- function(s1) {
  s1 <- .ra_s1(s1)
  n_s2 <- s1[status == "ok" & final_source == "step2_weighted", .N]
  p <- ra_pairs(s1)
  sc <- stage2_sigma_clean(s1); fb <- stats::median(sc$clean$sigma)
  # the clean set after the switch: switched cells take their boundary sigma,
  # or leave the clean set when that optimum is a sigma-cap edge
  ck <- paste(sc$clean$importer, sc$clean$good)
  sw <- p[, .(cell = paste(importer, good), sigma_bd, bd_edge)]
  cl <- data.table::data.table(cell = ck, sigma = sc$clean$sigma)   # not `key =`: data.table() reads that as its key argument
  cl <- merge(cl, sw, by = "cell", all.x = TRUE)
  cl <- cl[!(bd_edge %in% "sigma_cap")]
  cl[!is.na(sigma_bd), sigma := sigma_bd]
  list(step2_cells = n_s2, with_usable_boundary = nrow(p), share_usable = if (n_s2) nrow(p) / n_s2 else NA_real_,
       boundary_edges = as.list(table(p$bd_edge, useNA = "ifany")),
       shift_ln_sigma_minus_1 = as.list(stats::setNames(stats::quantile(log((p$sigma_bd - 1) / (p$sigma_s2 - 1)), c(0.1, 0.5, 0.9), names = FALSE), c("p10", "p50", "p90"))),
       fallback_now = fb, fallback_after = stats::median(cl$sigma))
}

ra_reading <- function(by_scale, el, le) {
  a <- nrow(by_scale) > 0L && all(by_scale$error_bd <= 0.9 * by_scale$error_s2 & abs(by_scale$bias_bd) < abs(by_scale$bias_s2))
  b <- is.finite(el$mae_bd) && is.finite(le$mae_bd) && el$mae_bd <= el$mae_s2 && le$mae_bd <= le$mae_s2
  list(verdict = if (a && b) "switch" else "keep Step 2", known_truth_part = a, period_part = b)
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  for (f in c("R/utils_general.R", "R/iteration_helpers.R")) source(f)
  wd <- get_arg("--worlds", NA_character_); ep <- get_arg("--early", NA_character_); lp <- get_arg("--late", NA_character_)
  s1p <- get_arg("--stage1", NA_character_)
  if (any(is.na(c(wd, ep, lp, s1p))) || !dir.exists(wd) || !all(file.exists(c(ep, lp, s1p))))
    stop("usage: Rscript validation/routing_ab.R --worlds DIR --early E.rds --late L.rds --stage1 S1.rds [--json F] [--md F]")
  json <- get_arg("--json", "results/routing_ab.json"); md <- get_arg("--md", "docs/results/routing_ab.md")
  worlds <- list.dirs(wd, recursive = FALSE)
  worlds <- worlds[file.exists(file.path(worlds, "truth.rds")) & file.exists(file.path(worlds, "shipped", paste0(RA_PREFIX, "_feenstra_sigma.rds")))]
  kt <- ra_known_truth(worlds)
  early <- readRDS(ep); late <- readRDS(lp)
  el <- ra_period(early, late); le <- ra_period(late, early)
  sh <- ra_shipped(readRDS(s1p))
  rd <- ra_reading(kt$by_scale, el, le)
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(worlds_dir = wd, worlds = length(worlds), early = ep, late = lp, stage1 = s1p, git_rev = rev,
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  jsonlite::write_json(list(meta = meta, reading = rd, known_truth = list(overall = kt$overall, by_scale = kt$by_scale),
                            period = list(early_to_late = el, late_to_early = le), shipped = sh),
                       json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f3 <- function(x) formatC(x, digits = 3, format = "f"); p1 <- function(x) sprintf("%.1f%%", 100 * x)
  kr <- function(d) sprintf("| %s | %d | %s / %s | %s / %s | %s / %s | %s |", d$lab, d$cells, f3(d$bias_s2), f3(d$bias_bd), f3(d$error_s2), f3(d$error_bd),
                            f3(d$error_pub_s2), f3(d$error_pub_bd), p1(d$share_bd_sigma_cap))
  tabk <- rbind(data.table::copy(kt$by_scale)[, lab := paste0("x", format(scale))], data.table::copy(kt$overall)[, `:=`(scale = NA, lab = "all")], fill = TRUE)
  edges <- paste(sprintf("%s %s", names(sh$boundary_edges), format(unlist(sh$boundary_edges), big.mark = ",")), collapse = ", ")
  writeLines(enc2utf8(c("# Stage-1 routing A/B: Step 2 against the boundary search (patch 0129)", "",
    sprintf("Cells routed through the Step-2 cascade whose boundary optimum is usable (both stored in the Stage-1 table; no re-estimation). %d known-truth worlds under `%s`; period windows `%s` / `%s`; shipped Stage 1 `%s`; rev %s, %s.",
            length(worlds), wd, ep, lp, s1p, rev, meta$timestamp), "",
    "## A. Known truth (ln(sigma - 1) against the truth; Step 2 / boundary)", "",
    "| scale | cells | bias | error (raw) | error (published) | boundary on the sigma cap |", "|---|---|---|---|---|---|",
    kr(tabk), "",
    "## B. Real data: predicting the other period's estimate (median absolute error on ln(sigma - 1); Step 2 / boundary)", "",
    sprintf("- 1995-2009 -> 2010-2024: %d cells, %s / %s", el$cells, f3(el$mae_s2), f3(el$mae_bd)),
    sprintf("- 2010-2024 -> 1995-2009: %d cells, %s / %s", le$cells, f3(le$mae_s2), f3(le$mae_bd)), "",
    "## C. The shipped Stage 1", "",
    sprintf("- Step-2 cells: %s; with a usable boundary optimum: %s (%s); their edges: %s.", format(sh$step2_cells, big.mark = ","),
            format(sh$with_usable_boundary, big.mark = ","), p1(sh$share_usable), edges),
    sprintf("- ln((sigma_bd - 1) / (sigma_step2 - 1)) on those cells: p10 %s, p50 %s, p90 %s.", f3(sh$shift_ln_sigma_minus_1$p10),
            f3(sh$shift_ln_sigma_minus_1$p50), f3(sh$shift_ln_sigma_minus_1$p90)),
    sprintf("- Fallback sigma (the clean-set median): %s now, %s after the switch.", formatC(sh$fallback_now, digits = 4, format = "f"),
            formatC(sh$fallback_after, digits = 4, format = "f")), "",
    sprintf("**Reading (fixed in patch 0129): %s** (known-truth part %s, period part %s). Switch if, at every shock scale, the boundary sigma's raw error is at least 10%% below Step 2's and its |bias| smaller, AND it predicts the other period no worse in both directions.",
            rd$verdict, rd$known_truth_part, rd$period_part))), md, useBytes = TRUE)
  cat(sprintf("routing A/B: %s (known truth %s, period %s); fallback %.4f -> %.4f (%s, %s)\n", rd$verdict, rd$known_truth_part, rd$period_part,
              sh$fallback_now, sh$fallback_after, json, md))
}
