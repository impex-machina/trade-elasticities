# ============================================================================
# test-sigma-edge-se.R  (patch 0090, 2026-10-10)
#
# The sigma-edge rule (patches 0086/0087) drops a Stage-1 cell whose sigma is
# a box edge from the clean set, so Stage 2b gives it the fallback sigma. The
# Stage-1 sigma_se and adjust lookups the sigma-propagation step reads were
# still built from the FULL Stage-1 table through v0.9.0, so on such a cell
# sigma_robust / gamma_se_total / sigma_se / dgamma_dsigma were computed with
# the SE of the discarded estimate beside the fallback sigma. Locks:
#   1. the cell estimator: a cell whose sigma is the fallback publishes
#      sigma_se / dgamma_dsigma / gamma_se_total NA and sigma_robust FALSE
#      even when the lookups carry a finite SE and adjust 6 for it; a cell
#      whose sigma is looked up still reads its SE and adjust code;
#   2. stage2b_sigma_lookups(): the four lookups come from one clean table,
#      keyed on character (importer, good); NULL where a column is absent;
#   3. apply_sigma_edge_se_rule(): on a table carrying the leak it reproduces
#      the patched estimator's output on the edge cell exactly, leaves every
#      other value alone, is idempotent, and refuses a table whose edge cells
#      do not share one sigma (i.e. not produced under the fallback rule).
# ============================================================================

.se_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

.se_run <- function(cfg, dt) {
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

# fixture: cell (840, 8501) has left the clean set (the edge rule), cell
# (276, 8501) is looked up with a finite SE and adjust 0; both lookups carry a
# finite SE / adjust 6 for the dropped cell, as the v0.9.0 runner built them.
.se_cfg <- function() {
  cfg <- make_synthetic_cfg()
  cfg$bw_lag <- "calendar"
  cfg$sigma_lookup <- cfg$sigma_lookup[!(importer == "840" & good == "8501")]
  cfg$sigma_fallback <- 2.306
  cfg$sigma_se_lookup <- data.table(importer = c("840", "276", "392"), good = "8501", sigma_se = c(0.30, 0.25, NA_real_))
  cfg$sigma_adjust_lookup <- data.table(importer = c("840", "276", "392"), good = "8501", adjust = c(6L, 0L, 0L))
  cfg
}

test_that("a fallback-sigma cell publishes no Stage-1 SE, no propagation and sigma_robust FALSE", {
  .se_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  out <- .se_run(.se_cfg(), dt)
  edge <- out[importer == "840" & good == "8501"]
  expect_gt(nrow(edge), 0L)
  expect_true(all(edge$sigma == 2.306))
  expect_true(all(is.na(edge$sigma_se)))
  expect_true(all(is.na(edge$dgamma_dsigma)))
  expect_true(all(is.na(edge$gamma_se_total)))
  expect_true(all(edge$sigma_robust[!is.na(edge$sigma_robust)] == FALSE))
  expect_true(any(edge$sigma_robust %in% FALSE))                    # estimated rows carry a flag
  expect_true(any(is.finite(edge$gamma_se)))                        # gamma and its conditional SE are untouched
  # the looked-up cell still reads its SE and adjust code on the merits
  kept <- out[importer == "276" & good == "8501" & !is.na(sigma_robust)]
  expect_gt(nrow(kept), 0L)
  expect_true(all(kept$sigma == 4.0))
  expect_true(all(kept$sigma_se == 0.25))
  expect_true(any(is.finite(kept$dgamma_dsigma)))
})

test_that("stage2b_sigma_lookups() builds the four lookups from one clean table", {
  .se_setup()
  clean <- data.table(importer = c(840L, 276L), good = c("8501", "8504"), sigma = c(4, 3),
                      sigma_se = c(0.3, NA_real_), adjust = c(0, 6))
  lk <- stage2b_sigma_lookups(clean)
  expect_setequal(names(lk), c("sigma_lookup", "sigma_se_lookup", "sigma_adjust_lookup", "sigma_V_lookup"))
  expect_identical(lk$sigma_lookup$importer, c("840", "276"))
  expect_identical(lk$sigma_lookup, lk$sigma_V_lookup)
  expect_identical(lk$sigma_se_lookup$sigma_se, c(0.3, NA_real_))
  expect_identical(lk$sigma_adjust_lookup$adjust, c(0L, 6L))
  expect_equal(nrow(lk$sigma_se_lookup[importer == "392"]), 0L)       # a cell outside the clean set has no row anywhere
  lk2 <- stage2b_sigma_lookups(clean[, .(importer, good, sigma)])
  expect_null(lk2$sigma_se_lookup); expect_null(lk2$sigma_adjust_lookup)
  expect_error(stage2b_sigma_lookups(clean[, .(importer, good)]), "sigma")
})

test_that("apply_sigma_edge_se_rule() reproduces the patched output on an existing table and is idempotent", {
  .se_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L)
  ref <- .se_run(.se_cfg(), dt)
  # plant the v0.9.0 leak on the edge cell: the discarded estimate's SE beside
  # the fallback sigma, a passed screen and a propagated SE
  leaky <- copy(ref)
  is_edge <- leaky$importer == "840" & leaky$good == "8501"
  leaky[is_edge & !is.na(sigma_robust), `:=`(sigma_se = 0.30, sigma_robust = TRUE,
                                             dgamma_dsigma = 0.1, gamma_se_total = sqrt(gamma_se^2 + 0.03^2))]
  expect_false(isTRUE(all.equal(leaky, ref)))
  stage1 <- data.table(importer = c("840", "276", "392"), good = "8501", status = "ok",
                       sigma_capped = c(TRUE, FALSE, FALSE), sigma = c(50, 4, 4))
  cen <- apply_sigma_edge_se_rule(leaky, stage1)
  expect_equal(cen$n_edge_cells_stage1, 1L); expect_equal(cen$n_edge_cells_in_table, 1L)
  expect_equal(cen$n_edge_rows, sum(is_edge)); expect_equal(cen$sigma_edge_value, 2.306)
  expect_gt(cen$before$sigma_robust_true, 0L)
  expect_identical(leaky, ref)                                        # exactly the patched estimator's output
  cen2 <- apply_sigma_edge_se_rule(leaky, stage1)
  expect_equal(cen2$n_values_reset, 0L); expect_identical(leaky, ref)
  # a Tier-3 row keeps sigma_robust NA
  t3 <- ref[is_edge & tier == 3L]
  if (nrow(t3)) expect_true(all(is.na(t3$sigma_robust)))
  # a table whose edge cells do not share one sigma was not produced under the fallback rule
  bad <- copy(ref); bad[is_edge & exporter == bad[is_edge]$exporter[1], sigma := 7]
  expect_error(apply_sigma_edge_se_rule(bad, stage1), "distinct sigma")
  # the script runs end to end on a saved table and leaves the row count intact
  s1_path <- tempfile(fileext = ".rds"); in_path <- tempfile(fileext = ".rds"); out_path <- tempfile(fileext = ".rds")
  saveRDS(stage1, s1_path)
  leaky2 <- copy(ref); leaky2[is_edge & !is.na(sigma_robust), `:=`(sigma_se = 0.30, sigma_robust = TRUE)]
  saveRDS(leaky2, in_path)
  script <- file.path(locate_source_dir(), "..", "scripts", "apply_sigma_edge_se_rule.R")
  skip_if_not(file.exists(script))
  res <- system2(file.path(R.home("bin"), "Rscript"), c(script, "--stage1", s1_path, "--in", in_path, "--out", out_path),
                 stdout = TRUE, stderr = TRUE)
  expect_true(file.exists(out_path), info = paste(res, collapse = "\n"))
  got <- readRDS(out_path); setDT(got)
  expect_equal(nrow(got), nrow(ref))
  expect_true(all(is.na(got[importer == "840" & good == "8501"]$sigma_se)))
  expect_true(all(got[importer == "840" & good == "8501" & !is.na(sigma_robust)]$sigma_robust == FALSE))
})
