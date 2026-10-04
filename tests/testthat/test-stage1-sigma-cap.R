# ============================================================================
# test-stage1-sigma-cap.R  (patch 0084, 2026-10-03)
#
# --stage1-sigma-cap threads estimate_cell_liml()'s sigma_start_cap -- the one
# number behind the closed-form HLIML admissibility, the sigma edge of the
# boundary box and the Step-2 clamp -- through run_stage1_liml(). Locks:
#   1. plumbing: CLI defaults (cap 10, capped-omega keep, fallback pin NA) and
#      rejections; build_config; validate_config; run_stage1_liml() carries
#      sigma_cap = 10 so an absent argument is the <= v0.8.3 rule;
#   2. a synthetic Feenstra panel with true sigma = 20 is published AT the cap
#      under cap 10 (sigma_capped) and as an interior estimate near 20 under
#      cap 50;
#   3. a panel with true sigma = 3 is bit-identical under cap 10 and cap 50:
#      the cap only touches cells it binds on.
# ============================================================================

.sc_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
# Feenstra DGP in differences (the generator of test-bootstrap-branch-tag.R):
# demand d ln s = -(sigma-1) d ln p + eps, supply d ln p = omega/(1+omega) d ln s + u,
# solved for the reduced form; exporter-specific shock scales for heteroskedasticity.
.sc_panel <- function(sigma_true, omega_true, J = 14L, T = 24L, seed = 1L,
                      sd_eps = 1.0, sd_u = 1.0, sd_meas = 0.2) {
  set.seed(seed)
  denom <- 1 + omega_true * sigma_true
  a_eps_s <- (1 + omega_true) / denom; a_u_s <- -(sigma_true - 1) / denom
  a_eps_p <- omega_true / denom;       a_u_p <- 1 / denom
  sd_eps_j <- runif(J, 0.5, 2.0) * sd_eps; sd_u_j <- runif(J, 0.5, 2.0) * sd_u
  rows <- vector("list", J)
  for (j in seq_len(J)) {
    d_eps <- rnorm(T, sd = sd_eps_j[j]); d_u <- rnorm(T, sd = sd_u_j[j])
    d_ln_s <- a_eps_s * d_eps + a_u_s * d_u
    d_ln_p <- a_eps_p * d_eps + a_u_p * d_u + rnorm(T, sd = sd_meas)
    ln_p <- cumsum(c(0, d_ln_p))[-1]; ln_v <- 10 + cumsum(c(0, d_ln_s))[-1]
    rows[[j]] <- data.frame(exporter = j, t = 1995L + seq_len(T) - 1L,
                            value = exp(ln_v), quantity = exp(ln_v - ln_p))
  }
  do.call(rbind, rows)
}
.sc_fit <- function(pan, cap) {
  prep <- prepare_cell_moments(pan, min_year = 1995L)
  estimate_cell_liml(prep$moments, ref_exporter = prep$ref_exporter, sigma_start_cap = cap)
}

test_that("CLI, build_config, validate_config and the wrapper carry the sigma-cap family", {
  .sc_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_sc_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  o <- parse_cli(base)
  expect_equal(o$stage1_sigma_cap, 50); expect_identical(o$stage1_capped_omega, "drop"); expect_true(is.na(o$stage2_sigma_fallback_pin))   # patch 0086 defaults
  o2 <- parse_cli(c(base, "--stage1-sigma-cap", "50", "--stage1-capped-omega", "drop", "--stage2-sigma-fallback-pin", "2.4618"))
  expect_equal(o2$stage1_sigma_cap, 50); expect_identical(o2$stage1_capped_omega, "drop"); expect_equal(o2$stage2_sigma_fallback_pin, 2.4618)
  cfg2 <- build_config(o2)
  expect_equal(cfg2$stage1_sigma_cap, 50); expect_identical(cfg2$stage1_capped_omega, "drop"); expect_equal(cfg2$stage2_sigma_fallback_pin, 2.4618)
  expect_error(parse_cli(c(base, "--stage1-sigma-cap", "1")), "stage1-sigma-cap")
  expect_error(parse_cli(c(base, "--stage1-capped-omega", "maybe")), "stage1-capped-omega")
  expect_error(parse_cli(c(base, "--stage2-sigma-fallback-pin", "0.5")), "stage2-sigma-fallback-pin")
  cfg <- make_synthetic_cfg()
  expect_silent(validate_config(cfg))
  bad <- cfg; bad$stage1_sigma_cap <- 1; expect_error(validate_config(bad), "stage1_sigma_cap")
  bad <- cfg; bad$stage1_capped_omega <- "maybe"; expect_error(validate_config(bad), "stage1_capped_omega")
  bad <- cfg; bad$stage2_sigma_fallback_pin <- 0.5; expect_error(validate_config(bad), "stage2_sigma_fallback_pin")
  expect_equal(formals(run_stage1_liml)$sigma_cap, 10)                 # the LIBRARY default stays 10; the CLI/config default is 50 (patch 0086)
  expect_equal(formals(estimate_cell_liml)$sigma_start_cap, 10)
})

test_that("a sigma = 20 cell is published at the cap under 10 and as an interior estimate under 50", {
  .sc_setup()
  pan <- .sc_panel(20, 0.5, J = 30L, T = 24L, seed = 20261003L, sd_meas = 0.01)
  f10 <- .sc_fit(pan, 10); f50 <- .sc_fit(pan, 50)
  expect_identical(f10$status, "ok"); expect_identical(f50$status, "ok")
  expect_equal(f10$sigma, 10)
  expect_true(isTRUE(f10$sigma_capped))
  expect_true(f10$adjust %in% c(4L, 7L))
  expect_false(isTRUE(f50$sigma_capped))
  expect_true(f50$sigma > 10 && f50$sigma < 50)
  expect_true(f50$adjust %in% c(0L, 1L))
  expect_equal(f50$sigma, 20, tolerance = 0.35)                         # recovers the truth within the DGP's noise
  expect_true(is.finite(f50$sigma_se))                                  # a capped sigma carries no SE; an estimate does
})

test_that("a sigma = 3 cell is bit-identical under cap 10 and cap 50 (point, route, SEs)", {
  .sc_setup()
  pan <- .sc_panel(3, 1, seed = 20261004L)
  f10 <- .sc_fit(pan, 10); f50 <- .sc_fit(pan, 50)
  expect_identical(f10$status, "ok")
  expect_false(isTRUE(f10$sigma_capped))
  # the boundary-search DIAGNOSTICS (sigma_hliml_bd, hliml_Q_bd) see the box's
  # sigma edge move; everything published for a cell the cap does not bind on
  # -- point, route, SEs, diagnostics of the chosen route -- is identical
  bd_diag <- c("sigma_hliml_bd", "hliml_Q_bd")
  expect_identical(f10[setdiff(names(f10), bd_diag)], f50[setdiff(names(f50), bd_diag)])
  for (fld in c("sigma", "omega", "rho", "adjust", "final_source", "sigma_se", "omega_se")) expect_identical(f10[[fld]], f50[[fld]], info = fld)
})
