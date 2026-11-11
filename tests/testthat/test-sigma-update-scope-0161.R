# ============================================================================
# test-sigma-update-scope-0161.R
#
# (patch 0161) --stage2-sigma-update-scope 2a2b: between the profile and the
# final Stage-2b pass, Stage 2a is re-estimated at the region medians of the
# updated sigma and the good-level priors and regional gamma_V medians are
# rebuilt from it. Checks: the CLI accepts both scopes and rejects others;
# under 2a2b the run logs the re-run, saves it beside the Stage-1-sigma Stage 2a
# (whose table is bit-identical to a 2b-scope run's and whose records rotate
# to _pass1), and the pass log records the scope and the prior medians.
# ============================================================================

.ss61_root <- function() dirname(locate_source_dir())
.ss61_run <- function(args, wd) {
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(wd); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, args, stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

test_that("the scope flag accepts 2b and 2a2b and rejects others", {
  src_dir <- locate_source_dir(); source(file.path(src_dir, "parse_cli.R"), local = TRUE)
  td <- tempfile("te_s61_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  base <- c("--data", td, "--out-dir", td)
  expect_equal(parse_cli(args = base)$stage2_sigma_update_scope, "2a2b")   # the default since patch 0167
  expect_equal(parse_cli(args = c(base, "--stage2-sigma-update-scope", "2b"))$stage2_sigma_update_scope, "2b")
  expect_equal(parse_cli(args = c(base, "--stage2-sigma-update-scope", "2a2b"))$stage2_sigma_update_scope, "2a2b")
  expect_error(parse_cli(args = c(base, "--stage2-sigma-update-scope", "2a")), "must be '2b' or '2a2b'")
})

test_that("under 2a2b Stage 2a is re-estimated at the updated sigma and the priors rebuilt; the Stage-1-sigma Stage 2a is kept", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "Rcpp")) skip_if_not_installed(p)
  root <- .ss61_root()
  td <- normalizePath(tempfile("te_s61e_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  sb$make_synthetic_baci_dir(baci, n_goods = 3L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L), years = 1995:2014, seed = 20261015L)
  runner <- shQuote(file.path(root, "scripts", "run_estimation.R"))
  o2b <- file.path(td, "s2b"); dir.create(o2b)
  r0 <- .ss61_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(o2b), "--ncores", "1", "--stage2-sigma-update-scope", "2b"), wd = td)   # 2a2b is the default since patch 0167
  expect_equal(r0$status, 0L, info = paste(utils::tail(r0$out, 20), collapse = "\n"))
  oq <- file.path(td, "s2a2b"); dir.create(oq)
  r1 <- .ss61_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(oq), "--ncores", "1", "--stage2-sigma-update-scope", "2a2b"), wd = td)
  expect_equal(r1$status, 0L, info = paste(utils::tail(r1$out, 20), collapse = "\n"))
  log <- paste(r1$out, collapse = "\n")
  expect_match(log, "scope: 2a2b", fixed = TRUE)
  expect_match(log, "scope 2a2b: Stage 2a re-estimated at the updated sigma", fixed = TRUE)
  reg <- "baci_hs92_v202601_elast_regional_hs4"
  # the Stage-1-sigma Stage 2a is the same table under both scopes; the re-run sits beside it; its records rotated
  a <- readRDS(file.path(o2b, paste0(reg, "_fixed_sigma.rds"))); b <- readRDS(file.path(oq, paste0(reg, "_fixed_sigma.rds")))
  data.table::setDT(a); data.table::setDT(b)
  expect_equal(nrow(a), nrow(b)); expect_equal(a$gamma, b$gamma, tolerance = 1e-12); expect_equal(a$sigma, b$sigma, tolerance = 1e-12)
  expect_true(file.exists(file.path(oq, paste0(reg, "_fixed_sigma_sigmaupd1.rds"))))
  ru <- readRDS(file.path(oq, paste0(reg, "_fixed_sigma_sigmaupd1.rds"))); data.table::setDT(ru)
  expect_gt(nrow(ru), 0L); expect_true(all(c("gamma", "sigma", "tier") %in% names(ru)))
  expect_true(file.exists(file.path(oq, paste0(reg, "_stage2_trimmed_pass1.csv"))) || !file.exists(file.path(o2b, paste0(reg, "_stage2_trimmed.csv"))))
  # the pass log carries the scope and the prior medians
  passes <- data.table::fread(file.path(oq, "baci_hs92_v202601_elast_country_hs4_sigma_update_passes.csv"))
  expect_equal(passes$scope, "2a2b"); expect_true(is.finite(passes$prior_median_before) && is.finite(passes$prior_median_after)); expect_gt(passes$stage2a_rows, 0L)
  p2b <- data.table::fread(file.path(o2b, "baci_hs92_v202601_elast_country_hs4_sigma_update_passes.csv"))
  expect_equal(p2b$scope, "2b"); expect_true(is.na(p2b$prior_median_after))
  # the final tables agree on their keys and the sigma column (the update is the same; only the priors differ)
  t2b <- readRDS(file.path(o2b, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")); tq <- readRDS(file.path(oq, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds"))
  data.table::setDT(t2b); data.table::setDT(tq)
  k <- c("importer", "exporter", "good"); m <- merge(t2b[, c(k, "sigma"), with = FALSE], tq[, c(k, "sigma"), with = FALSE], by = k)
  expect_equal(nrow(m), nrow(t2b)); expect_equal(m$sigma.x, m$sigma.y, tolerance = 1e-10)
})
