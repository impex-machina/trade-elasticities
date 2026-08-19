# ============================================================================
# test-stage1-harness-alignment.R
#
# Regression lock for the Pillar-2 harness DGP (validation/validate_liml.R,
# simulate_one_cell): the y / x1 / x2 columns must be ROW-ALIGNED with the
# exporter / t label columns.
#
# Background (2026-08-18 fresh-eyes audit): the moment columns were built
# with as.vector(t(sapply(non_ref, ...))) -- TIME-major order -- while the
# label columns were exporter-major (rep(non_ref, each = T)). Every labeled
# "exporter" was therefore a mixture of all true exporters, the dummies
# carried no cross-exporter heteroskedasticity, and estimate_cell_liml()
# saw a weak-instrument design that produced the 32-52% "yield" and the
# n-DECREASING yield reported as Pillar 2 through v0.5.0. Production Stage 1
# (prepare_cell_moments) was never affected -- it builds moments row-wise.
#
# test-stage1-harness-dgp.R cannot catch this: it checks a label-invariant
# identity on group means. The two checks below have power:
#   1. the labeled exporters must carry the DGP's cross-exporter
#      heteroskedasticity (large between/within F on x1) -- under the
#      misalignment F is ~1;
#   2. the production estimator must recover (sigma, omega) at a modest
#      sample size on a fixed seed -- under the misalignment it fails.
# ============================================================================

test_that("harness DGP labels are row-aligned with the moment columns", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)

  J <- 12L; T <- 200L
  mom <- simulate_one_cell(3, 1, J = J, T = T, seed = 20260818L)

  # 1. Structural: rows that share a t share the reference exporter's shock,
  #    so y is positively correlated ACROSS exporters at equal t when the
  #    labels are aligned (mean pairwise corr ~0.2-0.3); under the
  #    misalignment "equal t" rows come from different true periods and the
  #    mean pairwise correlation is ~0.
  Y <- matrix(mom$y, nrow = T, ncol = J - 1L)   # column j' = labeled exporter
  cm <- cor(Y)
  mean_offdiag <- mean(cm[upper.tri(cm)])
  expect_gt(mean_offdiag, 0.10)

  # 2. Row layout is exporter-major and t cycles within exporter.
  expect_equal(mom$exporter[1:T], rep(2L, T))
  expect_equal(mom$t[1:T], seq_len(T))
})

test_that("production estimator recovers (sigma, omega) on the aligned harness DGP", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)

  # Modest n keeps the dense HLIML/HNCS matrices small enough for CI.
  mom <- simulate_one_cell(3, 1, J = 25L, T = 100L, seed = 20260818L)
  fit <- estimate_cell_liml(mom, ref_exporter = 1L)

  expect_identical(fit$status, "ok")
  expect_lt(abs(fit$sigma - 3) / 3, 0.15)
  expect_gt(fit$omega, 0.5)
  expect_lt(fit$omega, 2.0)
})
