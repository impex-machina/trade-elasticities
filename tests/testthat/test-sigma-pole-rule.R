# ============================================================================
# test-sigma-pole-rule.R  (patch 0099, 2026-10-11)
#
# --stage2-sigma-pole-rule {none|fallback} with --stage2-sigma-pole-se C:
# a Stage-1 cell with sigma - 1 < C * sigma_se leaves the clean set under
# 'fallback', mirroring the v0.9.0 cap-edge rule; 'none' is the identity.
# Locks: the identity; the exact drop set at C = 1 and C = 0.5; cells with
# no finite SE are kept; invalid C refused; CLI / config / validation and
# the unchanged defaults.
# ============================================================================

.sp_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}

test_that("apply_sigma_pole_rule(): identity under none; exact drop set under fallback; NA SE kept", {
  .sp_setup()
  s <- data.table(importer = 1:6, good = "0101", sigma = c(1.04, 1.30, 2.00, 1.10, 3.00, 1.02),
                  sigma_se = c(0.10, 0.20, 0.30, NA_real_, 0.50, 0.01), sigma_capped = FALSE, gamma = 0.5)
  n <- apply_sigma_pole_rule(copy(s), "none", 1)
  expect_equal(attr(n, "n_pole_dropped"), 0L); data.table::setattr(n, "n_pole_dropped", NULL)
  expect_identical(as.data.frame(n), as.data.frame(s))
  # at c = 1: 1.04 (0.04 < 0.10) dropped; 1.30 (0.30 < 0.20? no), 1.02 (0.02 < 0.01? no) kept; NA SE kept
  f1 <- apply_sigma_pole_rule(copy(s), "fallback", 1)
  expect_equal(sort(f1$importer), c(2L, 3L, 4L, 5L, 6L)); expect_equal(attr(f1, "n_pole_dropped"), 1L)
  # at c = 0.5: 1.04 (0.04 < 0.05) still dropped, nothing else
  f05 <- apply_sigma_pole_rule(copy(s), "fallback", 0.5)
  expect_equal(sort(f05$importer), c(2L, 3L, 4L, 5L, 6L)); expect_equal(attr(f05, "n_pole_dropped"), 1L)
  # at c = 3: 1.04, 1.30 (0.30 < 0.60) and 1.02 (0.02 < 0.03) dropped; 2.00 (1.00 < 0.90? no) and 3.00 kept
  f3 <- apply_sigma_pole_rule(copy(s), "fallback", 3)
  expect_equal(sort(f3$importer), c(3L, 4L, 5L)); expect_equal(attr(f3, "n_pole_dropped"), 3L)
  expect_error(apply_sigma_pole_rule(copy(s), "fallback", 0), "positive")
  expect_error(apply_sigma_pole_rule(copy(s), "edge", 1))
  no_se <- apply_sigma_pole_rule(copy(s)[, sigma_se := NULL], "fallback", 1)
  expect_equal(attr(no_se, "n_pole_dropped"), 0L); expect_equal(nrow(no_se), nrow(s))
})

test_that("CLI, config and validation accept the pole-rule flags and keep the defaults", {
  .sp_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_sp_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  cfg <- build_config(parse_cli(base)); expect_identical(cfg$stage2_sigma_pole_rule, "fallback"); expect_equal(cfg$stage2_sigma_pole_se, 1); expect_silent(validate_config(cfg))   # patch 0101 default
  r <- build_config(parse_cli(c(base, "--stage2-sigma-pole-rule", "none"))); expect_identical(r$stage2_sigma_pole_rule, "none")   # the v0.9.1 reproducer
  e <- build_config(parse_cli(c(base, "--stage2-sigma-pole-rule", "fallback", "--stage2-sigma-pole-se", "0.5")))
  expect_identical(e$stage2_sigma_pole_rule, "fallback"); expect_equal(e$stage2_sigma_pole_se, 0.5); expect_silent(validate_config(e))
  expect_error(parse_cli(c(base, "--stage2-sigma-pole-rule", "drop")), "sigma-pole-rule")
  expect_error(parse_cli(c(base, "--stage2-sigma-pole-se", "-1")), "sigma-pole-se")
  bad <- cfg; bad$stage2_sigma_pole_rule <- "drop"; expect_error(validate_config(bad), "stage2_sigma_pole_rule")
  bad2 <- cfg; bad2$stage2_sigma_pole_se <- 0; expect_error(validate_config(bad2), "stage2_sigma_pole_se")
})
