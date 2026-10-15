# ============================================================================
# test-audit7-0117.R  (patch 0117, fresh-eyes audit #7: M1 / M2 measurements)
#
# Locks the three measurement tools:
#   1. validation/pole_rule_accuracy.R -- population_moments() replays the
#      Pillar-2 simulator's exporter scales (sample means converge to them),
#      omega_given_sigma() returns the true omega at the true sigma, and a
#      grid point's policies are what the design says (P0 exact; P1 / P2
#      differ only on pole-dropped cells; P3 uses the point's median kept
#      estimate);
#   2. analysis/stage2_reliability.R's goods bootstrap: the point equals
#      cor(da, db), intervals bracket it, a large paired difference excludes
#      0, draws are reproducible;
#   3. analysis/sigma_fallback_hierarchy_census.R: the variance share of the
#      good, the leave-one-out ladder beating the global median when sigma
#      varies by good, and the fallback cells' moves.
# ============================================================================

.a17_root <- function() dirname(locate_source_dir())
.a17_stage1_lib <- function() {
  root <- .a17_root()
  for (f in c("R/utils_general.R", "R/hs_codes.R", "R/liml_estimator.R", "validation/validate_liml.R"))
    source(file.path(root, f), local = FALSE)
  env <- new.env(); sys.source(file.path(root, "validation", "pole_rule_accuracy.R"), envir = env); env
}

test_that("pole_rule_accuracy: the population moments replay the simulator and recover omega at the true sigma", {
  env <- .a17_stage1_lib()
  for (st in c(1.2, 3, 8)) for (ot in c(0.3, 3)) {
    pm <- env$population_moments(st, ot, J = 25L, seed = 99L)
    expect_equal(env$omega_given_sigma(pm, st), ot, tolerance = 1e-3)
  }
  expect_true(is.na(env$omega_given_sigma(env$population_moments(2, 1, seed = 1L), 0.9)))
  mom <- simulate_one_cell(2, 1, J = 25, T = 20000, seed = 777L)
  sm <- data.table::as.data.table(mom)[, .(y = mean(y), x1 = mean(x1), x2 = mean(x2)), by = exporter][order(exporter)]
  pm <- env$population_moments(2, 1, J = 25L, seed = 777L)
  expect_identical(sm$exporter, pm$exporter)
  for (v in c("y", "x1")) expect_lt(max(abs(sm[[v]] - pm[[v]])) / mean(abs(pm[[v]])), 0.06)
  expect_gt(cor(sm$x2, pm$x2), 0.999)
})

test_that("pole_rule_accuracy: a grid point's policies follow the design", {
  env <- .a17_stage1_lib()
  d <- env$pole_accuracy_point(1.5, 1, n_reps = 8L, fallback = 2.4728, pole_c = 1, seed_base = 4L)
  expect_identical(nrow(d), 8L)
  expect_true(all(d$sigma_P0 == 1.5)); expect_true(all(abs(d$lr_P0) < 1e-3, na.rm = TRUE))
  expect_true(all(d$sigma_P1[!d$usable] == 2.4728))
  same <- !d$pole_drop
  expect_equal(d$sigma_P1[same], d$sigma_P2[same])
  expect_true(all(d$sigma_P2[d$pole_drop] == 2.4728))
  kept <- d$usable & !d$pole_drop
  if (any(kept)) expect_equal(unique(d$good_fallback), median(d$sigma_hat[kept]))
  expect_true(all(d$sigma_P3[!kept] == d$good_fallback[!kept]))
  sm <- env$pole_accuracy_summary(d)
  expect_identical(nrow(sm$by_point), 1L); expect_identical(sm$by_point$sigma_err_P0, 0)
  expect_true(all(c("tariff_err_P1", "tariff_err_P2", "tariff_err_P3", "pole_drop_share_of_usable") %in% names(sm$by_sigma)))
})

test_that("stage2_reliability: the goods bootstrap reproduces the point and separates a large difference", {
  RELIABILITY_NO_MAIN <- TRUE
  env <- new.env(); assign("RELIABILITY_NO_MAIN", TRUE, envir = env)
  sys.source(file.path(.a17_root(), "analysis", "stage2_reliability.R"), envir = env)
  set.seed(5)
  mk <- function(rho, goods = sprintf("%04d", 1:12)) {
    x <- data.table::rbindlist(lapply(goods, function(g) data.table::rbindlist(lapply(1:6, function(c) {
      n <- 5L; za <- rnorm(n); zb <- rho * za + sqrt(1 - rho^2) * rnorm(n)
      data.table::data.table(good = g, cell = paste(c, g), da = za - mean(za), db = zb - mean(zb))
    }))))
    x
  }
  j2 <- list(strong = mk(0.8), weak = mk(0.1))
  b <- env$goods_bootstrap(j2, B = 400L, seed = 11L, base = "weak")
  tb <- b$table
  expect_equal(tb[config == "strong", r_within], cor(j2$strong$da, j2$strong$db), tolerance = 1e-10)
  expect_true(tb[config == "strong", r_lo <= r_within & r_within <= r_hi])
  expect_gt(tb[config == "strong", delta_lo], 0)
  expect_lt(tb[config == "strong", share_delta_le_0], 0.05)
  expect_true(is.na(tb[config == "weak", delta]))
  b2 <- env$goods_bootstrap(j2, B = 400L, seed = 11L, base = "weak")      # same seed, same draws
  for (cn in c("r_within", "r_lo", "r_hi", "delta", "delta_lo", "delta_hi", "share_delta_le_0")) expect_identical(b2$table[[cn]], b$table[[cn]])
  # split_half_keys() is what split_half_reliability() reports from
  a <- data.table::data.table(importer = "1", exporter = c("a", "b", "c"), good = "0101", tier = 1L, convergence = 0L, gamma = c(1, 2, 4))
  bb <- data.table::copy(a); bb[, gamma := c(1.1, 2.2, 3.5)]
  kk <- env$split_half_keys(a, bb)
  expect_identical(nrow(kk$j2), 3L)
  expect_equal(env$split_half_reliability(a, bb, NULL)$r_within, cor(kk$j2$da, kk$j2$db))
})

test_that("sigma_fallback_hierarchy_census: the good explains sigma; the ladder beats the global median", {
  root <- .a17_root()
  for (f in c("R/utils_general.R", "R/region_map.R", "R/iteration_helpers.R")) source(file.path(root, f), local = FALSE)
  env <- new.env(); sys.source(file.path(root, "analysis", "sigma_fallback_hierarchy_census.R"), envir = env)
  set.seed(8)
  goods <- sprintf("%04d", 1:20); imps <- c(36L, 76L, 124L, 156L, 276L, 251L, 826L, 380L, 392L, 484L, 643L, 842L)
  s1 <- data.table::CJ(importer = imps, good = goods)
  gsig <- setNames(1 + exp(rnorm(length(goods), log(2), 0.8)), goods)
  s1[, sigma := 1 + (gsig[good] - 1) * exp(rnorm(.N, 0, 0.15))]
  s1[, `:=`(status = "ok", convergence = 0L, sigma_se = 0.1 * sigma, sigma_capped = FALSE)]
  s1[sample(.N, 30), sigma_se := 5]                                   # 30 cells the pole rule drops
  s1[, importer := as.character(importer)]
  s2b <- s1[, .(importer, good, exporter = "x", tier = 1L, convergence = 0L)]
  sc <- stage2_sigma_clean(s1, "fallback", "fallback", 1)
  s2b <- merge(s2b, sc$source, by = c("importer", "good"), all.x = TRUE)
  s2b[is.na(sigma_source), sigma_source := "fallback_no_estimate"]
  res <- env$sigma_hierarchy_census(s1, s2b, k = 3L)
  expect_gt(res$r2_good, 0.8)
  expect_lt(res$loo$err_ladder, 0.5 * res$loo$err_global)
  expect_identical(res$fallback$cells, sum(s2b$sigma_source != "estimated"))
  expect_true(res$fallback$cells_move_gt_25pct > 0L)
  expect_equal(res$global_fallback, median(sc$clean$sigma))
})
