# ============================================================================
# test-stage2-structural-dgp.R
#
# Regression lock for the Stage 2 import-side moment equation (Soderbery
# 2018, Eq. 10). Added in v0.4.0 after an audit found a transcription error
# in the Eq. (10) term-4 coefficient that the existing validation stack
# could not detect (Pillar 3 generates its truth from the production
# residual routine and is self-consistent by construction).
#
# Design rule this test enforces: the data-generating process is written
# directly from the paper's structural equations (5)-(6) and NEVER calls
# pipeline code to generate truth. The PRODUCTION objective is then
# evaluated at the true parameters. If the implemented moment equation is
# the model's Eq. (10), the residual is O(1/sqrt(T)) simulation noise
# (ratio ~0.01-0.02 of the outcome scale at T = 1e5); the audited bug
# produced a ratio of ~0.5. A negative control (deliberately perturbed
# gammas) proves the test has power. Fuller grid + joint-recovery checks:
# validation/stage2_structural_dgp.R.
#
# Pure base R: uses the R reference objective src/het_obj.R (same Eq. 10
# coefficients as the Rcpp objectives; their agreement is exercised by the
# Stage 2b e2e test when Rcpp is available).
# ============================================================================

test_that("production objective satisfies Eq. (10) on a structural DGP", {
  cpp_dir <- locate_cpp_dir()
  source(file.path(cpp_dir, "het_obj.R"), local = TRUE)

  set.seed(20260717)
  sigma_true <- 3.0
  gam_k      <- 0.7
  J          <- 8L
  T_len      <- 1e5
  gam_j <- exp(rnorm(J, log(gam_k), 0.5))

  # ---- DGP hardcoded from Eqs (5)-(6): do not replace with pipeline code.
  #   Demand (5): Dk_ls = -(sigma - 1) * Dk_lp + eps
  #   Supply (6): q     = Dk_ls - a_j * Dlp_j + a_k * Dlp_k,
  #               a_x = (1 + gamma_x) / gamma_x
  #   =>  Dk_lp = (eps - q - (a_j - a_k) * Dlp_k) / (a_j + sigma - 1)
  a <- function(g) (1 + g) / g
  Y <- numeric(J); X <- matrix(0, J, 5)
  for (j in seq_len(J)) {
    eps  <- rnorm(T_len, 0, 0.6)
    q    <- rnorm(T_len, 0, 0.5)
    dlpk <- rnorm(T_len, 0, 0.4)
    aj <- a(gam_j[j]); ak <- a(gam_k)
    Dk_lp <- (eps - q - (aj - ak) * dlpk) / (aj + sigma_true - 1)
    Dk_ls <- -(sigma_true - 1) * Dk_lp + eps
    Dlp_j <- Dk_lp + dlpk
    Y[j]  <- mean(Dk_lp^2)
    X[j, ] <- c(mean(Dk_ls^2), mean(Dk_ls * Dk_lp), mean(Dk_ls * Dlp_j),
                mean(Dk_ls * dlpk), mean(Dk_lp * dlpk))
  }

  # Production objective, import side only, no penalty. het_obj takes
  # d = (sigma, gamma_k, gamma_1..gamma_J).
  fs <- function(d) {
    het_obj(c(sigma_true, d), Y, X,
            numeric(0), matrix(0, 0, 9), integer(0),
            numeric(0), numeric(0), rep(1, J), numeric(0))
  }
  ratio <- function(d) sqrt(fs(d) / J) / mean(Y)

  d_true <- c(gam_k, gam_j)

  # 1. Moment identity at truth: residual is simulation noise, not signal.
  expect_lt(ratio(d_true), 0.05)

  # 2. Negative control: the same metric must be LARGE for wrong gammas,
  #    proving the test can detect coefficient drift.
  expect_gt(ratio(c(gam_k, gam_j * 1.25)), 0.10)

  # 3. Per-exporter recovery through the production objective, gamma_k
  #    fixed at truth: median |bias| small (the audited bug gave ~51%).
  est <- vapply(seq_len(J), function(j) {
    f <- function(g) { dd <- d_true; dd[j + 1L] <- g; fs(dd) }
    optimize(f, c(1e-4, 50))$minimum
  }, numeric(1))
  expect_lt(median(abs(est / gam_j - 1)), 0.10)
})
