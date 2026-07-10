# =============================================================================
# bootstrap_se.R
#
# Exporter-cluster bootstrap benchmark for the Stage 1 sigma standard errors
# on REAL data, implementing the design specified in
# docs/methodology/validation_section_draft.md (Section 4):
#
#   - stratified subsample of estimated (importer, HS4) cells, strata on
#     n_exporters x Cragg-Donald F x estimator source;
#   - within each cell, resample exporters with replacement (the exporter is
#     the independent sampling unit in the moment construction), relabeling
#     draws so duplicated exporters enter as distinct panels; the reference
#     exporter is re-selected per replicate by the production rule (it is
#     chosen inside prepare_cell_moments);
#   - compare the bootstrap dispersion of sigma-hat across successful
#     replicates to the analytic sigma_se, as a ratio distribution by
#     stratum.
#
# Caveats (stated in the paper section, reported by this harness):
#   - validates dispersion, NOT bias -- a bootstrap centered on a biased
#     point estimate inherits the bias;
#   - within-bootstrap selection: replicates that fail estimation are
#     dropped; per-cell bootstrap yield is reported alongside the ratio.
#
# Intended runner: the EC2 estimation box (62 cores; ~20-30 min at the
# defaults). Runs serially on Windows with a warning.
#
# Usage (from the repo root):
#   Rscript validation/bootstrap_se.R \
#     --cache  /tmp/v030/out/baci_hs92_v202601_elast_country_hs4_raw_cache.rds \
#     --stage1 /tmp/v030/out/baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds \
#     --n-cells 750 --B 399 --ncores 62
#
# Outputs (under --out-dir, default docs/methodology):
#   bootstrap_se_cells_<YYYYMMDD>.csv   -- one row per sampled cell
#   bootstrap_se_summary.csv            -- ratio quantiles by stratum + overall
# =============================================================================

if (!file.exists("R/liml_estimator.R")) {
  stop("Run from the repo root (where R/ lives).")
}

suppressMessages({
  library(data.table)
  library(optparse)
})

opt_list <- list(
  make_option("--cache",  type = "character", default = NULL,
              help = "Path to the Stage 1 raw cache .rds (post clean/aggregate panel)"),
  make_option("--stage1", type = "character", default = NULL,
              help = "Path to the published Stage 1 _feenstra_sigma.rds"),
  make_option("--n-cells", type = "integer", default = 750L, dest = "n_cells"),
  make_option("--B", type = "integer", default = 399L),
  make_option("--ncores", type = "integer",
              default = max(1L, parallel::detectCores() - 2L)),
  make_option("--seed", type = "integer", default = 20260709L),
  make_option("--min-year", type = "integer", default = 1995L,
              dest = "min_year",
              help = "Passed to prepare_cell_moments; match the production run"),
  make_option("--min-boot-ok", type = "integer", default = 50L,
              dest = "min_boot_ok",
              help = "Minimum successful replicates for a cell to report a ratio"),
  make_option("--out-dir", type = "character", default = "docs/methodology",
              dest = "out_dir")
)
opts <- parse_args(OptionParser(option_list = opt_list))
if (is.null(opts$cache) || is.null(opts$stage1)) {
  stop("--cache and --stage1 are required.", call. = FALSE)
}

source("R/liml_estimator.R")

today <- format(Sys.Date(), "%Y%m%d")
dir.create(opts$out_dir, showWarnings = FALSE, recursive = TRUE)

cat("========================================================================\n")
cat("EXPORTER-CLUSTER BOOTSTRAP: STAGE 1 SIGMA SE BENCHMARK\n")
cat("========================================================================\n")
cat(sprintf("  cells=%d  B=%d  ncores=%d  seed=%d  min_boot_ok=%d\n",
            opts$n_cells, opts$B, opts$ncores, opts$seed, opts$min_boot_ok))

# --- 1. Eligible universe and strata ----------------------------------------
s1 <- readRDS(opts$stage1)
setDT(s1)

need_cols <- c("importer", "good", "status", "sigma", "sigma_se",
               "n_exporters", "fstat_kp", "final_source")
missing <- setdiff(need_cols, names(s1))
if (length(missing) > 0) {
  stop("Stage 1 file lacks columns: ", paste(missing, collapse = ", "))
}

elig <- s1[status == "ok" & is.finite(sigma) & is.finite(sigma_se)]
if ("sigma_capped" %in% names(s1)) elig <- elig[!(sigma_capped %in% TRUE)]
cat(sprintf("  Eligible cells (ok, finite sigma_se, uncapped): %s of %s ok\n",
            format(nrow(elig), big.mark = ","),
            format(s1[status == "ok", .N], big.mark = ",")))

elig[, nexp_bin := as.character(cut(n_exporters, breaks = c(3, 9, 19, 49, Inf),
                       labels = c("4-9", "10-19", "20-49", "50+")))]
elig[is.na(nexp_bin), nexp_bin := "nexp_NA"]
elig[, f_bin := as.character(cut(fstat_kp, breaks = c(-Inf, 2, 7, Inf),
                    labels = c("F<2", "F2-7", "F>=7")))]
elig[is.na(f_bin), f_bin := "F_NA"]
elig[, stratum := paste(nexp_bin, f_bin, final_source, sep = " | ")]

# Proportional allocation with a floor, then trim largest strata to total.
set.seed(opts$seed)
tab <- elig[, .(n_avail = .N), by = stratum]
floor_n <- 10L
tab[, n_target := pmin(n_avail,
                       pmax(floor_n, round(opts$n_cells * n_avail / sum(n_avail))))]
while (sum(tab$n_target) > opts$n_cells) {
  i <- which.max(tab$n_target)
  tab$n_target[i] <- tab$n_target[i] - 1L
}
cells <- elig[, .SD[sample(.N, min(.N, tab[stratum == .BY$stratum, n_target]))],
              by = stratum,
              .SDcols = c("importer", "good", "sigma", "sigma_se",
                          "n_exporters", "fstat_kp", "final_source",
                          "nexp_bin", "f_bin")]
cat(sprintf("  Sampled %d cells across %d strata (floor %d/stratum)\n",
            nrow(cells), nrow(tab), floor_n))

# --- 2. Slice the raw cache once ---------------------------------------------
cat("  Loading raw cache (this is the slow, memory-heavy step)...\n")
cache <- readRDS(opts$cache)
setDT(cache)
# The raw cache stores (year, cusval); run_estimation.R renames these to
# (t, value) before the Stage 1 driver, and prepare_cell_moments expects
# the renamed schema. Do the same here (accept either schema).
if (!"t" %in% names(cache) && "year" %in% names(cache))
  setnames(cache, "year", "t")
if (!"value" %in% names(cache) && "cusval" %in% names(cache))
  setnames(cache, "cusval", "value")
need_cache <- c("importer", "exporter", "good", "t", "value", "quantity")
miss_cache <- setdiff(need_cache, names(cache))
if (length(miss_cache) > 0)
  stop("Cache lacks columns (after year/cusval rename): ",
       paste(miss_cache, collapse = ", "))
# Coerce lookup keys to the cache's classes so the keyed join cannot
# silently miss on type.
cells[, importer := methods::as(importer, class(cache$importer)[1])]
cells[, good     := methods::as(good,     class(cache$good)[1])]
setkey(cache, importer, good)
slices <- vector("list", nrow(cells))
for (i in seq_len(nrow(cells))) {
  slices[[i]] <- cache[.(cells$importer[i], cells$good[i]), nomatch = NULL]
}
rm(cache); invisible(gc())
nr <- vapply(slices, nrow, integer(1))
cat(sprintf("  Sliced %d cell panels (%.0f MB); rows/slice min %d | med %d | max %d\n",
            length(slices), as.numeric(object.size(slices)) / 1e6,
            min(nr), as.integer(median(nr)), max(nr)))
if (median(nr) == 0)
  stop("ABORT: slices are empty -- cache/stage1 key or schema mismatch. ",
       "No outputs written.")

# --- 3. Per-cell bootstrap worker --------------------------------------------
fit_sigma <- function(panel_df) {
  prep <- tryCatch(
    prepare_cell_moments(panel_df,
                         exporter_col = "exporter", time_col = "t",
                         value_col = "value", quantity_col = "quantity",
                         min_year = opts$min_year),
    error = function(e) NULL)
  if (is.null(prep) || is.null(prep$moments) ||
      is.null(prep$n_obs) || prep$n_obs < 5) return(NA_real_)
  fit <- tryCatch(
    estimate_cell_liml(prep$moments, ref_exporter = prep$ref_exporter),
    error = function(e) NULL)
  if (is.null(fit) || !isTRUE(fit$status == "ok")) return(NA_real_)
  as.numeric(fit$sigma)
}

boot_cell <- function(i) {
  data.table::setDTthreads(1)
  set.seed(opts$seed + i)          # deterministic regardless of scheduling
  sl <- slices[[i]]
  row <- cells[i]

  sigma_base <- fit_sigma(as.data.frame(sl))

  exps <- unique(sl$exporter)
  by_exp <- split(as.data.frame(sl), sl$exporter)
  sig_b <- rep(NA_real_, opts$B)
  for (b in seq_len(opts$B)) {
    draw <- sample(exps, length(exps), replace = TRUE)
    parts <- lapply(seq_along(draw), function(j) {
      x <- by_exp[[as.character(draw[j])]]
      x$exporter <- j              # relabel: duplicates enter as distinct panels
      x
    })
    sig_b[b] <- fit_sigma(do.call(rbind, parts))
  }
  ok <- sig_b[is.finite(sig_b)]
  n_ok <- length(ok)
  list(importer = row$importer, good = row$good,
       nexp_bin = as.character(row$nexp_bin), f_bin = as.character(row$f_bin),
       final_source = row$final_source,
       n_exporters = row$n_exporters, fstat_kp = row$fstat_kp,
       sigma_pub = row$sigma, sigma_se_pub = row$sigma_se,
       sigma_base = sigma_base,
       boot_n_ok = n_ok, boot_yield = n_ok / opts$B,
       boot_med = if (n_ok > 0) median(ok) else NA_real_,
       boot_sd = if (n_ok >= opts$min_boot_ok) sd(ok) else NA_real_,
       boot_mad_sd = if (n_ok >= opts$min_boot_ok) mad(ok) else NA_real_)
}

cat(sprintf("  Bootstrapping %d cells x %d replicates...\n",
            nrow(cells), opts$B))
t0 <- Sys.time()
res_list <- if (.Platform$OS.type == "unix" && opts$ncores > 1L) {
  parallel::mclapply(seq_len(nrow(cells)), boot_cell,
                     mc.cores = opts$ncores, mc.preschedule = TRUE)
} else {
  if (.Platform$OS.type != "unix")
    warning("Windows detected: running serially. This harness is intended ",
            "for the EC2 runner.", immediate. = TRUE)
  lapply(seq_len(nrow(cells)), boot_cell)
}
cat(sprintf("  Done in %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

res <- rbindlist(res_list, fill = TRUE)
res[, ratio_sd  := boot_sd / sigma_se_pub]
res[, ratio_mad := boot_mad_sd / sigma_se_pub]

n_base_ok <- sum(is.finite(res$sigma_base))
match_rate <- mean(abs(res$sigma_base - res$sigma_pub) <
                     pmax(1e-6, 1e-6 * abs(res$sigma_pub)), na.rm = TRUE)
cat(sprintf("  Baseline refits ok: %d/%d; refit == published sigma: %.1f%%\n",
            n_base_ok, nrow(res), 100 * match_rate))
if (n_base_ok == 0)
  stop("ABORT: zero baseline refits succeeded -- schema or interface ",
       "mismatch upstream of the bootstrap. No outputs written.")
if (is.finite(match_rate) && match_rate < 0.95)
  warning(sprintf("Only %.1f%% of baseline refits reproduce the published sigma; ",
                  100 * match_rate),
          "the bootstrap may not be perturbing the production path.",
          immediate. = TRUE)

cells_path <- file.path(opts$out_dir,
                        sprintf("bootstrap_se_cells_%s.csv", today))
fwrite(res, cells_path)

# --- 4. Summary: ratio distribution by stratum + overall ---------------------
summarize <- function(d, label) {
  r <- d[is.finite(ratio_sd)]
  data.table(stratum = label, n_cells = nrow(d), n_ratio = nrow(r),
             med_yield = round(median(d$boot_yield, na.rm = TRUE), 3),
             ratio_p25 = round(quantile(r$ratio_sd, .25, na.rm = TRUE), 3),
             ratio_med = round(median(r$ratio_sd, na.rm = TRUE), 3),
             ratio_p75 = round(quantile(r$ratio_sd, .75, na.rm = TRUE), 3),
             ratio_mad_med = round(median(r$ratio_mad, na.rm = TRUE), 3),
             share_within_25pct = round(mean(abs(log(r$ratio_sd)) <= log(1.25),
                                             na.rm = TRUE), 3))
}
summ <- rbind(
  summarize(res, "OVERALL"),
  res[, summarize(.SD, paste(nexp_bin, f_bin, final_source, sep = " | ")),
      by = .(nexp_bin, f_bin, final_source)][, -(1:3)]
)
summary_path <- file.path(opts$out_dir, "bootstrap_se_summary.csv")
fwrite(summ, summary_path)

cat("\n--- Bootstrap SE calibration (ratio = bootstrap SD / analytic sigma_se) ---\n")
print(summ, nrows = 40)
cat(sprintf("\nPer-cell detail: %s\nSummary:        %s\n",
            cells_path, summary_path))
cat("Reminder: this benchmarks DISPERSION, not bias; interpret alongside\n")
cat("Pillar 2 (docs/methodology/liml_validation_tier1a.csv).\n")
