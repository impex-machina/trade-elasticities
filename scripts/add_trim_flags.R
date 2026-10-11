#!/usr/bin/env Rscript
# ============================================================================
# scripts/add_trim_flags.R  (patch 0093, 2026-10-11)
#
# Gives an EXISTING drop-mode Stage-2b table the patch-0093 schema with
# add_trim_flags() (R/iteration_helpers.R): the trim_reason column (NA on
# every row the trim kept) and, with --trimmed, the run's _stage2_trimmed.csv
# rows re-appended with their reason -- the --stage2-trim-action flag table.
# A record written before patch 0093 carries (importer, exporter, good,
# sigma, gamma, tier, convergence, reason) only; its rows then publish NA in
# every other column, and the census says so. Without --trimmed only the
# column is added (the drop-mode schema). gamma_v_resid is added as NA if
# absent (scripts/add_gamma_v_resid.R fills it). Refuses a record whose rows
# are already in the table.
#
# Usage (repo root):
#   Rscript scripts/add_trim_flags.R --in TABLE.rds [--trimmed TRIMMED.rds|TRIMMED.csv] [--out PATH] [--csv]
# Prefer the .rds record (bit-exact); the CSV carries 15 significant digits,
# so a table rebuilt from it matches to ~1e-15 relative, not bit for bit.
# ============================================================================
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
in_path <- get_arg("--in", NA_character_); tr_path <- get_arg("--trimmed", NA_character_)
out_path <- get_arg("--out", in_path); write_csv <- "--csv" %in% args
if (is.na(in_path)) stop("usage: Rscript scripts/add_trim_flags.R --in TABLE.rds [--trimmed TRIMMED.csv] [--out PATH] [--csv]")
if (!file.exists(in_path)) stop("not found: ", in_path)
if (!is.na(tr_path) && !file.exists(tr_path)) stop("not found: ", tr_path)
.this_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), error = function(e) ".")
repo_root <- normalizePath(file.path(.this_dir, ".."), mustWork = FALSE)
sink(tempfile()); source(file.path(repo_root, "R", "feen94_het_baci.R")); sink()
dt <- readRDS(in_path); setDT(dt)
tr <- if (is.na(tr_path)) NULL else if (grepl("\\.rds$", tr_path, ignore.case = TRUE)) { x <- readRDS(tr_path); setDT(x); x } else
  fread(tr_path, colClasses = list(character = c("importer", "exporter", "good", "ref_exporter")))   # .rds is bit-exact; the CSV carries 15 significant digits
out <- add_trim_flags(dt, tr)
cen <- attr(out, "trim_flag_census")
out <- finalize_saved_output(out)
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, out_path); if (write_csv) fwrite(out, sub("\\.rds$", ".csv", out_path))
cat(sprintf("add_trim_flags: %s%s -> %s\n", in_path, if (is.na(tr_path)) "" else paste0(" + ", tr_path), out_path))
cat(sprintf("  published rows %s | flagged rows added %s%s\n", format(cen$n_published, big.mark = ","), format(cen$n_flagged_added, big.mark = ","),
            if (!is.null(cen$n_unrecorded_columns) && cen$n_unrecorded_columns > 0L)
              sprintf(" (the record predates patch 0093: %d columns NA on them)", cen$n_unrecorded_columns) else ""))
if (!is.null(cen$reasons)) cat(sprintf("  by reason: %s\n", paste(sprintf("%s=%s", names(cen$reasons), unlist(cen$reasons)), collapse = " ")))
