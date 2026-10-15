#!/usr/bin/env Rscript
# ============================================================================
# validation/pole_rule_accuracy.R  (patch 0117, fresh-eyes audit #7, M1/M2)
#
# Does the sigma-pole rule make the sigma Stage 2 uses -- and the optimal
# tariff that follows from it -- more ACCURATE where the truth is known? The
# rule (v0.10.0, c = 1) was adopted on split-half reliability, a stability
# metric whose halves share the full-panel sigma; replacing a noisy shared
# sigma with a constant raises it mechanically (the pole grid's r_within rose
# monotonically with the share of rows at the fallback). And Pillar 2's grid
# starts at sigma = 2, so no harness had a truth in the region where the rule
# acts. This is that harness.
#
# Design. Pillar 2's homogeneous-omega cell simulator (simulate_one_cell() in
# validation/validate_liml.R: J = 25 exporters x T = 30 periods,
# heteroskedastic shocks, price measurement error) and the shipped Stage-1
# estimator (estimate_cell_liml() defaults: closed-form HLIML, reject,
# hncs, kclass; sigma cap 50 as shipped). Each replicate is one importer x
# good cell; the replicates at one grid point share one true sigma, i.e. they
# are the cells of one good, so their median is a good-level sigma.
#   usable    = status ok, sigma > 1, not at the sigma cap (the edge rule)
#   pole_drop = usable, finite sigma_se, sigma - 1 < c * sigma_se
# The sigma Stage 2 would use under four policies:
#   P0 truth      sigma_true (oracle: the floor on any policy's error)
#   P1 no rule    sigma_hat if usable, else the global fallback
#   P2 shipped    sigma_hat if usable and not pole-dropped, else the global fallback
#   P3 good       as P2, but the fallback is the median kept sigma_hat at the
#                 grid point (a good-level fallback; M2's idea, idealised:
#                 every cell of the good shares one sigma)
# Consequence: in this homogeneous model the optimal tariff is omega itself.
# Given a sigma, omega*(sigma) is the omega that best fits the cell's
# POPULATION exporter moments (E y_j on E x1_j, E x2_j and a constant, with
# sigma fixed: Stage 2's import moment at gamma_j = gamma_k), computed from the
# replicate's own exporter variances. At the true sigma omega* is the true
# omega exactly, so a policy's tariff error is the compensating omega a wrong
# sigma forces -- the sigma-gamma trade-off the v0.10.0 level shift was --
# free of the finite-sample bias of refitting omega on T = 30 periods (a
# trial on sample means put the oracle's own error at 0.2-0.7 log points).
# Reported per grid point and per true sigma: yield, the rule's drop share,
# median |ln((sigma_used - 1)/(sigma_true - 1))| (the coefficient scale of
# Eq. (10)), median |ln(omega_hat / omega_true)|, its signed median, and the
# share of cells whose tariff is off by more than a factor of 2.
#
# No Stage-2 shrinkage here: in the pipeline the log-ridge pulls gamma toward
# a good-level prior built from Stage 2a, so a cell's own sigma moves its
# gamma less than here, and the prior moves instead (v0.10.0: about a seventh
# of the level shift came through the rule's own cells, the rest through
# Stage 2a). Read the tariff errors as the data term's response to sigma.
#
# Usage (repo root; ~3 min at the defaults on one core):
#   Rscript validation/pole_rule_accuracy.R [--reps 200] [--fallback 2.4728] [--pole-se 1]
#       [--sigma 1.2,1.5,2,3,5,8] [--omega 0.3,1,3] [--seed 20261015]
#       [--out results/pole_rule_accuracy.json] [--md docs/results/pole_rule_accuracy.md]
# ============================================================================

suppressPackageStartupMessages({ library(data.table) })

#' Population exporter moments of one simulate_one_cell() replicate: E y_j,
#' E x1_j, E x2_j for the non-reference exporters, from the exporter shock
#' scales the simulator draws first after set.seed(seed) (replayed here; the
#' test locks the replay to the simulator's sample means at large T).
population_moments <- function(sigma_true, omega_true, J = 25L, seed, sd_eps = 1, sd_u = 1, sd_meas = 0.3,
                               hetero_range = c(0.5, 2.0)) {
  set.seed(seed)
  s_eps <- runif(J, hetero_range[1], hetero_range[2]) * sd_eps
  s_u   <- runif(J, hetero_range[1], hetero_range[2]) * sd_u
  den <- 1 + omega_true * sigma_true
  a_es <- (1 + omega_true) / den; a_us <- -(sigma_true - 1) / den
  a_ep <- omega_true / den;       a_up <- 1 / den
  vp <- a_ep^2 * s_eps^2 + a_up^2 * s_u^2 + sd_meas^2
  vs <- a_es^2 * s_eps^2 + a_us^2 * s_u^2
  cps <- a_ep * a_es * s_eps^2 + a_up * a_us * s_u^2
  j <- 2:J
  data.table(exporter = j, y = vp[j] + vp[1], x1 = vs[j] + vs[1], x2 = cps[j] + cps[1])
}

#' omega given a fixed sigma: least squares of exporter-level y on x1 and x2
#' with the Feenstra coefficients at (sigma, omega) and a free constant, over
#' log omega. `m` holds one row per exporter (population or sample means).
#' NA when sigma <= 1 or the fit fails.
omega_given_sigma <- function(m, sigma, lo = 1e-4, hi = 1e3) {
  if (!is.finite(sigma) || sigma <= 1) return(NA_real_)
  m <- as.data.table(m)
  if (nrow(m) < 3L) return(NA_real_)
  ssr <- function(lw) {
    w <- exp(lw); rho <- w * (sigma - 1) / (1 + w * sigma)
    e1 <- rho / ((sigma - 1)^2 * (1 - rho)); e2 <- (2 * rho - 1) / ((sigma - 1) * (1 - rho))
    r <- m$y - e1 * m$x1 - e2 * m$x2
    sum((r - mean(r))^2)
  }
  o <- tryCatch(optimize(ssr, c(log(lo), log(hi))), error = function(e) NULL)
  if (is.null(o) || !is.finite(o$minimum)) NA_real_ else exp(o$minimum)
}

#' One grid point: n_reps simulated cells, the Stage-1 fit of each, the
#' rule's classification, and the sigma / omega each policy implies.
pole_accuracy_point <- function(sigma_true, omega_true, n_reps, fallback, pole_c = 1,
                                J = 25L, T = 30L, seed_base = 20261015L, cap = 50) {
  rows <- vector("list", n_reps)
  for (r in seq_len(n_reps)) {
    mom <- simulate_one_cell(sigma_true, omega_true, J = J, T = T,
                             seed = seed_base + r * 1009L + as.integer(sigma_true * 100) + as.integer(omega_true * 100))
    fit <- tryCatch(estimate_cell_liml(mom, ref_exporter = 1L, sigma_start_cap = cap), error = function(e) list(status = "error"))
    ok <- isTRUE(fit$status == "ok") && is.finite(fit$sigma %||% NA_real_)
    s_hat <- if (ok) fit$sigma else NA_real_
    se    <- if (ok) fit$sigma_se %||% NA_real_ else NA_real_
    usable <- ok && s_hat > 1 && !isTRUE(fit$sigma_capped)
    drop   <- usable && is.finite(se) && (s_hat - 1) < pole_c * se
    rows[[r]] <- list(rep = r, ok = ok, sigma_hat = s_hat, sigma_se = se, usable = usable, pole_drop = drop,
                      route = if (ok) as.character(fit$final_source %||% NA_character_) else NA_character_,
                      seed = seed_base + r * 1009L + as.integer(sigma_true * 100) + as.integer(omega_true * 100))
  }
  d <- rbindlist(rows)
  moms <- lapply(d$seed, function(sd) population_moments(sigma_true, omega_true, J = J, seed = sd))
  good_fb <- if (any(d$usable & !d$pole_drop)) median(d$sigma_hat[d$usable & !d$pole_drop]) else fallback
  d[, `:=`(sigma_P0 = sigma_true,
           sigma_P1 = fifelse(usable, sigma_hat, fallback),
           sigma_P2 = fifelse(usable & !pole_drop, sigma_hat, fallback),
           sigma_P3 = fifelse(usable & !pole_drop, sigma_hat, good_fb))]
  for (pp in c("P0", "P1", "P2", "P3")) {
    sv <- d[[paste0("sigma_", pp)]]
    om <- vapply(seq_len(nrow(d)), function(i) omega_given_sigma(moms[[i]], sv[i]), 0)
    set(d, j = paste0("omega_", pp), value = om)
    set(d, j = paste0("serr_", pp), value = abs(log((sv - 1) / (sigma_true - 1))))
    set(d, j = paste0("lr_", pp), value = log(om / omega_true))
  }
  d[, `:=`(sigma_true = sigma_true, omega_true = omega_true, good_fallback = good_fb)]
  d[]
}

#' Summaries by grid point and by true sigma.
pole_accuracy_summary <- function(d) {
  one <- function(x) {
    out <- list(n = nrow(x), yield = mean(x$ok), usable = mean(x$usable),
                pole_drop_share_of_usable = if (any(x$usable)) mean(x$pole_drop[x$usable]) else NA_real_)
    for (pp in c("P0", "P1", "P2", "P3")) {
      se <- x[[paste0("serr_", pp)]]; lr <- x[[paste0("lr_", pp)]]   # per-row, computed with the grid point's truth
      out[[paste0("sigma_err_", pp)]] <- median(se, na.rm = TRUE)
      out[[paste0("tariff_err_", pp)]] <- median(abs(lr), na.rm = TRUE)
      out[[paste0("tariff_bias_", pp)]] <- median(lr, na.rm = TRUE)
      out[[paste0("tariff_x2_", pp)]] <- mean(abs(lr) > log(2), na.rm = TRUE)
    }
    as.data.table(out)
  }
  list(by_point = d[, one(.SD), by = .(sigma_true, omega_true)],
       by_sigma = d[, one(.SD), by = sigma_true])
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get_arg <- function(flag, default) { w <- which(args == flag); if (length(w) == 1L && length(args) > w) args[w + 1L] else default }
  nums <- function(x) as.numeric(strsplit(x, ",", fixed = TRUE)[[1]])
  n_reps   <- as.integer(get_arg("--reps", "200"))
  fallback <- as.numeric(get_arg("--fallback", "2.4728"))
  pole_c   <- as.numeric(get_arg("--pole-se", "1"))
  sig_grid <- nums(get_arg("--sigma", "1.2,1.5,2,3,5,8"))
  om_grid  <- nums(get_arg("--omega", "0.3,1,3"))
  seed     <- as.integer(get_arg("--seed", "20261015"))
  out_json <- get_arg("--out", "results/pole_rule_accuracy.json")
  out_md   <- get_arg("--md", "docs/results/pole_rule_accuracy.md")
  if (!file.exists("R/liml_estimator.R")) stop("run from the repo root")
  for (f in c("R/utils_general.R", "R/hs_codes.R", "R/liml_estimator.R", "validation/validate_liml.R")) source(f)
  t0 <- Sys.time()
  d <- rbindlist(lapply(sig_grid, function(s) rbindlist(lapply(om_grid, function(o) {
    message(sprintf("pole_rule_accuracy: sigma %s, omega %s (%d reps)", s, o, n_reps))
    pole_accuracy_point(s, o, n_reps, fallback, pole_c, seed_base = seed)
  }))))
  sm <- pole_accuracy_summary(d)
  dir.create(dirname(out_json), showWarnings = FALSE, recursive = TRUE); dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(list(meta = list(reps = n_reps, fallback = fallback, pole_c = pole_c, sigma_grid = sig_grid, omega_grid = om_grid,
                                        seed = seed, J = 25L, T = 30L, sigma_cap = 50,
                                        git_rev = tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = NULL)[1], error = function(e) NA_character_),
                                        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
                                        minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)),
                            by_sigma = sm$by_sigma, by_point = sm$by_point),
                       out_json, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  f3 <- function(x) formatC(x, digits = 3, format = "f"); pc <- function(x) sprintf("%.1f%%", 100 * x)
  tab <- function(x, by) c(
    sprintf("| %s | yield | rule drops (of usable) | sigma err P0 / P1 / P2 / P3 | tariff err P0 / P1 / P2 / P3 | tariff bias P1 / P2 / P3 | tariff off x2 P1 / P2 / P3 |", by),
    "|---|---|---|---|---|---|---|",
    sprintf("| %s | %s | %s | %s / %s / %s / %s | %s / %s / %s / %s | %s / %s / %s | %s / %s / %s |",
            if (by == "sigma") x$sigma_true else paste0(x$sigma_true, ", ", x$omega_true), pc(x$yield), pc(x$pole_drop_share_of_usable),
            f3(x$sigma_err_P0), f3(x$sigma_err_P1), f3(x$sigma_err_P2), f3(x$sigma_err_P3),
            f3(x$tariff_err_P0), f3(x$tariff_err_P1), f3(x$tariff_err_P2), f3(x$tariff_err_P3),
            f3(x$tariff_bias_P1), f3(x$tariff_bias_P2), f3(x$tariff_bias_P3),
            pc(x$tariff_x2_P1), pc(x$tariff_x2_P2), pc(x$tariff_x2_P3)))
  md <- c("# The sigma-pole rule at known truth (patch 0117)", "",
          sprintf("%d cells per grid point (J = 25, T = 30; Pillar 2's simulator), the shipped Stage-1 estimator at sigma cap 50; global fallback %s, pole rule at c = %s; rev %s, %s (%.1f min).",
                  n_reps, fallback, pole_c, jsonlite::read_json(out_json)$meta$git_rev, format(Sys.time(), "%Y-%m-%d %H:%M %Z"),
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))), "",
          "Policies: P0 the true sigma; P1 no pole rule (estimate if usable, else the global fallback); P2 the shipped rule (global fallback for dropped cells); P3 the rule with a good-level fallback (the median kept estimate at the grid point). Errors are medians over cells: sigma error |ln((sigma_used - 1)/(sigma_true - 1))|; tariff error |ln(omega*/omega_true)|, omega* the omega that fits the cell's population moments at sigma_used (zero at the true sigma); bias is the signed median; \"off x2\" the share of cells whose tariff is wrong by more than a factor of two.", "",
          "## By true sigma (pooled over omega)", "", tab(sm$by_sigma, "sigma"), "",
          "## By grid point", "", tab(sm$by_point, "sigma, omega"), "",
          "Reading rules (fixed in docs/methodology/stage2_country.md before the run): see \"The sigma-pole rule at known truth\".", "")
  writeLines(md, out_md); cat(paste(md, collapse = "\n"), "\n")
  cat(sprintf("pole_rule_accuracy: wrote %s and %s\n", out_json, out_md))
}
