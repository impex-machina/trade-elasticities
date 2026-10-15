#' R/sigma_eb.R  (patch 0122, measurement tool -- not used by the pipeline)
#'
#' Empirical-Bayes shrinkage of the Stage-1 sigma, the continuous alternative
#' to the published rule. The published rule is binary: a cell keeps its own
#' sigma, or -- no estimate, a box edge (patch 0086), within one SE of the
#' pole (patch 0099) -- takes one global fallback. Here every cell gets a
#' posterior on z = ln(sigma - 1) under a normal prior N(mu, tau^2) fitted to
#' the cells' own estimates:
#'
#'   data cells (converged, sigma > 1, finite positive SE, not a box edge):
#'     s     = sigma_se / (sigma - 1)                (delta-method SE of z)
#'     B     = tau^2 / (tau^2 + s^2)                 (weight on the cell's own z)
#'     z_eb  = mu + B (z - mu),  sd_eb = sqrt(B) * s
#'   every other cell: z_eb = mu, sd_eb = tau
#'   sigma_eb = 1 + exp(z_eb)   (the posterior median of sigma)
#'
#' mu and tau^2 by Paule-Mandel (the tau^2 at which the precision-weighted
#' chi-square equals its degrees of freedom), globally or per group (e.g.
#' good) with a global fallback for thin groups. A cell near the pole has a
#' large s and is pulled to mu -- the pole rule, made continuous; a precise
#' estimate keeps most of its own value.
#'
#' Patch 0122 measures it at known truth (validation/known_truth_stage2.R,
#' arm "sigma_eb") and on the real period split
#' (analysis/sigma_eb_period_census.R) before any session would use it.
#'
#' Exported: sigma_eb_fit(z, s), sigma_eb_shrink(s1, group = NULL, ...).


#' Paule-Mandel estimate of (mu, tau^2) from estimates z with SEs s.
#' @return list(mu, tau2, n).
sigma_eb_fit <- function(z, s) {
  ok <- is.finite(z) & is.finite(s) & s > 0
  z <- z[ok]; s <- s[ok]; n <- length(z)
  if (n == 0L) return(list(mu = NA_real_, tau2 = NA_real_, n = 0L))
  if (n == 1L) return(list(mu = z, tau2 = 0, n = 1L))
  mu_at <- function(t2) { w <- 1 / (t2 + s^2); sum(w * z) / sum(w) }
  q_at  <- function(t2) { m <- mu_at(t2); sum((z - m)^2 / (t2 + s^2)) - (n - 1) }
  if (q_at(0) <= 0) return(list(mu = mu_at(0), tau2 = 0, n = n))
  hi <- max(stats::var(z), 1e-8) * 10 + max(s^2)
  while (q_at(hi) > 0) hi <- hi * 10
  t2 <- stats::uniroot(q_at, c(0, hi), tol = 1e-12)$root
  list(mu = mu_at(t2), tau2 = t2, n = n)
}


#' Shrink a Stage-1 table's sigma.
#'
#' @param s1 Stage-1 table (sigma, sigma_se, convergence or status, and
#'   optionally sigma_capped, the box-edge flag; importer, good).
#' @param group NULL (one global prior) or a column name (e.g. "good"): one
#'   prior per group, the global one where a group has fewer than `min_n`
#'   data cells.
#' @param min_n data cells a group needs for its own prior.
#' @return a copy of s1 with sigma_eb, sigma_eb_se, eb_weight (B; 0 off the
#'   data), eb_data (logical); attributes eb_mu, eb_tau2, eb_n (global fit)
#'   and, for a grouped fit, eb_groups (group, mu, tau2, n, own).
sigma_eb_shrink <- function(s1, group = NULL, min_n = 10L) {
  x <- data.table::copy(data.table::as.data.table(s1))
  conv <- if ("convergence" %in% names(x)) x$convergence == 0L else x$status == "ok"
  edge <- if ("sigma_capped" %in% names(x)) x$sigma_capped %in% TRUE else rep(FALSE, nrow(x))
  dat <- conv %in% TRUE & is.finite(x$sigma) & x$sigma > 1 & is.finite(x$sigma_se) & x$sigma_se > 0 & !edge
  z <- ifelse(dat, log(x$sigma - 1), NA_real_)
  s <- ifelse(dat, x$sigma_se / (x$sigma - 1), NA_real_)
  g_fit <- sigma_eb_fit(z[dat], s[dat])
  if (!is.finite(g_fit$mu)) stop("sigma_eb_shrink(): no data cells (converged, sigma > 1, finite SE, not on a box edge)")
  mu <- rep(g_fit$mu, nrow(x)); t2 <- rep(g_fit$tau2, nrow(x))
  groups <- NULL
  if (!is.null(group)) {
    gv <- as.character(x[[group]])
    groups <- data.table::rbindlist(lapply(split(seq_len(nrow(x)), gv), function(ix) {
      d <- ix[dat[ix]]
      f <- if (length(d) >= min_n) sigma_eb_fit(z[d], s[d]) else NULL
      own <- !is.null(f) && is.finite(f$mu)
      data.table::data.table(group = gv[ix[1]], mu = if (own) f$mu else g_fit$mu, tau2 = if (own) f$tau2 else g_fit$tau2,
                             n = length(d), own = own)
    }))
    m <- match(gv, groups$group); mu <- groups$mu[m]; t2 <- groups$tau2[m]
  }
  B <- ifelse(dat, t2 / (t2 + s^2), 0)
  B[dat & !is.finite(B)] <- 0                      # tau2 = 0 and s = 0 cannot occur (s > 0); guard anyway
  z_eb <- ifelse(dat, mu + B * (z - mu), mu)
  sd_eb <- ifelse(dat, sqrt(B) * s, sqrt(t2))
  x[, `:=`(sigma_eb = 1 + exp(z_eb), sigma_eb_se = exp(z_eb) * sd_eb, eb_weight = B, eb_data = dat)]
  data.table::setattr(x, "eb_mu", g_fit$mu); data.table::setattr(x, "eb_tau2", g_fit$tau2)
  data.table::setattr(x, "eb_n", g_fit$n)
  if (!is.null(groups)) data.table::setattr(x, "eb_groups", groups)
  x
}
