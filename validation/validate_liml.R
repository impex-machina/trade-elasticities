# =========================================================================
# validate_liml.R
#
# Validation harness for liml_estimator.R — no Stata dependency.
#
# Three validation tiers:
#
#   Tier 1: Synthetic recovery battery (self-contained)
#           Tests bias, SE coverage, and consistency on data simulated from
#           the structural model. Three sub-tests at fixed n, varying n,
#           and boundary regions.
#
#   Tier 2: Closed-form sanity checks (self-contained)
#           Properties that must hold regardless of external benchmarks:
#           structural inversion round-trip, exporter relabeling invariance,
#           time shift invariance, kappa range.
#
#   Tier 3: Published-Soderbery comparison (needs BACI + Soderbery file)
#           Run R port on BACI cells overlapping Soderbery 2018 sample,
#           compare marginal distributions. Confounded by data source and
#           estimator differences; tests ballpark agreement only.
#
# Usage:
#   source("liml_estimator.R")
#   source("validate_liml.R")
#   run_standalone_validations()   # Tiers 1 and 2
#   validate_tier3(baci_path = ..., soderbery_path = ..., n_cells = 100)
# =========================================================================

`%||%` <- function(a, b) if (is.null(a)) b else a

.cat_header <- function(txt) {
  bar <- paste(rep("=", 72), collapse = "")
  cat("\n", bar, "\n", txt, "\n", bar, "\n", sep = "")
}

.cat_section <- function(txt) {
  cat("\n--- ", txt, " ---\n", sep = "")
}


# =========================================================================
# SIMULATION DGP
# =========================================================================

simulate_one_cell <- function(sigma_true, omega_true,
                              J = 25, T = 30,
                              sd_eps = 1.0, sd_u = 1.0, sd_meas = 0.3,
                              hetero_range = c(0.5, 2.0),
                              seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  # Reduced form after reference-differencing (cancels phi and aggregate
  # price index). F10 FIX (v0.4.0): the previous version wrote the supply
  # side with slope 1/omega instead of (1+omega)/omega (its D was
  # 1 + (sigma-1)*omega), which made the simulated system identical to the
  # correct structural model at omega = omega_true/(1-omega_true): the
  # omega truth-labels were wrong, while the pseudo-true sigma equaled
  # sigma_true either way. Verified by feeding analytic population moments
  # through estimate_cell_liml: pre-fix data labeled (3, 0.3) returned
  # exactly (3.0000, 0.4286). Correct system, derived from
  #   demand: Dk_s = -(sigma-1)*Dk_p + eps
  #   supply: Dk_s = ((1+omega)/omega)*Dk_p - u/omega
  # =>
  #   Dk_p = (omega*eps + u) / D
  #   Dk_s = ((1+omega)*eps - (sigma-1)*u) / D,   D = 1 + omega*sigma
  # (tests/testthat/test-stage1-harness-dgp.R locks this to the paper.)
  denom <- 1 + omega_true * sigma_true
  a_eps_s <-  (1 + omega_true) / denom
  a_u_s   <- -(sigma_true - 1) / denom
  a_eps_p <-  omega_true / denom
  a_u_p   <-  1 / denom
  
  # IDENTIFICATION REQUIRES heteroskedasticity across exporters: each
  # exporter has its own (sigma_eps_j, sigma_u_j) drawn uniformly from
  # hetero_range. Without this, the cross-exporter moments are linearly
  # dependent and the LIML estimator is unidentified (this matches the
  # Feenstra 1994 identification argument).
  sd_eps_j <- runif(J, hetero_range[1], hetero_range[2]) * sd_eps
  sd_u_j   <- runif(J, hetero_range[1], hetero_range[2]) * sd_u
  
  d_eps <- matrix(rnorm(J * T, sd = rep(sd_eps_j, each = T)),
                  nrow = J, ncol = T, byrow = TRUE)
  d_u   <- matrix(rnorm(J * T, sd = rep(sd_u_j, each = T)),
                  nrow = J, ncol = T, byrow = TRUE)
  d_e   <- matrix(rnorm(J * T, sd = sd_meas), nrow = J, ncol = T)
  
  d_ln_s <- a_eps_s * d_eps + a_u_s * d_u
  d_ln_p <- a_eps_p * d_eps + a_u_p * d_u + d_e
  
  ref_j <- 1L
  non_ref <- setdiff(seq_len(J), ref_j)
  
  out <- data.frame(
    exporter = rep(non_ref, each = T),
    t        = rep(seq_len(T), times = J - 1L)
  )
  out$y  <- as.vector(t(sapply(non_ref,
                               function(j) (d_ln_p[j, ] - d_ln_p[ref_j, ])^2)))
  out$x1 <- as.vector(t(sapply(non_ref,
                               function(j) (d_ln_s[j, ] - d_ln_s[ref_j, ])^2)))
  out$x2 <- as.vector(t(sapply(non_ref,
                               function(j) (d_ln_p[j, ] - d_ln_p[ref_j, ]) *
                                 (d_ln_s[j, ] - d_ln_s[ref_j, ]))))
  out
}


# =========================================================================
# TIER 1: SYNTHETIC RECOVERY BATTERY
# =========================================================================

.tier1_inner <- function(sigma_true, omega_true, n_reps, J, T, seed_base) {
  res <- list(sigmas = rep(NA_real_, n_reps), omegas = rep(NA_real_, n_reps),
              sigma_ses = rep(NA_real_, n_reps), omega_ses = rep(NA_real_, n_reps),
              sigma_cov = rep(NA, n_reps), omega_cov = rep(NA, n_reps),
              fstats = rep(NA_real_, n_reps),
              statuses = character(n_reps))
  for (r in seq_len(n_reps)) {
    mom <- simulate_one_cell(sigma_true, omega_true, J = J, T = T,
                             seed = seed_base + r * 1009L +
                               as.integer(sigma_true * 100) +
                               as.integer(omega_true * 100))
    fit <- estimate_cell_liml(mom, ref_exporter = 1L)
    res$statuses[r] <- fit$status %||% "ok"
    if (isTRUE(fit$status == "ok") && !is.null(fit$sigma) && !is.na(fit$sigma)) {
      res$sigmas[r]    <- fit$sigma
      res$omegas[r]    <- fit$omega
      res$sigma_ses[r] <- fit$sigma_se
      res$omega_ses[r] <- fit$omega_se
      res$fstats[r]    <- fit$fstat_kp
      if (!is.na(fit$sigma_se))
        res$sigma_cov[r] <- abs(fit$sigma - sigma_true) <= 1.96 * fit$sigma_se
      if (!is.na(fit$omega_se))
        res$omega_cov[r] <- abs(fit$omega - omega_true) <= 1.96 * fit$omega_se
    }
  }
  res
}


validate_tier1a <- function(n_reps = 200,
                            sigma_grid = c(2, 3, 5, 8),
                            omega_grid = c(0.3, 1.0, 3.0),
                            J = 25, T = 30,
                            seed_base = 20260511L) {
  .cat_header("TIER 1a: BIAS & SE COVERAGE AT FIXED SAMPLE SIZE")
  cat("Sample size: J =", J, " exporters x T =", T, " periods\n", sep = "")
  cat("Replications per (sigma, omega) pair:", n_reps, "\n\n")
  
  summ <- data.frame()
  for (s_true in sigma_grid) {
    for (o_true in omega_grid) {
      r <- .tier1_inner(s_true, o_true, n_reps, J, T, seed_base)
      n_ok <- sum(!is.na(r$sigmas))
      med_s <- median(r$sigmas, na.rm = TRUE)
      med_o <- median(r$omegas, na.rm = TRUE)
      summ <- rbind(summ, data.frame(
        sigma_true   = s_true,
        omega_true   = o_true,
        success_rate = n_ok / n_reps,
        sigma_med    = med_s,
        sigma_bias   = (med_s - s_true) / s_true,
        omega_med    = med_o,
        omega_bias   = (med_o - o_true) / o_true,
        sigma_cov    = mean(r$sigma_cov, na.rm = TRUE),
        omega_cov    = mean(r$omega_cov, na.rm = TRUE),
        med_fstat    = median(r$fstats, na.rm = TRUE)
      ))
    }
  }
  print(summ, row.names = FALSE, digits = 3)
  
  .cat_section("Tier 1a verdict")
  # PATCHED: tier1_tier2_verdicts — incorporates success_rate into verdict.
  # Bias and coverage are computed CONDITIONAL on the estimator succeeding.
  # Low success rates expose selection bias in those conditional estimates.
  max_bias <- max(abs(c(summ$sigma_bias, summ$omega_bias)), na.rm = TRUE)
  med_coverage <- median(c(summ$sigma_cov, summ$omega_cov), na.rm = TRUE)
  min_success <- min(summ$success_rate, na.rm = TRUE)
  med_success <- median(summ$success_rate, na.rm = TRUE)

  cat(sprintf("  Worst median bias: %.1f%% (CONDITIONAL on estimator success)\n",
              100 * max_bias))
  cat(sprintf("  Median CI coverage: %.0f%% (nominal 95%%)\n", 100 * med_coverage))
  cat(sprintf("  Success rate: min %.0f%%, median %.0f%% across grid\n",
              100 * min_success, 100 * med_success))

  status <- if (max_bias < 0.05 && med_coverage > 0.93 && med_coverage < 0.97 &&
                min_success > 0.70) {
    "PASS"
  } else if (max_bias < 0.15 && med_coverage > 0.88 && med_coverage < 0.99 &&
             min_success > 0.50) {
    "MARGINAL"
  } else {
    "INVESTIGATE"
  }
  cat("  Status:", status, "\n")
  cat("  Notes:\n")
  cat("    - Soderbery 2015/Galstyan 2016 simulations show 5-15% median bias\n")
  cat("      is expected at omega >= 1 even with correct Fuller(1) LIML.\n")
  cat("    - Coverage < 90% likely means SE formula needs investigation.\n")
  cat("    - Success rate < 50% means bias is heavily conditional on a\n")
  cat("      selected subsample; full-sample MSE may be much larger.\n")
  invisible(summ)
}


validate_tier1b <- function(sigma_true = 3, omega_true = 1,
                            J_grid = c(10, 25, 50),
                            T_grid = c(15, 30, 60),
                            n_reps = 100,
                            seed_base = 20260511L) {
  .cat_header("TIER 1b: CONSISTENCY (BIAS vs SAMPLE SIZE)")
  cat("Fixed (sigma, omega) = (", sigma_true, ", ", omega_true, ")\n", sep = "")
  cat("Expectation: median bias decreases as J*T grows.\n\n")
  
  summ <- data.frame()
  for (J in J_grid) {
    for (T in T_grid) {
      r <- .tier1_inner(sigma_true, omega_true, n_reps, J, T, seed_base)
      med_s <- median(r$sigmas, na.rm = TRUE)
      med_o <- median(r$omegas, na.rm = TRUE)
      summ <- rbind(summ, data.frame(
        J = J, T = T, n_obs = J * T,
        sigma_bias = (med_s - sigma_true) / sigma_true,
        omega_bias = (med_o - omega_true) / omega_true,
        success_rate = sum(!is.na(r$sigmas)) / n_reps
      ))
    }
  }
  summ <- summ[order(summ$n_obs), ]
  print(summ, row.names = FALSE, digits = 3)
  
  .cat_section("Tier 1b verdict")
  # PATCHED: tier1_tier2_verdicts — surfaces success-rate trajectory.
  # If success rate falls as n grows, "bias worsens with n" likely
  # reflects increasing selection bias rather than estimator inconsistency.
  small <- summ[which.min(summ$n_obs), ]
  large <- summ[which.max(summ$n_obs), ]
  s_improves <- abs(large$sigma_bias) < abs(small$sigma_bias)
  o_improves <- abs(large$omega_bias) < abs(small$omega_bias)
  success_drops <- large$success_rate < small$success_rate
  if (s_improves && o_improves) {
    cat("  PASS: bias decreases monotonically with sample size.\n")
  } else {
    cat("  INVESTIGATE: bias not monotonically decreasing.\n")
    cat(sprintf("    sigma: %+.1f%% (n=%d) -> %+.1f%% (n=%d): %s\n",
                100 * small$sigma_bias, small$n_obs,
                100 * large$sigma_bias, large$n_obs,
                if (s_improves) "improves" else "WORSENS"))
    cat(sprintf("    omega: %+.1f%% (n=%d) -> %+.1f%% (n=%d): %s\n",
                100 * small$omega_bias, small$n_obs,
                100 * large$omega_bias, large$n_obs,
                if (o_improves) "improves" else "WORSENS"))
    cat(sprintf("    success_rate: %.0f%% (n=%d) -> %.0f%% (n=%d): %s\n",
                100 * small$success_rate, small$n_obs,
                100 * large$success_rate, large$n_obs,
                if (success_drops) "FALLS" else "rises"))
    if (success_drops) {
      cat("    NOTE: success rate falls with n. Bias measured on the\n")
      cat("    successful subsample may reflect selection bias rather\n")
      cat("    than estimator inconsistency. Full-sample MSE is the\n")
      cat("    correct quantity for consistency claims.\n")
    }
  }
  invisible(summ)
}


validate_tier1c <- function(n_reps = 100, J = 25, T = 30,
                            seed_base = 20260511L) {
  .cat_header("TIER 1c: BOUNDARY BEHAVIOR")
  cat("Galstyan 2016 documents poor identification at high sigma or high omega.\n")
  cat("Test that the R port handles these regions without silent failures.\n")
  
  boundary_cases <- data.frame(
    sigma = c(20,  5,   20),
    omega = c(0.1, 10,  10),
    label = c("high_sigma", "high_omega", "both_high")
  )
  
  for (i in seq_len(nrow(boundary_cases))) {
    s_true <- boundary_cases$sigma[i]
    o_true <- boundary_cases$omega[i]
    .cat_section(sprintf("%s: sigma=%.1f, omega=%.1f",
                         boundary_cases$label[i], s_true, o_true))
    r <- .tier1_inner(s_true, o_true, n_reps, J, T, seed_base + i * 100L)
    n_ok <- sum(!is.na(r$sigmas))
    cat(sprintf("  Convergence rate: %d / %d (%.0f%%)\n",
                n_ok, n_reps, 100 * n_ok / n_reps))
    if (n_ok > 0) {
      cat(sprintf("  Sigma  true=%.2f  med=%.3f  IQR=[%.3f, %.3f]\n",
                  s_true, median(r$sigmas, na.rm = TRUE),
                  quantile(r$sigmas, 0.25, na.rm = TRUE),
                  quantile(r$sigmas, 0.75, na.rm = TRUE)))
      cat(sprintf("  Omega  true=%.2f  med=%.3f  IQR=[%.3f, %.3f]\n",
                  o_true, median(r$omegas, na.rm = TRUE),
                  quantile(r$omegas, 0.25, na.rm = TRUE),
                  quantile(r$omegas, 0.75, na.rm = TRUE)))
    }
    cat("  Status breakdown:\n    ")
    print(table(r$statuses))
  }
  cat("\n  Verdict: No pass/fail. Bug indicator: silent NA outputs without\n")
  cat("  status flag, or catastrophic convergence failure (<20%).\n")
  invisible(NULL)
}


validate_tier1 <- function(n_reps = 200) {
  .cat_header("TIER 1: SYNTHETIC RECOVERY BATTERY")
  cat("Running 1a, 1b, 1c in sequence. Total time: a few minutes.\n")
  a <- validate_tier1a(n_reps = n_reps)
  b <- validate_tier1b(n_reps = max(50L, n_reps %/% 2L))
  c <- validate_tier1c(n_reps = max(50L, n_reps %/% 2L))
  invisible(list(tier1a = a, tier1b = b, tier1c = c))
}


# =========================================================================
# TIER 2: CLOSED-FORM SANITY CHECKS
# =========================================================================

validate_tier2 <- function(seed = 20260511L, tol = 1e-8) {
  .cat_header("TIER 2: CLOSED-FORM SANITY CHECKS")
  fails <- character(0)
  
  # --- 2.1 structural inversion round-trips ---
  .cat_section("Test 2.1: structural inversion round-trips")
  # Avoid rho = 0.5 exactly: at that point eta_2 = 0 and the inverse mapping
  # sigma = 1 + (2 rho - 1) / ((1 - rho) eta_2) is 0/0. The structural model
  # is identified there but via a limit, not the closed-form expression.
  test_grid <- expand.grid(sigma = c(2, 3, 5, 8),
                           rho   = c(0.1, 0.3, 0.4, 0.6, 0.7))
  rt_err <- numeric(nrow(test_grid))
  for (i in seq_len(nrow(test_grid))) {
    sig <- test_grid$sigma[i]
    rho <- test_grid$rho[i]
    # Forward map per Galstyan Eq 4:
    eta1 <- rho / ((sig - 1)^2 * (1 - rho))
    eta2 <- (2 * rho - 1) / ((sig - 1) * (1 - rho))
    inv <- invert_structural(eta1, eta2)
    rt_err[i] <- if (is.na(inv$sigma) || is.na(inv$rho)) Inf else
      max(abs(inv$sigma - sig), abs(inv$rho - rho))
  }
  if (max(rt_err) < tol) {
    cat(sprintf("  PASS: max round-trip error = %.2e\n", max(rt_err)))
  } else {
    cat(sprintf("  FAIL: max round-trip error = %.2e (> %.0e)\n",
                max(rt_err), tol))
    fails <- c(fails, "structural_inversion")
  }
  
  # --- 2.2 exporter relabeling invariance ---
  .cat_section("Test 2.2: invariance to exporter ID relabeling")
  set.seed(seed)
  mom1 <- simulate_one_cell(sigma_true = 3, omega_true = 1, J = 25, T = 30,
                            seed = seed)
  fit1 <- estimate_cell_liml(mom1, ref_exporter = 1L)
  mapping <- c(1L, sample(2:25))
  mom2 <- mom1
  mom2$exporter <- mapping[mom1$exporter]
  fit2 <- estimate_cell_liml(mom2, ref_exporter = 1L)
  if (isTRUE(fit1$status == "ok") && isTRUE(fit2$status == "ok")) {
    d_s <- abs(fit1$sigma - fit2$sigma)
    d_o <- abs(fit1$omega - fit2$omega)
    if (max(d_s, d_o) < 1e-8) {
      cat("  PASS: estimates identical under relabeling.\n")
    } else {
      cat(sprintf("  FAIL: sigma diff = %.2e, omega diff = %.2e\n", d_s, d_o))
      fails <- c(fails, "exporter_invariance")
    }
  } else {
    cat("  SKIP: estimation failed on one or both runs.\n")
    fails <- c(fails, "skip:exporter_invariance")
  }
  
  # --- 2.3 time shift invariance ---
  .cat_section("Test 2.3: invariance to time shift")
  mom3 <- mom1
  mom3$t <- mom1$t + 1000L
  fit3 <- estimate_cell_liml(mom3, ref_exporter = 1L)
  if (isTRUE(fit1$status == "ok") && isTRUE(fit3$status == "ok")) {
    d_s <- abs(fit1$sigma - fit3$sigma)
    d_o <- abs(fit1$omega - fit3$omega)
    if (max(d_s, d_o) < 1e-8) {
      cat("  PASS: estimates identical under time shift.\n")
    } else {
      cat(sprintf("  FAIL: sigma diff = %.2e, omega diff = %.2e\n", d_s, d_o))
      fails <- c(fails, "time_invariance")
    }
  } else {
    cat("  SKIP: estimation failed on one or both runs.\n")
    fails <- c(fails, "skip:time_invariance")
  }
  
  # --- 2.4 kappa in valid range ---
  .cat_section("Test 2.4: Fuller kappa in plausible range")
  set.seed(seed + 2L)
  kappas <- numeric(20)
  for (i in seq_len(20)) {
    m <- simulate_one_cell(sigma_true = 3, omega_true = 1, J = 25, T = 30,
                           seed = seed + 100L + i)
    f <- estimate_cell_liml(m, ref_exporter = 1L)
    kappas[i] <- if (isTRUE(f$status == "ok")) f$kappa else NA_real_
  }
  kappas <- kappas[!is.na(kappas)]
  if (length(kappas) > 0 && all(kappas > 0.9) && all(kappas < 5)) {
    cat(sprintf("  PASS: kappa range [%.3f, %.3f], median %.3f\n",
                min(kappas), max(kappas), median(kappas)))
  } else {
    cat("  INVESTIGATE: kappa values:\n    ")
    print(summary(kappas))
    cat("  Expected: kappa slightly > 1 for well-identified Fuller(1) cells.\n")
  }
  
  # --- 2.5 status flags rather than silent NA ---
  .cat_section("Test 2.5: no silent NA from estimator")
  # Construct a degenerate cell: 3 exporters, 2 periods (insufficient)
  bad_mom <- data.frame(
    exporter = c(1L, 1L, 2L, 2L, 3L, 3L),
    t        = c(1L, 2L, 1L, 2L, 1L, 2L),
    y  = rnorm(6)^2, x1 = rnorm(6)^2, x2 = rnorm(6)
  )
  bad_fit <- estimate_cell_liml(bad_mom)
  if (bad_fit$status != "ok" &&
      grepl("fail|invert|singular|insufficient", bad_fit$status)) {
    cat(sprintf("  PASS: degenerate cell flagged with status '%s'\n",
                bad_fit$status))
  } else {
    cat(sprintf("  INVESTIGATE: degenerate cell returned status '%s'\n",
                bad_fit$status))
  }
  
  # --- Verdict ---
  .cat_section("Tier 2 verdict")
  hard_fails <- fails[!grepl("^skip:", fails)]
  skips      <- fails[grepl("^skip:", fails)]
  if (length(hard_fails) == 0 && length(skips) == 0) {
    cat("  PASS: all closed-form sanity checks succeeded.\n")
  } else if (length(hard_fails) == 0 && length(skips) > 0) {
    cat("  INCOMPLETE: some tests skipped because estimation failed on\n")
    cat("  the underlying simulated cell. No hard failures, but coverage\n")
    cat("  is partial. Skipped:", paste(sub("^skip:", "", skips),
                                         collapse = ", "), "\n")
  } else {
    cat("  FAIL:", paste(hard_fails, collapse = ", "), "\n")
    if (length(skips) > 0) {
      cat("  Also skipped:", paste(sub("^skip:", "", skips),
                                    collapse = ", "), "\n")
    }
  }
  invisible(list(fails = hard_fails, skips = skips))
}


# =========================================================================
# TIER 3: COMPARISON AGAINST PUBLISHED SODERBERY 2018
# =========================================================================
#
# IMPORTANT: confounded by:
#   1. BACI vs Comtrade data
#   2. Pure 2015 LIML vs Soderbery 2018 heterogeneous estimator
#   3. Possible sample period differences
# Tests ballpark agreement on marginals, not cell-by-cell decimal match.
# Realistic Spearman target: 0.1 - 0.4.

validate_tier3 <- function(baci_path = NULL,
                           soderbery_path = "Elasticities_Soderbery2018.csv",
                           n_cells = 100,
                           min_year = 1991, max_year = 2007,
                           seed = 20260511L) {
  .cat_header("TIER 3: COMPARISON AGAINST PUBLISHED SODERBERY 2018")
  cat("Note: confounded by data source and estimator differences.\n")
  cat("Target: marginals in right ballpark, Spearman 0.1-0.4.\n")
  
  if (is.null(baci_path) || !file.exists(baci_path)) {
    cat("\nERROR: baci_path not provided or missing.\n")
    cat("Provide BACI HS92 trade flows with columns:\n")
    cat("  importer, exporter, hs (HS6), year, value, quantity\n")
    cat("(.rds or CSV; a directory of BACI_*_Y*_V*.csv files also accepted)\n")
    return(invisible(NULL))
  }
  if (!file.exists(soderbery_path)) {
    cat("\nERROR: Soderbery file missing.\n")
    return(invisible(NULL))
  }
  
  cat("Loading BACI from", baci_path, "...\n")
  baci <- if (grepl("\\.rds$", baci_path, ignore.case = TRUE)) {
    as.data.frame(readRDS(baci_path))
  } else {
    read.csv(baci_path)
  }
  cat("  Loaded", nrow(baci), "rows.\n")
  
  yr_col  <- intersect(c("year", "t", "yr"),                names(baci))[1]
  hs_col  <- intersect(c("hs", "hs6", "k", "product"),      names(baci))[1]
  imp_col <- intersect(c("importer", "iiso", "i", "i_iso"), names(baci))[1]
  exp_col <- intersect(c("exporter", "eiso", "j", "j_iso"), names(baci))[1]
  val_col <- intersect(c("value", "v", "value_kUSD"),       names(baci))[1]
  qty_col <- intersect(c("quantity", "q", "qty"),           names(baci))[1]
  if (any(is.na(c(yr_col, hs_col, imp_col, exp_col, val_col, qty_col))))
    stop("Could not identify BACI columns. Have: ",
         paste(names(baci), collapse = ", "))
  
  baci <- baci[baci[[yr_col]] >= min_year & baci[[yr_col]] <= max_year, ]
  baci$hs4 <- substr(as.character(baci[[hs_col]]), 1, 4)
  cat("  After filtering to ", min_year, "-", max_year, ": ", nrow(baci),
      " rows.\n", sep = "")
  
  # Aggregate to (importer, exporter, hs4, year)
  baci$.imp <- baci[[imp_col]]; baci$.exp <- baci[[exp_col]]
  baci$.val <- baci[[val_col]]; baci$.qty <- baci[[qty_col]]
  baci$.yr  <- baci[[yr_col]]
  agg <- aggregate(cbind(value = baci$.val, quantity = baci$.qty) ~
                     .imp + .exp + hs4 + .yr, data = baci, FUN = sum)
  names(agg)[1:4] <- c("importer", "exporter", "hs4", "year")
  cat("  Aggregated to (importer, exporter, hs4, year):", nrow(agg), "rows.\n")
  
  # Load Soderbery
  sod <- read.csv(soderbery_path)
  sod <- sod[!is.na(sod$sigma) & !is.na(sod$omega), ]
  sod$hs4 <- sprintf("%04d", suppressWarnings(as.integer(sod$hs4)))
  
  agg$cell_id <- paste(agg$importer, agg$hs4, sep = "_")
  sod$cell_id <- paste(sod$iiso, sod$hs4, sep = "_")
  common_cells <- intersect(unique(agg$cell_id), unique(sod$cell_id))
  cat("  Overlapping cells:", length(common_cells), "\n")
  if (length(common_cells) == 0) {
    cat("ERROR: no overlapping cells. Check ISO codes match.\n")
    return(invisible(NULL))
  }
  
  set.seed(seed)
  sampled <- sample(common_cells, min(n_cells, length(common_cells)))
  cat("  Estimating on", length(sampled), "sampled cells...\n")
  
  results <- vector("list", length(sampled))
  pb <- txtProgressBar(min = 0, max = length(sampled), style = 3)
  for (i in seq_along(sampled)) {
    sub <- agg[agg$cell_id == sampled[i], ]
    fit <- tryCatch(
      estimate_elasticities(
        trade_df = data.frame(exporter = sub$exporter, t = sub$year,
                              value = sub$value, quantity = sub$quantity),
        min_year = min_year
      ),
      error = function(e) list(status = paste0("error: ", conditionMessage(e)))
    )
    fit$cell_id <- sampled[i]
    results[[i]] <- fit
    setTxtProgressBar(pb, i)
  }
  close(pb)
  
  ok <- vapply(results, function(r) isTRUE(r$status == "ok"), logical(1))
  .cat_section("Estimation success rate")
  cat(sprintf("  %d / %d cells (%.0f%%)\n",
              sum(ok), length(results), 100 * mean(ok)))
  if (sum(ok) == 0) return(invisible(results))
  
  ok_res <- results[ok]
  rdf <- data.frame(
    cell_id = vapply(ok_res, function(r) r$cell_id, character(1)),
    sigma_r = vapply(ok_res, function(r) r$sigma, numeric(1)),
    omega_r = vapply(ok_res, function(r) r$omega, numeric(1)),
    fstat   = vapply(ok_res, function(r) r$fstat_kp %||% NA_real_, numeric(1))
  )
  sod_summ <- aggregate(cbind(sigma_sod = sod$sigma, omega_sod = sod$omega) ~
                          cell_id, data = sod, FUN = median, na.rm = TRUE)
  comp <- merge(rdf, sod_summ, by = "cell_id")
  cat("  Cells with both estimates:", nrow(comp), "\n")
  
  if (nrow(comp) > 0) {
    .cat_section("Marginal distributions")
    qs <- c(.05, .10, .25, .50, .75, .90, .95)
    out <- data.frame(
      quantile = c("p05","p10","p25","p50","p75","p90","p95"),
      sigma_R     = quantile(comp$sigma_r,   qs, na.rm = TRUE),
      sigma_Soder = quantile(comp$sigma_sod, qs, na.rm = TRUE),
      omega_R     = quantile(comp$omega_r,   qs, na.rm = TRUE),
      omega_Soder = quantile(comp$omega_sod, qs, na.rm = TRUE)
    )
    print(out, row.names = FALSE, digits = 3)
    
    .cat_section("Cell-level agreement")
    sp_s <- cor(comp$sigma_r, comp$sigma_sod, method = "spearman",
                use = "complete.obs")
    sp_o <- cor(comp$omega_r, comp$omega_sod, method = "spearman",
                use = "complete.obs")
    cat(sprintf("  Spearman corr (sigma): %.3f\n", sp_s))
    cat(sprintf("  Spearman corr (omega): %.3f\n", sp_o))
    
    .cat_section("Tier 3 verdict")
    sig_ratio <- median(comp$sigma_r, na.rm = TRUE) /
      median(comp$sigma_sod, na.rm = TRUE)
    omg_ratio <- median(comp$omega_r, na.rm = TRUE) /
      median(comp$omega_sod, na.rm = TRUE)
    cat(sprintf("  Median sigma ratio (R / Soderbery): %.2f\n", sig_ratio))
    cat(sprintf("  Median omega ratio (R / Soderbery): %.2f\n", omg_ratio))
    if (sig_ratio > 0.7 && sig_ratio < 1.4) {
      cat("  PASS: median sigma within +/-40% of Soderbery (plausible given confounds).\n")
    } else if (sig_ratio > 0.5 && sig_ratio < 2.0) {
      cat("  MARGINAL: 40-100% gap. Could be confound or port issue.\n")
    } else {
      cat("  INVESTIGATE: large gap.\n")
    }
    cat("  Spearman 0.1-0.4 is the realistic ceiling given confounds.\n")
  }
  invisible(list(comp = if (nrow(comp) > 0) comp else NULL,
                 all_results = results))
}


# =========================================================================
# CONVENIENCE
# =========================================================================

run_standalone_validations <- function(n_reps = 200) {
  t1 <- validate_tier1(n_reps = n_reps)
  t2 <- validate_tier2()
  cat("\n\nTier 3 requires data. See:\n")
  cat("  validate_tier3(baci_path = ..., soderbery_path = ...)\n")
  invisible(list(tier1 = t1, tier2 = t2))
}

# =========================================================================
# END
# =========================================================================
