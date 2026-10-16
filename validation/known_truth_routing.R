#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_routing.R  (patch 0127, after audit #8)
#
# Stage 1 routes every cell: HLIML's closed form when it is admissible
# ("hliml"), the boundary search when the optimum sits on the edge of the
# admissible region ("hliml_boundary"), and otherwise the Step-2 weighted
# cascade ("step2_weighted"). The routing comparison parked since v0.7.3 asks
# whether cells whose closed form is inadmissible should go to the boundary
# search instead of Step 2. The 2026-10-14 sandbox run hinted at an upward
# bias on the Step-2 route (sigma - 1 about 1.7 times the truth at baseline
# volatility, on 8 cells). This script reads the known-truth worlds the
# harness already ran (validation/known_truth_stage2.R; `truth.rds` and the
# shipped arm's Stage-1 table in each world) -- no new estimation -- and
# measures sigma's accuracy by route:
#   raw: the cell's own estimate, for cells with an estimate (status ok);
#   published: the sigma Stage 2 uses (the cell's own if it is in the clean
#     set of stage2_sigma_clean(), else the fallback), on the same cells.
# Errors are on ln(sigma - 1): bias = median of ln((s_hat - 1)/(s - 1)),
# error = median of its absolute value. With --stage1 (the shipped table) the
# report adds how many real cells take each route and stay in the clean set.
#
# Reading (fixed in patch 0127, before the numbers): the Step-2 route is
# "biased" if, at every shock scale (worlds pooled), its raw bias exceeds
# +0.2 (sigma - 1 overstated by more than ~22% at the median) AND its raw
# error is at least 1.5 times the "hliml" route's -- the routing comparison
# then earns a local A/B; otherwise "closed".
#
# Usage (repo root; seconds):
#   Rscript validation/known_truth_routing.R --worlds DIR [--stage1 S1.rds]
#       [--json results/known_truth_routing.json] [--md docs/results/known_truth_routing.md]
#   DIR is the harness's --out (e.g. %USERPROFILE%\te_known_truth).
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

KR_PREFIX <- "baci_hs92_v202601_elast_country_hs4"

#' Cell-level accuracy rows for one world.
kr_world <- function(wdir) {
  s1 <- data.table::as.data.table(readRDS(file.path(wdir, "shipped", paste0(KR_PREFIX, "_feenstra_sigma.rds"))))
  tr <- readRDS(file.path(wdir, "truth.rds"))
  for (k in c("importer", "good")) data.table::set(s1, j = k, value = as.character(s1[[k]]))
  if (!"convergence" %in% names(s1)) s1[, convergence := fifelse(status == "ok", 0L, -99L)]
  sc <- stage2_sigma_clean(s1)
  fb <- stats::median(sc$clean$sigma)
  clean_key <- paste(sc$clean$importer, sc$clean$good)
  ts <- tr$sigma[, .(importer = as.character(importer), good = as.character(good), sigma_true)]
  m <- merge(s1[status == "ok" & is.finite(sigma) & sigma > 1, .(importer, good, route = final_source, sigma)], ts, by = c("importer", "good"))
  m[, in_clean := paste(importer, good) %in% clean_key]
  m[, sigma_pub := fifelse(in_clean, sigma, fb)]
  m[, `:=`(lr_raw = log((sigma - 1) / (sigma_true - 1)), lr_pub = log((sigma_pub - 1) / (sigma_true - 1)))]
  meta <- tr$meta
  m[, `:=`(world = basename(wdir), seed = meta$seed, scale = meta$shock_scale,
           structure = if (!is.null(meta$good_sd) && (meta$good_sd > 0 || meta$importer_sd > 0)) "structured" else "none")]
  m
}

#' Accuracy by route, overall and per shock scale.
kr_summarise <- function(cells) {
  f <- function(d) d[, .(cells = .N, bias_raw = stats::median(lr_raw), error_raw = stats::median(abs(lr_raw)),
                         within_1.5x = mean(abs(lr_raw) < log(1.5)), share_clean = mean(in_clean),
                         bias_pub = stats::median(lr_pub), error_pub = stats::median(abs(lr_pub))), by = route][order(route)]
  list(overall = f(cells), by_scale = cells[, f(.SD), by = scale][order(scale, route)])
}

#' The pre-registered reading.
kr_reading <- function(by_scale) {
  sc <- sort(unique(by_scale$scale))
  ok <- vapply(sc, function(x) {
    s2 <- by_scale[scale == x & route == "step2_weighted"]; hl <- by_scale[scale == x & route == "hliml"]
    nrow(s2) == 1L && nrow(hl) == 1L && s2$bias_raw > 0.2 && s2$error_raw >= 1.5 * hl$error_raw
  }, TRUE)
  list(verdict = if (length(ok) && all(ok)) "biased" else "closed",
       rule = "Step-2 raw bias > +0.2 AND raw error >= 1.5x the hliml route's, at every shock scale")
}

#' Real cells by route in a shipped Stage-1 table.
kr_real_routes <- function(s1) {
  s1 <- data.table::as.data.table(s1)
  for (k in c("importer", "good")) data.table::set(s1, j = k, value = as.character(s1[[k]]))
  if (!"convergence" %in% names(s1)) s1[, convergence := fifelse(status == "ok", 0L, -99L)]
  sc <- stage2_sigma_clean(s1)
  ck <- paste(sc$clean$importer, sc$clean$good)
  s1[status == "ok", .(cells = .N, share_of_estimated = .N / s1[status == "ok", .N],
                       clean = sum(paste(importer, good) %in% ck)), by = .(route = final_source)][order(-cells)]
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  for (f in c("R/utils_general.R", "R/iteration_helpers.R")) source(f)
  wd <- get_arg("--worlds", NA_character_)
  if (is.na(wd) || !dir.exists(wd)) stop("usage: Rscript validation/known_truth_routing.R --worlds DIR [--stage1 S1.rds] [--json F] [--md F]")
  json <- get_arg("--json", "results/known_truth_routing.json"); md <- get_arg("--md", "docs/results/known_truth_routing.md")
  s1p <- get_arg("--stage1", NA_character_)
  worlds <- list.dirs(wd, recursive = FALSE)
  worlds <- worlds[file.exists(file.path(worlds, "truth.rds")) & file.exists(file.path(worlds, "shipped", paste0(KR_PREFIX, "_feenstra_sigma.rds")))]
  if (!length(worlds)) stop("no harness worlds (truth.rds + shipped Stage-1 table) under ", wd)
  cells <- data.table::rbindlist(lapply(worlds, kr_world), fill = TRUE)
  s <- kr_summarise(cells); rd <- kr_reading(s$by_scale)
  real <- if (!is.na(s1p) && file.exists(s1p)) kr_real_routes(readRDS(s1p)) else NULL
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  meta <- list(worlds_dir = wd, worlds = basename(worlds), cells = nrow(cells), stage1 = s1p, git_rev = rev,
               timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  jsonlite::write_json(list(meta = meta, reading = rd, overall = s$overall, by_scale = s$by_scale, real_routes = real),
                       json, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  f3 <- function(x) formatC(x, digits = 3, format = "f"); p1 <- function(x) sprintf("%.1f%%", 100 * x)
  tab <- function(d) c("| route | cells | bias (raw) | error (raw) | within 1.5x | in clean set | bias (published) | error (published) |",
                       "|---|---|---|---|---|---|---|---|",
                       sprintf("| %s | %d | %s | %s | %s | %s | %s | %s |", ifelse(is.na(d$route), "(none)", d$route), d$cells, f3(d$bias_raw),
                               f3(d$error_raw), p1(d$within_1.5x), p1(d$share_clean), f3(d$bias_pub), f3(d$error_pub)))
  scales <- sort(unique(s$by_scale$scale))
  out <- c("# Stage-1 sigma accuracy by route, at known truth (patch 0127)", "",
           sprintf("%d known-truth worlds from `validation/known_truth_stage2.R` under `%s` (%s cells with an estimate); rev %s, %s. Errors on ln(sigma - 1): bias is the median of ln((s_hat - 1)/(s - 1)), error the median of its absolute value; published is the sigma Stage 2 uses (own if in the clean set, else the fallback).",
                   length(worlds), wd, format(nrow(cells), big.mark = ","), rev, meta$timestamp), "",
           "## All worlds", "", tab(s$overall), "")
  for (x in scales) out <- c(out, sprintf("## Shock scale x%s", format(x)), "", tab(s$by_scale[scale == x]), "")
  if (!is.null(real)) out <- c(out, "## Real cells by route (shipped Stage-1 table)", "",
                               "| route | cells with an estimate | share | in the clean set |", "|---|---|---|---|",
                               sprintf("| %s | %s | %s | %s |", ifelse(is.na(real$route), "(none)", real$route), format(real$cells, big.mark = ","),
                                       p1(real$share_of_estimated), format(real$clean, big.mark = ",")), "")
  out <- c(out, sprintf("**Reading (fixed in patch 0127): %s** -- %s.", rd$verdict, rd$rule))
  writeLines(enc2utf8(out), md, useBytes = TRUE)
  cat(sprintf("known-truth routing: %d worlds, %d cells -> %s (%s, %s)\n", length(worlds), nrow(cells), rd$verdict, json, md))
}
