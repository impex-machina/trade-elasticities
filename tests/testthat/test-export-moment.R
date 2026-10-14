# ============================================================================
# test-export-moment.R  (patch 0110)
#
# --stage2-export-moment {share|value}: 'share' (and an absent key) leaves
# prepare_data() bit-identical; 'value' puts log export value in ls_exp, so
# ls_exp_dif = d ln cusval = (share difference) + d ln exporter total, and
# nothing else moves. --stage2a-handoff-rows {all|published}: the
# stage2a_handoff_rows() helper. And the claim behind the value form, on the
# model's primitives: Eq. (11) at the truth misses on export shares when
# gamma_I != gamma_V and holds on export values (an R transcription of the
# C++ export prediction; harness Test F runs the production objective).
# ============================================================================

.em_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  source(file.path(src_dir, "parse_cli.R"), local = FALSE)
  source(file.path(src_dir, "build_config.R"), local = FALSE)
  invisible(TRUE)
}
.em_baci <- function() {
  dir <- file.path(tempdir(), paste0("baci_em_", sample.int(1e6, 1))); dir.create(dir)
  for (yr in 2014:2017) {
    k <- yr - 2013
    d <- data.table(t = yr,
                    i = c(156L, 156L, 156L, 410L, 410L, 410L, 392L, 392L),
                    j = c(840L, 276L, 392L, 840L, 392L, 276L, 840L, 276L),
                    k = "850110",
                    v = c(100 * k, 50 + 7 * k^2, 30, 80 + 3 * k, 30 * k, 40, 60 / k, 20 + k),
                    q = c(10 * k, 5 + k, 3, 8, 3 * k, 4, 6, 2 + k))
    fwrite(d, file.path(dir, sprintf("BACI_HS92_Y%d_V202601.csv", yr)))
  }
  dir
}

test_that("prepare_data(): the default is 'value' (patch 0113); 'value' = log export value in ls_exp", {
  .em_setup(); skip_if_not_installed("optparse")
  dir <- .em_baci(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  base <- c("--data", dir, "--minyear", "2014")
  prep <- function(extra) {
    sink(tempfile()); on.exit(sink(), add = TRUE)
    cfg <- build_config(parse_cli(c(base, extra))); cfg$use_regions <- FALSE   # the runner sets this per stage
    data.table::as.data.table(prepare_data(cfg)$dt)
  }
  d0 <- prep(character(0)); d1 <- prep(c("--stage2-export-moment", "share")); d2 <- prep(c("--stage2-export-moment", "value"))
  expect_identical(d0, d2)                          # patch 0113: value is the default
  expect_gt(nrow(d2), 0L)
  expect_equal(d2$ls_exp, log(d2$cusval))
  for (col in setdiff(names(d1), c("ls_exp", "ls_exp_dif"))) expect_identical(d1[[col]], d2[[col]], info = col)
  k <- c("importer", "exporter", "good", "t")
  m <- merge(d1[, c(k, "ls_exp_dif", "exp_total"), with = FALSE], d2[, c(k, "ls_exp_dif"), with = FALSE], by = k, suffixes = c(".s", ".v"))
  data.table::setorderv(m, k)
  m[, dlnV := log(exp_total) - shift(log(exp_total)), by = .(importer, exporter, good)]
  m[, gap := t - shift(t), by = .(importer, exporter, good)]
  ok <- m$gap %in% 1L & is.finite(m$ls_exp_dif.s)
  expect_gt(sum(ok), 0L)
  expect_equal(m$ls_exp_dif.v[ok], m$ls_exp_dif.s[ok] + m$dlnV[ok], tolerance = 1e-12)
})

test_that("CLI, config and validation for the two patch-0110 flags", {
  .em_setup(); skip_if_not_installed("optparse")
  sink(tempfile()); on.exit(sink(), add = TRUE)
  cfg <- build_config(parse_cli(c("--data", tempdir())))
  expect_identical(cfg$stage2_export_moment, "value"); expect_identical(cfg$stage2a_handoff_rows, "published")   # patch 0113
  cfg2 <- build_config(parse_cli(c("--data", tempdir(), "--stage2-export-moment", "value", "--stage2a-handoff-rows", "published")))
  expect_identical(cfg2$stage2_export_moment, "value"); expect_identical(cfg2$stage2a_handoff_rows, "published")
  expect_error(validate_config(modifyList(cfg, list(stage2_export_moment = "shares"))), "stage2_export_moment")
  expect_error(validate_config(modifyList(cfg, list(stage2a_handoff_rows = "flagged"))), "stage2a_handoff_rows")
  expect_true(any(grepl("stage2_export_moment", deparse(body(.fs_cfg_stamp)), fixed = TRUE)))   # checkpoints see the key
})

test_that("stage2a_handoff_rows(): 'all' is the identity, 'published' drops flagged rows", {
  src <- file.path(locate_source_dir(), "iteration_helpers.R"); source(src, local = TRUE)
  tab <- data.table::data.table(importer = "EAS", exporter = sprintf("x%02d", 1:10), good = "0101", sigma = 2.5,
                                gamma = exp(seq(-2, 2, length.out = 10)), tier = 1L, convergence = 0L,
                                trim_reason = c("gamma_lo", rep(NA, 8), "gamma_hi"))
  expect_identical(stage2a_handoff_rows(tab, "all"), tab)
  expect_identical(stage2a_handoff_rows(tab, NULL), tab)
  pub <- stage2a_handoff_rows(tab, "published")
  expect_equal(nrow(pub), 8L); expect_true(all(is.na(pub$trim_reason)))
  expect_identical(stage2a_handoff_rows(tab[, !"trim_reason"], "published"), tab[, !"trim_reason"])   # drop-mode tables: identity
  expect_error(stage2a_handoff_rows(tab, "flagged"), "rule")
})

test_that("Eq. (11) at the truth on the primitives: misses on shares when gamma_I != gamma_V, holds on values", {
  pred <- function(X, sig, sigV, gI, gV) {        # transcription of het_obj_fixed_sigma_rcpp.cpp, export block (G1 signs)
    sm1 <- sig - 1; iI <- 1 / (1 + gI); iV <- 1 / (1 + gV)
    sum(X * c(gI * iI / sm1, (gI * (sig - 2) - 1) * iI / sm1, gV * iV / sm1, (1 - gV * (sig - 2)) * iV / sm1,
              -(1 - gV * (sigV - 2)) * iV / sm1, -(gI * (sigV - 2) - 1) * iI / sm1,
              -(gV * (1 + gI) + gI * (1 + gV)) * iI * iV / sm1, (sig - sigV) / sm1, (sigV - sig) / sm1))
  }
  sim <- function(gI, gV, AI, AV, Tn = 200000L, D = 6L) {
    set.seed(20261013L)
    n <- Tn + 1L; sig <- rep(3, D); gam <- c(gI, gV, rep(0.8, D - 2L))
    lnA <- matrix(log(c(AI, AV, rep(0.7, D - 2L))), n, D, byrow = TRUE) + matrix(rnorm(n * D, 0, 0.2), n, D)
    lnb <- matrix(rnorm(n * D, 0, 0.4), n, D); eta <- matrix(rnorm(n * D, 0, 0.4), n, D)
    G <- matrix(gam, n, D, byrow = TRUE)
    lnp <- (eta + G * (lnb + lnA)) / (1 + G * 3); lnR <- -2 * lnp + lnb + lnA
    dlV <- diff(log(rowSums(exp(lnR)))); P <- diff(lnp[, 1]); Q <- diff(lnp[, 2])
    r <- function(a, b) { Y <- mean((P - Q)^2)
      abs(Y - pred(c(mean(a*a), mean(a*P), mean(b*b), mean(b*P), mean(b*Q), mean(a*Q), mean(a*b), mean(Q*Q), mean(Q*P)), 3, 3, gI, gV)) / Y }
    c(share = r(diff(lnR[, 1]) - dlV, diff(lnR[, 2]) - dlV), value = r(diff(lnR[, 1]), diff(lnR[, 2])))
  }
  het <- sim(0.3, 1.5, 5, 2)
  expect_gt(het[["share"]], 0.05); expect_lt(het[["value"]], 0.025)
  hom <- sim(0.8, 0.8, 1, 2)                       # gamma_I = gamma_V: the term vanishes, both hold
  expect_lt(hom[["share"]], 0.025); expect_lt(hom[["value"]], 0.025)
})
