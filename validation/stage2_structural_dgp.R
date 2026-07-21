# =============================================================================
# validation/stage2_structural_dgp.R
#
# Structural-DGP validation of the Stage 2 import-side moment equation
# (Soderbery 2018, Eq. 10). Added in v0.4.0 after an audit found that the
# implemented Eq. (10) term-4 coefficient deviated from the paper -- a
# defect the existing validation stack could not detect, because Pillar 3's
# Monte Carlo generates its truth FROM the production residual routine and
# is therefore self-consistent by construction.
#
# This pillar closes that gap. The data-generating process below is written
# directly from the paper's structural equations and NEVER calls pipeline
# code to generate truth:
#
#   Demand (Eq. 5):  Dk_ls_j = -(sigma - 1) * Dk_lp_j + eps_j
#   Supply (Eq. 6):  q_j     = Dk_ls_j - a_j * Dlp_j + a_k * Dlp_k,
#                    with a_x = (1 + gamma_x) / gamma_x
#
# with eps (taste), q (supply), and Dlp_k (the reference exporter's own
# price change) mutually independent mean-zero shocks. Solving the two
# equations for the equilibrium double-differenced price change:
#
#   Dk_lp_j = (eps_j - q_j - (a_j - a_k) * Dlp_k) / (a_j + sigma - 1)
#
# Moments are then time-averaged per exporter exactly as the pipeline does,
# and the PRODUCTION objective (het_obj_fixed_sigma_rcpp, or the pure-R
# het_obj fallback) is evaluated at the TRUE parameters. If the implemented
# moment equation is the model's Eq. (10), the population residual is zero
# up to O(1/sqrt(T)) simulation noise; any drift in the coefficients shows
# up as a residual of the order of the outcome itself (the audited bug
# produced ~55% of the outcome scale).
#
# Tests:
#   A. Moment identity at truth across a (sigma x gamma_k) grid, plus a
#      negative control (deliberately perturbed gammas) proving the test
#      has power to detect misspecification.
#   B. Per-exporter gamma recovery with gamma_k fixed at truth.
#   C. Joint recovery of (gamma_k, gamma_j) from neutral starts via
#      L-BFGS-B, mirroring the pipeline's optimizer.
#
# G2 (v0.4.1): export-side coverage. The v0.4.0 harness passed empty export
# matrices, leaving Eq. (11) unvalidated -- the same gap class that let the
# Eq. (10) term-4 bug live for three releases. The audit that closed it also
# established that the x5/x6 coefficients as PRINTED in Soderbery (2018)
# Eq. (11) are sign-flipped relative to the product of the paper's own
# Eq. (8) and Eq. (9) residuals (see
# docs/methodology/eq11_sign_correction.md). Two tests are added:
#   D. Export-side moment identity at truth (corrected signs), written
#      directly from Eqs. (8)-(9); the negative control is the PRINTED
#      equation itself (paper_exact_eq11 = TRUE), which must miss by a
#      clear margin -- so any regression toward the printed signs fails CI.
#   E. Joint per-exporter gamma recovery from import + export rows
#      together, mirroring a Tier-1 cell.
#
# Usage (from the repo root):
#   Rscript validation/stage2_structural_dgp.R              # full (T = 1e6)
#   Rscript validation/stage2_structural_dgp.R --quick      # T = 1e5
#   Rscript validation/stage2_structural_dgp.R --seed 42 --out results/stage2_dgp_summary.json
#
# G2 (v0.4.1): with --quick and no explicit --out, the summary goes to
# results/stage2_dgp_summary_quick.json so a casual quick run can no longer
# overwrite the committed full-run artifact.
#
# Writes results/stage2_dgp_summary.json (requires jsonlite; falls back to
# a plain-text summary otherwise). Exits nonzero on any FAIL so the script
# can gate CI or a release checklist. The fast regression version of Test A
# runs on every test invocation via
# tests/testthat/test-stage2-structural-dgp.R.
# =============================================================================

if (!file.exists("src/het_obj.R")) {
  stop("Run from the repo root (where src/ lives).")
}

# ---- lightweight CLI --------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
opt_quick <- "--quick" %in% args
opt_seed  <- 20260717L
opt_out   <- "results/stage2_dgp_summary.json"
opt_out_given <- FALSE
if (length(w <- which(args == "--seed")) == 1L && length(args) > w)
  opt_seed <- as.integer(args[w + 1L])
if (length(w <- which(args == "--out")) == 1L && length(args) > w) {
  opt_out <- args[w + 1L]
  opt_out_given <- TRUE
}
# G2 (v0.4.1): protect the committed full-run artifact from quick runs.
if (opt_quick && !opt_out_given)
  opt_out <- "results/stage2_dgp_summary_quick.json"
opt_json <- !("--no-json" %in% args)

T_len  <- if (opt_quick) 1e5 else 1e6
tol_A  <- if (opt_quick) 0.05 else 0.02   # max |resid| / mean(Y) at truth
tol_B  <- if (opt_quick) 0.10 else 0.05   # median |gamma bias|, 1-D recovery
tol_C  <- if (opt_quick) 0.10 else 0.05   # median |gamma_j bias|, joint fit
tol_D  <- if (opt_quick) 0.05 else 0.02   # max |resid| / mean(Y), export side
tol_E  <- if (opt_quick) 0.10 else 0.05   # median |gamma bias|, imp+exp 1-D
POWER_MULT <- 5   # negative control must exceed POWER_MULT x its own truth
                  # ratio at every grid point (and the tol_A floor): the
                  # absolute size of a fixed perturbation's residual shrinks
                  # at high sigma / high gamma_k, so power is judged as
                  # separation from truth, not on an absolute scale.

set.seed(opt_seed)

# ---- load the PRODUCTION objective -----------------------------------------
# Prefer the compiled fixed-sigma objective; fall back to the pure-R
# reference implementation (src/het_obj.R) which shares the same Eq. (10)
# coefficients. Either way, the object under test is production code.
load_objective <- function() {
  if (requireNamespace("Rcpp", quietly = TRUE)) {
    ok <- tryCatch({
      Rcpp::sourceCpp("src/het_obj_fixed_sigma_rcpp.cpp")
      TRUE
    }, error = function(e) FALSE)
    if (ok) {
      # G2 (v0.4.1): full objective including export rows and the Eq. (11)
      # sign switch (paper_exact = TRUE reproduces the printed equation).
      f_full <- function(d, sigma, imp_Y, imp_X, wt_imp,
                         exp_Y, exp_X, exp_jmap, sig_V, gam_V, wt_exp,
                         paper_exact = FALSE) {
        het_obj_fixed_sigma_rcpp(d, sigma, imp_Y, imp_X,
                                 exp_Y, exp_X, exp_jmap, sig_V, gam_V,
                                 wt_imp, wt_exp, NA_real_, 0, paper_exact)
      }
      f <- function(d, sigma, imp_Y, imp_X, wt_imp) {
        f_full(d, sigma, imp_Y, imp_X, wt_imp,
               numeric(0), matrix(0, 0, 9), integer(0),
               numeric(0), numeric(0), numeric(0))
      }
      return(list(fun = f, fun_full = f_full, engine = "rcpp"))
    }
  }
  source("src/het_obj.R")
  f_full <- function(d, sigma, imp_Y, imp_X, wt_imp,
                     exp_Y, exp_X, exp_jmap, sig_V, gam_V, wt_exp,
                     paper_exact = FALSE) {
    het_obj(c(sigma, d), imp_Y, imp_X,
            exp_Y, exp_X, exp_jmap, sig_V, gam_V, wt_imp, wt_exp,
            paper_exact_eq11 = paper_exact)
  }
  f <- function(d, sigma, imp_Y, imp_X, wt_imp) {
    f_full(d, sigma, imp_Y, imp_X, wt_imp,
           numeric(0), matrix(0, 0, 9), integer(0),
           numeric(0), numeric(0), numeric(0))
  }
  list(fun = f, fun_full = f_full, engine = "pure-R")
}
obj <- load_objective()
cat(sprintf("Objective engine: %s | T per exporter: %s | seed: %d\n",
            obj$engine, format(T_len, big.mark = ","), opt_seed))

# ---- structural DGP (Eqs 5-6; independent of all pipeline code) ------------
simulate_cell_moments <- function(sigma, gam_k, gam_j, T_len,
                                  sd_eps = 0.6, sd_q = 0.5, sd_pk = 0.4) {
  a <- function(g) (1 + g) / g
  J <- length(gam_j)
  Y <- numeric(J)
  X <- matrix(0, J, 5)
  for (j in seq_len(J)) {
    eps  <- rnorm(T_len, 0, sd_eps)
    q    <- rnorm(T_len, 0, sd_q)
    dlpk <- rnorm(T_len, 0, sd_pk)
    aj <- a(gam_j[j]); ak <- a(gam_k)
    Dk_lp <- (eps - q - (aj - ak) * dlpk) / (aj + sigma - 1)
    Dk_ls <- -(sigma - 1) * Dk_lp + eps
    Dlp_j <- Dk_lp + dlpk
    Y[j]  <- mean(Dk_lp^2)
    X[j, ] <- c(mean(Dk_ls^2), mean(Dk_ls * Dk_lp), mean(Dk_ls * Dlp_j),
                mean(Dk_ls * dlpk), mean(Dk_lp * dlpk))
  }
  list(Y = Y, X = X)
}

resid_ratio <- function(d, sigma, mom, J) {
  # RMS residual (via the production SSR) relative to the outcome scale.
  sqrt(obj$fun(d, sigma, mom$Y, mom$X, rep(1, J)) / J) / mean(mom$Y)
}

# ---- Test A: moment identity at truth + negative control -------------------
cat("\n== Test A: moment identity at TRUE parameters (grid) ==\n")
grid <- expand.grid(sigma = c(2, 3, 5), gam_k = c(0.3, 0.7, 1.5))
J_A <- 10L
rowsA <- vector("list", nrow(grid))
for (g in seq_len(nrow(grid))) {
  sg <- grid$sigma[g]; gk <- grid$gam_k[g]
  gj <- exp(rnorm(J_A, log(gk), 0.5))
  mom <- simulate_cell_moments(sg, gk, gj, T_len)
  r_true <- resid_ratio(c(gk, gj), sg, mom, J_A)
  r_pert <- resid_ratio(c(gk, gj * 1.25), sg, mom, J_A)  # negative control
  rowsA[[g]] <- data.frame(sigma = sg, gam_k = gk,
                           resid_ratio_true = r_true,
                           resid_ratio_perturbed = r_pert)
  cat(sprintf("  sigma=%.1f gam_k=%.1f : resid/Y at truth = %.4f | perturbed = %.3f\n",
              sg, gk, r_true, r_pert))
}
A <- do.call(rbind, rowsA)
passA_true  <- max(A$resid_ratio_true) < tol_A
sep         <- A$resid_ratio_perturbed / A$resid_ratio_true
passA_power <- all(A$resid_ratio_perturbed > pmax(POWER_MULT * A$resid_ratio_true, tol_A))
cat(sprintf("  A verdict: max truth ratio %.4f < %.2f -> %s | min separation %.1fx (need > %dx and > tol_A) -> %s\n",
            max(A$resid_ratio_true), tol_A, ifelse(passA_true, "PASS", "FAIL"),
            min(sep), POWER_MULT, ifelse(passA_power, "PASS", "FAIL")))

# ---- Test B: per-exporter recovery, gamma_k fixed at truth -----------------
cat("\n== Test B: per-exporter gamma recovery (gamma_k fixed at truth) ==\n")
sg <- 3; gk <- 0.7; J_B <- 12L
gj <- exp(rnorm(J_B, log(gk), 0.5))
momB <- simulate_cell_moments(sg, gk, gj, T_len)
est_1d <- vapply(seq_len(J_B), function(j) {
  f <- function(g) {
    dd <- c(gk, gj); dd[j + 1L] <- g
    obj$fun(dd, sg, momB$Y, momB$X, rep(1, J_B))
  }
  optimize(f, c(1e-4, 50))$minimum
}, numeric(1))
biasB <- median(abs(est_1d / gj - 1))
passB <- biasB < tol_B
cat(sprintf("  median |gamma bias| = %.3f (tol %.2f) -> %s\n",
            biasB, tol_B, ifelse(passB, "PASS", "FAIL")))

# ---- Test C: joint recovery from neutral starts ----------------------------
cat("\n== Test C: joint (gamma_k, gamma_j) recovery, L-BFGS-B ==\n")
fitC <- optim(rep(gk, J_B + 1L),
              function(d) obj$fun(d, sg, momB$Y, momB$X, rep(1, J_B)),
              method = "L-BFGS-B", lower = rep(1e-6, J_B + 1L))
biasC_k <- abs(fitC$par[1] / gk - 1)
biasC_j <- median(abs(fitC$par[-1] / gj - 1))
passC <- (fitC$convergence == 0L) && (biasC_j < tol_C) && (biasC_k < 2 * tol_C)
cat(sprintf("  gam_k %.3f (true %.3f, |bias| %.3f) | median |gam_j bias| %.3f | conv %d -> %s\n",
            fitC$par[1], gk, biasC_k, biasC_j, fitC$convergence,
            ifelse(passC, "PASS", "FAIL")))

# ---- export-side structural DGP (Eqs 8-9; independent of pipeline code) ----
# Per period, the reference-destination processes (Dls_V, Dlp_V) are
# exogenous (a slope links them so BOTH x5 = Dls_V*Dlp_V and
# x6 = Dls_i*Dlp_V discriminating moments are active); eps (destination
# taste) and q (supply) are independent shocks. Solving the printed
# Eq. (8) supply and Eq. (9) demand curves for the focal destination:
#
#   Dls_i = ( (1 + (sigma-1)*g_V) * Dls_V + (sigma_V - sigma) * Dlp_V
#             - (sigma - 1) * q + eps ) / (1 + (sigma-1)*g_I)
#   Dlp_i = Dlp_V + g_I * Dls_i - g_V * Dls_V + q,   g_x = gam_x/(1+gam_x)
#
# The moment identity Y = sum(c_m x_m) + q*eps/(sigma-1) is then an exact
# algebraic consequence of the two curves -- for ANY distribution of the
# exogenous block -- iff the c_m are the derivation-consistent (G1)
# coefficients. E[q*eps] = 0 makes the population residual zero.
simulate_export_moments <- function(sigma, sigma_V, gam_I_vec, gam_V, T_len,
                                    sd_eps = 0.5, sd_q = 0.4,
                                    sd_pV = 0.4, sd_sV = 0.5, slope_V = 0.8) {
  gfun <- function(g) g / (1 + g)
  M <- length(gam_I_vec)
  Y <- numeric(M); X <- matrix(0, M, 9)
  gV <- gfun(gam_V)
  for (m in seq_len(M)) {
    gI    <- gfun(gam_I_vec[m])
    dlp_V <- rnorm(T_len, 0, sd_pV)
    dls_V <- slope_V * dlp_V + rnorm(T_len, 0, sd_sV)
    eps   <- rnorm(T_len, 0, sd_eps)
    q     <- rnorm(T_len, 0, sd_q)
    dls_i <- ((1 + (sigma - 1) * gV) * dls_V + (sigma_V - sigma) * dlp_V -
                (sigma - 1) * q + eps) / (1 + (sigma - 1) * gI)
    dlp_i <- dlp_V + gI * dls_i - gV * dls_V + q
    Y[m]  <- mean((dlp_i - dlp_V)^2)
    X[m, ] <- c(mean(dls_i^2),        mean(dls_i * dlp_i),
                mean(dls_V^2),        mean(dls_V * dlp_i),
                mean(dls_V * dlp_V),  mean(dls_i * dlp_V),
                mean(dls_i * dls_V),  mean(dlp_V^2),
                mean(dlp_V * dlp_i))
  }
  list(Y = Y, X = X)
}

exp_resid_ratio <- function(gam_I_vec, sigma, sigma_V, gam_V, mom,
                            paper_exact = FALSE) {
  M <- length(gam_I_vec)
  d <- c(0.7, gam_I_vec)                # gam_k placeholder; no import rows
  ssr <- obj$fun_full(d, sigma,
                      numeric(0), matrix(0, 0, 5), numeric(0),
                      mom$Y, mom$X, seq_len(M) + 2L,
                      rep(sigma_V, M), rep(gam_V, M), rep(1, M),
                      paper_exact = paper_exact)
  sqrt(ssr / M) / mean(mom$Y)
}

# ---- Test D: export moment identity at truth; printed signs as control ----
cat("\n== Test D: EXPORT moment identity at truth (Eq. 11, corrected signs) ==\n")
gridD <- expand.grid(sigma = c(2.5, 4), sigma_V = c(3, 5), gam_V = c(0.9))
J_D <- 8L
rowsD <- vector("list", nrow(gridD))
for (g in seq_len(nrow(gridD))) {
  sg <- gridD$sigma[g]; sV <- gridD$sigma_V[g]; gV <- gridD$gam_V[g]
  gI <- exp(rnorm(J_D, log(0.7), 0.5))
  momD <- simulate_export_moments(sg, sV, gI, gV, T_len)
  r_true    <- exp_resid_ratio(gI, sg, sV, gV, momD, paper_exact = FALSE)
  r_printed <- exp_resid_ratio(gI, sg, sV, gV, momD, paper_exact = TRUE)
  rowsD[[g]] <- data.frame(sigma = sg, sigma_V = sV, gam_V = gV,
                           resid_ratio_true = r_true,
                           resid_ratio_printed = r_printed)
  cat(sprintf("  sigma=%.1f sigma_V=%.1f : resid/Y corrected = %.4f | printed Eq.(11) = %.3f\n",
              sg, sV, r_true, r_printed))
}
D <- do.call(rbind, rowsD)
passD_true  <- max(D$resid_ratio_true) < tol_D
passD_power <- all(D$resid_ratio_printed >
                     pmax(POWER_MULT * D$resid_ratio_true, tol_D))
cat(sprintf("  D verdict: max truth ratio %.4f < %.2f -> %s | printed-sign control separation %.1fx (need > %dx and > tol_D) -> %s\n",
            max(D$resid_ratio_true), tol_D, ifelse(passD_true, "PASS", "FAIL"),
            min(D$resid_ratio_printed / D$resid_ratio_true), POWER_MULT,
            ifelse(passD_power, "PASS", "FAIL")))

# ---- Test E: joint per-exporter recovery, import + export rows -------------
cat("\n== Test E: per-exporter gamma recovery, import + export rows ==\n")
sgE <- 3; sVE <- 4; gkE <- 0.7; gVE <- 0.9; J_E <- 10L
gjE  <- exp(rnorm(J_E, log(gkE), 0.5))
momI <- simulate_cell_moments(sgE, gkE, gjE, T_len)
momX <- simulate_export_moments(sgE, sVE, gjE, gVE, T_len)
est_E <- vapply(seq_len(J_E), function(j) {
  f <- function(g) {
    dd <- c(gkE, gjE); dd[j + 1L] <- g
    obj$fun_full(dd, sgE, momI$Y, momI$X, rep(1, J_E),
                 momX$Y, momX$X, seq_len(J_E) + 2L,
                 rep(sVE, J_E), rep(gVE, J_E), rep(1, J_E))
  }
  optimize(f, c(1e-4, 50))$minimum
}, numeric(1))
biasE <- median(abs(est_E / gjE - 1))
passE <- biasE < tol_E
cat(sprintf("  median |gamma bias| = %.3f (tol %.2f) -> %s\n",
            biasE, tol_E, ifelse(passE, "PASS", "FAIL")))

# ---- summary ---------------------------------------------------------------
all_pass <- passA_true && passA_power && passB && passC &&
            passD_true && passD_power && passE
cat(sprintf("\n== OVERALL: %s ==\n", ifelse(all_pass, "PASS", "FAIL")))

git_rev <- tryCatch(
  system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1],
  error = function(e) NA_character_)
summary_obj <- list(
  meta = list(engine = obj$engine, T_per_exporter = T_len, seed = opt_seed,
              quick = opt_quick, git_rev = git_rev,
              timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  tolerances = list(tol_A = tol_A, power_mult = POWER_MULT,
                    tol_B = tol_B, tol_C = tol_C,
                    tol_D = tol_D, tol_E = tol_E),
  eq11_signs = "corrected (G1, v0.4.1); Test D negative control is the printed equation",
  test_A = list(grid = A, pass_truth = passA_true, pass_power = passA_power),
  test_B = list(median_abs_bias = biasB, pass = passB),
  test_C = list(gam_k_hat = fitC$par[1], gam_k_true = gk,
                median_abs_bias_j = biasC_j, convergence = fitC$convergence,
                pass = passC),
  test_D = list(grid = D, pass_truth = passD_true, pass_power = passD_power),
  test_E = list(median_abs_bias = biasE, pass = passE),
  overall_pass = all_pass
)
if (opt_json) {
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    dir.create(dirname(opt_out), showWarnings = FALSE, recursive = TRUE)
    jsonlite::write_json(summary_obj, opt_out, auto_unbox = TRUE,
                         digits = 8, pretty = TRUE)
    cat(sprintf("Summary written: %s\n", opt_out))
  } else {
    cat("jsonlite not available; JSON summary skipped.\n")
  }
}

if (!interactive() && !all_pass) quit(save = "no", status = 1L)
