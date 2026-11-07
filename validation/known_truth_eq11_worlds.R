#!/usr/bin/env Rscript
# ===========================================================================
# validation/known_truth_eq11_worlds.R  (prototype, patch 0150 follow-up)
#
# Breadth for the Stage-2 arms: a grid of synthetic worlds (seeds x
# structures), the three-stage pipeline on each, the arms of
# known_truth_stage2_arms.R on each, and the readings pooled.
#
# Structures are the ones of known_truth_stage2.R (patch 0123):
#   none          good_sd 0    importer_sd 0    within_sd 0.7
#   good          good_sd 0.7  importer_sd 0    within_sd 0.35
#   good_importer good_sd 0.7  importer_sd 0.5  within_sd 0.35
#
# Per world (idempotent -- every step is skipped when its output exists, so
# the grid can be resumed or extended by re-running the same command):
#   1. generate <out>/w<seed>_<structure>/BACI_HS92_V202601 and truth.rds
#      (validation/synthetic_baci.R, 15 countries, --goods goods);
#   2. scripts/run_estimation.R --stage all --ncores N  (Stage 1, 2a, 2b);
#   3. validation/known_truth_stage2_arms.R for --arms (default A,B,C), which
#      writes <world>/out/kt_arm_readings.rds.
# Then it pools kt_arm_readings.rds over worlds: medians and means per arm,
# overall and by structure, plus the per-world table.
#
# Usage (from the repo root; ~8 min per world on one core at 12 goods):
#   Rscript validation/known_truth_eq11_worlds.R --out ../te_kt_worlds \
#           [--seeds 20261015,20261016,20261017] [--structures none,good,good_importer]
#           [--goods 12] [--arms A,B,C] [--ncores 1] [--pool-only]
# --pool-only skips every run and just pools whatever readings exist.
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(optparse) })

.this_dir <- function() {
  f <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else normalizePath(".")
}
root <- normalizePath(file.path(.this_dir(), ".."))

opt <- parse_args(OptionParser(option_list = list(
  make_option("--out", type = "character", default = "te_kt_worlds", help = "grid directory [default %default]"),
  make_option("--seeds", type = "character", default = "20261015,20261016,20261017", help = "comma-separated seeds [default %default]"),
  make_option("--structures", type = "character", default = "none,good,good_importer", help = "comma-separated structures [default %default]"),
  make_option("--goods", type = "integer", default = 12L, help = "HS4 goods per world (max 12) [default %default]"),
  make_option("--arms", type = "character", default = "A,B,C", help = "arms for known_truth_stage2_arms.R [default %default]"),
  make_option("--ncores", type = "integer", default = 1L, help = "cores for the pipeline run [default %default]"),
  make_option("--pool-only", action = "store_true", default = FALSE, dest = "pool_only", help = "skip the runs, pool existing readings")
)))
seeds <- as.integer(strsplit(opt$seeds, ",")[[1]])
structures <- strsplit(opt$structures, ",")[[1]]
STRUCT <- list(none          = list(good_sd = 0,   importer_sd = 0,   within_sd = 0.7),
               good          = list(good_sd = 0.7, importer_sd = 0,   within_sd = 0.35),
               good_importer = list(good_sd = 0.7, importer_sd = 0.5, within_sd = 0.35))
bad <- setdiff(structures, names(STRUCT)); if (length(bad)) stop("unknown structure(s): ", paste(bad, collapse = ", "))
out_root <- normalizePath(opt$out, mustWork = FALSE); dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)

run_step <- function(label, args, envlist = list(), log) {
  # system2(env =) is Unix-only; variables set in this session are inherited by the child on every platform
  if (length(envlist)) do.call(Sys.setenv, envlist)
  t0 <- Sys.time()
  rc <- system2("Rscript", args, stdout = log, stderr = log)
  cat(sprintf("    %-28s rc=%d  %.0f s\n", label, rc, as.numeric(Sys.time() - t0, units = "secs")))
  if (rc != 0L) stop(label, " failed; see ", log)
}

if (!opt$pool_only) for (sd in seeds) for (st in structures) {
  pars <- STRUCT[[st]]
  world <- file.path(out_root, sprintf("w%d_%s", sd, st)); baci <- file.path(world, "BACI_HS92_V202601"); out <- file.path(world, "out")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== world seed %d, structure %s (good_sd %g, importer_sd %g, within_sd %g) ===\n", sd, st, pars$good_sd, pars$importer_sd, pars$within_sd))
  # 1. the world and its truth
  if (!file.exists(file.path(world, "truth.rds"))) {
    truth <- sb$make_synthetic_baci_dir(baci, n_goods = opt$goods, seed = sd, within_sd = pars$within_sd,
                                        good_sd = pars$good_sd, importer_sd = pars$importer_sd)
    saveRDS(truth, file.path(world, "truth.rds")); cat("    world generated\n")
  } else cat("    world exists\n")
  # 2. the pipeline
  if (!length(list.files(out, pattern = "_country_hs4_fixed_sigma\\.rds$"))) {
    run_step("run_estimation --stage all",
             c(file.path(root, "scripts", "run_estimation.R"), "--data", baci, "--out-dir", out, "--ncores", as.character(opt$ncores), "--stage", "all"),
             log = file.path(world, "log_pipeline.txt"))
  } else cat("    pipeline outputs exist\n")
  # 3. the arms (only the missing ones)
  have <- sub("^kt_arm_(.*)\\.rds$", "\\1", list.files(out, pattern = "^kt_arm_[A-Z]\\.rds$"))
  want <- setdiff(strsplit(opt$arms, ",")[[1]], have)
  if (length(want) || !file.exists(file.path(out, "kt_arm_readings.rds"))) {
    run_step(sprintf("arms %s", paste(want, collapse = ",")),
             c(file.path(root, "validation", "known_truth_stage2_arms.R"), "--data", baci, "--out-dir", out, "--ncores", "1", "--stage", "all"),
             envlist = list(KT_SEED = as.character(sd), KT_WITHIN_SD = format(pars$within_sd), KT_GOODS = as.character(opt$goods),
                            KT_ARMS = paste(want, collapse = ",")),
             log = file.path(world, "log_arms.txt"))
  } else cat("    arms exist\n")
}

# ---- pool ----
files <- list.files(out_root, pattern = "^kt_arm_readings\\.rds$", recursive = TRUE, full.names = TRUE)
if (!length(files)) stop("no readings found under ", out_root)
pool <- rbindlist(lapply(files, function(f) {
  r <- readRDS(f); w <- basename(dirname(dirname(f)))
  a <- copy(r$all)[, `:=`(world = w, seed = as.integer(sub("^w(\\d+)_.*$", "\\1", w)), structure = sub("^w\\d+_", "", w))]
  if (!is.null(r$tier1)) a <- merge(a, r$tier1[, .(arm, within_r_tier1, med_abs_le_tier1)], by = "arm", all.x = TRUE)
  a
}))
setcolorder(pool, c("world", "seed", "structure", "arm"))
fwrite(pool, file.path(out_root, "arm_readings_by_world.csv")); saveRDS(pool, file.path(out_root, "arm_readings_by_world.rds"))
metrics <- intersect(c("sigma_med_abs_lr", "R1_within_r", "within_r_tier1", "R2_tariff_r", "row_med_abs_le", "cell_med_abs_le", "tariff_med_abs_le"), names(pool))
cat(sprintf("\n=== per world (%d worlds) ===\n", uniqueN(pool$world)))
print(pool[order(structure, seed, arm), c("world", "arm", metrics), with = FALSE])
cat("\n=== pooled: median over worlds, by structure and arm ===\n")
print(pool[, lapply(.SD, function(x) round(median(x, na.rm = TRUE), 3)), by = .(structure, arm), .SDcols = metrics][order(structure, arm)])
cat("\n=== pooled: median over all worlds, by arm (n worlds per arm in brackets) ===\n")
print(pool[, c(list(n = .N), lapply(.SD, function(x) round(median(x, na.rm = TRUE), 3))), by = arm, .SDcols = metrics][order(arm)])
cat("\n=== paired against arm A, median over worlds of the difference (arm minus A) ===\n")
if ("A" %in% pool$arm) {
  base <- pool[arm == "A", c("world", metrics), with = FALSE]
  d <- merge(pool[arm != "A"], base, by = "world", suffixes = c("", "_A"))
  for (m in metrics) d[, (m) := get(m) - get(paste0(m, "_A"))]
  print(d[, c(list(n = .N), lapply(.SD, function(x) round(median(x, na.rm = TRUE), 3))), by = arm, .SDcols = metrics][order(arm)])
}
cat("\nWritten:", file.path(out_root, "arm_readings_by_world.csv"), "\n")
