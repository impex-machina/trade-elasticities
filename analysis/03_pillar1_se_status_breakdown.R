#' analysis/03_pillar1_se_status_breakdown.R
#' Pillar 1: gamma standard-error status table. Reads `stage2b` from 00_setup.R.
#'
#' Authored N+12 against the real stage2b schema. SEs are penalized
#' Gauss-Newton (pen_gn, calibrated within +/-7%, memory #13). The status
#' column is gamma_se_status ("ok" etc.); tier is the estimator-provenance
#' tier (1-4).

s2b <- stage2b

# --- Table: SE status x tier crosstab --------------------------------------
xt <- s2b[, .(n = .N), by = .(tier, gamma_se_status)][order(tier, gamma_se_status)]
xt[, pct_within_tier := 100 * n / sum(n), by = tier]
save_table(xt, "03_pillar1_se_status_breakdown")

# --- Table: headline SE coverage (share with usable SE) --------------------
se_head <- s2b[, .(
  n_total   = .N,
  n_se_ok   = sum(gamma_se_status == "ok", na.rm = TRUE),
  pct_se_ok = 100 * mean(gamma_se_status == "ok", na.rm = TRUE),
  gamma_se_med = median(gamma_se[is.finite(gamma_se)], na.rm = TRUE)
)]
save_table(se_head, "03_pillar1_se_status_headline")

message("03_pillar1_se_status_breakdown.R: SE status = ok in ",
        round(se_head$pct_se_ok, 1), "% of country-pair cells")
