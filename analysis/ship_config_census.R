#!/usr/bin/env Rscript
# ===========================================================================
# analysis/ship_config_census.R  (patch 0155)
#
# Two runs of the pipeline on the same panel -- the current defaults (base)
# and the configuration as it will ship -- read side by side: what the
# shipping configuration changes in the published table before the default
# is flipped. Readings (fixed before the numbers): sigma, gamma and
# opt_tariff quantiles; sigma_source and sigma_robust shares; cell by cell,
# the share of cells whose sigma moved and by how much (median |d ln(sigma -
# 1)|), the share of rows whose gamma moved by more than 1%, the share of
# cells whose opt_tariff moved by more than 1%; coverage (rows, cells,
# fallback cells) in each. No rule: this is the description the default-flip
# patch and its README text are written from.
#
# Usage (from the repo root):
#   Rscript analysis/ship_config_census.R --base <out-dir of the base run> --ship <out-dir of the ship run> [--md docs/results/ship_config_census.md]
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(optparse) })

opt <- parse_args(OptionParser(option_list = list(
  make_option("--base", type = "character", help = "--out-dir of the run under the current defaults"),
  make_option("--ship", type = "character", help = "--out-dir of the run under the configuration as it will ship"),
  make_option("--md", type = "character", default = "", help = "optional markdown record to write")
)))
if (is.null(opt$base) || is.null(opt$ship)) stop("--base and --ship are required")

load_tab <- function(dir) {
  f <- list.files(dir, pattern = "_country_hs4_fixed_sigma\\.rds$", full.names = TRUE)
  if (length(f) != 1L) stop("expected one *_country_hs4_fixed_sigma.rds under ", dir, ", found ", length(f))
  t <- readRDS(f); setDT(t)
  if (!"sigma_source" %in% names(t)) t[, sigma_source := NA_character_]
  t[, `:=`(importer = as.character(importer), exporter = as.character(exporter), good = as.character(good))]
  pub <- if ("trim_reason" %in% names(t)) is.na(t$trim_reason) | t$trim_reason == "" else rep(TRUE, nrow(t))
  list(all = t, pub = t[pub], file = basename(f))
}
B <- load_tab(opt$base); S <- load_tab(opt$ship)
q <- function(x) { x <- x[is.finite(x)]; sprintf("%.3f / %.3f / %.3f", quantile(x, 0.25), median(x), quantile(x, 0.75)) }
est <- function(t) t[tier %in% c(0L, 1L, 2L) | (is.finite(convergence) & convergence >= 0L)]

desc <- function(W, lab) {
  t <- W$pub; cells <- unique(t[, .(importer, good, sigma, sigma_source)])
  data.table(table = lab, rows = nrow(t), cells = nrow(cells),
             sigma_q = q(cells$sigma), gamma_q = q(t$gamma), tariff_q = q(unique(t[, .(importer, good, opt_tariff)])$opt_tariff),
             fallback_cells = sum(startsWith(cells$sigma_source, "fallback_"), na.rm = TRUE),
             sigma_robust_share = if ("sigma_robust" %in% names(t)) round(mean(t$sigma_robust %in% TRUE), 3) else NA_real_,
             tier3_share = round(mean(t$tier == 3L), 3))
}
D <- rbind(desc(B, "base"), desc(S, "ship"))
cat("\n=== ship-config census: base vs ship, published rows ===\n"); cat("base:", B$file, "| ship:", S$file, "\n")
print(D)
cat("\n-- sigma_source shares (published rows) --\n")
ss <- rbind(B$pub[, .(table = "base", n = .N), by = sigma_source], S$pub[, .(table = "ship", n = .N), by = sigma_source])
print(dcast(ss, sigma_source ~ table, value.var = "n", fill = 0L))

# cell by cell
cb <- unique(B$pub[, .(importer, good, sigma_b = sigma, tau_b = opt_tariff)]); cs <- unique(S$pub[, .(importer, good, sigma_s = sigma, tau_s = opt_tariff)])
cc <- merge(cb, cs, by = c("importer", "good"))
cc[, dls := log(sigma_s - 1) - log(sigma_b - 1)]
rb <- B$pub[, .(importer, exporter, good, gamma_b = gamma)]; rs <- S$pub[, .(importer, exporter, good, gamma_s = gamma)]
rr <- merge(rb, rs, by = c("importer", "exporter", "good"))
rr[, dlg := log(gamma_s) - log(gamma_b)]
cat("\n-- cell by cell (cells in both tables) --\n")
cat(sprintf("  cells %d | sigma moved (|d ln(sigma-1)| > 1e-6) in %.1f%% | median |d ln(sigma-1)| among moved %.3f | r(ln sigma_b, ln sigma_s) %.3f\n",
            nrow(cc), 100 * mean(abs(cc$dls) > 1e-6, na.rm = TRUE), median(abs(cc$dls[abs(cc$dls) > 1e-6]), na.rm = TRUE), cor(log(cc$sigma_b), log(cc$sigma_s), use = "complete.obs")))
cat(sprintf("  opt_tariff moved by > 1%% in %.1f%% of cells | median |d ln tau| %.4f\n",
            100 * mean(abs(log(cc$tau_s / cc$tau_b)) > 0.01, na.rm = TRUE), median(abs(log(cc$tau_s / cc$tau_b)), na.rm = TRUE)))
cat(sprintf("  rows %d | gamma moved by > 1%% in %.1f%% of rows | median |d ln gamma| %.4f | p90 %.4f\n",
            nrow(rr), 100 * mean(abs(rr$dlg) > 0.01, na.rm = TRUE), median(abs(rr$dlg), na.rm = TRUE), quantile(abs(rr$dlg), 0.9, na.rm = TRUE)))
cat(sprintf("  rows only in base %d | only in ship %d\n", nrow(rb) - nrow(rr), nrow(rs) - nrow(rr)))

if (nzchar(opt$md)) {
  f3 <- function(x) sprintf("%.3f", x)
  lines <- c("# Ship-config census (patch 0155)", "", sprintf("Base `%s` (current defaults) against ship `%s` (configuration as it will ship), published rows.", B$file, S$file), "",
             "| table | rows | cells | sigma q25/50/75 | gamma q25/50/75 | opt_tariff q25/50/75 | fallback cells | sigma_robust share | Tier-3 share |", "|---|---|---|---|---|---|---|---|---|",
             sprintf("| %s | %d | %d | %s | %s | %s | %d | %s | %s |", D$table, D$rows, D$cells, D$sigma_q, D$gamma_q, D$tariff_q, D$fallback_cells, f3(D$sigma_robust_share), f3(D$tier3_share)), "",
             sprintf("Cell by cell: %d common cells; sigma moved in %.1f%% (median |d ln(sigma-1)| among moved %.3f; r %.3f); opt_tariff moved by > 1%% in %.1f%% of cells (median |d ln tau| %.4f); gamma moved by > 1%% in %.1f%% of %d common rows (median |d ln gamma| %.4f, p90 %.4f).",
                     nrow(cc), 100 * mean(abs(cc$dls) > 1e-6, na.rm = TRUE), median(abs(cc$dls[abs(cc$dls) > 1e-6]), na.rm = TRUE), cor(log(cc$sigma_b), log(cc$sigma_s), use = "complete.obs"),
                     100 * mean(abs(log(cc$tau_s / cc$tau_b)) > 0.01, na.rm = TRUE), median(abs(log(cc$tau_s / cc$tau_b)), na.rm = TRUE),
                     100 * mean(abs(rr$dlg) > 0.01, na.rm = TRUE), nrow(rr), median(abs(rr$dlg), na.rm = TRUE), quantile(abs(rr$dlg), 0.9, na.rm = TRUE)), "",
             "sigma_source (published rows):", "", "| sigma_source | base | ship |", "|---|---|---|")
  w <- dcast(ss, sigma_source ~ table, value.var = "n", fill = 0L)
  lines <- c(lines, sprintf("| %s | %d | %d |", w$sigma_source, w$base, w$ship))
  writeLines(lines, opt$md); cat("Written:", opt$md, "\n")
}
