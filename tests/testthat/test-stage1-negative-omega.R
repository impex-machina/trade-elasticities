# ============================================================================
# test-stage1-negative-omega.R  (patch 0046, 2026-09-01 fresh-eyes audit)
#
# A negative algebraic omega in the Feenstra inversion (rho beyond
# (sigma-1)/sigma) is the continuation of the admissible interval past
# omega = +Inf. invert_structural() clamps it to the 1e-4 floor (Stata-style;
# the OPPOSITE end of the supply-elasticity axis). The production census of
# 2026-09-01 found 36,914 shipped interior-HLIML cells in this state and
# showed that re-routing them through the Step-2 cascade alone (patch 0043
# `strict`) lands 68% of them on the same clamp again. negative_omega =
# "reject" makes the point inadmissible at EVERY inversion and lets the
# boundary search take the cell.
#
# Locks:
#   1. invert_structural(negative_omega = "reject"): beyond-Inf -> omega NA,
#      status constraint_violated, sigma/rho unchanged; the omega -> 0
#      continuation (eta1_nonpositive), an interior point, and a sub-floor
#      POSITIVE omega (still floored, status ok) are untouched.
#   2. estimate_cell_liml(): default "floor" is bit-identical to v0.6.x on a
#      beyond-Inf cell and on an interior cell.
#   3. "reject" routing on three seeded cells: (a) cf beyond-Inf + Step 2
#      failed -> boundary omega_cap; (b) cf beyond-Inf + Step 2 interior ->
#      step2_weighted adjust 1 with an interior omega; (c) cf beyond-Inf AND
#      Step 2 beyond-Inf -> boundary omega_cap even though Step 2 supplied a
#      sigma (retained in sigma_step2; omega_step2 is NA).
#   4. run_stage1_liml() stamps hliml_negative_omega on every Step-3 row;
#      --stage1-negative-omega parses, defaults to floor, validates.
# ============================================================================

.no_cell <- function(sigma, omega, J, T, seed) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  simulate_one_cell(sigma, omega, J = J, T = T, seed = seed)
}
.no_source <- function(env) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = env)
  source(file.path(root, "R", "utils_general.R"), local = env)
  source(file.path(root, "R", "liml_estimator.R"), local = env)
}

test_that("invert_structural(reject) returns omega = NA for the beyond-Inf case only", {
  .no_source(environment())
  fwd <- function(w, s) c(w / ((1 + w) * (s - 1)), (w * (s - 2) - 1) / ((1 + w) * (s - 1)))
  lim <- fwd(1e6, 3); beyond <- c(lim[1] + 1e-3, lim[2] + 2e-3)
  f <- invert_structural(beyond[1], beyond[2])
  r <- invert_structural(beyond[1], beyond[2], negative_omega = "reject")
  expect_identical(f$status, "constraint_violated"); expect_equal(f$omega, 1e-4)
  expect_identical(r$status, "constraint_violated"); expect_true(is.na(r$omega))
  expect_identical(r$sigma, f$sigma); expect_identical(r$rho, f$rho)
  # default is floor
  expect_identical(invert_structural(beyond[1], beyond[2]), f)
  # omega -> 0 continuation: unchanged
  expect_identical(invert_structural(-1e-3, -0.5, negative_omega = "reject"),
                   invert_structural(-1e-3, -0.5))
  # interior point: unchanged
  th <- fwd(0.3, 3)
  expect_identical(invert_structural(th[1], th[2], negative_omega = "reject"),
                   invert_structural(th[1], th[2]))
  # sub-floor but POSITIVE omega: still floored, status ok, under both rules
  th2 <- fwd(1e-6, 3)
  a <- invert_structural(th2[1], th2[2]); b <- invert_structural(th2[1], th2[2], negative_omega = "reject")
  expect_identical(a, b); expect_identical(a$status, "ok"); expect_equal(a$omega, 1e-4)
})

test_that("default floor is bit-identical to v0.6.x; reject re-routes the three seeded cases", {
  .no_source(environment())
  # (a) seed 91043: cf beyond-Inf, Step 2 fails (eta1_nonpositive)
  m <- .no_cell(2, 0.01, 10L, 15L, seed = 91043L)
  f0 <- estimate_cell_liml(m, hliml_method = "closed")
  ff <- estimate_cell_liml(m, hliml_method = "closed", negative_omega = "floor")
  fr <- estimate_cell_liml(m, hliml_method = "closed", negative_omega = "reject")
  expect_identical(f0, ff); expect_identical(ff$hliml_negative_omega, "floor")
  expect_identical(ff$final_source, "hliml"); expect_true(ff$omega_floored)
  expect_identical(fr$hliml_negative_omega, "reject")
  expect_identical(fr$final_source, "hliml_boundary")
  expect_identical(fr$hliml_boundary_edge, "omega_cap"); expect_identical(fr$adjust, 8L)
  expect_equal(fr$omega, 10); expect_true(fr$omega_capped); expect_false(fr$omega_floored)
  expect_true(is.na(fr$sigma_se))
  expect_false(fr$hliml_cf_admissible); expect_true(is.na(fr$omega_hliml_cf))
  expect_identical(fr$hliml_cf_inversion, "constraint_violated")
  expect_identical(fr$sigma_hliml_cf, ff$sigma_hliml_cf)   # the cf sigma is still reported
  # (b) seed 91004: cf beyond-Inf, Step 2 interior -> Step 2 wins (precedence unchanged)
  m2 <- .no_cell(2, 0.01, 10L, 15L, seed = 91004L)
  g <- estimate_cell_liml(m2, hliml_method = "closed", negative_omega = "reject")
  expect_identical(g$final_source, "step2_weighted"); expect_identical(g$adjust, 1L)
  expect_identical(g$inversion_status, "ok")
  expect_equal(g$sigma, g$sigma_step2); expect_equal(g$omega, g$omega_step2)
  expect_gt(g$omega, 1e-4); expect_lt(g$omega, 10); expect_true(is.finite(g$sigma_se))
  # (c) seed 91051: cf beyond-Inf AND Step 2 beyond-Inf -> boundary outranks sigma-without-omega
  m3 <- .no_cell(2, 0.01, 10L, 15L, seed = 91051L)
  hf <- estimate_cell_liml(m3, hliml_method = "closed")
  hr <- estimate_cell_liml(m3, hliml_method = "closed", negative_omega = "reject")
  expect_identical(hf$inversion_status, "constraint_violated"); expect_equal(hf$omega_step2, 1e-4)
  expect_identical(hr$inversion_status, "constraint_violated"); expect_true(is.na(hr$omega_step2))
  expect_true(is.finite(hr$sigma_step2))                     # Step-2 sigma retained
  expect_identical(hr$final_source, "hliml_boundary"); expect_identical(hr$hliml_boundary_edge, "omega_cap")
  expect_equal(hr$omega, 10); expect_true(is.na(hr$sigma_se))
  # an interior cell is unchanged apart from the provenance field
  mi <- .no_cell(3, 1, 20L, 40L, seed = 20260819L)
  a <- estimate_cell_liml(mi, ref_exporter = 1L)
  b <- estimate_cell_liml(mi, ref_exporter = 1L, negative_omega = "reject")
  expect_identical(a$final_source, "hliml"); expect_identical(a$hliml_cf_inversion, "ok")
  a$hliml_negative_omega <- NULL; b$hliml_negative_omega <- NULL
  expect_identical(a, b)
})

test_that("the wrapper stamps hliml_negative_omega; the CLI flag parses and validates", {
  suppressPackageStartupMessages(library(data.table))
  .no_source(environment())
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  set.seed(1L)
  raw <- data.table::data.table(importer = 1L, good = "0202",
    exporter = rep(1:6, each = 12L), t = rep(1995:2006, 6L),
    value = exp(rnorm(72)), quantity = exp(rnorm(72)))
  tmp <- tempfile(fileext = ".rds")
  out <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                         min_periods = 3L, verbose = FALSE, negative_omega = "reject")
  expect_true(all(out$hliml_negative_omega[!is.na(out$hliml_method)] == "reject"))
  out0 <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                          min_periods = 3L, verbose = FALSE)
  expect_true(all(out0$hliml_negative_omega[!is.na(out0$hliml_method)] == "floor"))
  unlink(tmp)

  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  source(file.path(root, "R", "validate_config.R"), local = TRUE)
  dd <- tempfile(); dir.create(dd)
  o0 <- parse_cli(c("--data", dd))
  expect_identical(o0$stage1_negative_omega, "floor")
  expect_identical(build_config(o0)$stage1_negative_omega, "floor")
  o1 <- parse_cli(c("--data", dd, "--stage1-negative-omega", "reject"))
  expect_identical(o1$stage1_negative_omega, "reject")
  expect_error(parse_cli(c("--data", dd, "--stage1-negative-omega", "clamp")),
               "stage1-negative-omega")
  cfg <- build_config(o1); cfg$stage1_negative_omega <- "clamp"
  expect_error(validate_config(cfg), "stage1_negative_omega")
  unlink(dd, recursive = TRUE)
})
