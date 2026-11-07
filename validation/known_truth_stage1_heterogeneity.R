#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_stage1_heterogeneity.R  (patch 0150)
#
# Does within-cell gamma heterogeneity bias the Stage-1 sigma?
#
# Stage 1 estimates sigma under the homogeneous-supply restriction (Eq. (10)
# with gamma_j = gamma_k: Feenstra / HLIML). Stage 2 then relaxes exactly that
# restriction, conditional on the restricted sigma. This harness isolates the
# heterogeneity-induced component of the Stage-1 sigma error that the
# routing / known-truth reports (within_sd 0.7 or 0.35 in every world) cannot
# separate from the estimator's own small-sample error: for each seed it
# generates synthetic BACI worlds that differ ONLY in the within-cell spread
# of ln gamma (validation/synthetic_baci.R, within_sd; same seed = same sigma,
# shocks and trade pattern), runs Stage 1 alone on each, and compares the
# published sigma with the truth cell by cell.
#
# Sandbox reading (2026-10-27, 12 goods x 15 countries x 1995-2024, 2 seeds,
# ~350 ok cells per world; production defaults, --stage1-sigma-cap 50):
#   median ln((sigma_hat - 1) / (sigma - 1)), interior HLIML cells, pooled:
#     within_sd 0 -> -0.016 | 0.35 -> +0.056 | 0.7 -> +0.122 | 1.2 -> +0.148
#   all ok cells by world: 0.02 / 0.03 | 0.07 / 0.11 | 0.12 / 0.16 | 0.14 / 0.19
# i.e. the estimator is unbiased for sigma when supply is homogeneous and
# biased upward, monotonically in the heterogeneity, when it is not. The
# dispersion (median |log ratio| ~0.2-0.3) does not change; the centre does.
#
# Usage (from the repo root; ~25 s per world on one core at 12 goods):
#   Rscript validation/known_truth_stage1_heterogeneity.R --out te_kt_het \
#           [--seeds 20261015,20261016] [--within-sd 0,0.35,0.7,1.2] [--goods 12]
#           [--sigma-cap 50] [--ncores 1]
# Writes <out>/sigma_by_world.rds (one row per cell and world) and prints the
# tables above. Every Stage-1 run goes through scripts/run_estimation.R
# --stage 1 under production defaults, so the harness measures the shipped
# estimator, not a re-implementation.
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(optparse) })

.this_dir <- function() {
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else normalizePath(".")
}
root <- normalizePath(file.path(.this_dir(), ".."))

opt <- parse_args(OptionParser(option_list = list(
  make_option("--out", type = "character", default = "te_kt_het", help = "output directory [default %default]"),
  make_option("--seeds", type = "character", default = "20261015,20261016", help = "comma-separated seeds [default %default]"),
  make_option("--within-sd", type = "character", default = "0,0.35,0.7,1.2", dest = "within_sd",
              help = "comma-separated within-cell s.d. of ln gamma [default %default]"),
  make_option("--goods", type = "integer", default = 12L, help = "HS4 goods per world (max 12) [default %default]"),
  make_option("--sigma-cap", type = "double", default = 50, dest = "sigma_cap", help = "--stage1-sigma-cap [default %default]"),
  make_option("--ncores", type = "integer", default = 1L, help = "cores for the Stage-1 run [default %default]")
)))
seeds <- as.integer(strsplit(opt$seeds, ",")[[1]])
wsds  <- as.numeric(strsplit(opt$within_sd, ",")[[1]])
out_root <- normalizePath(opt$out, mustWork = FALSE); dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)

res <- list()
for (sd in seeds) for (ws in wsds) {
  td <- file.path(out_root, sprintf("w%g_s%d", ws, sd)); dir.create(td, recursive = TRUE, showWarnings = FALSE)
  baci <- file.path(td, "BACI_HS92_V202601")
  truth <- sb$make_synthetic_baci_dir(baci, n_goods = opt$goods, seed = sd, within_sd = ws, good_sd = 0, importer_sd = 0)
  out <- file.path(td, "out"); dir.create(out, showWarnings = FALSE)
  t0 <- Sys.time()
  rc <- system2("Rscript", c(file.path(root, "scripts", "run_estimation.R"), "--data", baci, "--out-dir", out,
                             "--ncores", as.character(opt$ncores), "--stage", "1",
                             "--stage1-sigma-cap", format(opt$sigma_cap)),
                stdout = file.path(td, "log.txt"), stderr = file.path(td, "log.txt"))
  if (rc != 0L) stop("Stage 1 failed for world within_sd=", ws, " seed=", sd, "; see ", file.path(td, "log.txt"))
  s1 <- list.files(out, pattern = "_feenstra_sigma\\.rds$", full.names = TRUE)
  cat(sprintf("world within_sd=%g seed=%d: %.0f s\n", ws, sd, as.numeric(Sys.time() - t0, units = "secs")))
  d <- readRDS(s1); setDT(d)
  d[, `:=`(importer = as.integer(importer), good = as.character(good))]
  tr <- copy(truth$sigma); tr[, `:=`(importer = as.integer(importer), good = as.character(good))]
  m <- merge(d, tr, by = c("importer", "good"))
  m[, `:=`(within_sd = ws, seed = sd)]
  res[[length(res) + 1L]] <- m[, .(within_sd, seed, importer, good, status, final_source, adjust, sigma, sigma_se,
                                   sigma_true, sigma_capped, omega, n_exporters)]
}
all <- rbindlist(res)
saveRDS(all, file.path(out_root, "sigma_by_world.rds"))

ok <- all[status == "ok" & is.finite(sigma) & sigma > 1]
ok[, lr := log((sigma - 1) / (sigma_true - 1))]
n_world <- all[, .(n_cells = .N), by = .(within_sd, seed)]

cat("\n=== Stage-1 sigma accuracy by world (all ok cells; lr = ln((sigma_hat - 1) / (sigma - 1))) ===\n")
tab <- ok[, .(ok_cells = .N, med_lr = round(median(lr), 3), mean_lr = round(mean(lr), 3),
              med_abs_lr = round(median(abs(lr)), 3), share_abs_lt_0.2 = round(mean(abs(lr) < 0.2), 3),
              cap_share = round(mean(sigma_capped %in% TRUE), 3)), by = .(within_sd, seed)]
tab <- merge(n_world, tab, by = c("within_sd", "seed"))[, yield := round(ok_cells / n_cells, 3)][]
print(tab[order(seed, within_sd)])

cat("\n=== by route, pooled over seeds ===\n")
print(ok[, .(cells = .N, med_lr = round(median(lr), 3), med_abs_lr = round(median(abs(lr)), 3)),
         by = .(final_source, within_sd)][order(final_source, within_sd)])

cat("\n=== paired: the same cell across within_sd levels (seed-matched, ok in every level) ===\n")
p <- dcast(ok, seed + importer + good ~ within_sd, value.var = "lr")
lv <- as.character(sort(unique(ok$within_sd)))
p <- p[complete.cases(p[, lv, with = FALSE])]
cat("paired cells:", nrow(p), "\n")
print(data.table(within_sd = lv,
                 med_lr = round(sapply(lv, function(l) median(p[[l]])), 3),
                 med_abs_lr = round(sapply(lv, function(l) median(abs(p[[l]]))), 3)))
cat("\nWritten:", file.path(out_root, "sigma_by_world.rds"), "\n")
