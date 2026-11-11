# ============================================================================
# test-defaults-0167.R  (patch 0167, fresh-eyes audit #11: the configuration
# the next re-estimation ships, decided by the measurements of 2026-11-11)
#
#   1. the CLI: closed-form profile, one gamma_V refresh and the 2a2b scope by
#      default; the sigma tail of the trim 'auto'; unprofiled cells with a
#      Stage-1 sigma at the level; --stage2b-resume-from validated;
#   2. check_resume_table(): a table from this run's panel and Stage 1 passes,
#      one from another panel or Stage 1 stops with a reason;
#   3. a run under the defaults: no sigma_lo row once sigma is the shrunk
#      update, no row left at a Stage-1 sigma, the refresh logged and
#      gamma_v_resid taken from it, the rules in the pass log; and a run
#      resumed from its gamma_V-final table reproduces it exactly;
#   4. scripts/refresh_table_censuses.R --re-estimated reports a moved census
#      instead of stopping, and sourcing the script runs nothing.
# ============================================================================

.d67_root <- function() dirname(locate_source_dir())
.d67_run <- function(args, wd) {
  owd <- setwd(wd); on.exit(setwd(owd), add = TRUE)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), args, stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = out)
}

test_that("CLI: the new defaults, and the three new options validated", {
  src_dir <- locate_source_dir(); source(file.path(src_dir, "parse_cli.R"), local = TRUE)
  td <- tempfile("te_d67c_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  base <- c("--data", td, "--out-dir", td)
  o <- parse_cli(args = base)
  expect_identical(o$stage2_sigma_profile, "closed"); expect_identical(o$stage2_gamma_v_refresh, 1L)
  expect_identical(o$stage2_sigma_update_scope, "2a2b"); expect_identical(o$stage2_trim_sigma_tail, "auto")
  expect_identical(o$stage2_sigma_update_unprofiled, "level"); expect_null(o$stage2b_resume_from)
  expect_error(parse_cli(args = c(base, "--stage2-trim-sigma-tail", "low")), "must be 'auto', 'on' or 'off'")
  expect_error(parse_cli(args = c(base, "--stage2-sigma-update-unprofiled", "keep")), "must be 'level' or 'stage1'")
  expect_error(parse_cli(args = c(base, "--stage2b-resume-from", file.path(td, "nope.rds"))), "file not found")
  f <- file.path(td, "p3.rds"); saveRDS(data.frame(x = 1), f)
  expect_error(parse_cli(args = c(base, "--stage2-sigma-update", "off", "--stage2b-resume-from", f)), "needs --stage2-sigma-update import")
  expect_identical(parse_cli(args = c(base, "--stage2b-resume-from", f))$stage2b_resume_from, f)
})

test_that("check_resume_table: this run's table passes; another panel's or another Stage 1's stops", {
  e <- new.env(); for (f in c("R/utils_general.R", "R/iteration_helpers.R")) sys.source(file.path(.d67_root(), f), envir = e)
  suppressPackageStartupMessages(library(data.table))
  panel <- data.table(importer = rep(c(1L, 2L, 3L), each = 4), good = "0101", exporter = 11:14)
  tab <- data.table(importer = rep(c("1", "2"), each = 2), exporter = c("11", "12", "11", "12"), good = "0101",
                    gamma = c(0.5, 0.7, 0.6, 0.8), sigma = c(2.5, 2.5, 3.1, 3.1), tier = c(0L, 1L, 0L, 1L), convergence = 0L)
  cfg <- list(sigma_lookup = data.table(importer = c("1", "2"), good = "0101", sigma = c(2.5, 3.1)))
  r <- e$check_resume_table(tab, panel, cfg)
  expect_identical(r$cells, 2L); expect_equal(r$cover, 2 / 3); expect_identical(r$sigma_checked, 4L)
  bad_cell <- rbind(tab, data.table(importer = "9", exporter = "11", good = "0101", gamma = 1, sigma = 2, tier = 0L, convergence = 0L))
  expect_error(e$check_resume_table(bad_cell, panel, cfg), "not in this run's panel")
  bad_sig <- copy(tab)[importer == "2", sigma := 2.9]
  expect_error(e$check_resume_table(bad_sig, panel, cfg), "Stage 1 does not give their cell")
  expect_error(e$check_resume_table(tab[, !"tier"], panel, cfg), "lacks column")
})

test_that("a run under the defaults has no sigma tail, no Stage-1 sigma left, the refresh logged; resuming reproduces it", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "Rcpp")) skip_if_not_installed(p)
  root <- .d67_root()
  td <- normalizePath(tempfile("te_d67e_"), winslash = "/", mustWork = FALSE); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  sb$make_synthetic_baci_dir(baci, n_goods = 3L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L), years = 1995:2014, seed = 20261015L)
  runner <- shQuote(file.path(root, "scripts", "run_estimation.R"))
  oa <- file.path(td, "full"); dir.create(oa)
  r1 <- .d67_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(oa), "--ncores", "1"), wd = td)
  expect_equal(r1$status, 0L, info = paste(utils::tail(r1$out, 25), collapse = "\n"))
  log1 <- paste(r1$out, collapse = "\n")
  expect_match(log1, "Stage-2 sigma profile: closed | gamma_V refresh passes: 1", fixed = TRUE)
  expect_match(log1, "update pass: exporter gamma_V lookup rebuilt from the gamma_V-final table", fixed = TRUE)
  expect_match(log1, "sigma bounds over none: no sigma tail (patch 0167)", fixed = TRUE)
  expect_match(log1, "gamma_v_resid (refresh 1 vs the table before it)", fixed = TRUE)
  pre <- file.path(oa, "baci_hs92_v202601_elast_country_hs4")
  s2b <- data.table::as.data.table(readRDS(paste0(pre, "_fixed_sigma.rds")))
  expect_false(any(s2b$trim_reason %in% "sigma_lo"))                         # no sigma tail on the shrunk sigma
  expect_false(any(s2b$sigma_source %in% "estimated"))                       # no cell left at its Stage-1 sigma
  expect_true(all(s2b$sigma_source %in% c("updated_import_shrunk", "updated_level") | grepl("^fallback_", s2b$sigma_source)))
  ulog <- data.table::fread(paste0(pre, "_sigma_update_passes.csv"))
  expect_identical(as.character(ulog$unprofiled[1L]), "level"); expect_false(as.logical(ulog$trim_sigma_tail[1L]))
  expect_identical(as.character(ulog$scope[1L]), "2a2b")
  rf <- data.table::fread(paste0(pre, "_gamma_v_refresh.csv")); expect_identical(nrow(rf), 1L)
  pre_ref <- data.table::as.data.table(readRDS(paste0(pre, "_fixed_sigma_prerefresh1.rds")))
  k <- function(d) paste(d$importer, d$exporter, d$good)
  mm <- match(k(s2b), k(pre_ref)); okr <- !is.na(s2b$gamma_v_resid)
  expect_gt(sum(okr), 0L)
  expect_equal(s2b$gamma_v_resid[okr], abs(log(s2b$gamma[okr]) - log(pre_ref$gamma[mm[okr]])), tolerance = 1e-10)
  # resumed from the gamma_V-final table, with this run's Stage 1, Stage 2a and raw cache: the same table
  ob <- file.path(td, "resumed"); dir.create(ob)
  for (f in c("_feenstra_sigma.rds", "_raw_cache.rds")) file.copy(paste0(pre, f), ob)
  file.copy(file.path(oa, "baci_hs92_v202601_elast_regional_hs4_fixed_sigma.rds"), ob)
  r2 <- .d67_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(ob), "--ncores", "1",
                   "--stage2b-resume-from", shQuote(paste0(pre, "_fixed_sigma_pass3.rds"))), wd = td)
  expect_equal(r2$status, 0L, info = paste(utils::tail(r2$out, 25), collapse = "\n"))
  expect_match(paste(r2$out, collapse = "\n"), "Stage 2b resumed from", fixed = TRUE)
  s2b_r <- data.table::as.data.table(readRDS(file.path(ob, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")))
  data.table::setorderv(s2b, c("importer", "good", "exporter")); data.table::setorderv(s2b_r, c("importer", "good", "exporter"))
  cols <- c("importer", "exporter", "good", "sigma", "gamma", "tier", "convergence", "opt_tariff", "trim_reason", "sigma_source", "gamma_v_resid")
  expect_true(isTRUE(all.equal(s2b[, ..cols], s2b_r[, ..cols], check.attributes = FALSE)))
})

test_that("refresh_table_censuses.R --re-estimated: a moved census is reported, not a stop; sourcing runs nothing", {
  src <- readLines(file.path(.d67_root(), "scripts", "refresh_table_censuses.R"), warn = FALSE)
  i0 <- grep("# --- refresh helpers (patch 0144)", src, fixed = TRUE); i1 <- grep("# --- end refresh helpers (patch 0144)", src, fixed = TRUE)
  env <- new.env(parent = globalenv()); eval(parse(text = src[i0:i1]), envir = env)
  expect_true(env$parse_refresh_args(c("--re-estimated"))$re_estimated)
  expect_false(env$parse_refresh_args(character(0))$re_estimated)
  td <- tempfile("te_d67r_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  a <- file.path(td, "a.json"); b <- file.path(td, "b.json")
  jsonlite::write_json(list(x = 1, meta = list(timestamp = "t0")), a, auto_unbox = TRUE)
  jsonlite::write_json(list(x = 2, meta = list(timestamp = "t1")), b, auto_unbox = TRUE)
  expect_true(env$compare_census(b, a, "same")$moved)
  expect_false(env$compare_census(b, a, "changed")$moved)
  expect_true(any(grepl("if (sys.nframe() == 0L) main()", src, fixed = TRUE)))
  expect_true(any(grepl('plan <- lapply(plan, function(p) { p$expect <- "changed"; p })', src, fixed = TRUE)))
})
