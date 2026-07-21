# ============================================================================
# test-stage1-diagnostic-counts.R
#
# Locks for the G3 (v0.4.1) Stage-1 diagnostics count corrections.
#
# Once the reference exporter's all-zero rows are dropped (GS_Data.do:98 and
# estimate_cell_liml both do), the exporter dummies span the constant, so:
#   - effective excluded instruments = J_nr - 1  (not J_nr),
#   - Sargan dof = J_nr - 3: a 3-exporter cell is JUST-identified and the
#     Sargan test does not exist (sargan_pass = NA, not a mechanical pass),
#   - the strict Stock-Yogo row is J_nr - 1,
#   - the Cragg-Donald statistic partials the constant out of both blocks
#     (hence is invariant to constant shifts of the endogenous regressors),
# while the gs25 / sargan_pass_gs columns reproduce G&S's own published
# conventions (SY row at total supplier count J_nr + 1; HN-J dof J_nr - 2).
# See docs/methodology/stata_port_deviations.md, section B3.
# ============================================================================

liml_env <- new.env()
local({
  src_dir <- locate_source_dir()
  source(file.path(src_dir, "hs_codes.R"), local = liml_env)
  source(file.path(src_dir, "liml_estimator.R"), local = liml_env)
})

mk_cell <- function(J_nr, Tn = 12, seed = 1) {
  set.seed(seed)
  d <- expand.grid(exporter = paste0("E", seq_len(J_nr)), t = seq_len(Tn))
  d$y  <- abs(rnorm(nrow(d), 0.5, 0.2))
  d$x1 <- abs(rnorm(nrow(d), 0.8, 0.3))
  d$x2 <- rnorm(nrow(d), 0.1, 0.2)
  d
}

test_that("3-exporter cells are just-identified: sargan_pass is NA", {
  r <- liml_env$estimate_cell_liml(mk_cell(3), ref_exporter = "REF_ABSENT")
  expect_identical(r$status, "ok")
  expect_true(is.na(r$jstat_pval))
  expect_true(is.na(r$sargan_pass))
})

test_that("Sargan dof is J_nr - 3 for overidentified cells", {
  seeds <- c(`4` = 7L, `6` = 3L)   # first seeds giving status == "ok"
  for (J in c(4L, 6L)) {
    r <- liml_env$estimate_cell_liml(mk_cell(J, seed = seeds[[as.character(J)]]),
                                     ref_exporter = "REF_ABSENT")
    expect_identical(r$status, "ok")
    expect_equal(r$jstat_pval, 1 - pchisq(r$jstat, df = J - 3L),
                 tolerance = 1e-12, label = sprintf("J_nr = %d", J))
  }
})

test_that("Stock-Yogo rows: strict at J_nr - 1, gs25 at J_nr + 1", {
  tbl <- liml_env$.stockyogo_2endog_liml
  cv_at <- function(row, col) tbl[[col]][match(row, tbl$suppliers)]
  r <- liml_env$estimate_cell_liml(mk_cell(3), ref_exporter = "REF_ABSENT")
  expect_equal(r$stockyogo_cv, cv_at(2L, "cv_0.10"))
  expect_equal(r$stockyogo_cv_gs25, cv_at(4L, "cv_0.25"))
  r6 <- liml_env$estimate_cell_liml(mk_cell(6, seed = 3), ref_exporter = "REF_ABSENT")
  expect_equal(r6$stockyogo_cv, cv_at(5L, "cv_0.10"))
  expect_equal(r6$stockyogo_cv_gs25, cv_at(7L, "cv_0.25"))
})

test_that("Cragg-Donald F partials out the constant (shift invariance)", {
  d <- mk_cell(6, seed = 3)
  Z <- sapply(paste0("E", 1:6), function(e) as.numeric(d$exporter == e))
  f1 <- liml_env$kleibergen_paap_F(cbind(d$x1, d$x2), Z)
  f2 <- liml_env$kleibergen_paap_F(cbind(d$x1 + 100, d$x2 - 50), Z)
  expect_equal(f1, f2, tolerance = 1e-8)
  # and weighted variant
  w <- runif(nrow(d), 0.5, 2)
  f3 <- liml_env$kleibergen_paap_F(cbind(d$x1, d$x2), Z, weights = w)
  f4 <- liml_env$kleibergen_paap_F(cbind(d$x1 + 7, d$x2 + 3), Z, weights = w)
  expect_equal(f3, f4, tolerance = 1e-8)
})

test_that("G&S-protocol overid screen uses jstat_h at dof J_nr - 2", {
  r <- liml_env$estimate_cell_liml(mk_cell(6, seed = 3), ref_exporter = "REF_ABSENT")
  expect_identical(r$status, "ok")
  if (!is.na(r$jstat_h)) {
    expect_equal(r$jstat_h_pval_gs, 1 - pchisq(r$jstat_h, df = 6L + 1L - 3L),
                 tolerance = 1e-12)
    expect_identical(r$sargan_pass_gs, r$jstat_h_pval_gs > 0.2)
  } else {
    succeed("jstat_h NA on this fixture; gs columns correctly NA")
    expect_true(is.na(r$sargan_pass_gs))
  }
})
