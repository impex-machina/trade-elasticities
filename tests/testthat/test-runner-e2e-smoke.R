# ============================================================================
# test-runner-e2e-smoke.R  (patch 0121, fresh-eyes audit #8)
#
# Until this file, no test EXECUTED scripts/run_estimation.R, analysis/00_setup.R
# or scripts/build_readme.R end to end on pipeline output: the runner tests read
# its text. The runner-level defects of the last releases were all found on the
# box or in the release train -- v0.11.0's sigma_source column lost to a
# data.table shallow copy (patch 0114), 00_setup.R's Pillar-3 line after its
# rm() (patch 0115) -- where each costs a session. This test runs the whole
# chain on a small synthetic BACI directory (validation/synthetic_baci.R:
# Soderbery's model with known parameters, BACI's own file layout):
#
#   1. scripts/run_estimation.R --stage all --ncores 1 under the production
#      defaults (Stage 1, Stage 2a, three Stage-2b gamma_V passes);
#   2. analysis/master.R on its outputs, in a scratch copy of the analysis
#      layer (it writes results/*.json and figures relative to its working
#      directory, so it must not run in the repo);
#   3. scripts/build_readme.R on the JSONs that run wrote.
#
# Assertions are structural (schema, labels, files, exit codes), not numeric,
# so platform differences in the optimizer cannot flake them. ~1-2 min on one
# core. Set TE_SKIP_E2E=1 to skip (e.g. while iterating on unrelated tests).
# ============================================================================

.e2e_root <- function() normalizePath(file.path(locate_source_dir(), ".."), winslash = "/")

.e2e_run <- function(args, wd = NULL, env = character()) {
  rs <- file.path(R.home("bin"), "Rscript")
  if (!is.null(wd)) { old <- setwd(wd); on.exit(setwd(old), add = TRUE) }
  if (length(env)) {
    nm <- sub("=.*$", "", env); val <- sub("^[^=]*=", "", env)
    prev <- Sys.getenv(nm, unset = NA)
    do.call(Sys.setenv, as.list(stats::setNames(val, nm)))
    on.exit(for (i in seq_along(nm)) if (is.na(prev[i])) Sys.unsetenv(nm[i]) else do.call(Sys.setenv, as.list(stats::setNames(prev[i], nm[i]))), add = TRUE)
  }
  out <- suppressWarnings(system2(rs, args, stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

test_that("runner -> analysis layer -> README build run end to end on synthetic BACI (production defaults)", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "ggplot2", "jsonlite", "glue", "openssl", "Rcpp")) skip_if_not_installed(p)
  root <- .e2e_root()
  td <- normalizePath(tempfile("te_e2e_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)

  # --- synthetic BACI directory with known parameters ------------------------
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  truth <- sb$make_synthetic_baci_dir(baci, n_goods = 3L,
                                      countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L),
                                      years = 1995:2014, seed = 20261015L)
  expect_equal(length(list.files(baci, pattern = "^BACI_HS92_Y\\d{4}_V202601\\.csv$")), 20L)
  expect_gt(nrow(truth$gamma), 50L)

  # --- 1. the runner, production defaults ------------------------------------
  out <- file.path(td, "out"); dir.create(out)
  run <- .e2e_run(c(shQuote(file.path(root, "scripts", "run_estimation.R")), "--data", shQuote(baci),
                    "--out-dir", shQuote(out), "--ncores", "1"), wd = td)
  expect_equal(run$status, 0L, info = paste(utils::tail(run$out, 40), collapse = "\n"))
  log <- paste(run$out, collapse = "\n")
  # the header echoes the shipped configuration (v0.11.0 defaults)
  expect_match(log, "Export moment:    value | Stage-2a handoff rows: published", fixed = TRUE)
  expect_match(log, "passes: 3", fixed = TRUE)
  expect_match(log, "sigma pole: fallback (c = 1 SE)", fixed = TRUE)
  expect_match(log, "THREE-STAGE ESTIMATION COMPLETE", fixed = TRUE)

  pre <- file.path(out, "baci_hs92_v202601_elast")
  f <- list(s1 = paste0(pre, "_country_hs4_feenstra_sigma.rds"), s1rich = paste0(pre, "_country_hs4_feenstra_sigma_liml.rds"),
            s2a = paste0(pre, "_regional_hs4_fixed_sigma.rds"), s2b = paste0(pre, "_country_hs4_fixed_sigma.rds"),
            s2b_sum = paste0(pre, "_country_hs4_summary.rds"), s2b_txt = paste0(pre, "_country_hs4_summary.txt"),
            passes = paste0(pre, "_country_hs4_gamma_v_passes.csv"))
  for (nm in names(f)) expect_true(file.exists(f[[nm]]), info = nm)
  expect_false(any(file.exists(paste0(pre, c("_country_hs4_fs_checkpoint.rds", "_regional_hs4_fs_checkpoint.rds")))))
  # patch 0111: no run record lands in the working directory
  expect_length(list.files(td, pattern = "^baci_.*_(stage2_|fs_checkpoint)"), 0L)
  expect_equal(nrow(data.table::fread(f$passes)), 2L)

  # (patch 0163) the summary's CONFIGURATION block reports what the final Stage-2b pass ran under -- the level
  # sigma as the sigma_V default, the median good-level prior as the gamma_V default and gamma start -- not
  # build_config()'s placeholders (sigma_V=2.880, gamma_V=0.690 in every summary through v0.12.0)
  stxt <- paste(readLines(f$s2b_txt, warn = FALSE), collapse = "\n")
  ulog <- data.table::fread(paste0(pre, "_country_hs4_sigma_update_passes.csv"))
  expect_false(grepl("sigma_V=2.880, gamma_V=0.690", stxt, fixed = TRUE))
  pmed <- if ("prior_median_after" %in% names(ulog) && is.finite(ulog$prior_median_after[1L])) ulog$prior_median_after[1L] else ulog$prior_median_before[1L]   # 2a2b (default since 0167): the rebuilt priors
  expect_match(stxt, sprintf("Structural defaults:  sigma_V=%.3f, gamma_V=%.3f", ulog$level_sigma[1L], pmed), fixed = TRUE)
  expect_match(stxt, sprintf("Starting value:       gamma=%.3f", pmed), fixed = TRUE)
  sprov <- readRDS(f$s2b_sum)$provenance
  expect_equal(sprov$sigma_V_default, ulog$level_sigma[1L], tolerance = 1e-9)
  expect_equal(sprov$gamma_V_default, pmed, tolerance = 1e-9)
  rtxt2 <- paste(readLines(paste0(pre, "_regional_hs4_summary.txt"), warn = FALSE), collapse = "\n")
  expect_match(rtxt2, "Structural defaults:  sigma_V=", fixed = TRUE)
  expect_false(grepl("not recorded", rtxt2, fixed = TRUE))          # Stage 2a was estimated in this run
  expect_false(grepl("sigma_V=2.880, gamma_V=0.690", rtxt2, fixed = TRUE))

  s2b <- data.table::as.data.table(readRDS(f$s2b))
  expect_setequal(names(s2b), c("importer", "exporter", "good", "sigma", "gamma", "gamma_se", "gamma_se_total",
                                "sigma_robust", "sigma_se", "dgamma_dsigma", "gamma_se_status", "gamma_exposure",
                                "gamma_shrink_wt", "ref_exporter", "opt_tariff", "opt_tariff_all", "convergence",
                                "obj_value", "tier", "avg_trade", "gamma_v_resid", "trim_reason", "sigma_source",
                                "sigma_source_stage1", "sigma_update", "sigma_stage1",   # patch 0152/0154: the sigma update is the default since patch 0155
                                "total_trade", "opt_tariff_total"))   # patch 0139
  pub <- s2b[is.na(trim_reason)]
  # (patch 0139) the estimator writes total_trade and opt_tariff_total natively
  expect_true(all(c("total_trade", "opt_tariff_total") %in% names(s2b)))
  ug <- new.env(); sys.source(file.path(root, "R", "utils_general.R"), envir = ug)
  est_rows <- ug$is_estimated_row(pub$tier, pub$convergence)
  c1 <- pub[est_rows][, .N, by = .(importer, good)][N >= 2L][1L]
  if (nrow(c1) && !is.na(c1$N)) {
    cc <- pub[importer == c1$importer & good == c1$good]
    e1 <- ug$is_estimated_row(cc$tier, cc$convergence)
    expect_equal(cc$opt_tariff_total[1L], ug$optimal_tariff(cc$gamma[e1], cc$sigma[e1][1L], cc$total_trade[e1]))
  }
  expect_gt(nrow(pub), 100L)
  # patch 0114: sigma_source reaches the saved table, on every row
  expect_false(anyNA(s2b$sigma_source))
  expect_true(all(s2b$sigma_source %in% c("estimated", "fallback_no_estimate", "fallback_sigma_edge", "fallback_sigma_pole",
                                          "updated_import", "updated_import_shrunk", "updated_level")))   # patch 0152/0154/0155
  expect_true(all(s2b$sigma_source_stage1 %in% c("estimated", "fallback_no_estimate", "fallback_sigma_edge", "fallback_sigma_pole")))
  expect_gt(sum(s2b$sigma_source == "updated_import_shrunk"), 0L)   # the default: the shrunk update
  # every fallback row carries the one fallback sigma
  # under the shrunk update (patch 0154/0155) the one shared value is the level: fallback_* and updated_level rows carry it
  lvl <- pub[startsWith(sigma_source, "fallback_") | sigma_source == "updated_level", sigma]
  expect_equal(data.table::uniqueN(lvl), min(1L, length(lvl)))
  expect_true(all(is.na(s2b$trim_reason) | s2b$trim_reason %in% c("sigma_lo", "sigma_hi", "gamma_lo", "gamma_hi", "na_sigma_or_gamma")))
  expect_true(any(is.finite(pub$gamma_v_resid)))
  expect_true(all(pub[tier == 3L, convergence] == -1L))

  # --- 2. the analysis layer on those outputs ---------------------------------
  work <- file.path(td, "repo"); dir.create(work)
  for (d in c("analysis", "R", "results")) {
    dir.create(file.path(work, d))
    file.copy(list.files(file.path(root, d), full.names = TRUE), file.path(work, d), recursive = TRUE)
  }
  file.copy(file.path(root, "README.template.md"), work)
  dir.create(file.path(work, "docs", "methodology"), recursive = TRUE)   # 00_setup.R reads the Pillar-2/3 CSVs here
  file.copy(file.path(root, "docs", "known_limitations_record.template.md"), file.path(work, "docs"))   # patch 0143: the second template
  file.copy(list.files(file.path(root, "docs", "methodology"), pattern = "\\.csv$", full.names = TRUE),
            file.path(work, "docs", "methodology"))
  dir.create(file.path(work, "data"))
  file.copy(file.path(root, "data", "manifest.csv"), file.path(work, "data"))            # build_readme.R counts it
  unlink(file.path(work, "analysis", "figures"), recursive = TRUE)
  dv <- file.path(work, "data", "derived")
  for (s in c("stage1", "stage2a", "stage2b", "validation")) dir.create(file.path(dv, s), recursive = TRUE)
  file.copy(f$s1, file.path(dv, "stage1")); file.copy(f$s2a, file.path(dv, "stage2a"))
  file.copy(c(f$s2b, f$s2b_sum, f$s2b_txt), file.path(dv, "stage2b"))
  file.copy(file.path(dirname(f$s2b), "baci_hs92_v202601_elast_country_hs4_sigma_update_passes.csv"), file.path(dv, "stage2b"))   # patch 0158: the update's pass log travels with the release
  meth <- file.path(root, "docs", "methodology")
  file.copy(file.path(meth, c("liml_validation_tier1a.csv", "liml_validation_tier1b.csv",
                              "se_calibration_mc_summary.csv", "bootstrap_se_summary.csv")), file.path(dv, "validation"))
  newest <- function(pat) sort(list.files(meth, pattern = pat, full.names = TRUE), decreasing = TRUE)[1]
  file.copy(newest("^se_calibration_mc_per_param_\\d{8}\\.csv$"), file.path(dv, "validation", "se_calibration_mc_per_param.csv"))
  file.copy(newest("^bootstrap_se_cells_\\d{8}\\.csv$"), file.path(dv, "validation", "bootstrap_se_cells.csv"))
  # (patch 0130) since v0.11.1 the manifest also lists the product-level table;
  # build it from this run's Stage-2b table with the release's own tool, so the
  # table builder runs end to end too (0129's smoke run stopped at master.R's
  # completeness check because the scratch tree lacked it)
  man <- data.table::fread(file.path(work, "data", "manifest.csv"))
  prod_path <- grep("^data/derived/product/.*\\.csv$", man$local_path, value = TRUE)   # (0138) the CSV; v0.11.2 added a Parquet twin
  if (length(prod_path)) {
    pr <- .e2e_run(c(shQuote(file.path(root, "analysis", "product_summary.R")), "--stage2b", shQuote(f$s2b),
                     "--table", prod_path, "--json", file.path(td, "ps.json"), "--md", file.path(td, "ps.md")), wd = work)
    expect_equal(pr$status, 0L, info = paste(utils::tail(pr$out, 20), collapse = "\n"))
    ptab <- data.table::fread(file.path(work, prod_path), colClasses = list(character = "good"))
    expect_identical(nrow(ptab), data.table::uniqueN(pub$good))
    # (patch 0163) a cell's own sigma is the update: the share is the share of such cells, not ~0
    own <- pub[, .(own = ug$sigma_is_cell_specific(sigma_source[1L])), by = .(good, importer)][, .(share = mean(own)), by = good]
    expect_equal(ptab$share_cells_own_sigma, own$share[match(ptab$good, own$good)])
    expect_gt(max(ptab$share_cells_own_sigma), 0.5)
  }
  # (patch 0138) since v0.11.2 the manifest also lists Parquet copies: write them
  # with the release's own tool (which checks each copy against its source)
  # where nanoparquet is installed; elsewhere (CI restores renv.lock, which does
  # not carry it) drop those rows from this scratch copy of the manifest, so
  # master.R's completeness check covers the files this run can stage
  pq_rows <- grepl("\\.parquet$", man$local_path)
  if (any(pq_rows)) {
    if (requireNamespace("nanoparquet", quietly = TRUE)) {
      px <- .e2e_run(shQuote(file.path(root, "scripts", "export_parquet.R")), wd = work)
      expect_equal(px$status, 0L, info = paste(utils::tail(px$out, 20), collapse = "\n"))
    } else {
      man <- man[!pq_rows]
      data.table::fwrite(man, file.path(work, "data", "manifest.csv"), quote = TRUE)
    }
  }
  # every file the manifest lists exists in the scratch tree (a new manifest row
  # must be staged here, or master.R stops)
  expect_true(all(file.exists(file.path(work, man$local_path))),
              info = paste(man$local_path[!file.exists(file.path(work, man$local_path))], collapse = ", "))

  ma <- .e2e_run(file.path("analysis", "master.R"), wd = work)
  expect_equal(ma$status, 0L, info = paste(utils::tail(ma$out, 40), collapse = "\n"))
  # (patch 0163) pillar 1's headline line does not call a cell's updated sigma "the fallback"
  mlog <- paste(ma$out, collapse = "\n")
  expect_match(mlog, "published sigma median (Stage-2b rows, the README's headline)", fixed = TRUE)
  expect_false(grepl("the fallback sigma [0-9.]+ is on", mlog))
  lvl_share <- mean(!ug$sigma_is_cell_specific(pub$sigma_source))
  if (lvl_share > 0) expect_match(mlog, sprintf("%.1f%% of rows carry the level / fallback sigma", 100 * lvl_share), fixed = TRUE)
  s1j  <- jsonlite::fromJSON(file.path(work, "results", "stage1_summary.json"))
  s2bj <- jsonlite::fromJSON(file.path(work, "results", "stage2b_summary.json"))
  expect_equal(s1j$n_cells, nrow(readRDS(f$s1)))
  expect_equal(s2bj$n_cells, nrow(pub))
  # patch 0121: the fallback count is the sigma_source count, not the value spike
  expect_equal(s2bj$sigma_provenance$n_fallback, sum(startsWith(pub$sigma_source, "fallback_")))   # patch 0155: an updated_* row is not a fallback
  expect_true(isTRUE(s2bj$sigma_update$present))                                                    # patch 0158: the update's block of the JSON
  expect_equal(s2bj$sigma_update$n_shrunk, sum(pub$sigma_source == "updated_import_shrunk"))
  expect_equal(s2bj$sigma_update$shrink_b_full, 2 * 0.146 / 1.146, tolerance = 1e-9)
  expect_true(is.finite(s2bj$sigma_update$level_sigma) && s2bj$sigma_update$cells_profiled > 0)

  # --- 3. the README build on the JSONs that run wrote ------------------------
  rd <- file.path(td, "README.md"); rec <- file.path(td, "known_limitations_record.md")   # patch 0143
  br <- .e2e_run(shQuote(file.path(root, "scripts", "build_readme.R")), wd = work,
                 env = c(paste0("README_BUILD_OUTPUT=", rd), paste0("README_RECORD_BUILD_OUTPUT=", rec)))
  expect_equal(br$status, 0L, info = paste(utils::tail(br$out, 20), collapse = "\n"))
  txt <- paste(readLines(rd, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, sprintf("Outputs cover %d HS4 products", data.table::uniqueN(pub$good)), fixed = TRUE)
  expect_false(grepl("{{", txt, fixed = TRUE))
  # (patch 0163) the build stops on a table row GitHub would cut off (status 3); it did not, and the README
  # says the standard-error columns' state from the JSON this run wrote
  expect_match(txt, "| `gamma_exposure` | Number of moment rows that involve the row's", fixed = TRUE)
  if (identical(as.numeric(s2bj$sigma_robust$robust), 0)) expect_match(txt, "so it is `NA` throughout", fixed = TRUE)
  rtxt <- paste(readLines(rec, warn = FALSE, encoding = "UTF-8"), collapse = "\n")   # patch 0143: the record renders too
  expect_match(rtxt, "the long-form record", fixed = TRUE)
  expect_false(grepl("{{", rtxt, fixed = TRUE))
})
