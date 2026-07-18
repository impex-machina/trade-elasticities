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
# Usage (from the repo root):
#   Rscript validation/stage2_structural_dgp.R              # full (T = 1e6)
#   Rscript validation/stage2_structural_dgp.R --quick      # T = 1e5
#   Rscript validation/stage2_structural_dgp.R --seed 42 --out results/stage2_dgp_summary.json
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
if (length(w <- which(args == "--seed")) == 1L && length(args) > w)
  opt_seed <- as.integer(args[w + 1L])
if (length(w <- which(args == "--out")) == 1L && length(args) > w)
  opt_out <- args[w + 1L]
opt_json <- !("--no-json" %in% args)

T_len  <- if (opt_quick) 1e5 else 1e6
tol_A  <- if (opt_quick) 0.05 else 0.02   # max |resid| / mean(Y) at truth
tol_B  <- if (opt_quick) 0.10 else 0.05   # median |gamma bias|, 1-D recovery
tol_C  <- if (opt_quick) 0.10 else 0.05   # median |gamma_j bias|, joint fit
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
      f <- function(d, sigma, imp_Y, imp_X, wt_imp) {
        het_obj_fixed_sigma_rcpp(d, sigma, imp_Y, imp_X,
                                 numeric(0), matrix(0, 0, 9), integer(0),
                                 numeric(0), numeric(0),
                                 wt_imp, numeric(0), NA_real_, 0)
      }
      return(list(fun = f, engine = "rcpp"))
    }
  }
  source("src/het_obj.R")
  f <- function(d, sigma, imp_Y, imp_X, wt_imp) {
    het_obj(c(sigma, d), imp_Y, imp_X,
            numeric(0), matrix(0, 0, 9), integer(0),
            numeric(0), numeric(0), wt_imp, numeric(0))
  }
  list(fun = f, engine = "pure-R")
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

# ---- summary ---------------------------------------------------------------
all_pass <- passA_true && passA_power && passB && passC
cat(sprintf("\n== OVERALL: %s ==\n", ifelse(all_pass, "PASS", "FAIL")))

git_rev <- tryCatch(
  system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1],
  error = function(e) NA_character_)
summary_obj <- list(
  meta = list(engine = obj$engine, T_per_exporter = T_len, seed = opt_seed,
              quick = opt_quick, git_rev = git_rev,
              timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  tolerances = list(tol_A = tol_A, power_mult = POWER_MULT,
                    tol_B = tol_B, tol_C = tol_C),
  test_A = list(grid = A, pass_truth = passA_true, pass_power = passA_power),
  test_B = list(median_abs_bias = biasB, pass = passB),
  test_C = list(gam_k_hat = fitC$par[1], gam_k_true = gk,
                median_abs_bias_j = biasC_j, convergence = fitC$convergence,
                pass = passC),
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
