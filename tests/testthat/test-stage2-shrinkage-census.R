# ============================================================================
# test-stage2-shrinkage-census.R  (patch 0067, 2026-09-24 fresh-eyes audit #3)
#
# analysis/stage2_shrinkage_census.R measures, on the shipped Stage-2b/2a
# tables, how much of the published gamma is the good-level prior. Locks:
#   1. on a table whose gamma IS the prior on every row, the census reports
#      |dev| = 0 everywhere, a 100% good share in the variance decomposition,
#      and the implied data share 2(1-s)/(2-s) of its shrink_wt;
#   2. on a random table the three decomposition shares sum to one, every
#      headline is finite, and imputed rows (tier 3, or convergence -1 on a
#      reference row) are excluded from the estimated set;
#   3. the CLI path writes the JSON and the markdown.
# ============================================================================

.census_src <- function() {
  src_dir <- locate_source_dir()
  file.path(dirname(src_dir), "analysis", "stage2_shrinkage_census.R")
}
.load_census <- function() {
  env <- new.env(parent = globalenv())
  assign("SHRINKAGE_CENSUS_NO_MAIN", TRUE, envir = env)
  sys.source(.census_src(), envir = env)
  env
}
.mk_tables <- function(seed = 7L, prior_only = TRUE, shrink = 0.98) {
  set.seed(seed)
  goods <- sprintf("%04d", 1001:1004); lnp <- c(-0.5, -0.2, 0.1, 0.4); names(lnp) <- goods
  s2a <- data.table::CJ(importer = c("R1", "R2", "R3"), good = goods)
  s2a[, sigma := 3]; s2a[, gamma := exp(lnp[good] + c(-0.05, 0, 0.05)[match(importer, c("R1", "R2", "R3"))])]
  rows <- list()
  for (g in goods) for (imp in as.character(1:5)) {
    exp_ids <- sprintf("%d", 100 + 1:6)
    tier <- c(0L, 1L, 1L, 2L, 3L, 3L)
    gam <- if (prior_only) rep(exp(lnp[[g]]), 6) else exp(lnp[[g]] + rnorm(6, 0, 0.5))
    rows[[length(rows) + 1L]] <- data.table::data.table(
      importer = imp, exporter = exp_ids, good = g, sigma = 3, gamma = gam,
      gamma_shrink_wt = ifelse(tier < 3L, shrink, NA_real_), tier = tier,
      convergence = ifelse(tier < 3L, 0L, -1L), avg_trade = runif(6, 1, 100),
      opt_tariff = exp(lnp[[g]]) * (if (prior_only) 1 else exp(rnorm(1, 0, 0.3))), ref_exporter = exp_ids[1])
  }
  # one all-Tier-3 cell: the reference row is imputed (tier 0, convergence -1)
  rows[[length(rows) + 1L]] <- data.table::data.table(
    importer = "9", exporter = c("201", "202", "203"), good = goods[1], sigma = 3, gamma = exp(lnp[[1]]),
    gamma_shrink_wt = NA_real_, tier = c(3L, 3L, 0L), convergence = -1L, avg_trade = c(5, 6, 7),
    opt_tariff = NA_real_, ref_exporter = "203")
  list(s2b = data.table::rbindlist(rows), s2a = s2a, priors = lnp)
}

test_that("a prior-only table reads as 100% prior", {
  env <- .load_census(); tb <- .mk_tables(prior_only = TRUE, shrink = 0.98)
  res <- env$shrinkage_census(tb$s2b, tb$s2a)
  expect_equal(res$meta$n_estimated, 4 * 5 * 4)                      # tier 0/1/1/2 per cell; imputed cell excluded
  expect_equal(res$q3$share_within_1pct, 1)
  expect_equal(res$q3$abs_dev$p90, 0)
  expect_equal(res$q2$unweighted$share_good, 1)
  expect_equal(res$q2$unweighted$share_exporter_within_cell, 0)
  expect_equal(res$q1$implied_data_share$p50, 2 * 0.02 / 1.02, tolerance = 1e-12)
  expect_equal(res$q4$within_cell_sd_log_gamma$p90, 0)
  expect_equal(res$q5$share_within_5pct, 1)
  expect_equal(res$q3$reference_rows$n, 20)
})

test_that("a random table gives a valid decomposition and excludes imputed rows", {
  env <- .load_census(); tb <- .mk_tables(prior_only = FALSE, shrink = 0.5)
  res <- env$shrinkage_census(tb$s2b, tb$s2a)
  v <- res$q2$unweighted
  expect_equal(v$share_good + v$share_cell_within_good + v$share_exporter_within_cell, 1, tolerance = 1e-10)
  v <- res$q2$trade_weighted
  expect_equal(v$share_good + v$share_cell_within_good + v$share_exporter_within_cell, 1, tolerance = 1e-10)
  expect_gt(res$q2$unweighted$share_exporter_within_cell, 0.3)
  expect_equal(res$meta$n_estimated, 80)                               # the convergence -1 reference row is out
  expect_true(all(is.finite(unlist(res$q1$shrink_wt))))
  expect_equal(res$q1$implied_data_share$p50, 2 * 0.5 / 1.5, tolerance = 1e-12)
  expect_true(is.finite(res$q4$ratio_median_within_cell_sd_to_prior_sd))
  expect_true(all(res$q6$n >= 0))
  md <- env$.render_md(res, "s2b.rds", "s2a.rds")
  expect_true(any(grepl("^## Q2", md)))
})

test_that("the CLI path writes JSON and markdown", {
  tb <- .mk_tables(prior_only = FALSE)
  td <- tempfile("census_"); dir.create(td)
  p2b <- file.path(td, "s2b.rds"); p2a <- file.path(td, "s2a.rds")
  saveRDS(tb$s2b, p2b); saveRDS(tb$s2a, p2a)
  out_json <- file.path(td, "out.json"); out_md <- file.path(td, "out.md")
  rscript <- file.path(R.home("bin"), "Rscript")
  status <- system2(rscript, c(.census_src(), "--stage2b", p2b, "--stage2a", p2a, "--out", out_json, "--md", out_md),
                    stdout = FALSE, stderr = FALSE)
  expect_equal(status, 0L)
  expect_true(file.exists(out_json)); expect_true(file.exists(out_md))
  j <- jsonlite::fromJSON(out_json)
  expect_equal(j$meta$n_estimated, 80)
  unlink(td, recursive = TRUE)
})
