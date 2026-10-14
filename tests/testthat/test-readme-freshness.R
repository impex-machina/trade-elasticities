# ============================================================================
# test-readme-freshness.R  (patch 0109)
#
# The README's census freshness guard in scripts/build_readme.R: a census is
# quoted as the shipped table's only when its meta$stage2b_sha256 equals the
# manifest's; otherwise the newest release-tagged census is quoted with its
# vintage (stale_note()). Through patch 0108 the template named the v0.9.0
# census and kept quoting it after v0.10.0. Also the Pillar-2 cap note and the
# Spearman-Brown helper. The helper block is extracted from the script and
# evaluated against a fake manifest.
# ============================================================================

.fr_env <- function(sha_2b) {
  root <- dirname(locate_source_dir())
  src <- readLines(file.path(root, "scripts", "build_readme.R"), warn = FALSE)
  i0 <- grep("# --- Freshness helpers (patch 0109)", src, fixed = TRUE)
  i1 <- grep("# --- end freshness helpers (patch 0109)", src, fixed = TRUE)
  expect_length(i0, 1L); expect_length(i1, 1L)
  env <- new.env(parent = globalenv())
  mf <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(local_path = c("data/derived/stage1/x_feenstra_sigma.rds",
                                             "data/derived/stage2a/x_fixed_sigma.rds",
                                             "data/derived/stage2b/x_fixed_sigma.rds"),
                              hf_url = "u", sha256 = c("aa", "bb", sha_2b)), mf, row.names = FALSE)
  assign("MANIFEST_PATH", mf, envir = env)
  eval(parse(text = src[i0:i1]), envir = env)
  env
}

test_that("release suffixes map to versions", {
  e <- .fr_env("cc")
  expect_identical(e$release_of_suffix("v090"), "v0.9.0")
  expect_identical(e$release_of_suffix("v0101"), "v0.10.1")
  expect_identical(e$release_of_suffix("v083"), "v0.8.3")
})

test_that("the census computed on the shipped table wins; otherwise the newest is quoted with its vintage", {
  e <- .fr_env("CC")
  res <- list(stage2_shrinkage_census_v083 = list(meta = list(), q1 = 1),
              stage2_shrinkage_census_v090 = list(meta = list(stage2b_sha256 = "dd"), q1 = 2),
              stage2_shrinkage_census_v074rc_lambda0.01 = list(meta = list(stage2b_sha256 = "cc"), q1 = 9))
  p <- e$pick_census("stage2_shrinkage_census", res = res)
  expect_identical(p$key, "stage2_shrinkage_census_v090")     # newest tagged; experiment variants never match
  expect_false(p$fresh); expect_identical(p$vintage, "v0.9.0")
  expect_identical(e$stale_note(p), " (census of the v0.9.0 table, not yet re-run on the shipped table)")
  expect_identical(e$stale_note(p, "; ", ""), "; census of the v0.9.0 table, not yet re-run on the shipped table")
  res$stage2_shrinkage_census_v0101 <- list(meta = list(stage2b_sha256 = "cc"), q1 = 3)   # case-insensitive compare
  p <- e$pick_census("stage2_shrinkage_census", res = res)
  expect_identical(p$key, "stage2_shrinkage_census_v0101"); expect_true(p$fresh)
  expect_identical(e$stale_note(p), "")
  res$stage2_shrinkage_census_v0101$meta$stage2b_sha256 <- "ee"         # a later table: stale again
  expect_false(e$pick_census("stage2_shrinkage_census", res = res)$fresh)
})

test_that("an untagged legacy census is used with its declared vintage", {
  e <- .fr_env("cc")
  res <- list(stage2_fallback_census = list(meta = list(csv = "x"), n_cells = 5),
              stage2_fallback_census_v090rc_A = list(meta = list(stage2b_sha256 = "cc")))
  p <- e$pick_census("stage2_fallback_census", legacy = c(stage2_fallback_census = "v0.9.0"), res = res)
  expect_identical(p$key, "stage2_fallback_census"); expect_identical(p$vintage, "v0.9.0"); expect_false(p$fresh)
  res$stage2_fallback_census_v0101 <- list(meta = list(stage2b_sha256 = "cc"), n_cells = 6)
  p <- e$pick_census("stage2_fallback_census", legacy = c(stage2_fallback_census = "v0.9.0"), res = res)
  expect_identical(p$key, "stage2_fallback_census_v0101"); expect_true(p$fresh)
  expect_error(e$pick_census("no_such_census", res = res), "census")
})

test_that("Pillar 2's cap note and Spearman-Brown", {
  e <- .fr_env("cc")
  expect_match(e$pillar2_cap_note(list(), list(sigma_cap = 50)), "cap of 10")
  expect_identical(e$pillar2_cap_note(list(sigma_cap = 50), list(sigma_cap = 50)), "")
  expect_identical(e$pillar2_cap_note(list(sigma_cap = 50), list()), "")      # shipped cap defaults to 50
  expect_equal(e$spearman_brown(0.369), 2 * 0.369 / 1.369)
})

test_that("the README build refuses a shrinkage census on the legacy definition (patch 0112)", {
  e <- .fr_env("cc")
  expect_true(e$shrink_census_ok(list(data = list(meta = list(shrink_wt_def = "half")))))
  expect_false(e$shrink_census_ok(list(data = list(meta = list(shrink_wt_def = "legacy")))))
  expect_false(e$shrink_census_ok(list(data = list(meta = list()))))
  root <- dirname(locate_source_dir())
  sc <- readLines(file.path(root, "analysis", "stage2_shrinkage_census.R"), warn = FALSE)
  expect_true(any(grepl('get_arg("--shrink-wt-def", "half")', sc, fixed = TRUE)))
  expect_true(any(grepl('shrink_wt_def = c("half", "legacy")', sc, fixed = TRUE)))
  br <- readLines(file.path(root, "scripts", "build_readme.R"), warn = FALSE)
  expect_true(any(grepl("if (!shrink_census_ok(render_env$SHRINK))", br, fixed = TRUE)))
})

test_that("Pillar 3's import-constant clause follows the capture (patch 0113)", {
  e <- .fr_env("cc")
  expect_match(e$pillar3_constant_clause(list()), "does not include the import-side constant")
  expect_match(e$pillar3_constant_clause(list(import_constant = FALSE)), "does not include")
  expect_match(e$pillar3_constant_clause(list(import_constant = TRUE)), "concentrated out as the shipped estimator does")
})
