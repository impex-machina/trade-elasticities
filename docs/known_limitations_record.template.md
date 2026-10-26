# Known limitations — the long-form record

<!--
  GENERATED FILE. docs/known_limitations_record.md is written by
  scripts/build_readme.R from docs/known_limitations_record.template.md and
  results/*.json, under the same lock as README.md (the pre-commit hook and the
  CI step compare both). Edit the .template.md, run the build, commit both.
-->

This is the long form of the README's *Known limitations* (patch 0143): the same
limitations, with every measurement that bears on them and the release in which
each rule changed, rendered from the same `results/*.json` as the README so its
numbers are as current as the README's. The release-by-release history is the
dataset card's changelog (`docs/hf_dataset_card.md`); the measurement records
are in `docs/methodology/` and `docs/results/`. Paths below are relative to the
repository root. The sections are numbered in the order the README cites them.

Stated forthrightly:

- **§1. σ small-sample bias and selection under the Stage-1 homogeneity
  assumption.** Synthetic recovery (Pillar 2){{pillar2_cap_note(r$pillar2, r$stage1)}} shows the estimator *returns
  an estimate* in {{format_prop_pct(req(r$pillar2$tier1a_summary, "min_success_rate"))}}–{{format_prop_pct(req(r$pillar2$tier1a_summary, "max_success_rate"))}} of replications across the σ × ω grid
  (median {{format_prop_pct(req(r$pillar2$tier1a_summary, "median_success_rate"))}}) — a yield rate, not a recovery-within-tolerance rate —
  and the yield {{yield_direction_phrase(r$pillar2$tier1b_summary)}} as the
  sample grows from {{format_int(req(r$pillar2$tier1b_summary, "n_obs_smallest"))}} to {{format_int(req(r$pillar2$tier1b_summary, "n_obs_largest"))}} observations. Conditional on
  success, the median σ bias across the grid runs from
  {{format_prop_pct(min(sapply(r$pillar2$tier1a, function(x) x$sigma_bias)))}} to {{format_prop_pct(max(sapply(r$pillar2$tier1a, function(x) x$sigma_bias)))}} ({{sigma_bias_sign_phrase(r$pillar2$tier1a)}}),
  so comparisons to Feenstra-GMM or Broda–Weinstein estimates should not
  assume the upward bias of that tradition.{{pillar2_coverage_clause(r$pillar2)}}{{sigma_window_clause(SWIN)}}{{sigma_eb_period_clause(SEB, KT)}}
- **§2. Since v0.11.0 Eq. (11)'s export side is built on log export values, not on the export shares of the printed Eq. (8).** From Soderbery's Eq. (7), prices on export shares carry (ρ_I − ρ_V)·Δln V_j, V_j the exporter's total sales, which the printed Eq. (8) leaves in the error, where it moves with the Eq. (9) demand residual; his own account of that error (§3.3: the reference difference of the exporter's supply shocks) is what the value form delivers. On log export values the supply curve is exact and the nine-term Eq. (11) holds unchanged (harness Test F). Before the switch the value form moved within-cell γ on the 2% subsample by a median 0.0056 in log points (p99 0.64) and left split-half reliability at 0.360 against 0.368; in the v0.11.0 run, together with the corrected Stage-2a handoff (v0.10.x built Stage 2b's priors partly from Stage-2a rows its tail trim had flagged) and three γ_V passes, directly estimated γ moved by a median 0.007–0.010 in log points (p99 0.84–1.06; `docs/methodology/stage2_country.md`, "The v0.11.0 run"). `--stage2-export-moment share` reproduces v0.10.x; the exporter totals, whose value-only flows patch 0108 measured, no longer enter.
- **§3. Within-cell dispersion of γ is a λ-dependent presentation; the within-cell ranking is not.** Measured on the 2% subsample (2026-10-12; `docs/methodology/stage2_country.md`, "The reference exporter and λ, measured"): across λ = 0.03 / 0.1 / 0.3 the split-half reproducibility of the within-cell-demeaned log γ is flat (r = 0.362 / 0.369 / 0.368) while the within-cell standard deviation scales with λ (0.88 / 0.64 / 0.46). {{known_truth_order_sentence(KT)}} The choice of reference exporter, by contrast, does not matter: three rules give r = 0.367–0.368.
- **§4. γ heterogeneity within a cell reproduces within a period and drifts across periods{{known_truth_title_tail(KT)}}.** The Stage-2 log-ridge (λ = 0.1) is strong relative to the data curvature of a time-averaged moment row: the median row keeps a data share of {{format_num(req(SHRINK$data$q1$implied_data_share, "p50"))}}, the trade-weighted share is {{format_num(req(SHRINK$data$q1, "implied_data_share_trade_weighted"))}}, and a cell's largest exporter keeps {{format_num(req(Filter(function(b) identical(b$rank_bin, "1"), SHRINK$data$q1$by_trade_rank)[[1]], "data_share_median"))}} against {{format_num(req(Filter(function(b) identical(b$rank_bin, ">10"), SHRINK$data$q1$by_trade_rank)[[1]], "data_share_median"))}} for exporters ranked below tenth{{stale_note(SHRINK)}}. On a 2% product subsample, an exporter's deviation from its cell mean reproduces across odd- and even-year observations of the same period, under the shipped configuration, at r = {{format_num(req(Filter(function(x) identical(x$config, "v0110_cfg"), r$stage2_reliability_v0110_cfg$split)[[1]], "r_within"))}} (rank ρ {{format_num(req(Filter(function(x) identical(x$config, "v0110_cfg"), r$stage2_reliability_v0110_cfg$split)[[1]], "rho_rank"))}}; ≈ {{format_num(spearman_brown(req(Filter(function(x) identical(x$config, "v0110_cfg"), r$stage2_reliability_v0110_cfg$split)[[1]], "r_within")), 2L)}} at full panel length by Spearman–Brown), but only at r = {{format_num(req(Filter(function(x) identical(x$config, "v0110_period"), r$stage2_reliability_v0110_cfg$split)[[1]], "r_within"))}} between 1995–2009 and 2010–2024, also under the shipped configuration — {{within_signal_phrase(KT)}}.{{window_drift_clause(WDRIFT)}}{{known_truth_within_clause(KT)}} Loosening λ or changing the prior's form adds noise rather than signal, so λ stays at 0.1 with the log prior. Since v0.8.0 the reference exporter's own export-side moment and Soderbery's importer–exporter constant (fn. 14, concentrated out) are included; since v0.8.1 the cell optimizer runs to 5,000 iterations (non-converged cells 9% → ~2%); since v0.8.3 a cell whose L-BFGS-B fit does not converge — far more often a failed line search than the iteration cap — publishes the better of its L-BFGS-B point and the Nelder–Mead restart (through v0.8.2 the restart was published unconditionally, and on a 2% product subsample it was the worse point on 123 of the 138 such cells), and the good-level prior and γ_V are medians over directly estimated Stage-2a rows only (through v0.8.2 they included Stage 2a's own Tier-3 imputations).{{fallback_clause(FALLBACK)}} Since v0.9.0 the Stage-1 σ cap is 50 (10 through v0.8.3, which censored a continuous right tail), the tail trim takes a low-tail σ bound over cells (no high bound: a σ on a box edge is handled by the edge rule, and a large estimated σ is flagged by `sigma_robust`) and the Stage-2a plateau replacement is retired, Eq. (11)'s γ_V is the exporter's own γ at the reference destination from the previous Stage-2b pass (three passes; the residual in the tail is a stated limitation), the export-side Broda–Weinstein T is the pair's panel length, and a Stage-1 cell whose σ is a box edge takes the fallback σ like a cell with no estimate — as does, since v0.10.0, a cell whose σ is within one standard error of the pole (σ − 1 < SE; Eq. (10)'s 1/(σ−1) coefficients make such a cell's γ uninformative, and estimating it at the fallback σ raised the split-half reproducibility of the within-cell γ from 0.333 to 0.365 on the 2% subsample grid, 0.369 with Stage 2a re-estimated under the rule as shipped).{{pole_accuracy_clause(r$pole_rule_accuracy)}} **The γ level rose with v0.10.0** (median 0.644 → 0.806, `opt_tariff` 0.733 → 0.869): about a seventh of it from the rule's own cells, the rest through Stage 2a, whose regional σ's no longer include pole cells; the import moments pin the composite γ/((1+γ)(σ−1)), which is unchanged on cells whose σ moved only through the fallback (0.326 → 0.325), so the shift is the σ–γ trade-off of a less pole-biased σ rather than new information about γ — compare levels across releases with that in mind (`docs/methodology/stage2_country.md`, "v0.10.0, the full run"). Since v0.9.1 its Stage-1 SE and adjust code leave the clean set with it: through v0.9.0 the σ-propagation step still read them, so the ω-edge corner cells among the 13,810 edge cells published the discarded σ = 50 point's `sigma_se` on 81,401 rows and its `dgamma_dsigma` on 80,521, beside the fallback σ; the pole test rejected every one of those rows, so `sigma_robust` and `gamma_se_total` were unaffected (the v0.9.0 statement that `sigma_robust` is FALSE on the edge cells held in fact — by the test's outcome, not by construction). `scripts/apply_sigma_edge_se_rule.R` is the correction, applied to the shipped v0.9.0 table without re-estimation. Details and the grids: `docs/methodology/stage2_country.md` ("v0.8.0", "v0.8.1"), `docs/results/stage2_reliability_*.md`, `docs/results/stage2_lambda_curve_v074rc.md`.{{known_truth_structured_bullet(KTS)}}{{routing_bullet(KR, AB)}}{{ridge_experiment_bullet(KR5, KEB, EB, CK, TC)}}
- **§5. The Broda–Weinstein row weights are not fn. 14 as printed, and the measured alternative is worse.** Each exporter's moment row is a within-exporter weighted mean, so the T^{3/2} factor of Soderbery's fn. 14 cancels; the only trace of it is that the first differenced observation of every trading run — the pair's entry year — takes `bw_weight()`'s NA → 1 fallback (~1 beside 10–3,000 for its neighbours) because the calendar lag is looked up on the differenced table. The across-exporter weight is trade value scaled by min(T, 10)/10, a documented departure. Both were measured on a 2% product subsample on 2026-10-11 (`docs/methodology/stage2_country.md`, "The fn-14 flags, measured"): restoring the entry-year observation (`--bw-lag raw`) moves the median Tier-1 γ by 2.3% and the p90 row by 35% and lowers split-half reliability of the within-cell heterogeneity from r = 0.333 to 0.303; the fn-14 cross-variety weight (`--exporter-weight bw_sum`) lowers it to 0.314 and widens within-cell dispersion by 40%; both together 0.307. The shipped weighting stays; the two flags remain available and default-off.
- **§6. Estimator-provenance composition.** {{provenance_lead(r$stage1)}}{{boundary_phrase(r$stage1$routing_summary, req(r$stage1, "n_cells"), r$stage1$edge_se)}}{{provenance_tail(r$stage1)}}. {{format_pct(req(r$stage1, "sy_fails"), req(r$stage1, "sy_evaluated"))}} of cells fail the
  Stock-Yogo weak-instrument threshold at the strict 10% maximal-size
  critical value this pipeline screens at. At Grant-Soderbery (2024)'s own
  25% rule of thumb, {{format_pct(req(r$stage1, "sy_pass_gs25"), req(r$stage1, "sy_gs25_evaluated"))}} of the {{format_int(req(r$stage1, "sy_gs25_evaluated"))}} evaluated cells pass the
  weak-instrument screen, and {{format_pct(req(r$stage1, "sargan_passes"), req(r$stage1, "sargan_evaluated"))}} of the {{format_int(req(r$stage1, "sargan_evaluated"))}} cells with an
  overidentified Step-2 fit pass its Sargan test (conventional p > 0.2). The
  joint credibility screen of the G&S protocol pairs the 25% weak-instrument
  rule with the HLIML-residual overidentification statistic J_h, which exists
  only on the interior-HLIML cells: of the {{format_int(req(r$stage1, "gs_both_evaluated"))}} cells where both are
  defined, {{format_pct(req(r$stage1, "gs_both_passes"), req(r$stage1, "gs_both_evaluated"))}} pass both. Per-cell flags
  (`stockyogo_pass_gs25`, `sargan_pass`, `sargan_pass_gs`, `gs_pass_both`) ship
  in the Stage 1 output so either threshold can be applied downstream. Conditional on `status == "ok"`
  the interior rate rises to {{format_pct(req(r$stage1$provenance_rates$interior_conditional_on_ok, "numerator"), req(r$stage1$provenance_rates$interior_conditional_on_ok, "denominator"))}}; both framings appear in the methodology
  write-up. Headline σ medians are reported on the canonical {{format_int(req(r$stage1, "n_products"))}} HS4
  universe.
- **§7. Period extension relative to Soderbery (2018).** This pipeline
  estimates over a longer window than Soderbery's original sample, which
  contributes to estimate differences independently of the estimator
  change from Feenstra GMM to HLIML.
- **§8. Supply-side boundaries: two ends of the ω axis.** The Feenstra
  inversion has no positive ω for a point whose ρ exceeds (σ−1)/σ: the
  algebraic ω is negative, and geometrically the point is the continuation
  of the admissible interval *past ω = +∞*. Grant & Soderbery's Stata code
  clamps such points to the 1e-4 floor — the opposite end of the axis —
  and reports them as near-perfectly-elastic supply; this pipeline did the
  same through v0.6.1{{beyond_inf_phrase(r$stage1$negative_omega)}}. From v0.7.0
  (`--stage1-negative-omega {{req(r$stage1$negative_omega, "rule")}}`; `floor` reproduces v0.6.1) such points are
  inadmissible at every inversion and take the constrained boundary optimum,
  which lands at the ω *cap* in most cases (`omega_capped`, `adjust` 8).
  The ω floor now holds {{format_pct(req(r$stage1$omega_floor, "n_floor"), req(r$stage1$omega_floor, "denominator"))}} of cells,
  {{format_int(req(r$stage1$omega_floor, "n_floor_boundary_edge"))}} of them constrained floor-edge optima (`adjust` 6) — the genuine
  perfectly-elastic-supply end, which the `omega_floored` boolean isolates.
  Two populations need care: {{format_int(req(r$stage1$negative_omega, "n_sigma_without_omega"))}} cells report a Step-2 σ with ω
  undetermined (no admissible ω, no usable edge; `omega` is NA), and
  {{format_int(req(r$stage1$negative_omega, "n_boundary_corner"))}} floor-edge optima were reached from a beyond-∞ point
  (`boundary_corner`): they sit near σ = 1 with a flat objective and should be
  filtered for supply-side uses. Stage 2 ridge shrinkage toward good-level
  priors lifts floored mass, so the published γ floors in only {{format_pct(req(r$stage2b$gamma_floor, "n_floor"), req(r$stage2b$gamma_floor, "denominator"))}} of cells and looks
  better-behaved than the Stage 1 supply identification underneath it
  (see `docs/methodology/stage1_README.md`). Where ω is floored, both γ and the
  derived `opt_tariff` collapse toward zero — toward elastic supply and a
  near-zero optimal tariff — so a γ or tariff sitting at that boundary is an
  identification artifact, not an interior estimate.
- **§9. Standard errors: conditional on σ, with a robustness screen.** `gamma_se`
  is computed with σ held fixed at its Stage 1 value (a global-median fallback
  wherever Stage 1 did not identify σ), so it is conditional on σ. Only
  {{format_pct(req(r$stage2b$se_status, "ok"), req(r$stage2b$se_status, "total"))}} of rows carry a clean cell-specific SE: {{format_pct(req(r$stage2b$se_status, "tier3_prior"), req(r$stage2b$se_status, "total"))}} are rows
  assigned the good-level prior outright, with no SE (Tier 3, and the reference row of a cell
  whose other exporters are all Tier 3) and the remaining
  {{format_pct(req(r$stage2b$se_status, "other"), req(r$stage2b$se_status, "total"))}} are rows at an extreme where no SE is computed (`boundary`, γ < 0.01;
  `plateau`, γ > 5), non-converged fits, or variances that could not be formed.{{convergence_clause(CONV)}} The pipeline
  additionally propagates the Stage 1 σ uncertainty by the delta method into
  `gamma_se_total` and flags the result with a cell-level `sigma_robust` screen:
  σ̂ unclamped and with a finite SE, clear of the σ = 1 pole, and no γ SE in the
  cell inflated beyond threshold. {{format_pct(req(r$stage2b$sigma_robust, "robust"), req(r$stage2b$sigma_robust, "total"))}} of rows pass ({{format_pct(req(r$stage2b$sigma_robust, "robust"), req(r$stage2b$sigma_robust, "n_estimated"))}} of the rows outside Tier 3); {{format_pct(req(r$stage2b$sigma_robust, "not_robust"), req(r$stage2b$sigma_robust, "total"))}} are flagged `FALSE` and {{format_pct(req(r$stage2b$sigma_robust, "tier3_na"), req(r$stage2b$sigma_robust, "total"))}} are Tier-3 imputed cells (`NA`) with no per-cell σ. The screen is governed almost entirely by σ̂'s distance from the σ = 1 pole, not by the inflation cutoff, and the pass rate is stable across a wide grid of both thresholds (`analysis/sensitivity_sweep.R` reproduces it). Where `sigma_robust` is `FALSE` or `NA`, treat `gamma_se` as a conditional, lower-bound measure of uncertainty; where `TRUE`, `gamma_se_total` is the σ-aware SE — and in either case the SE is frequently as large as the estimate itself.{{step2_vce_clause(r$stage1$step2_vce)}}{{bootstrap_clause(r$bootstrap_se)}} In the Pillar-3 Monte Carlo — a regression-level harness on the shipped variance formula (sandwich with the ridge in λ/γ² units) {{pillar3_constant_clause(r$pillar3)}} — the SE has a median ratio to the empirical sampling SD of {{format_num(req(r$pillar3$pen_sandwich_summary, "prod_med_ratio"))}} in a regime whose median `gamma_shrink_wt` is {{format_num(req(r$pillar3$pen_sandwich_summary, "prod_shrink_wt_median"))}} (the shipped table's is {{format_num(req(SHRINK$data$q1$shrink_wt, "p50"))}}{{stale_note(SHRINK, "; ", "")}}) and {{format_num(req(r$pillar3$pen_sandwich_summary, "med_ratio_min"))}}–{{format_num(req(r$pillar3$pen_sandwich_summary, "med_ratio_max"))}} across all {{req(r$pillar3$pen_sandwich_summary, "n_regimes")}} regimes (`docs/methodology/se_calibration_mc_summary.csv`).
- **§10. σ is sensitive to the estimator, not only the sample.** On the Tier 4
  comparison against the legacy Feenstra-GMM baseline, the HLIML σ and the
  GMM σ agree poorly in both level and cross-cell rank ordering. Comparisons
  of these σ to GMM- or Broda-Weinstein-style estimates elsewhere should
  account for the estimator difference, not just the sample and period.
- **§11. BACI vs. the COMTRADE data Soderbery (2018) used.** This pipeline uses
  CEPII BACI — mirror-reconciled, FOB-valued, and carrying a share of
  quantities that CEPII imputes from mirror-flow unit-value conversion and
  does not flag in the released data (so the corresponding unit values are
  partly synthetic and cannot be filtered out) — rather than the
  COMTRADE of the original, which uses the importer's and the exporter's
  reports separately: Soderbery's import moments use the importer-reported
  (delivered) flows, his export moments the exporter-reported (shipped)
  ones, and he names the gap between shipped and delivered unit values as a
  source of the variation that keeps the import and export hyperbolae
  distinct (his §3.1 and fn. 11). BACI reconciles the two reports into one
  flow, so here both sets of moments share one unit value and identification
  rests on the difference between import shares and export shares alone,
  which Soderbery's fn. 11 argues is enough in principle. HS4 unit values are weight-based composites
  (value divided by tonnes, summed over the constituent HS6 lines) and so
  move with product mix, not only price. These data-construction choices
  reshape the cross-exporter second moments that identify σ and ω, and
  contribute to differences from Soderbery independently of the estimator
  and period.
