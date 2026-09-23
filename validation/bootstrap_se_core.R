# =============================================================================
# validation/bootstrap_se_core.R  (patch 0063, 2026-09-22)
#
# The per-cell worker of the exporter-cluster bootstrap benchmark, factored
# out of validation/bootstrap_se.R so it is (a) testable on a synthetic panel
# without the CLI, the cache or a Stage-1 table, and (b) free of the script's
# `opts` global. bootstrap_se.R sources this file and supplies the arguments.
#
# Requires the Stage-1 estimator to be loaded first, in dependency order:
#   source("R/utils_general.R"); source("R/hs_codes.R"); source("R/liml_estimator.R")
# utils_general.R is NOT optional: estimate_cell_liml() calls boundary_flags()
# at its boundary-routing site (patch 0031), and a missing definition is
# swallowed by the per-replicate tryCatch as a silent failure. Through
# 2026-09-22 bootstrap_se.R sourced liml_estimator.R alone, so on any table
# estimated under v0.6.0+ every boundary-routed replicate -- and every
# boundary-routed baseline cell -- would have counted as a failed replicate.
# The 2026-07-10 run predates boundary routing and was unaffected.
#
# Branch tagging (the follow-up named in validation_section_draft.md S4):
# each replicate records the route estimate_cell_liml() took
# (`final_source`: hliml / step2_weighted / hliml_boundary), so a cell's
# bootstrap dispersion decomposes into within-branch dispersion (replicates
# on the published route) and branch-switching. The analytic sigma_se is
# conditional on the branch; the within-branch ratio is the like-for-like
# comparison, the all-replicate ratio the unconditional one.
# =============================================================================

.bs_routes <- c("hliml", "step2_weighted", "hliml_boundary")

#' Fit one (importer, HS4) raw panel through the production path.
#'
#' @param panel_df data.frame with exporter, t, value, quantity (one cell).
#' @param min_year passed to prepare_cell_moments (match the production run).
#' @param step2_vce NULL = the estimator's default; otherwise "legacy"/"kclass"
#'   is passed to estimate_cell_liml() (patch 0061). NULL is right after the
#'   default flip; the rc window passes the flag the run used.
#' @return list(sigma, sigma_se, route) or NULL when the fit does not reach
#'   status "ok".
bs_fit_cell <- function(panel_df, min_year = 1995L, step2_vce = NULL) {
  prep <- tryCatch(
    prepare_cell_moments(panel_df,
                         exporter_col = "exporter", time_col = "t",
                         value_col = "value", quantity_col = "quantity",
                         min_year = min_year),
    error = function(e) NULL)
  if (is.null(prep) || is.null(prep$moments) ||
      is.null(prep$n_obs) || prep$n_obs < 5) return(NULL)
  args <- list(prep$moments, ref_exporter = prep$ref_exporter)
  if (!is.null(step2_vce)) args$step2_vce <- step2_vce
  fit <- tryCatch(do.call(estimate_cell_liml, args), error = function(e) NULL)
  if (is.null(fit) || !isTRUE(fit$status == "ok") || !is.finite(fit$sigma))
    return(NULL)
  list(sigma = as.numeric(fit$sigma),
       sigma_se = as.numeric(fit$sigma_se %||% NA_real_),
       route = as.character(fit$final_source %||% NA_character_))
}

#' Exporter-cluster bootstrap of one cell, branch-tagged.
#'
#' @param slice data.frame/data.table: the cell's raw rows (exporter, t,
#'   value, quantity).
#' @param published_route the Stage-1 table's final_source for the cell (the
#'   branch the analytic sigma_se is conditional on).
#' @param B replicates; seed per-cell seed (index-based upstream, so results
#'   are independent of scheduling); min_boot_ok minimum successful
#'   replicates before a dispersion is reported.
#' @return a one-row list. Fields up to boot_mad_sd are the pre-0063 schema,
#'   unchanged; the branch-tag fields follow.
bs_boot_cell <- function(slice, published_route, B, seed, min_boot_ok = 50L,
                         min_year = 1995L, step2_vce = NULL) {
  set.seed(seed)
  sl <- as.data.frame(slice)
  base <- bs_fit_cell(sl, min_year = min_year, step2_vce = step2_vce)

  exps <- unique(sl$exporter)
  by_exp <- split(sl, sl$exporter)
  sig_b <- rep(NA_real_, B); se_b <- rep(NA_real_, B); route_b <- rep(NA_character_, B)
  for (b in seq_len(B)) {
    draw <- sample(exps, length(exps), replace = TRUE)
    parts <- lapply(seq_along(draw), function(j) {
      x <- by_exp[[as.character(draw[j])]]
      x$exporter <- j              # relabel: duplicates enter as distinct panels
      x
    })
    f <- bs_fit_cell(do.call(rbind, parts), min_year = min_year, step2_vce = step2_vce)
    if (!is.null(f)) { sig_b[b] <- f$sigma; se_b[b] <- f$sigma_se; route_b[b] <- f$route }
  }
  ok <- is.finite(sig_b)
  n_ok <- sum(ok)
  same <- ok & !is.na(route_b) & route_b == published_route
  n_same <- sum(same)
  share <- function(r) if (n_ok > 0) sum(ok & route_b %in% r) / n_ok else NA_real_
  disp <- function(x, n) if (n >= min_boot_ok) c(sd(x), mad(x)) else c(NA_real_, NA_real_)
  d_all <- disp(sig_b[ok], n_ok); d_same <- disp(sig_b[same], n_same)
  list(
    # ---- pre-0063 schema (unchanged) ----
    sigma_base = if (is.null(base)) NA_real_ else base$sigma,
    boot_n_ok = n_ok, boot_yield = n_ok / B,
    boot_med = if (n_ok > 0) median(sig_b[ok]) else NA_real_,
    boot_sd = d_all[1], boot_mad_sd = d_all[2],
    # ---- branch tags (patch 0063) ----
    base_source = if (is.null(base)) NA_character_ else base$route,
    boot_share_same = if (n_ok > 0) n_same / n_ok else NA_real_,
    boot_share_hliml = share("hliml"),
    boot_share_step2 = share("step2_weighted"),
    boot_share_boundary = share("hliml_boundary"),
    boot_n_same = n_same,
    boot_med_same = if (n_same > 0) median(sig_b[same]) else NA_real_,
    boot_sd_same = d_same[1], boot_mad_sd_same = d_same[2],
    boot_med_se_same = if (n_same > 0 && any(is.finite(se_b[same])))
      median(se_b[same], na.rm = TRUE) else NA_real_
  )
}
