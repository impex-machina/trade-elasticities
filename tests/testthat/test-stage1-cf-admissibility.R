# ============================================================================
# test-stage1-cf-admissibility.R  (patch 0043, 2026-09-01 fresh-eyes audit)
#
# The closed-form HLIML point is inverted through invert_structural(), which
# clamps a NEGATIVE algebraic omega (rho > (sigma-1)/sigma, status
# "constraint_violated") up to the 1e-4 floor. hliml_closed_form()'s legacy
# admissibility test only checks omega > 0, so such a point is routed as an
# interior HLIML estimate (adjust 0, final_source "hliml", omega_floored).
# Geometrically that point is the continuation of the admissible interval
# past omega = +Inf, so the floor is the wrong end: on the synthetic DGP the
# constrained optimum of the same cell sits on the omega CAP edge.
#
# Locks:
#   1. invert_structural() geometry: the "constraint_violated" region is the
#      omega -> +Inf continuation (theta2 > 1 - theta1 with theta1 > 0), and
#      the "eta1_nonpositive" region is the omega -> 0 continuation.
#   2. hliml_closed_form(strict = TRUE) rejects a clamped point that the
#      legacy rule accepts; every other field is identical.
#   3. estimate_cell_liml(): default cf_admissibility is "legacy" and
#      bit-identical to v0.6.x; "strict" re-routes a seeded constraint-
#      violated cell to the cascade -- one seed lands on the omega_cap
#      boundary edge, another on Step 2 -- and never leaves the cell
#      without a sigma where legacy had one.
#   4. run_stage1_liml() carries hliml_cf_admissibility on every Step-3 row.
#   5. --stage1-cf-admissibility parses, defaults to legacy, validates.
# ============================================================================

.cfa_cell <- function(sigma, omega, J, T, seed) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  simulate_one_cell(sigma, omega, J = J, T = T, seed = seed)
}

.cfa_source <- function(env) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = env)
  source(file.path(root, "R", "utils_general.R"), local = env)
  source(file.path(root, "R", "liml_estimator.R"), local = env)
}

test_that("constraint_violated is the omega -> +Inf continuation, eta1 <= 0 the omega -> 0 one", {
  .cfa_source(environment())
  # forward map at sigma = 3: theta1 = w/((1+w)*2), theta2 = (w - 1)/((1+w)*2)
  fwd <- function(w) c(w / ((1 + w) * 2), (w - 1) / ((1 + w) * 2))
  # omega -> Inf limit is (1/2, 1/2): theta2 = 1 - theta1. Step just past it.
  lim <- fwd(1e6)
  beyond <- c(lim[1] + 1e-3, lim[2] + 2e-3)        # theta2 > 1 - theta1, theta1 > 0
  r <- invert_structural(beyond[1], beyond[2])
  expect_identical(r$status, "constraint_violated")
  expect_equal(r$omega, 1e-4)                       # clamped to the FLOOR ...
  expect_gt(r$rho, (r$sigma - 1) / r$sigma)         # ... although rho says omega = +Inf side
  # inside the box just short of the limit: a large positive omega, status ok
  inside <- fwd(50)
  r2 <- invert_structural(inside[1], inside[2])
  expect_identical(r2$status, "ok"); expect_gt(r2$omega, 10)
  # the other end: theta1 <= 0 is the omega -> 0 continuation
  r3 <- invert_structural(-1e-3, -0.5)
  expect_identical(r3$status, "eta1_nonpositive")
})

test_that("strict closed form rejects a clamped point the legacy rule accepts", {
  .cfa_source(environment())
  # Plant theta just past the omega -> +Inf limit at sigma = 3 on a panel
  # whose x1/x2 carry strong exporter (group) variation, so the HLIM
  # eigenvector lands on the planted theta: the inversion clamps omega.
  set.seed(4L)
  J <- 12L; T <- 20L; g <- rep(seq_len(J), each = T)
  ge1 <- rnorm(J)[g]; ge2 <- rnorm(J)[g]
  x1 <- exp(ge1 + rnorm(J * T, 0, 0.3)); x2 <- ge2 + rnorm(J * T, 0, 0.3)
  fwd <- function(w, s) c(w / ((1 + w) * (s - 1)), (w * (s - 2) - 1) / ((1 + w) * (s - 1)))
  lim <- fwd(1e6, 3)
  th <- c(0.7, lim[1] + 0.02, lim[2] + 0.04)
  X <- cbind(1, x1, x2); Y <- as.numeric(X %*% th) + rnorm(J * T, 0, 0.05)
  lg <- hliml_closed_form(Y, X, g)
  st <- hliml_closed_form(Y, X, g, strict = TRUE)
  expect_identical(lg$status, "ok"); expect_identical(st$status, "ok")
  expect_identical(lg$inversion_status, "constraint_violated")
  expect_gt(lg$rho, (lg$sigma - 1) / lg$sigma)      # the omega = +Inf side
  expect_true(lg$admissible)                        # legacy: floored omega passes
  expect_false(st$admissible)                       # strict: rejected
  expect_equal(lg$omega, 1e-4)
  # everything except the verdict is identical
  lg$admissible <- NULL; st$admissible <- NULL
  expect_identical(lg, st)
})

test_that("estimate_cell_liml: default is legacy and bit-identical; strict re-routes to the cascade", {
  .cfa_source(environment())
  # seed 91043 -> strict lands on the omega_cap boundary edge
  mom <- .cfa_cell(2, 0.01, 10L, 15L, seed = 91043L)
  f0 <- estimate_cell_liml(mom, ref_exporter = NULL, hliml_method = "closed")
  fl <- estimate_cell_liml(mom, ref_exporter = NULL, hliml_method = "closed",
                           cf_admissibility = "legacy")
  fs <- estimate_cell_liml(mom, ref_exporter = NULL, hliml_method = "closed",
                           cf_admissibility = "strict")
  expect_identical(f0, fl)                          # default == legacy
  expect_identical(fl$hliml_cf_admissibility, "legacy")
  expect_identical(fs$hliml_cf_admissibility, "strict")
  # legacy: interior HLIML with a floored omega -- the shipped v0.6.x reading
  expect_identical(fl$status, "ok")
  expect_identical(fl$final_source, "hliml"); expect_identical(fl$adjust, 0L)
  expect_true(fl$omega_floored); expect_equal(fl$omega, 1e-4)
  expect_identical(fl$hliml_cf_inversion, "constraint_violated")
  expect_true(fl$hliml_cf_admissible)
  expect_true(is.na(fl$hliml_bd_edge))              # boundary search never ran
  # strict: closed form inadmissible, cascade ran, boundary search picked the cap
  expect_identical(fs$status, "ok")
  expect_false(fs$hliml_cf_admissible)
  expect_identical(fs$hliml_status, "cf_inadmissible")
  expect_identical(fs$final_source, "hliml_boundary")
  expect_identical(fs$hliml_boundary_edge, "omega_cap"); expect_identical(fs$adjust, 8L)
  expect_true(fs$omega_capped); expect_false(fs$omega_floored)
  expect_equal(fs$omega, 10)
  expect_gt(fs$sigma, 1); expect_lt(fs$sigma, 10)
  # the two sigmas differ: the unconstrained point is not the constrained one
  expect_false(isTRUE(all.equal(fs$sigma, fl$sigma)))
  # Steps 1-2 are shared, so the Step-2 fields agree across rules
  expect_identical(fs$sigma_step2, fl$sigma_step2)
  expect_identical(fs$eta_step2, fl$eta_step2)
  # the closed-form point itself is reported identically in both modes
  expect_identical(fs$sigma_hliml_cf, fl$sigma_hliml_cf)
  expect_identical(fs$hliml_Q_cf, fl$hliml_Q_cf)

  # seed 91004 -> strict falls to Step 2 (interior sigma_w, omega_w), adjust 1
  mom2 <- .cfa_cell(2, 0.01, 10L, 15L, seed = 91004L)
  gl <- estimate_cell_liml(mom2, ref_exporter = NULL, hliml_method = "closed")
  gs <- estimate_cell_liml(mom2, ref_exporter = NULL, hliml_method = "closed",
                           cf_admissibility = "strict")
  expect_identical(gl$final_source, "hliml"); expect_true(gl$omega_floored)
  expect_identical(gs$final_source, "step2_weighted"); expect_identical(gs$adjust, 1L)
  expect_equal(gs$sigma, gs$sigma_step2); expect_equal(gs$omega, gs$omega_step2)
  expect_gt(gs$omega, 1e-4)                         # not floored
  expect_identical(gs$hliml_status, "cf_inadmissible")
})

test_that("bfgs mode ignores the rule; an ordinary interior cell is unaffected by strict", {
  .cfa_source(environment())
  mom <- .cfa_cell(3, 1, 20L, 40L, seed = 20260819L)   # the closed-form lock cell
  fl <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "closed")
  fs <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "closed",
                           cf_admissibility = "strict")
  expect_identical(fl$hliml_cf_inversion, "ok")
  fl$hliml_cf_admissibility <- NULL; fs$hliml_cf_admissibility <- NULL
  expect_identical(fl, fs)
  bl <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "bfgs")
  bs <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "bfgs",
                           cf_admissibility = "strict")
  bl$hliml_cf_admissibility <- NULL; bs$hliml_cf_admissibility <- NULL
  expect_identical(bl, bs)
})

test_that("run_stage1_liml() carries hliml_cf_admissibility on every Step-3 row", {
  suppressPackageStartupMessages(library(data.table))
  .cfa_source(environment())
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "stage1_liml_wrapper.R"), local = TRUE)
  set.seed(1L)
  # two tiny synthetic cells in the raw (importer, exporter, good, t, value,
  # quantity) layout the wrapper expects; the first will be thin (non-ok)
  raw <- data.table::rbindlist(list(
    data.table::data.table(importer = 1L, good = "0101",
      exporter = rep(1:2, each = 3L), t = rep(1995:1997, 2L),
      value = runif(6, 1, 2), quantity = runif(6, 1, 2)),
    data.table::data.table(importer = 1L, good = "0202",
      exporter = rep(1:6, each = 12L), t = rep(1995:2006, 6L),
      value = exp(rnorm(72)), quantity = exp(rnorm(72)))))
  tmp <- tempfile(fileext = ".rds")
  out <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                         min_periods = 3L, verbose = FALSE,
                         cf_admissibility = "strict")
  expect_true("hliml_cf_admissibility" %in% names(out))
  # pre-Step-3 rows (thin panels) carry NA here exactly as they do for
  # hliml_method; every row that reached the estimator carries the rule.
  reached <- !is.na(out$hliml_method)
  expect_true(any(reached))
  expect_true(all(out$hliml_cf_admissibility[reached] == "strict"))
  expect_true(all(is.na(out$hliml_cf_admissibility[!reached])))
  out2 <- run_stage1_liml(raw, output_path = tmp, n_cores = 1L, min_exporters = 2L,
                          min_periods = 3L, verbose = FALSE)
  expect_true(all(out2$hliml_cf_admissibility[!is.na(out2$hliml_method)] == "legacy"))
  unlink(tmp)
})

test_that("--stage1-cf-admissibility parses, defaults to legacy, and rejects unknown values", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "parse_cli.R"), local = TRUE)
  source(file.path(root, "R", "build_config.R"), local = TRUE)
  source(file.path(root, "R", "validate_config.R"), local = TRUE)
  dd <- tempfile(); dir.create(dd)
  o0 <- parse_cli(c("--data", dd))
  expect_identical(o0$stage1_cf_admissibility, "legacy")
  expect_identical(build_config(o0)$stage1_cf_admissibility, "legacy")
  o1 <- parse_cli(c("--data", dd, "--stage1-cf-admissibility", "strict"))
  expect_identical(o1$stage1_cf_admissibility, "strict")
  expect_identical(build_config(o1)$stage1_cf_admissibility, "strict")
  expect_error(parse_cli(c("--data", dd, "--stage1-cf-admissibility", "lenient")),
               "stage1-cf-admissibility")
  cfg <- build_config(o1); cfg$stage1_cf_admissibility <- "lenient"
  expect_error(validate_config(cfg), "stage1_cf_admissibility")
  unlink(dd, recursive = TRUE)
})
