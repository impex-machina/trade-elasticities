# ============================================================================
# test-sigma-shrink-0154.R
#
# (patch 0154) --stage2-sigma-shrink B: the updated sigma shrunk toward the
# full-panel level by Spearman-Brown's b_full = 2B / (1 + B) before the final
# Stage-2b run; cells with no updated sigma take the level, which is also the
# fallback. Checks the published sigma against the formula, cell by cell, the
# labels, the sigma_update / sigma_stage1 columns, the log fields, and the
# CLI guards.
# ============================================================================

.ss_root <- function() dirname(locate_source_dir())
.ss_run <- function(args, wd) {
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(wd); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, args, stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

test_that("--stage2-sigma-shrink is validated: [0, 1), 0 = off, ignored when the update is off; the defaults are import / 0.146 (patch 0155)", {
  src_dir <- locate_source_dir()
  source(file.path(src_dir, "parse_cli.R"), local = TRUE)
  td <- tempfile("te_ss_cli_"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  base <- c("--data", td, "--out-dir", td)
  expect_error(parse_cli(args = c(base, "--stage2-sigma-update", "import", "--stage2-sigma-shrink", "1.5")), "must be in \\[0, 1\\)")
  expect_error(parse_cli(args = c(base, "--stage2-sigma-shrink", "-0.1")), "must be in \\[0, 1\\)")
  o <- parse_cli(args = c(base, "--stage2-sigma-update", "import", "--stage2-sigma-shrink", "0.146"))
  expect_equal(o$stage2_sigma_shrink_b, 0.146); expect_equal(o$stage2_sigma_update_mode, "import")
  o0 <- parse_cli(args = base)                      # the defaults since patch 0155
  expect_equal(o0$stage2_sigma_update_mode, "import"); expect_equal(o0$stage2_sigma_shrink_b, 0.146); expect_equal(o0$stage2_sigma_update_passes, 1L)
  ooff <- parse_cli(args = c(base, "--stage2-sigma-update", "off"))   # the shrink is ignored, not an error
  expect_equal(ooff$stage2_sigma_update_mode, "off")
  oz <- parse_cli(args = c(base, "--stage2-sigma-shrink", "0")); expect_equal(oz$stage2_sigma_shrink_b, 0)
})

test_that("the runner under --stage2-sigma-update import --stage2-sigma-shrink publishes the shrunk sigma, the level and the record", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "Rcpp")) skip_if_not_installed(p)
  root <- .ss_root()
  td <- normalizePath(tempfile("te_ss_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  sb$make_synthetic_baci_dir(baci, n_goods = 3L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L),
                             years = 1995:2014, seed = 20261015L)
  out <- file.path(td, "out"); dir.create(out)
  B <- 0.146
  # no flags: the defaults since patch 0155 are the update with B = 0.146
  r <- .ss_run(c(shQuote(file.path(root, "scripts", "run_estimation.R")), "--data", shQuote(baci), "--out-dir", shQuote(out), "--ncores", "1"), wd = td)
  expect_equal(r$status, 0L, info = paste(utils::tail(r$out, 30), collapse = "\n"))
  log <- paste(r$out, collapse = "\n")
  expect_match(log, "Stage-2 sigma update: import (passes: 1, scope: 2b", fixed = TRUE)
  expect_match(log, "shrink: B = 0.146 (half-window), b_full = 0.255", fixed = TRUE)
  expect_match(log, "sigma profile: ", fixed = TRUE)
  expect_match(log, "fallback and sigma_V default = level", fixed = TRUE)
  expect_match(log, "updated_import_shrunk", fixed = TRUE)

  pre <- file.path(out, "baci_hs92_v202601_elast_country_hs4")
  t1 <- readRDS(paste0(pre, "_fixed_sigma.rds")); data.table::setDT(t1)
  p3 <- readRDS(paste0(pre, "_fixed_sigma_pass3.rds")); data.table::setDT(p3)
  passes <- data.table::fread(paste0(pre, "_sigma_update_passes.csv"))
  prof <- data.table::fread(paste0(pre, "_sigma_update_pass1.csv"), colClasses = list(character = c("importer", "good")))
  b_full <- 2 * B / (1 + B)
  expect_equal(passes$shrink_b_half, B); expect_equal(passes$shrink_b_full, b_full, tolerance = 1e-12)
  expect_true(all(c("sigma_source", "sigma_source_stage1", "sigma_update", "sigma_stage1") %in% names(t1)))
  expect_true(all(t1$sigma_source %in% c("estimated", "fallback_no_estimate", "fallback_sigma_edge", "fallback_sigma_pole", "updated_import_shrunk", "updated_level")))

  # the level: the median of ln(sigma_update - 1) over the updated cells, from the profile record
  ok <- prof[status == "ok"]
  L <- median(log(ok$sigma - 1)); level_sigma <- 1 + exp(L)
  expect_equal(passes$level_sigma, level_sigma, tolerance = 1e-10)
  expect_equal(prof[status == "ok", sigma_shrunk], 1 + exp(L + b_full * (log(ok$sigma - 1) - L)), tolerance = 1e-10)

  # published sigma on shrunk rows == the formula applied to the published sigma_update, cell by cell
  sh <- unique(t1[sigma_source == "updated_import_shrunk", .(importer = as.character(importer), good = as.character(good), sigma, sigma_update)])
  expect_gt(nrow(sh), 0L)
  expect_true(all(is.finite(sh$sigma_update)))
  expect_equal(sh$sigma, 1 + exp(L + b_full * (log(sh$sigma_update - 1) - L)), tolerance = 1e-10)
  # the unshrunk profile is what sigma_update carries
  m <- merge(sh, ok[, .(importer, good, sigma_prof = sigma)], by = c("importer", "good"))
  expect_equal(nrow(m), nrow(sh)); expect_equal(m$sigma_update, m$sigma_prof, tolerance = 1e-12)
  # cells with no updated sigma (profile not ok) and fallback cells sit at the level
  lv <- t1[sigma_source == "updated_level"]
  if (nrow(lv)) expect_equal(unique(lv$sigma), level_sigma, tolerance = 1e-10)
  fb <- t1[startsWith(sigma_source, "fallback_")]
  if (nrow(fb)) expect_equal(unique(fb$sigma), level_sigma, tolerance = 1e-10)
  # sigma_stage1 is the sigma the cell had before the update (the gamma_V final table)
  s1 <- merge(unique(t1[, .(importer = as.character(importer), good = as.character(good), sigma_stage1)]),
              unique(p3[, .(importer = as.character(importer), good = as.character(good), s_p3 = sigma)]), by = c("importer", "good"))
  s1 <- s1[!is.na(sigma_stage1)]
  expect_gt(nrow(s1), 0L); expect_equal(s1$sigma_stage1, s1$s_p3, tolerance = 1e-12)
  # no Stage-1-style SE on shrunk rows
  expect_true(all(is.na(t1[sigma_source == "updated_import_shrunk", sigma_se])))
  expect_true(all(t1[sigma_source == "updated_import_shrunk", sigma_robust] %in% FALSE))
})
