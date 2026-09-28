# ============================================================================
# test-stage2-v080-flags.R  (patch 0071 -- v0.8.0 experiment infrastructure)
# Five default-off flags plus the reliability script. Locks:
#   1. prior forms: the objective's penalty equals lambda sum ((d-g)/g)^2
#      (level) and lambda sum (s(d)-s(g))^2 (share); the analytic gradient
#      matches a central difference for every form; the SE ridge curvature
#      is lambda/d^2, lambda/g^2, lambda/(1+d)^4;
#   2. import constant: the objective's import block equals the weighted
#      within-transformed SSR; the gradient matches a central difference;
#      the SE routine spends one df and uses the demeaned J'WJ;
#   3. the reference-exporter export row is accepted with jmap = 2 and the
#      Jacobian places its entry in column 0;
#   4. sample_products is deterministic and exact; CLI/validate/stamp carry
#      the new fields; the defaults (patch 0073: log prior, maxit 500, both
#      moments ON) are what an absent key means, and switching maxit / the
#      moments / the prior away from them changes the fit;
#   5. the reliability script recovers r = 1 on identical halves and lower
#      on perturbed ones.
# ============================================================================

.vf_setup <- function() {
  src_dir <- locate_source_dir(); assert_cpp_files_present(locate_cpp_dir())
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE); invisible(TRUE)
}
.vf_cell <- function(seed = 3L, J = 6L, M = 4L, T_len = 30L, sigma = 3, gam_k = 0.7) {
  set.seed(seed); a <- function(g) (1 + g) / g; gfun <- function(g) g / (1 + g)
  gj <- exp(rnorm(J, log(gam_k), 0.4)); Y <- numeric(J); X <- matrix(0, J, 5)
  for (j in seq_len(J)) { eps <- rnorm(T_len, 0, 0.6); q <- rnorm(T_len, 0, 0.5); dlpk <- rnorm(T_len, 0, 0.4)
    aj <- a(gj[j]); ak <- a(gam_k); Dk_lp <- (eps - q - (aj - ak) * dlpk) / (aj + sigma - 1); Dk_ls <- -(sigma - 1) * Dk_lp + eps; Dlp_j <- Dk_lp + dlpk
    Y[j] <- mean(Dk_lp^2); X[j, ] <- c(mean(Dk_ls^2), mean(Dk_ls * Dk_lp), mean(Dk_ls * Dlp_j), mean(Dk_ls * dlpk), mean(Dk_lp * dlpk)) }
  eY <- numeric(M); eX <- matrix(0, M, 9); gV <- gfun(0.9); sV <- 4
  for (m in seq_len(M)) { gI <- gfun(gj[m]); dlp_V <- rnorm(T_len, 0, 0.4); dls_V <- 0.8 * dlp_V + rnorm(T_len, 0, 0.5); eps <- rnorm(T_len, 0, 0.5); q <- rnorm(T_len, 0, 0.4)
    dls_i <- ((1 + (sigma - 1) * gV) * dls_V + (sV - sigma) * dlp_V - (sigma - 1) * q + eps) / (1 + (sigma - 1) * gI); dlp_i <- dlp_V + gI * dls_i - gV * dls_V + q
    eY[m] <- mean((dlp_i - dlp_V)^2); eX[m, ] <- c(mean(dls_i^2), mean(dls_i * dlp_i), mean(dls_V^2), mean(dls_V * dlp_i), mean(dls_V * dlp_V), mean(dls_i * dlp_V), mean(dls_i * dls_V), mean(dlp_V^2), mean(dlp_V * dlp_i)) }
  list(Y = Y, X = X, eY = eY, eX = eX, jmap = seq_len(M) + 2L, sV = rep(sV, M), gV = rep(0.9, M), wi = runif(J, 0.5, 2), we = rep(1, M),
       gj = gj, sigma = sigma, d = c(gam_k, gj) * exp(rnorm(J + 1L, 0, 0.1)))
}
.obj <- function(d, c, lam, lnp, pf = 0L, ic = FALSE) het_obj_fixed_sigma(d, c$sigma, c$Y, c$X, c$eY, c$eX, c$jmap, c$sV, c$gV, c$wi, c$we, lnp, lam, FALSE, TRUE, pf, ic)
.grd <- function(d, c, lam, lnp, pf = 0L, ic = FALSE) het_grad_fixed_sigma(d, c$sigma, c$Y, c$X, c$eY, c$eX, c$jmap, c$sV, c$gV, c$wi, c$we, lnp, lam, FALSE, TRUE, pf, ic)
.fd <- function(f, d, h = 1e-6) vapply(seq_along(d), function(i) { e <- numeric(length(d)); e[i] <- h; (f(d + e) - f(d - e)) / (2 * h) }, numeric(1))
.jac <- function(d, c) het_residuals_and_jacobian_fixed_sigma_rcpp(d, c$sigma, c$Y, c$X, c$eY, c$eX, c$jmap, c$sV, c$gV, c$wi, c$we, FALSE)

test_that("prior forms: closed-form penalties, gradients vs central differences, SE curvature", {
  .vf_setup(); c <- .vf_cell(); lam <- 0.1; lnp <- log(0.7); g <- 0.7; d <- c$d
  base <- .obj(d, c, 0, NA_real_)
  expect_equal(.obj(d, c, lam, lnp, 0L) - base, lam * sum((log(d) - lnp)^2), tolerance = 1e-10)
  expect_equal(.obj(d, c, lam, lnp, 1L) - base, lam * sum(((d - g) / g)^2), tolerance = 1e-10)
  expect_equal(.obj(d, c, lam, lnp, 2L) - base, lam * sum((d / (1 + d) - g / (1 + g))^2), tolerance = 1e-10)
  # level and share are finite at gamma = 0 (log is not defined there)
  d0 <- d; d0[3] <- 0
  expect_true(is.finite(.obj(d0, c, lam, lnp, 1L)) && is.finite(.obj(d0, c, lam, lnp, 2L)))
  for (pf in 0:2) expect_equal(.grd(d, c, lam, lnp, pf), .fd(function(x) .obj(x, c, lam, lnp, pf), d), tolerance = 1e-5, info = paste("form", pf))
  # SE ridge curvature per form (half-objective units under sandwich)
  cur <- function(pf) .ridge_curvature(d, lam, lnp, pf, 1)
  expect_equal(cur(0L), lam / d^2); expect_equal(cur(1L), rep(lam / g^2, length(d))); expect_equal(cur(2L), lam / (1 + d)^4)
  se_l <- compute_penalized_gn_se(d, c$sigma, c$Y, c$X, c$eY, c$eX, c$jmap, c$sV, c$gV, c$wi, c$we, shrinkage_lambda = lam, ln_gamma_prior = lnp, prior_form = 1L)
  expect_true(all(se_l$status == "ok")); expect_true(all(is.finite(se_l$se)))
})

test_that("import constant: within-transformed import SSR, gradient, and one df", {
  .vf_setup(); c <- .vf_cell(); lam <- 0.1; lnp <- log(0.7); d <- c$d; J <- length(c$Y)
  o_off <- .obj(d, c, 0, NA_real_, 0L, FALSE); o_on <- .obj(d, c, 0, NA_real_, 0L, TRUE)
  jac <- .jac(d, c); ri <- jac$residuals[seq_len(J)]; wi <- jac$weights[seq_len(J)]; rbar <- sum(wi * ri) / sum(wi)
  expect_equal(o_off - o_on, sum(wi * ri^2) - sum(wi * (ri - rbar)^2), tolerance = 1e-10)
  expect_equal(.grd(d, c, lam, lnp, 0L, TRUE), .fd(function(x) .obj(x, c, lam, lnp, 0L, TRUE), d), tolerance = 1e-5)
  se_off <- compute_penalized_gn_se(d, c$sigma, c$Y, c$X, c$eY, c$eX, c$jmap, c$sV, c$gV, c$wi, c$we, shrinkage_lambda = lam, ln_gamma_prior = lnp)
  se_on  <- compute_penalized_gn_se(d, c$sigma, c$Y, c$X, c$eY, c$eX, c$jmap, c$sV, c$gV, c$wi, c$we, shrinkage_lambda = lam, ln_gamma_prior = lnp, import_constant = TRUE)
  expect_true(all(se_on$status == "ok")); expect_false(isTRUE(all.equal(se_on$se, se_off$se)))
  # demeaned J'WJ from a dense reconstruction
  K <- length(d); Jm <- matrix(0, length(jac$residuals), K); for (t in seq_along(jac$jac_row)) Jm[jac$jac_row[t] + 1L, jac$jac_col[t] + 1L] <- jac$jac_val[t]
  Jd <- Jm; jbar <- colSums(wi * Jm[seq_len(J), , drop = FALSE]) / sum(wi); Jd[seq_len(J), ] <- sweep(Jm[seq_len(J), , drop = FALSE], 2, jbar)
  mb <- .import_block_means(jac$jac_row + 1L, jac$jac_col + 1L, jac$jac_val, jac$weights, J, K)
  expect_equal(crossprod(Jm, jac$weights * Jm) - mb$sw * tcrossprod(mb$jbar), crossprod(Jd, jac$weights * Jd), tolerance = 1e-10)
  # exactly one df fewer: with M = K - J + 1 export rows the unconstrained df is M - 1
  c2 <- c; c2$eY <- c$eY[1:2]; c2$eX <- c$eX[1:2, , drop = FALSE]; c2$jmap <- c$jmap[1:2]; c2$sV <- c$sV[1:2]; c2$gV <- c$gV[1:2]; c2$we <- c$we[1:2]
  s_off <- compute_penalized_gn_se(d, c2$sigma, c2$Y, c2$X, c2$eY, c2$eX, c2$jmap, c2$sV, c2$gV, c2$wi, c2$we, shrinkage_lambda = lam, ln_gamma_prior = lnp)
  s_on  <- compute_penalized_gn_se(d, c2$sigma, c2$Y, c2$X, c2$eY, c2$eX, c2$jmap, c2$sV, c2$gV, c2$wi, c2$we, shrinkage_lambda = lam, ln_gamma_prior = lnp, import_constant = TRUE)
  expect_true(all(s_off$status == "ok")); expect_true(all(s_on$status == "insufficient_df"))
})

test_that("the reference exporter's export row maps to column 0", {
  .vf_setup(); c <- .vf_cell(); d <- c$d
  c$jmap[1] <- 2L                                   # first export row now belongs to gamma_k
  jac <- .jac(d, c); J <- length(c$Y)
  expect_identical(jac$status, "ok")
  expect_true(any(jac$jac_row == J & jac$jac_col == 0L))   # 0-based: export row 0 is row J, column 0
  expect_true(is.finite(.obj(d, c, 0.1, log(0.7))))
  expect_equal(.grd(d, c, 0.1, log(0.7)), .fd(function(x) .obj(x, c, 0.1, log(0.7)), d), tolerance = 1e-5)
})

test_that("sample_products, CLI, validate_config and the stamp carry the new fields; defaults bit-preserving; flags change the fit", {
  .vf_setup(); skip_if_not_installed("optparse")
  goods <- sprintf("%04d", 1001:1100)
  s1 <- sample_products(goods, 0.1, 7L); s2 <- sample_products(goods, 0.1, 7L); s3 <- sample_products(goods, 0.1, 8L)
  expect_identical(s1, s2); expect_length(s1, 10L); expect_true(all(s1 %in% goods)); expect_false(identical(s1, s3))
  expect_identical(sample_products(goods, 1, 7L), goods); expect_error(sample_products(goods, 0, 7L))
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_vf_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE); on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  o <- parse_cli(c("--data", fake, "--stage2-prior", "share", "--stage2-maxit", "2000", "--stage2-ref-export-moment", "on", "--stage2-import-constant", "on", "--product-sample", "0.02", "--product-seed", "5"))
  expect_identical(o$stage2_prior, "share"); expect_equal(o$stage2_maxit, 2000L); expect_identical(o$stage2_ref_export_moment, "on"); expect_identical(o$stage2_import_constant, "on"); expect_equal(o$product_sample, 0.02)
  d <- parse_cli(c("--data", fake)); expect_identical(d$stage2_prior, "log"); expect_equal(d$stage2_maxit, 500L); expect_equal(d$product_sample, 1)
  expect_identical(d$stage2_ref_export_moment, "on"); expect_identical(d$stage2_import_constant, "on")   # patch 0073 defaults
  expect_error(parse_cli(c("--data", fake, "--stage2-prior", "flat")), "stage2-prior"); expect_error(parse_cli(c("--data", fake, "--product-sample", "1.5")), "product-sample")
  cfg <- make_synthetic_cfg(); dt <- make_synthetic_baci(seed = 42L)
  cfg_bad <- cfg; cfg_bad$stage2_prior <- "flat"; expect_error(validate_config(cfg_bad), "stage2_prior")
  cfg_x <- cfg; cfg_x$stage2_prior <- "level"; expect_false(identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_x, dt)))
  cfg_d <- cfg; cfg_d$stage2_prior <- "log"; cfg_d$stage2_maxit <- 500L; cfg_d$stage2_ref_export_moment <- "on"; cfg_d$stage2_import_constant <- "on"
  expect_identical(.fs_cfg_stamp(cfg, dt), .fs_cfg_stamp(cfg_d, dt))
  run <- function(cfg) { r <- NULL; suppressMessages(suppressWarnings(capture.output(r <- estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt), type = "output"))); finalize_saved_output(r) }
  r_def <- run(cfg); expect_identical(r_def, run(cfg_d))
  for (nm in c("stage2_prior", "stage2_ref_export_moment", "stage2_import_constant", "stage2_maxit")) {
    cfg_v <- cfg; cfg_v[[nm]] <- switch(nm, stage2_prior = "level", stage2_ref_export_moment = "off", stage2_import_constant = "off", stage2_maxit = 2L)
    r_v <- run(cfg_v)
    expect_setequal(names(r_v), names(r_def)); expect_false(identical(r_v$gamma, r_def$gamma), info = nm)
  }
})

test_that("the reliability script scores identical halves at r = 1 and perturbed halves lower", {
  env <- new.env(parent = globalenv()); assign("RELIABILITY_NO_MAIN", TRUE, envir = env)
  sys.source(file.path(dirname(locate_source_dir()), "analysis", "stage2_reliability.R"), envir = env)
  set.seed(9); goods <- sprintf("%04d", 1001:1003); lnp <- c(-0.3, 0, 0.3); names(lnp) <- goods
  mk <- function(noise) { rows <- list(); for (g in goods) for (imp in as.character(1:6)) { n <- 8L; tier <- c(0L, rep(1L, 6), 3L)
    base <- lnp[[g]] + c(0, seq(-0.6, 0.6, length.out = 6), 0)
    rows[[length(rows) + 1L]] <- data.table::data.table(importer = imp, exporter = sprintf("%d", 100 + 1:n), good = g, gamma = exp(base + rnorm(n, 0, noise)),
      gamma_shrink_wt = 0.5, tier = tier, convergence = ifelse(tier < 3L, 0L, -1L), gamma_se_status = ifelse(tier < 3L, "ok", "tier3_prior"), opt_tariff = exp(lnp[[g]])) }
    data.table::rbindlist(rows) }
  priors <- data.table::data.table(good = goods, ln_gamma_prior = unname(lnp))
  A <- mk(0); B <- mk(0)
  r0 <- env$split_half_reliability(A, B, priors); expect_equal(r0$r_within, 1, tolerance = 1e-12); expect_equal(r0$rho_rank, 1, tolerance = 1e-12)
  r1 <- env$split_half_reliability(mk(0.5), mk(0.5), priors); expect_lt(r1$r_within, 0.95); expect_gt(r1$n_keys, 50)
  s <- env$reliability_summary(A, priors); expect_equal(s$share_non_converged, 0); expect_true(is.finite(s$within_cell_sd_median))
  runs <- data.table::data.table(config = c("c1", "c1", "c1"), split = c("full", "A", "B"), path = c(tempfile(fileext = ".rds"), tempfile(fileext = ".rds"), tempfile(fileext = ".rds")))
  saveRDS(A, runs$path[1]); saveRDS(A, runs$path[2]); saveRDS(B, runs$path[3])
  rep <- env$reliability_report(runs, priors); expect_equal(nrow(rep$full), 1L); expect_equal(rep$split$r_within[1], 1, tolerance = 1e-12)
})
