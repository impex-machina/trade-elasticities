# ============================================================================
# test-stage2b-prior-source.R  (patch 0079, 2026-09-29 fresh-eyes audit #4)
#
# The Stage-2b good-level prior and gamma_V are medians over Stage-2a rows.
# Through v0.8.2 they ran over every row with gamma > 0, including Stage 2a's
# own Tier-3 imputations (convergence -1). Locks:
#   1. stage2b_priors_from_regional(rows = "all") reproduces the runner's
#      v0.8.2 arithmetic exactly; rows = "estimated" drops imputed rows and
#      moves the medians where they were numerous, leaves them where absent;
#   2. a good with no estimated row disappears from the estimated prior (the
#      runner's lookup then falls to no-prior / the default, as for any good
#      absent from the table) rather than silently keeping the imputed value;
#   3. plumbing: CLI accepts all/estimated and rejects others, default all,
#      validate_config likewise, the checkpoint stamp moves with the field;
#   4. the census script runs end to end on a synthetic Stage-2a table and
#      writes its JSON and markdown.
# ============================================================================

.pr_setup <- function() {
  src_dir <- locate_source_dir()
  assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
# A synthetic Stage-2a-shaped table: two regions, three goods. Good "0101" has
# estimated rows at gamma ~ 1 and a block of Tier-3 rows imputed at 0.2 large
# enough to drag the median; "0202" has no imputed rows; "0303" is imputed only.
.pr_table <- function() {
  est <- function(region, good, g, tier = 1L) data.table(importer = region, exporter = paste0("e", seq_along(g)),
    good = good, sigma = 3, gamma = g, tier = tier, convergence = 0L)
  imp <- function(region, good, g, n) data.table(importer = region, exporter = paste0("t", seq_len(n)),
    good = good, sigma = 3, gamma = g, tier = 3L, convergence = -1L)
  rbindlist(list(
    est("R1", "0101", c(0.8, 1.0, 1.2, 1.4)), imp("R1", "0101", 0.2, 6L),
    est("R2", "0101", c(0.9, 1.1)),           imp("R2", "0101", 0.2, 1L),
    est("R1", "0202", c(0.5, 0.6, 0.7)),      est("R2", "0202", c(0.4, 0.8)),
    imp("R1", "0303", 0.3, 3L),
    # an all-Tier-3 early return: reference row tier 0 but convergence -1
    data.table(importer = "R2", exporter = "ref", good = "0303", sigma = 3, gamma = 0.3, tier = 0L, convergence = -1L)
  ), use.names = TRUE)
}

test_that("rows = 'all' is the v0.8.2 arithmetic; 'estimated' drops imputed rows", {
  .pr_setup()
  reg <- .pr_table(); rc <- reg[!is.na(sigma) & !is.na(gamma) & gamma > 0]
  p_all <- stage2b_priors_from_regional(rc, rows = "all")
  # the runner's v0.8.2 lines, verbatim
  ref_prior <- rc[, .(ln_gamma_prior = median(log(gamma), na.rm = TRUE)), by = good]
  ref_gv    <- rc[, .(gamma = median(gamma, na.rm = TRUE)), by = .(region = importer, good)]
  expect_equal(p_all$country_priors, ref_prior)
  expect_equal(p_all$gam_V_regional, ref_gv)
  expect_equal(p_all$n_rows_used, nrow(rc))
  p_est <- stage2b_priors_from_regional(rc, rows = "estimated")
  expect_equal(p_est$n_rows_used, sum(rc$convergence == 0L))
  # "0101": imputed rows dragged the all-rows prior to 0.2 = the imputed value
  expect_equal(exp(p_all$country_priors[good == "0101", ln_gamma_prior]), 0.2, tolerance = 1e-12)
  expect_equal(p_est$country_priors[good == "0101", ln_gamma_prior], median(log(c(0.8, 1.0, 1.2, 1.4, 0.9, 1.1))), tolerance = 1e-12)
  # "0202": no imputed rows -> identical under either rule
  expect_equal(p_all$country_priors[good == "0202", ln_gamma_prior], p_est$country_priors[good == "0202", ln_gamma_prior])
  expect_equal(p_all$gam_V_regional[good == "0202"], p_est$gam_V_regional[good == "0202"])
  # "0303": imputed only -> present under 'all' (at the imputed value), absent under 'estimated'
  expect_true("0303" %in% p_all$country_priors$good)
  expect_false("0303" %in% p_est$country_priors$good)
  expect_false("0303" %in% p_est$gam_V_regional$good)
  # gamma_V for (R1, 0101): 0.2 under all (6 imputed of 10 rows), ~1.1 under estimated
  expect_equal(p_all$gam_V_regional[region == "R1" & good == "0101", gamma], 0.2)
  expect_equal(p_est$gam_V_regional[region == "R1" & good == "0101", gamma], median(c(0.8, 1.0, 1.2, 1.4)))
  expect_error(stage2b_priors_from_regional(rc, rows = "some"), "arg")
  expect_error(stage2b_priors_from_regional(rc[, !"tier"], rows = "estimated"), "tier")
})

test_that("CLI, validate_config and the checkpoint stamp carry stage2b_prior_source", {
  .pr_setup()
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_pr_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  expect_identical(parse_cli(c(base, "--stage2b-prior-source", "estimated"))$stage2b_prior_source, "estimated")
  expect_identical(parse_cli(base)$stage2b_prior_source, "all")
  expect_error(parse_cli(c(base, "--stage2b-prior-source", "some")), "stage2b-prior-source")
  opts <- parse_cli(c(base, "--stage2b-prior-source", "estimated"))
  expect_identical(build_config(opts)$stage2b_prior_source, "estimated")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  expect_silent(validate_config(cfg))
  cfg_bad <- cfg; cfg_bad$stage2b_prior_source <- "some"
  expect_error(validate_config(cfg_bad), "stage2b_prior_source")
  cfg_est <- cfg; cfg_est$stage2b_prior_source <- "estimated"
  expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_est, dt)))
  cfg_all <- cfg; cfg_all$stage2b_prior_source <- "all"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_all, dt))   # absent key == all
})

test_that("the census script runs on a synthetic Stage-2a table", {
  .pr_setup()
  skip_if_not_installed("jsonlite")
  script <- file.path(locate_source_dir(), "..", "analysis", "stage2a_prior_rows_census.R")
  skip_if_not(file.exists(script))
  td <- tempfile("prc_"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  tab <- file.path(td, "s2a.rds"); saveRDS(.pr_table(), tab)
  js <- file.path(td, "c.json"); md <- file.path(td, "c.md")
  rs <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rs, c(shQuote(script), "--stage2a", shQuote(tab), "--out", shQuote(js), "--md", shQuote(md)),
                                  stdout = TRUE, stderr = TRUE))
  expect_true(file.exists(js), info = paste(out, collapse = "\n"))
  expect_true(file.exists(md))
  j <- jsonlite::fromJSON(js)
  expect_equal(j$composition$n_imputed, 11L)
  expect_equal(j$composition$n_goods_all_imputed, 1L)
  expect_equal(j$prior_shift$n_goods_no_estimated_rows, 1L)
  expect_gt(j$prior_shift$abs_d_ln_quantiles$p95, 1)      # the "0101" shift, 0.2 -> ~1.05
  expect_true(any(grepl("Good-level prior", readLines(md))))
})
