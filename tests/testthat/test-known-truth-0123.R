# ============================================================================
# test-known-truth-0123.R  (patch 0123, audit #8: structured worlds, R4, records)
#
#   1. validation/synthetic_baci.R: an unstructured world is the one patch 0121
#      generated (fingerprints of a small world taken before 0123); a
#      structured world keeps sigma, the shocks and the trade pattern of the
#      unstructured world of the same seed and changes only gamma.
#   2. validation/known_truth_stage2.R: world directories, the settings check,
#      the between- and within-good metrics, reading R4, and R1-R3 reading only
#      the unstructured worlds.
#   3. scripts/build_readme.R: the known-truth and sigma out-of-sample clauses
#      (and their fallbacks without the JSONs); README and card carry them.
# ============================================================================

.k23_root <- function() dirname(locate_source_dir())
.k23_env <- function() {
  env <- new.env()
  for (f in c("R/utils_general.R", "R/iteration_helpers.R", "R/sigma_eb.R", "validation/synthetic_baci.R", "validation/known_truth_stage2.R"))
    sys.source(file.path(.k23_root(), f), envir = env)
  env
}

test_that("an unstructured world is unchanged; a structured one changes gamma only", {
  e <- .k23_env()
  ctys <- c(842L, 276L, 392L, 156L, 251L, 826L)
  d0 <- tempfile("w0_"); d1 <- tempfile("w1_"); on.exit(unlink(c(d0, d1), recursive = TRUE), add = TRUE)
  t0 <- e$make_synthetic_baci_dir(d0, n_goods = 2L, countries = ctys, years = 2001:2010, seed = 7L)
  f <- sort(list.files(d0, full.names = TRUE))
  x1 <- data.table::fread(f[1], colClasses = list(character = "k")); x10 <- data.table::fread(f[10], colClasses = list(character = "k"))
  # fingerprints taken with the patch-0121 generator (line endings do not enter them)
  expect_identical(c(nrow(x1), nrow(x10), sum(is.na(x1$q))), c(56L, 78L, 3L))
  expect_equal(c(sum(x1$v), sum(x1$q, na.rm = TRUE), sum(x10$v), sum(x10$q, na.rm = TRUE)),
               c(76611043.112, 4327870.901, 76611115.355, 11687802.211), tolerance = 1e-10)
  expect_equal(c(nrow(t0$sigma), nrow(t0$gamma)), c(11L, 42L))
  expect_equal(c(sum(t0$sigma$sigma_true), sum(t0$gamma$gamma_true)), c(36.558764249506, 30.297515382574), tolerance = 1e-10)

  t1 <- e$make_synthetic_baci_dir(d1, n_goods = 2L, countries = ctys, years = 2001:2010, seed = 7L,
                                  good_sd = 0.7, importer_sd = 0.5, within_sd = 0.35)
  expect_identical(t1$sigma, t0$sigma)
  expect_identical(t1$gamma[, .(importer, exporter, good)], t0$gamma[, .(importer, exporter, good)])
  expect_false(isTRUE(all.equal(t1$gamma$gamma_true, t0$gamma$gamma_true)))
  expect_equal(t1$meta$good_sd, 0.7); expect_equal(t1$meta$importer_sd, 0.5)
  # the effects are in the truth: ln gamma minus the good and importer effects has the within s.d. scale
  res <- log(t1$gamma$gamma_true) - log(0.7) - t1$meta$good_effects[t1$gamma$good] - t1$meta$importer_effects[as.character(t1$gamma$importer)]
  expect_lt(abs(sd(res) - 0.35), 0.15)
})

test_that("world directories and the settings check", {
  e <- .k23_env()
  expect_identical(basename(e$kt_world_dir("/x", 20261015L, 1, "none")), "w20261015_x1")
  expect_identical(basename(e$kt_world_dir("/x", 20261015L, 3, "good_importer")), "w20261015_x3_good_importer")
  meta0121 <- list(seed = 7L, shock_scale = 1, n_goods = 5L, countries = 1:15, years = c(1995L, 2024L))   # no structure fields
  expect_true(e$kt_check_world(meta0121, 7L, 1, 5L, 1:15, 1995:2024, e$KT_STRUCTURES$none))
  expect_error(e$kt_check_world(meta0121, 7L, 1, 12L, 1:15, 1995:2024, e$KT_STRUCTURES$none), "n_goods")
  expect_error(e$kt_check_world(meta0121, 7L, 1, 5L, 1:15, 1995:2024, e$KT_STRUCTURES$good), "good_sd")
})

test_that("between- and within-good metrics on hand-built tables", {
  e <- .k23_env()
  td <- tempfile("k23m_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  g <- data.table::CJ(importer = 1:4, exporter = 10:12, good = c("0101", "0202", "0303"))[importer != exporter]
  g[, gamma_true := exp(c(`0101` = -1, `0202` = 0, `0303` = 1)[good] + 0.3 * (importer - 2.5) + 0.2 * (exporter - 11))]
  truth <- list(gamma = g, sigma = unique(g[, .(importer, good)])[, sigma_true := 2.5])
  mk <- function(gam) {
    s2b <- data.table::data.table(importer = as.character(g$importer), exporter = as.character(g$exporter), good = g$good, sigma = 2.5,
                                  gamma = gam, tier = 1L, convergence = 0L, avg_trade = 1 + g$exporter %% 3, gamma_shrink_wt = 0.9,
                                  trim_reason = NA_character_, sigma_source = "estimated")
    s2b[, opt_tariff := e$optimal_tariff(gamma, sigma[1], avg_trade), by = .(importer, good)]
    saveRDS(s2b, file.path(td, paste0(e$KT_PREFIX, "_fixed_sigma.rds")))
    e$kt_metrics(td, truth)
  }
  m <- mk(g$gamma_true)
  expect_equal(m$between_good_gamma_r, 1); expect_equal(m$between_good_tariff_r, 1)
  expect_equal(m$within_good_gamma_r, 1); expect_equal(m$within_good_gamma_sd_ratio, 1)
  expect_equal(m$within_good_tariff_r, 1)
  # the good-level prior: right between goods, no importer differences within a good
  m2 <- mk(exp(c(`0101` = -1, `0202` = 0, `0303` = 1)[g$good]))
  expect_equal(m2$between_good_gamma_r, 1)
  expect_equal(m2$within_good_gamma_sd_ratio, 0)
  expect_true(is.na(m2$within_good_gamma_r))
})

test_that("reading R4, and R1-R3 read the unstructured worlds only", {
  e <- .k23_env()
  sm <- function(bg, bt, wr, ws) data.table::data.table(
    structure = rep(c("good", "good_importer"), each = 2), arm_name = "shipped", scale = c(1, 3, 1, 3),
    between_good_gamma_r = c(bg, NA, NA), between_good_tariff_r = c(bt, NA, NA),
    within_good_gamma_r = c(NA, NA, wr), within_good_gamma_sd_ratio = c(NA, NA, ws), within_good_tariff_r = NA_real_)
  r <- e$kt_readings_r4(sm(c(0.9, 0.85), c(0.8, 0.75), c(0.3, 0.25), c(0.01, 0.02)))
  expect_identical(r$R4a_between_goods$verdict, "recovered")
  expect_identical(r$R4b_within_goods$verdict, "not recovered")
  expect_true(r$good_level_reading)
  expect_identical(e$kt_readings_r4(sm(c(0.2, 0.3), c(0.1, 0.2), c(0.6, 0.7), c(0.6, 0.8)))$R4a_between_goods$verdict, "not recovered")
  expect_identical(e$kt_readings_r4(sm(c(0.2, 0.3), c(0.1, 0.2), c(0.6, 0.7), c(0.6, 0.8)))$R4b_within_goods$verdict, "recovered")
  expect_identical(e$kt_readings_r4(sm(c(0.9, 0.5), c(0.8, 0.8), c(0.3, 0.6), c(0.2, 0.6)))$R4a_between_goods$verdict, "partial")
  expect_false(e$kt_readings_r4(sm(c(0.9, 0.5), c(0.8, 0.8), c(0.3, 0.6), c(0.2, 0.6)))$good_level_reading)
  expect_identical(e$kt_readings_r4(sm(c(0.9, 0.5), c(0.8, 0.8), c(0.3, 0.6), c(0.2, 0.6))[structure == "good"])$R4b_within_goods$verdict, "not measured")
  # R1 ignores structured rows
  s <- data.table::data.table(structure = c("none", "none", "good", "good"), arm_name = c("shipped", "truesigma0", "shipped", "truesigma0"),
                              scale = 1, within_r = c(0.05, 0.2, 0.9, 0.9), opt_tariff_r = c(0.1, 0.1, 0.9, 0.9))
  expect_identical(e$kt_readings(s, data.table::data.table(), data.table::data.table())$R1_within_cell_gamma$verdict, "not recovered")
})

test_that("README clauses: known truth and sigma out of sample, with fallbacks", {
  bf <- readLines(file.path(.k23_root(), "scripts", "build_readme.R"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^kt_row <- function", bf); i1 <- grep("^# --- Stage-2 DGP harness line", bf) - 1L
  env <- new.env()
  env$req <- function(obj, key) { v <- obj[[key]]; if (is.null(v)) stop("missing ", key); v }
  env$format_num <- function(x, digits = 3L) formatC(x, digits = digits, format = "f")
  eval(parse(text = bf[i0:i1]), envir = env)
  expect_match(env$within_signal_phrase(NULL), "about half the within-cell heterogeneity is signal", fixed = TRUE)
  expect_identical(env$known_truth_title_tail(NULL), "")
  expect_identical(env$known_truth_within_clause(NULL), "")
  expect_identical(env$sigma_eb_period_clause(NULL, NULL), "")
  kt <- jsonlite::fromJSON(file.path(.k23_root(), "results", "known_truth_stage2.json"), simplifyVector = FALSE)
  expect_match(env$known_truth_within_clause(kt), "Reproducible is not the same as recovered", fixed = TRUE)
  expect_match(env$known_truth_title_tail(kt), "not recovered at known truth", fixed = TRUE)
  seb <- list(data = jsonlite::fromJSON(file.path(.k23_root(), "results", "sigma_eb_period_census_v0110.json"), simplifyVector = FALSE),
              key = "sigma_eb_period_census_v0110")
  cl <- env$sigma_eb_period_clause(seb, kt)
  expect_match(cl, "Out of sample the global value does better still", fixed = TRUE)
  expect_match(cl, "Empirical-Bayes shrinkage of \u03c3 is not adopted", fixed = TRUE)

  readme <- generated_docs_text(.k23_root())   # patch 0143: README.md + the long-form record
  expect_match(readme, "Reproducible is not the same as recovered (patch 0122)", fixed = TRUE)
  expect_match(readme, "cell-level differences in \u03c3 do not carry from one period to the other", fixed = TRUE)
  expect_false(grepl("about half the within-cell heterogeneity is signal", readme, fixed = TRUE))
  card <- paste(readLines(file.path(.k23_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_match(card, "**Measured since v0.11.0 (2026-10-15, patches 0122\u20130", fixed = TRUE)   # 0123; 0124 extended the range
  expect_match(card, "no longer stands", fixed = TRUE)
})
