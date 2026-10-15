# ============================================================================
# test-audit7-0116.R  (patch 0116, fresh-eyes audit #7)
#
# Locks the 0116 fixes:
#   A7  stage2_convergence_census(): the optimizer's codes (1 / 10 / 51 / 52)
#       on directly estimated rows vs the imputed rows' -1, published rows
#       only; analysis/stage2b_convergence_census.R end to end;
#   A3  pole_na_se_census(): the clean-set cells with no finite sigma_se;
#   A4  rotate_pass_records() renames the trim .rds twin with the CSVs, and
#       the runner uses it; A5 the runner's checksum paths are repo-relative;
#   A9  hf_url_at_revision(), load_outputs(revision, manifest_path) and
#       scripts/pin_manifest_revision.R (offline: the files exist, only the
#       hashes are verified);
#   A1 / A8 / A7 / M4  build_readme.R's 0116 phrases, extracted by parsing
#       the script's top-level function definitions;
#   A8  analysis/01, 02, 04 and 06 on synthetic tables: boundary cells are a
#       route of their own, Tier-3 rows stay out of the heterogeneity table.
# ============================================================================

.a7_root <- function() dirname(locate_source_dir())
.a7_lib <- function() {
  src_dir <- locate_source_dir()
  source(file.path(src_dir, "utils_general.R"), local = FALSE)
  source(file.path(src_dir, "iteration_helpers.R"), local = FALSE)
  source(file.path(src_dir, "output_paths.R"), local = FALSE)
  source(file.path(src_dir, "load_outputs.R"), local = FALSE)
  invisible(TRUE)
}
.a7_table <- function() {
  # two fitted cells (one converged, one at the iteration cap), one all-Tier-3
  # cell (imputed reference + Tier 3), one flagged trimmed row
  data.table::data.table(
    importer    = c("1", "1", "1", "2", "2", "2", "3", "3", "1"),
    exporter    = c("a", "b", "c", "a", "b", "c", "a", "b", "d"),
    good        = "0101",
    tier        = c(0L, 1L, 3L, 0L, 1L, 2L, 0L, 3L, 1L),
    convergence = c(0L, 0L, -1L, 1L, 1L, 1L, -1L, -1L, 0L),
    gamma_se_status = c("ok", "ok", "tier3_prior", "non_converged", "non_converged", "non_converged",
                        "tier3_prior", "tier3_prior", "ok"),
    trim_reason = c(NA, NA, NA, NA, NA, NA, NA, NA, "gamma_hi"))
}

test_that("A7: stage2_convergence_census() separates the optimizer's codes from the imputed rows", {
  .a7_lib()
  cc <- stage2_convergence_census(.a7_table())
  expect_identical(cc$n_rows, 8L)                     # the flagged row is not published
  expect_identical(cc$n_estimated, 5L)                # tier < 3 and not -1
  expect_identical(cc$n_nonconverged, 3L)             # the capped cell's three rows
  expect_equal(cc$share_nonconverged, 3 / 5)
  expect_identical(cc$n_cells_estimated, 2L)
  expect_identical(cc$n_cells_nonconverged, 1L)
  expect_identical(cc$n_imputed_reference, 1L)        # cell 3's reference row
  expect_equal(cc$share_imputed_reference, 1 / 6)     # of the six tier < 3 rows
  expect_identical(cc$n_tier3, 2L)
  expect_identical(cc$n_status_non_converged, 3L)
  expect_identical(cc$codes_estimated[["1"]], 3L)
  # the gates' pre-0116 metric, -1 among tier < 3 rows, is the imputed share
  x <- .a7_table()[is.na(trim_reason)]
  expect_equal(mean(x[tier < 3L]$convergence %in% -1L), cc$share_imputed_reference)
  expect_error(stage2_convergence_census(data.table::data.table(importer = "1")), "missing columns")
})

test_that("A7: analysis/stage2b_convergence_census.R writes the census with the table's sha256", {
  skip_if_not_installed("jsonlite"); skip_if_not_installed("openssl")
  script <- file.path(.a7_root(), "analysis", "stage2b_convergence_census.R"); skip_if_not(file.exists(script))
  d <- tempfile("cc_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  p <- file.path(d, "t.rds"); saveRDS(.a7_table(), p)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c(script, "--stage2b", p, "--label", "vTEST", "--out", file.path(d, "c.json"), "--md", file.path(d, "c.md")),
    stdout = TRUE, stderr = TRUE))
  expect_true(file.exists(file.path(d, "c.json")), info = paste(out, collapse = "\n"))
  j <- jsonlite::fromJSON(file.path(d, "c.json"))
  con <- file(p, "rb"); sha <- tolower(unclass(as.character(openssl::sha256(con)))); close(con)
  expect_identical(j$meta$stage2b_sha256, sha)
  expect_identical(j$census$n_nonconverged, 3L)
  expect_true(isTRUE(j$status_matches_codes))
  md <- readLines(file.path(d, "c.md"))
  expect_true(any(grepl("Optimizer non-convergence", md)))
  expect_true(any(grepl("Imputed reference rows", md)))
})

test_that("A3: pole_na_se_census() finds the clean-set cells the pole test cannot assess", {
  .a7_lib()
  script <- file.path(.a7_root(), "analysis", "pole_na_se_census.R"); skip_if_not(file.exists(script))
  env <- new.env(); sys.source(script, envir = env)          # function only: the CLI block needs Rscript
  s1 <- data.table::data.table(
    importer = as.character(1:8), good = "0101", status = "ok", convergence = 0L,
    sigma    = c(3, 4, 1.05, 1.3, 2.5, 50, 1.02, 6),
    sigma_se = c(0.5, 0.5, 0.2, NA, NA, NA, 0.5, 1),
    sigma_capped = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
    final_source = c("hliml", "hliml", "hliml", "hliml_boundary", "hliml_boundary", "hliml_boundary", "hliml", "hliml_boundary"),
    hliml_boundary_edge = c(NA, NA, NA, "omega_floor", "omega_cap", "sigma_cap", NA, "omega_floor"),
    edge_se_status = c(NA, NA, NA, "negative_variance", "singular", NA, NA, "ok"),
    boundary_corner = c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
  s2b <- data.table::data.table(importer = rep(as.character(1:8), each = 2), exporter = rep(c("a", "b"), 8), good = "0101",
                                tier = 1L, convergence = 0L, gamma = 0.8, sigma_robust = FALSE, trim_reason = NA_character_)
  res <- env$pole_na_se_census(s1, s2b, pole_c = 1)
  expect_identical(res$dropped_pole, 2L)                    # cells 3 (1.05, SE 0.2) and 7 (1.02, SE 0.5)
  expect_identical(res$dropped_edge, 1L)                    # cell 6 at the cap
  expect_identical(res$unassessed_cells, 2L)                # cells 4 and 5: NA SE, kept
  expect_identical(res$unassessed_boundary_corner, 1L)
  expect_identical(res$unassessed_sigma_lt[["1.5"]], 1L)
  expect_identical(res$stage2b_rows, 4L)
  expect_identical(res$stage2b_sigma_robust_true, 0L)
  expect_setequal(res$cells$importer, c("4", "5"))
})

test_that("A4 / A5: pass records rotate together; the runner uses the helper and repo-relative checksum paths", {
  .a7_lib()
  d <- tempfile("rot_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  b <- file.path(d, "baci_x_elast_country_hs4")
  for (e in c("_stage2_fallbacks.csv", "_stage2_trimmed.csv", "_stage2_trimmed.rds")) writeLines("x", paste0(b, e))
  writeLines("stale", paste0(b, "_stage2_trimmed_pass2.rds"))            # a stale target is replaced
  rotate_pass_records(b, 2L)
  expect_setequal(basename(list.files(d)), paste0("baci_x_elast_country_hs4",
    c("_stage2_fallbacks_pass2.csv", "_stage2_trimmed_pass2.csv", "_stage2_trimmed_pass2.rds")))
  expect_identical(readLines(paste0(b, "_stage2_trimmed_pass2.rds")), "x")
  expect_length(rotate_pass_records(b, 3L), 0L)                           # nothing left to rotate
  run <- readLines(file.path(.a7_root(), "scripts", "run_estimation.R"), warn = FALSE)
  expect_true(any(grepl("rotate_csvs <- function(k) rotate_pass_records(prefix_country, k)", run, fixed = TRUE)))
  expect_false(any(grepl("file.rename(f, sub(", run, fixed = TRUE)))
  # (patch 0125) the end-of-run manifest check was removed: it hashed the published
  # files in data/derived, not the run's outputs
  expect_false(any(grepl("DIFFERS from manifest", run, fixed = TRUE)))
})

test_that("A9: hub URLs point at a revision; load_outputs() verifies another manifest offline", {
  .a7_lib()
  u <- "https://huggingface.co/datasets/impex-machina/trade-elasticities/resolve/main/stage1/a.rds"
  expect_identical(hf_url_at_revision(u, NULL), u)
  expect_identical(hf_url_at_revision(u, "v0.11.0"),
                   "https://huggingface.co/datasets/impex-machina/trade-elasticities/resolve/v0.11.0/stage1/a.rds")
  expect_identical(hf_url_at_revision(sub("main", "v0.10.2", u), "19843d50fb7cf71b437ca52af8f61fe4a8b20f11"),
                   sub("main", "19843d50fb7cf71b437ca52af8f61fe4a8b20f11", u))
  expect_error(hf_url_at_revision(u, "v0.11.0/../x"), "not a revision name")
  expect_error(hf_url_at_revision("https://example.org/a.rds", "v1"), "not a hub resolve URL")
  skip_if_not_installed("openssl")
  d <- tempfile("dl_"); dir.create(file.path(d, "data", "derived"), recursive = TRUE)
  old <- setwd(d); on.exit({ setwd(old); unlink(d, recursive = TRUE) }, add = TRUE)
  writeLines("payload", "data/derived/f.txt")
  con <- file("data/derived/f.txt", "rb"); sha <- tolower(unclass(as.character(openssl::sha256(con)))); close(con)
  m <- data.table::data.table(local_path = "data/derived/f.txt", hf_url = u, sha256 = sha, size_bytes = 8L,
                              produced_by = "x", pillar = 1L, description = "d")
  data.table::fwrite(m, "m_old.csv", quote = TRUE)
  expect_message(load_outputs(revision = "v0.10.2", manifest_path = "m_old.csv"), "already present and verified")
  m$sha256 <- strrep("0", 64); data.table::fwrite(m, "m_bad.csv", quote = TRUE)
  expect_error(load_outputs(manifest_path = "m_bad.csv"), "Checksum mismatch")
})

test_that("A9: pin_manifest_revision.R rewrites only the URLs, in rehash_manifest.R's format", {
  script <- file.path(.a7_root(), "scripts", "pin_manifest_revision.R"); skip_if_not(file.exists(script))
  env <- new.env(); sys.source(script, envir = env)
  src <- file.path(.a7_root(), "data", "manifest.csv"); skip_if_not(file.exists(src))
  p <- tempfile(fileext = ".csv"); file.copy(src, p); on.exit(unlink(p), add = TRUE)
  before <- readLines(p)
  res <- env$pin_manifest_revision(p, "v0.11.0")
  after <- readLines(p)
  expect_identical(length(after), length(before))
  expect_identical(res$after, "v0.11.0")
  expect_true(all(grepl("/resolve/v0.11.0/", after[-1])))
  expect_identical(sub("/resolve/[^/]+/", "/resolve/X/", after), sub("/resolve/[^/]+/", "/resolve/X/", before))
  expect_identical(unique(env$manifest_revisions(data.table::fread(p)$hf_url)), "v0.11.0")
  expect_error(env$pin_manifest_revision(p, "bad rev"), "not a revision name")
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(script, "--check", "--manifest", p), stdout = TRUE, stderr = TRUE))
  expect_true(any(grepl("names v0.11.0 \\(", out)), info = paste(out, collapse = "\n"))
})

test_that("README phrases (0116): provenance shares, the headline sigma note, coverage, the convergence clause", {
  path <- file.path(.a7_root(), "scripts", "build_readme.R"); skip_if_not(file.exists(path))
  env <- new.env()
  for (e in parse(path, keep.source = FALSE)) {          # every top-level `name <- function(...)`, nothing else
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function")))
      eval(e, env)
  }
  s1 <- list(n_cells = 1000L, routing_summary = list(hliml_interior = 300L, step2_total = 150L, clamped_total = 20L,
                                                     pre_discard = 350L, boundary_total = 200L))
  lead <- env$provenance_lead(s1); tail <- env$provenance_tail(s1)
  expect_match(lead, "30.0% of", fixed = TRUE); expect_match(lead, "15.0% (150 cells)", fixed = TRUE)
  expect_match(lead, "2.0% of the full universe (20 cells)", fixed = TRUE)
  expect_match(tail, "the remaining 35.0% (350 cells) return no estimate", fixed = TRUE)
  expect_false(grepl("the rest fall", paste(lead, tail)))
  s2 <- list(sigma_median = 2.4728, sigma_provenance = list(fallback_value = 2.4728, n_fallback = 41L, denominator = 100L))
  expect_match(env$headline_sigma_note(s2), "41.0% of rows carry it", fixed = TRUE)
  s2$sigma_median <- 2.6
  expect_identical(env$headline_sigma_note(s2), "")
  p2 <- list(tier1a = list(
    list(sigma_true = 2, omega_true = 0.3, sigma_cov = 0.97, sigma_cov_hliml = 0.96),
    list(sigma_true = 5, omega_true = 3,   sigma_cov = 0.736, sigma_cov_hliml = 0.687),
    list(sigma_true = 8, omega_true = 3,   sigma_cov = 0.606, sigma_cov_hliml = 0.466),
    list(sigma_true = 8, omega_true = 1,   sigma_cov = 0.816, sigma_cov_hliml = 0.805)))
  cl <- env$pillar2_coverage_clause(p2)
  expect_match(cl, "below 80% at 2 of 4 points, both at the grid's largest", fixed = TRUE)
  expect_match(cl, "60.6% at \u03c3 = 8 (46.6% on interior-HLIML fits) and 73.6% at \u03c3 = 5", fixed = TRUE)
  expect_match(cl, "smallest \u03c3 is 2", fixed = TRUE)
  p2$tier1a[[2]]$sigma_cov <- 0.9; p2$tier1a[[3]]$sigma_cov <- 0.95
  expect_false(grepl("below 80%", env$pillar2_coverage_clause(p2)))
  expect_identical(env$convergence_clause(NULL), "")
  conv <- list(data = list(census = list(n_nonconverged = 50L, n_estimated = 1000L, n_cells_nonconverged = 4L,
                                         n_cells_estimated = 100L)), key = "stage2b_convergence_census_v0110", fresh = TRUE)
  expect_match(env$convergence_clause(conv), "did not converge on 5.0% of directly estimated rows (4 of 100 fitted cells)", fixed = TRUE)
})

test_that("A8: the Pillar-1 scripts route boundary cells and keep Tier 3 out of the heterogeneity table", {
  skip_if_not_installed("ggplot2")
  root <- .a7_root()
  for (f in c("01_pillar1_empirical_overview.R", "02_pillar1_sigma_provenance.R", "04_pillar1_heterogeneity.R"))
    skip_if_not(file.exists(file.path(root, "analysis", f)))
  env <- new.env()
  env$OUTPUT_DIR <- tempfile("fig_"); dir.create(file.path(env$OUTPUT_DIR, "tables"), recursive = TRUE)
  on.exit(unlink(env$OUTPUT_DIR, recursive = TRUE), add = TRUE)
  evalq({
    suppressPackageStartupMessages(library(ggplot2))
    theme_paper <- function(base_size = 11) ggplot2::theme_minimal(base_size = base_size)
    save_figure <- function(plot, name, width = 6.5, height = 4.5) invisible(file.path(OUTPUT_DIR, paste0(name, ".pdf")))
    save_table  <- function(x, name) { p <- file.path(OUTPUT_DIR, "tables", paste0(name, ".csv")); data.table::fwrite(x, p); invisible(p) }
    stage1 <- data.table::data.table(importer = as.character(1:10), good = "0101",
                                     adjust = c(0L, 0L, 1L, 4L, 6L, 7L, 8L, 8L, NA, NA),
                                     status = c(rep("ok", 8), "all_inversions_failed", "prep_thin_total"))
    stage1[, sigma := c(2, 3, 2.5, 50, 1.2, 50, 4, 5, NA, NA)]
    stage2b <- data.table::data.table(importer = rep(as.character(1:4), each = 4), exporter = rep(letters[1:4], 4), good = "0101",
                                      tier = rep(c(0L, 1L, 2L, 3L), 4), convergence = rep(c(0L, 0L, 0L, -1L), 4),
                                      gamma = rep(c(0.5, 1.5, 2.5, 9), 4), sigma = 2.4728, sigma_source = "fallback_sigma_pole")
  }, env)
  for (f in c("01_pillar1_empirical_overview.R", "02_pillar1_sigma_provenance.R", "04_pillar1_heterogeneity.R"))
    suppressMessages(sys.source(file.path(root, "analysis", f), envir = env))
  prov <- data.table::fread(file.path(env$OUTPUT_DIR, "tables", "02_pillar1_sigma_provenance.csv"))
  expect_identical(prov[route == "No estimate", n], 2L)                        # only the two non-ok cells
  expect_identical(sum(prov[grepl("^Boundary", route), n]), 4L)
  expect_identical(prov[route == "HLIML interior", n], 2L)
  ch <- data.table::fread(file.path(env$OUTPUT_DIR, "tables", "04_pillar1_gamma_by_hs_chapter.csv"), colClasses = list(character = "hs_chapter"))
  expect_equal(ch$gamma_med_estimated, 1.5)                                    # Tier 3's 9 excluded
  expect_equal(ch$gamma_med_all, 2)                                            # beside the all-rows median
  mad <- data.table::fread(file.path(env$OUTPUT_DIR, "tables", "04_pillar1_within_pair_mad.csv"))
  expect_identical(mad$n_cells, 4L)
  expect_equal(mad$mad_med, 1)
})
