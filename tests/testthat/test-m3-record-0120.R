# ============================================================================
# test-m3-record-0120.R  (patch 0120: M3 recorded in the README)
#
# build_readme.R's window_drift_clause() and sigma_window_clause() render the
# patch-0119 censuses (2% subsample) with the reading their numbers support,
# and are empty without them; pick_latest() takes the newest release-tagged
# census; the template carries both clauses.
# ============================================================================

.r20_env <- function() {
  path <- file.path(dirname(locate_source_dir()), "scripts", "build_readme.R"); skip_if_not(file.exists(path))
  env <- new.env()
  for (e in parse(path, keep.source = FALSE))
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function")))
      eval(e, env)
  env
}

test_that("window_drift_clause(): the three readings and the empty case", {
  env <- .r20_env()
  mk <- function(ratio) list(data = list(quantities = list(cell_tariff = list(ratio_robust = ratio))), key = "window_drift_census_v0110")
  expect_identical(env$window_drift_clause(NULL), "")
  expect_match(env$window_drift_clause(mk(1.42)), "by 1.42 times the variance of its odd/even-year difference, below 1.5, so the full-panel average", fixed = TRUE)
  expect_match(env$window_drift_clause(mk(1.8)), "between 1.5 and 2, short of the factor of 2", fixed = TRUE)
  expect_match(env$window_drift_clause(mk(2.6)), "above the factor of 2 at which a 2010\u20132024 estimate describes current conditions better", fixed = TRUE)
})

test_that("sigma_window_clause(): weak reproducibility stated from the numbers, a milder sentence above rho 0.3", {
  env <- .r20_env()
  mk <- function(rho) list(data = list(early_vs_late = list(cells = 1282L, rho = rho, share_change_gt_x2 = 0.6256,
                                                            share_z = list(se_x1 = 0.299, `se_x1.5` = 0.1665))), key = "sigma_window_census_v0110")
  expect_identical(env$sigma_window_clause(NULL), "")
  w <- env$sigma_window_clause(mk(0.0502))
  expect_match(w, "ranks the 1,282 cells clean in both almost independently (rank \u03c1 0.05 on ln(\u03c3 \u2212 1))", fixed = TRUE)
  expect_match(w, "more than a factor of 2 in 62.6% of them", fixed = TRUE)
  expect_match(w, "only 16.7% of the changes exceed 1.96 combined standard errors", fixed = TRUE)
  s <- env$sigma_window_clause(mk(0.62))
  expect_match(s, "ranks the cells clean in both alike (rank \u03c1 0.62", fixed = TRUE)
  expect_false(grepl("weakly", s, fixed = TRUE))
})

test_that("pick_latest() takes the newest release-tagged census; the template carries both clauses", {
  env <- .r20_env()
  res <- list(window_drift_census_v0110 = list(a = 1), window_drift_census_v0102 = list(a = 2), other = 3)
  expect_identical(env$pick_latest("window_drift_census", res = res)$key, "window_drift_census_v0110")
  expect_null(env$pick_latest("sigma_window_census", res = res))
  tpl <- readLines(file.path(dirname(locate_source_dir()), "README.template.md"), warn = FALSE, encoding = "UTF-8")
  expect_true(any(grepl("{{sigma_window_clause(SWIN)}}", tpl, fixed = TRUE)))
  expect_true(any(grepl("{{window_drift_clause(WDRIFT)}}", tpl, fixed = TRUE)))
})
