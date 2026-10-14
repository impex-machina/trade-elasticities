#!/usr/bin/env Rscript
# ============================================================================
# scripts/add_sigma_source.R  (patch 0103, 2026-10-12)
#
# Attaches sigma_source to an EXISTING Stage-2b table from its Stage-1 table,
# through stage2_sigma_clean() + attach_sigma_source() (R/iteration_helpers.R)
# -- the same code path the runner uses natively since patch 0103:
#   estimated / fallback_no_estimate / fallback_sigma_edge / fallback_sigma_pole.
# It then VERIFIES the reconstruction against the table: every "estimated"
# row must carry its cell's Stage-1 sigma and every fallback row the fallback
# sigma (the clean-set median, or --fallback-pin). A mismatch means the rules
# given here are not the ones the table was produced under; nothing is written.
# Idempotent. This is how v0.10.1 is produced from the shipped v0.10.0 table.
#
# Usage (repo root):
#   Rscript scripts/add_sigma_source.R --stage1 STAGE1.rds --in TABLE.rds [--out PATH]
#       [--edge-rule fallback|publish] [--pole-rule fallback|none] [--pole-se 1] [--fallback-pin X]
# Defaults are the v0.10.0 configuration (edge fallback, pole fallback, c = 1).
# ============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
s1_path <- get_arg("--stage1", NA_character_); in_path <- get_arg("--in", NA_character_); out_path <- get_arg("--out", in_path)
edge_rule <- get_arg("--edge-rule", "fallback"); pole_rule <- get_arg("--pole-rule", "fallback")
pole_c <- as.numeric(get_arg("--pole-se", "1")); pin <- suppressWarnings(as.numeric(get_arg("--fallback-pin", NA_character_)))
if (is.na(s1_path) || is.na(in_path)) stop("usage: Rscript scripts/add_sigma_source.R --stage1 STAGE1.rds --in TABLE.rds [--out PATH] [--edge-rule R] [--pole-rule R] [--pole-se C] [--fallback-pin X]")
for (p in c(s1_path, in_path)) if (!file.exists(p)) stop("not found: ", p)
.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()

s1 <- readRDS(s1_path); setDT(s1)
dt <- readRDS(in_path); setDT(dt)
sc <- stage2_sigma_clean(s1, edge_rule = edge_rule, pole_rule = pole_rule, pole_c = pole_c)
fallback <- if (!is.na(pin)) pin else median(sc$clean$sigma, na.rm = TRUE)
ssr <- attach_sigma_source(dt, sc$source)   # patch 0114: the function returns the labelled table
dt <- ssr$table; cen <- ssr$census

# verification: estimated rows carry their cell's Stage-1 sigma, fallback rows the fallback sigma
s1k <- s1[, .(k = paste(as.character(importer), as.character(good), sep = "\r"), s1_sigma = sigma)]
k_dt <- paste(as.character(dt$importer), as.character(dt$good), sep = "\r")
s1_sig <- s1k$s1_sigma[match(k_dt, s1k$k)]
close <- function(a, b) is.finite(a) & is.finite(b) & abs(a - b) <= 1e-9 * pmax(abs(b), 1)
est <- dt$sigma_source == "estimated"
bad_est <- sum(est & !close(dt$sigma, s1_sig))
bad_fb <- sum(!est & !close(dt$sigma, fallback))
cat(sprintf("add_sigma_source: %s (+ %s) | rules: edge %s, pole %s (c = %s) | fallback sigma %.6f\n",
            in_path, s1_path, edge_rule, pole_rule, pole_c, fallback))
cat(sprintf("  published rows: estimated %s | fallback_no_estimate %s | fallback_sigma_edge %s | fallback_sigma_pole %s\n",
            format(cen$estimated, big.mark = ","), format(cen$fallback_no_estimate, big.mark = ","),
            format(cen$fallback_sigma_edge, big.mark = ","), format(cen$fallback_sigma_pole, big.mark = ",")))
cat(sprintf("  verification over all %s rows: estimated rows off their Stage-1 sigma %s | fallback rows off the fallback %s\n",
            format(nrow(dt), big.mark = ","), format(bad_est, big.mark = ","), format(bad_fb, big.mark = ",")))
if (bad_est + bad_fb > 0L) stop("the rules given do not reproduce the table's sigma column -- nothing written (check --edge-rule / --pole-rule / --pole-se / --fallback-pin)")
out <- finalize_saved_output(dt)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, out_path)
cat(sprintf("  wrote %s (%d columns)\n", out_path, ncol(out)))
