# ============================================================================
# test-v090-defaults.R  (patch 0086, 2026-10-04)
#
# v0.9.0 defaults and the two helpers behind the native gamma_V iteration and
# the sigma-edge rule. Locks:
#   1. CLI/config defaults: sigma cap 50, capped-cell omega drop, trim v2,
#      gamma_V passes 3, export period count panel, sigma edge publish, and
#      the reproducers (10 / keep / legacy / 1 / rows) still accepted;
#   2. apply_sigma_edge_rule(): 'publish' returns the table unchanged with
#      n_edge_dropped 0; 'fallback' removes exactly the sigma_capped cells and
#      records the count; a table without the column is returned unchanged;
#   3. gamma_v_step(): |d ln gamma| on Tier-1 rows estimated and converged in
#      both passes, with known quantiles on a synthetic pair.
# ============================================================================

.v9_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

test_that("v0.9.0 CLI and config defaults, with the reproducers still accepted", {
  .v9_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_v9_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  o <- parse_cli(base); cfg <- build_config(o)
  expect_equal(cfg$stage1_sigma_cap, 50); expect_identical(cfg$stage1_capped_omega, "drop")
  expect_identical(cfg$stage2_trim, "v2"); expect_equal(cfg$stage2_gamma_v_passes, 3L)
  expect_identical(cfg$stage2_export_period_count, "panel"); expect_identical(cfg$stage2_sigma_edge, "publish")
  expect_identical(cfg$stage2_fallback, "best"); expect_identical(cfg$stage2b_prior_source, "estimated")
  rep <- build_config(parse_cli(c(base, "--stage1-sigma-cap", "10", "--stage1-capped-omega", "keep", "--stage2-trim", "legacy",
                                   "--stage2-gamma-v-passes", "1", "--stage2-export-period-count", "rows", "--stage2-sigma-edge", "fallback")))
  expect_equal(rep$stage1_sigma_cap, 10); expect_identical(rep$stage1_capped_omega, "keep"); expect_identical(rep$stage2_trim, "legacy")
  expect_equal(rep$stage2_gamma_v_passes, 1L); expect_identical(rep$stage2_export_period_count, "rows"); expect_identical(rep$stage2_sigma_edge, "fallback")
  expect_error(parse_cli(c(base, "--stage2-gamma-v-passes", "0")), "stage2-gamma-v-passes")
  expect_error(parse_cli(c(base, "--stage2-sigma-edge", "drop")), "stage2-sigma-edge")
  expect_silent(validate_config(cfg))
  bad <- cfg; bad$stage2_sigma_edge <- "drop"; expect_error(validate_config(bad), "stage2_sigma_edge")
  bad <- cfg; bad$stage2_gamma_v_passes <- 0L; expect_error(validate_config(bad), "stage2_gamma_v_passes")
  dt <- make_synthetic_baci(seed = 42L); c0 <- make_synthetic_cfg()
  c_e <- c0; c_e$stage2_sigma_edge <- "fallback"
  expect_false(identical(.fs_cfg_stamp(c0, dt), .fs_cfg_stamp(c_e, dt)))
  c_pub <- c0; c_pub$stage2_sigma_edge <- "publish"
  expect_identical(.fs_cfg_stamp(c0, dt), .fs_cfg_stamp(c_pub, dt))      # absent key == publish
})

test_that("apply_sigma_edge_rule() removes exactly the sigma_capped cells under 'fallback'", {
  .v9_setup()
  s <- data.table(importer = as.character(1:6), good = "0101", sigma = c(2, 3, 50, 4, 50, 50), convergence = 0L,
                  sigma_capped = c(FALSE, FALSE, TRUE, FALSE, TRUE, NA))
  p <- apply_sigma_edge_rule(copy(s), "publish")
  expect_equal(nrow(p), 6L); expect_equal(attr(p, "n_edge_dropped"), 0L)
  f <- apply_sigma_edge_rule(copy(s), "fallback")
  expect_equal(nrow(f), 4L); expect_equal(attr(f, "n_edge_dropped"), 2L)
  expect_setequal(f$importer, c("1", "2", "4", "6"))                        # NA sigma_capped is not an edge
  nocol <- apply_sigma_edge_rule(copy(s)[, !"sigma_capped"], "fallback")
  expect_equal(nrow(nocol), 6L); expect_equal(attr(nocol, "n_edge_dropped"), 0L)
  expect_error(apply_sigma_edge_rule(copy(s), "drop"), "arg")
})

test_that("gamma_v_step() measures |d ln gamma| on Tier-1 rows estimated and converged in both passes", {
  .v9_setup()
  set.seed(3)
  n <- 2000L
  prev <- data.table(importer = as.character(seq_len(n) %% 40L), exporter = paste0("e", seq_len(n)), good = "0101",
                     gamma = exp(rnorm(n, -0.4, 0.5)), tier = rep(c(1L, 1L, 1L, 0L, 3L), length.out = n), convergence = 0L)
  cur <- copy(prev); d <- rnorm(n, 0, 0.1); cur[, gamma := gamma * exp(d)]
  cur[1:10, convergence := 1L]                                              # rows not converged in the new pass are excluded
  st <- gamma_v_step(prev, cur)
  keep <- prev$tier == 1L & cur$convergence == 0L
  expect_equal(unname(st["n"]), sum(keep))
  expect_equal(unname(st["p50"]), unname(quantile(abs(d[keep]), .5)))
  expect_equal(unname(st["p90"]), unname(quantile(abs(d[keep]), .9)))
  expect_equal(unname(st["max"]), max(abs(d[keep])))
  expect_equal(unname(st["share_lt_1e2"]), mean(abs(d[keep]) < 1e-2))
  expect_equal(unname(gamma_v_step(prev, prev)["p99"]), 0)
})
