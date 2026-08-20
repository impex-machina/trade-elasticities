# ============================================================================
# test-boundary-search-edges.R  (patch 0038)
#
# Locks for the hliml_boundary_search() edge scan introduced by patch 0038.
#
# Background (2026-08-20 fresh-eyes audit): the original search ran one blind
# optimize() per box edge. optimize() assumes a unimodal objective; the 1-D
# edge profiles of Q are routinely multimodal, so the search returned a
# strictly worse boundary point in ~13% of inadmissible synthetic cells --
# usually on the wrong edge entirely. Patch 0038 replaces the blind call with
# a deterministic log-spaced scan + local optimize() polish, and makes
# `usable` value-based as well as label-based (a best point at the
# sigma -> 1 pole is reported but not usable, mirroring patch 0033's
# value-based cap flags).
#
#   1. On seeded cells where the old search provably mis-picked, the scanned
#      search attains the boundary minimum of an INDEPENDENT dense-algebra
#      reference grid (tolerance 1e-6).
#   2. A cell whose constrained optimum sits at the sigma floor on the
#      omega_floor edge is reported with usable = FALSE, and
#      estimate_cell_liml() refuses to route it (no sigma = 1 + 1e-6 rows
#      can reach the output through the boundary path).
#   3. The scan is deterministic and monotone in n_scan (a finer scan never
#      returns a higher Q).
#
# The mis-pick seeds were located by brute-force census under the canonical
# harness DGP (validation/validate_liml.R::simulate_one_cell); each was
# verified to make the pre-0038 search return a strictly worse point than
# the reference grid (gaps 0.0005 - 0.056 in Q).
# ============================================================================

.bd_cell <- function(sigma_true, omega_true, J, T, seed) {
  root <- dirname(locate_source_dir())
  source(file.path(root, "validation", "validate_liml.R"), local = TRUE)
  simulate_one_cell(sigma_true, omega_true, J = J, T = T, seed = seed)
}

# Independent reference: profiled Q over theta0 at fixed (sigma, omega),
# computed from DENSE projection algebra (explicit exporter-dummy Z and
# off-diagonal-zeroed hat matrix), not from the O(n) group sums the
# estimator uses. Mirrors the structure of the .dense_Q helper in
# test-stage1-hliml-closed-form.R.
.dense_profile_Q <- function(mom) {
  Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)
  ex <- sort(unique(mom$exporter))
  Z <- sapply(ex, function(e) as.numeric(mom$exporter == e))
  P <- Z %*% solve(crossprod(Z), t(Z))
  Pmd <- P; diag(Pmd) <- 0
  Xc <- cbind(Y, X)
  A_d <- crossprod(Xc)
  B_d <- crossprod(Xc, Pmd %*% Xc)
  function(sig, om) {
    d <- (1 + om) * (sig - 1)
    t1 <- om / d; t2 <- (om * (sig - 2) - 1) / d
    u <- c(1, 0, -t1, -t2); w <- c(0, -1, 0, 0)
    Bm <- matrix(c(sum(u * (B_d %*% u)), sum(u * (B_d %*% w)),
                   sum(u * (B_d %*% w)), sum(w * (B_d %*% w))), 2)
    Am <- matrix(c(sum(u * (A_d %*% u)), sum(u * (A_d %*% w)),
                   sum(u * (A_d %*% w)), sum(w * (A_d %*% w))), 2)
    e <- tryCatch(eigen(solve(Am, Bm)), error = function(err) NULL)
    if (is.null(e)) return(Inf)
    q <- min(Re(e$values))
    if (!is.finite(q)) Inf else q
  }
}

# Boundary minimum of the reference over a fine log grid on all four edges.
.ref_boundary_min <- function(mom, n = 220,
                              sigma_cap = 10, omega_cap = 10,
                              omega_floor = 1e-4, sigma_floor = 1 + 1e-6) {
  Qe <- .dense_profile_Q(mom)
  sg <- exp(seq(log(sigma_floor), log(sigma_cap), length.out = n))
  og <- exp(seq(log(omega_floor), log(omega_cap), length.out = n))
  min(min(sapply(sg, Qe, om = omega_floor)),
      min(sapply(sg, Qe, om = omega_cap)),
      min(sapply(og, function(o) Qe(sigma_cap, o))),
      min(sapply(og, function(o) Qe(sigma_floor, o))))
}

test_that("edge scan attains the independent reference boundary minimum on known mis-pick cells", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)

  # Seeds where the pre-0038 blind optimize() returned a strictly worse
  # point than the reference grid (edge label of the OLD pick in comments).
  cases <- list(
    list(sigma = 2 + (35 %% 5),  omega = exp(-4 + (35 %% 6)),  J = 4 + (35 %% 8),
         T = 5 + (35 %% 10), seed = 400035L),   # old pick: omega_floor
    list(sigma = 2 + (56 %% 5),  omega = exp(-4 + (56 %% 6)),  J = 4 + (56 %% 8),
         T = 5 + (56 %% 10), seed = 400056L),   # old pick: sigma_floor, gap 0.056
    list(sigma = 2 + (74 %% 5),  omega = exp(-4 + (74 %% 6)),  J = 4 + (74 %% 8),
         T = 5 + (74 %% 10), seed = 400074L)    # old pick: sigma_cap
  )

  for (cs in cases) {
    mom <- .bd_cell(cs$sigma, cs$omega, cs$J, cs$T, cs$seed)
    Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)

    cf <- hliml_closed_form(Y, X, mom$exporter)
    expect_identical(cf$status, "ok")
    expect_false(cf$admissible)   # these cells are boundary-search inputs

    bd <- hliml_boundary_search(Y, X, mom$exporter)
    expect_identical(bd$status, "ok")

    ref <- .ref_boundary_min(mom)
    expect_lte(bd$Q, ref + 1e-6)

    # The returned point must reproduce its own Q through the independent
    # dense evaluator (guards against a scan that reports a Q it does not
    # attain).
    Qe <- .dense_profile_Q(mom)
    expect_equal(Qe(bd$sigma, bd$omega), bd$Q, tolerance = 1e-6)
  }
})

test_that("a boundary optimum at the sigma -> 1 pole is reported but not usable, and is not routed", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "utils_general.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)

  # Located by census: the constrained optimum lies on the omega_floor edge
  # with sigma driven into the sigma floor. Pre-0038, the edge LABEL made
  # this `usable = TRUE` and estimate_cell_liml() shipped sigma = 1 + 1e-6,
  # which survives the downstream `sigma > 1` cleanliness filter.
  mom <- .bd_cell(sigma_true = 1.6, omega_true = 3, J = 4 + (12 %% 5),
                  T = 5 + (12 %% 8), seed = 500012L)
  Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)

  bd <- hliml_boundary_search(Y, X, mom$exporter)
  expect_identical(bd$status, "ok")
  expect_identical(bd$edge, "omega_floor")
  expect_lte(bd$sigma, 1.001)
  expect_false(bd$usable)

  fit <- estimate_cell_liml(mom, ref_exporter = 1L, hliml_method = "closed")
  expect_false(identical(fit$final_source, "hliml_boundary"))
  if (isTRUE(fit$status == "ok")) {
    # If some other stage rescued the cell, it must not carry the pole value.
    expect_gt(fit$sigma, 1.001)
  }
})

test_that("edge scan is deterministic and monotone in n_scan", {
  root <- dirname(locate_source_dir())
  source(file.path(root, "R", "hs_codes.R"), local = TRUE)
  source(file.path(root, "R", "liml_estimator.R"), local = TRUE)

  mom <- .bd_cell(2 + (74 %% 5), exp(-4 + (74 %% 6)),
                  4 + (74 %% 8), 5 + (74 %% 10), 400074L)
  Y <- mom$y; X <- cbind(1, mom$x1, mom$x2)

  a <- hliml_boundary_search(Y, X, mom$exporter)
  b <- hliml_boundary_search(Y, X, mom$exporter)
  expect_identical(a, b)

  fine <- hliml_boundary_search(Y, X, mom$exporter, n_scan = 512L)
  expect_lte(fine$Q, a$Q + 1e-9)
})
