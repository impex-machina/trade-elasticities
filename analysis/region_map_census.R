#!/usr/bin/env Rscript
# ============================================================================
# analysis/region_map_census.R  (patch 0125, audit #8)
#
# Which country codes in the estimation data does R/region_map.R not cover?
# Stage 2a aggregates countries into Soderbery's 13 countries + 7 regions;
# prepare_data() sends an unmapped code to a catch-all "OTHER" region, which
# then becomes a Stage-2a "region" of its own (its regional gamma feeds Stage
# 2b's good-level priors and the starting values of any unmapped importer).
# This census lists the unmapped codes of the raw cache with their weight.
#
# Reading (fixed in patch 0125): "negligible" if the unmapped codes together
# carry < 0.1% of trade value as importers AND < 0.1% as exporters -- the
# catch-all is then documented, not changed; otherwise the codes are mapped in
# a later patch and the change queued for the next Stage-2 session
# (docs/next_session_queue.md): mapping them moves Stage 2a, hence 2b.
#
# Usage (repo root; local; ~1 min, most of it reading the cache):
#   Rscript analysis/region_map_census.R --raw-cache PATH
#       [--out results/region_map_census.json] [--md docs/results/region_map_census.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

#' Unmapped codes of a raw-cache table (year, importer, exporter, cusval, ...).
region_map_census <- function(raw, region_codes) {
  raw <- data.table::as.data.table(raw)
  tot <- sum(raw$cusval, na.rm = TRUE)
  side <- function(col) {
    x <- raw[, .(value = sum(cusval, na.rm = TRUE), rows = .N, first = min(year), last = max(year)), by = c(col)]
    data.table::setnames(x, col, "code")
    x[, code := as.integer(code)]
    x[!code %in% region_codes]
  }
  imp <- side("importer"); exp <- side("exporter")
  codes <- sort(unique(c(imp$code, exp$code)))
  tab <- data.table::data.table(code = codes)
  tab <- merge(tab, imp[, .(code, imp_value = value, imp_rows = rows, imp_first = first, imp_last = last)], by = "code", all.x = TRUE)
  tab <- merge(tab, exp[, .(code, exp_value = value, exp_rows = rows, exp_first = first, exp_last = last)], by = "code", all.x = TRUE)
  for (k in c("imp_value", "exp_value", "imp_rows", "exp_rows")) data.table::set(tab, which(is.na(tab[[k]])), k, 0)
  tab[, `:=`(imp_share = imp_value / tot, exp_share = exp_value / tot)]
  data.table::setorder(tab, -imp_share, -exp_share)
  n_data <- data.table::uniqueN(c(raw$importer, raw$exporter))
  share_imp <- sum(tab$imp_share); share_exp <- sum(tab$exp_share)
  list(codes_in_data = n_data, codes_mapped_in_data = n_data - nrow(tab), unmapped = tab,
       unmapped_importer_value_share = share_imp, unmapped_exporter_value_share = share_exp,
       unmapped_importer_rows = sum(tab$imp_rows), unmapped_exporter_rows = sum(tab$exp_rows),
       reading = if (share_imp < 0.001 && share_exp < 0.001) "negligible" else "map them")
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  rc <- get_arg("--raw-cache", NA_character_)
  if (is.na(rc) || !file.exists(rc)) stop("usage: Rscript analysis/region_map_census.R --raw-cache PATH [--out F.json] [--md F.md]")
  out <- get_arg("--out", "results/region_map_census.json"); md <- get_arg("--md", "docs/results/region_map_census.md")
  source("R/region_map.R")
  codes <- build_region_map()$cty_code
  raw <- readRDS(rc)
  res <- region_map_census(raw, codes)
  rev <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  res$meta <- list(raw_cache = rc, rows = nrow(raw), years = range(raw$year), region_map_codes = length(codes), git_rev = rev,
                   timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  jsonlite::write_json(res, out, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  u <- res$unmapped
  pct <- function(x) sprintf("%.4f%%", 100 * x)
  rows <- if (nrow(u)) sprintf("| %d | %s | %s | %s | %s | %s |", u$code, pct(u$imp_share), format(u$imp_rows, big.mark = ","),
                               pct(u$exp_share), format(u$exp_rows, big.mark = ","),
                               ifelse(is.na(u$imp_first) & is.na(u$exp_first), "", sprintf("%s-%s", pmin(u$imp_first, u$exp_first, na.rm = TRUE), pmax(u$imp_last, u$exp_last, na.rm = TRUE))))
          else "| (none) | | | | | |"
  writeLines(enc2utf8(c("# Region-map coverage of the estimation data (patch 0125)", "",
    sprintf("Raw cache `%s` (%s rows, %d-%d); `R/region_map.R` maps %d codes; rev %s, %s.", rc, format(nrow(raw), big.mark = ","),
            res$meta$years[1], res$meta$years[2], length(codes), rev, res$meta$timestamp), "",
    sprintf("%d country codes appear in the data; %d of them are unmapped and fall into Stage 2a's catch-all `OTHER` region. Together they carry %s of trade value as importers (%s rows) and %s as exporters (%s rows).",
            res$codes_in_data, nrow(u), pct(res$unmapped_importer_value_share), format(res$unmapped_importer_rows, big.mark = ","),
            pct(res$unmapped_exporter_value_share), format(res$unmapped_exporter_rows, big.mark = ",")), "",
    "| code | value share as importer | rows as importer | value share as exporter | rows as exporter | years |", "|---|---|---|---|---|---|", rows, "",
    sprintf("**Reading (fixed in patch 0125): %s.** Negligible means under 0.1%% of trade value on both sides: the catch-all is documented, not changed. Otherwise the codes are mapped in a later patch and queued for the next Stage-2 session, because mapping them moves Stage 2a and so Stage 2b.", res$reading))),
    md, useBytes = TRUE)
  cat(sprintf("region map census: %d unmapped codes, %.4f%% of value as importers, %.4f%% as exporters -> %s (%s, %s)\n",
              nrow(u), 100 * res$unmapped_importer_value_share, 100 * res$unmapped_exporter_value_share, res$reading, out, md))
}
