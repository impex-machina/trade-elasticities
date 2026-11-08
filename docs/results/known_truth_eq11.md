# Stage-1 sigma under heterogeneity, the Stage-2 objective block by block, and the Eq. (11) moment condition, at known truth (patch 0150 session)

Synthetic worlds from `validation/synthetic_baci.R` (15 countries unless stated, 1995-2024, shock scale 1, good_sd 0, importer_sd 0, seed 20261015 unless stated), production defaults, rev 114d960 plus patch 0150; sandbox run 2026-10-27, every number in sections 1-5 reproduced to the digit on the author's machine (R 4.6.0) except the lambda-0 arms of section 5, which differ in the second decimal. Errors on sigma are ln((s_hat - 1)/(s - 1)) ("lr"): bias is its median, error the median of its absolute value. Harnesses: `validation/known_truth_stage1_heterogeneity.R`, `known_truth_sigma_update.R`, `known_truth_eq11_shares.R`, `known_truth_stage2_arms.R`, `known_truth_eq11_worlds.R` (all prototypes; the middle three splice onto `estimate_importer_product_fixed_sigma()` by introspection, anchored on its `d_start <- rep(gam_init, ...)` statement). Section 7 is the nine-world grid run on the author's machine (2026-10-27), `results/known_truth_eq11_arms_by_world.csv`.

**Rules, fixed before the numbers.** (1) The Stage-1 estimator is *heterogeneity-biased* if the bias of ok cells rises monotonically with `within_sd` from a homogeneous world (within_sd 0) whose bias is within +/-0.05. (2) A block of the Stage-2 objective *identifies sigma* if, with every parameter at the truth, the profile over sigma has median lr within +/-0.1 and median |lr| below the Stage-1 error. (3) A moment condition *fails* if the residual rows at the truth have a mean of at least 0.1 sd(Y) with |t| > 4. (4) An arm *beats* the shipped arm if it is not worse on tariff median |log error| and better on within-cell r on the Tier-1 rows of the shipped arm. (5) On the grid, a candidate *advances* to the 2% subsample if its target reading improves against the shipped arm in at least 7 of 9 worlds and no other reading's paired median is worse than -0.01; the all-rows within-cell r is reported but not gated, because its sign is set by the thin exporters' rows (section 7).

## 1. Stage-1 sigma bias is heterogeneity-induced

`known_truth_stage1_heterogeneity.R`, 12 goods, seeds 20261015 and 20261016 (~350 ok cells per world); the same seed gives the same sigma, shocks and trade pattern, only the within-cell spread of ln gamma differs. Median lr, interior HLIML cells, pooled over seeds; all-ok-cell medians by seed in brackets.

| within_sd | 0 | 0.35 | 0.7 | 1.2 |
|---|---|---|---|---|
| median lr | -0.016 [0.02, 0.03] | +0.056 [0.07, 0.11] | +0.122 [0.12, 0.16] | +0.148 [0.14, 0.19] |

Median |lr| is 0.2-0.3 at every level: the centre moves, the dispersion does not. **Reading (rule 1): heterogeneity-biased.** Stage 1 imposes gamma_j = gamma_k (Feenstra / HLIML drops the x4, x5 terms of Eq. (10)); Stage 2 relaxes exactly that restriction conditional on the restricted sigma. The repo's routing worlds all use within_sd 0.7 or 0.35, so this component was never separated from small-sample error before.

## 2. The Stage-2 objective profiled over sigma, block by block

`known_truth_sigma_update.R`: Stage 2b as shipped, then sigma re-solved per cell from the objective with the gammas held fixed (240-point log grid, polish), lambda 0. Cells with their own Stage-1 sigma; heterogeneous world within_sd 0.7 (158 cells), homogeneous world within_sd 0 (140 cells). Every profile minimum beats the objective at the sigma used in 100% of cells.

| profile of ... at | heterogeneous: median lr / |lr| | homogeneous: median lr / |lr| |
|---|---|---|
| Stage-1 sigma as used (reference) | +0.097 / 0.176 | -0.010 / 0.220 |
| Eq. (10)+(11), gamma-hats | +1.23 / 1.23 | +0.49 / 0.55 |
| Eq. (10)+(11), true gammas | +1.79 / 1.79 | +0.49 / 0.54 |
| Eq. (10)+(11), true gammas and true sigma_V, gamma_V | +0.81 / 0.84 | -- |
| **Eq. (10) only, gamma-hats** | **+0.085 / 0.122** (70% within 0.2) | +0.049 / 0.113 |
| Eq. (10) only, true gammas | +0.024 / 0.111 (78%) | +0.035 / 0.132 |
| Eq. (11) only, gamma-hats | +2.03 | +0.32 (true sigma_V, gamma_V) |
| Eq. (11) only, true gammas | +2.54 | +0.39 (true sigma_V, gamma_V) |

**Reading (rule 2): the import block identifies sigma; the export block does not, even at the truth.** An import-only sigma update at the Stage-2b gamma-hats removes most of section 1's bias and cuts the Stage-1 dispersion by a third; it must not include Eq. (11).

## 3. Why the export block fails: the moment rows at the truth

`known_truth_eq11_shares.R` (no estimation: every lookup at the truth), 4 goods, within_sd 0.7, worlds of 15 and 30 countries (exporters per cell 10.5 and 21.8; mean top share 0.50 and 0.38; HHI 0.355 and 0.237).

| | 15 countries | 30 countries |
|---|---|---|
| export-block sigma bias (median lr) | +0.822 | +0.832 |
| import-block sigma bias | +0.069 | +0.038 |
| export rows: mean u / sd(Y), t | +0.337, 9.9 | +0.376, 18.7 |
| import rows: mean u / sd(Y), t | -0.217, -6.1 | -0.113, -4.2 |
| ... with uniform within-row weights (fn. 14 off), export bias | +0.637 | +0.710 |
| ... export rows mean u / sd(Y), t | +0.320, 9.5 | +0.374, 18.1 |
| ... with V = most periods (ties by value), export bias | +0.359 | -- |
| ... export rows mean u / sd(Y), t | +0.262, 6.7 | -- |

By good: the single-HS6-line good (2709, unit value exactly p) has centred import rows (t -1.6 in both worlds) and export rows as biased as any (+0.41 / +0.45, t 6.0 / 13.3); the two-line goods carry the import-row means (t -3.8 to -4.9), i.e. composition noise in the composite HS4 unit value -- the Broda-Weinstein measurement-error case the import constant absorbs. The export block has no constant.

Observation level (good 2709, 3,868 (j, i, t) rows, residuals of Eqs. (8) and (9) at the truth):

| reference destination V | E[q] (t) | E[eps] (t) | E[q eps] (t) | cor(q, eps) |
|---|---|---|---|---|
| largest other market by panel value (shipped) | +0.0202 (5.6) | -0.0043 (-0.5) | +0.0160 (6.7) | 0.123 |
| most differenced periods, ties by value | -0.0083 (-2.3) | +0.0663 (6.7) | +0.0138 (5.0) | 0.093 |
| random draw | +0.0011 (0.3) | +0.0014 (0.1) | +0.0075 (2.5) | 0.050 |
| random draw, 30-country world | +0.0024 (1.2) | -0.0029 (-0.5) | +0.0096 (7.3) | 0.061 |

**Reading (rule 3): E[u^J] = 0 fails in equilibrium data, and it decomposes.** About half is the reference-destination rule: the largest market selects on the realized cost and demand paths (a random-walk path that is low on average has innovations that are negative on average, so E[d le_v] < 0 and E[q^J] > 0); with a random V both residuals are centred. The other half is a positive correlation of q^J and eps^J that survives a random V and does not fall from 10 to 22 exporters per market; eps co-moves with the destination price indices (cor with a dln P_i proxy 0.6) but the channel is not pinned down. Ruled out as causes: within-cell gamma heterogeneity (the homogeneous world shows it), composite HS4 unit values (the single-line good shows it), fn. 14's contemporaneous weights, plug-in sigma_V / gamma_V, the Eq. (10)/(11) algebra (sympy-verified) and the panel construction (differences match a direct recomputation to machine precision).

## 4. Not the algebra, not the data

Checked and clean in this session: the five Eq. (10) coefficients close the moment identity from Eqs. (5)-(6) with u = -gamma_j / ((1 + gamma_j)(sigma - 1)) q eps; the corrected Eq. (11) coefficients close it from Eqs. (8)-(9) with u = q eps / (sigma - 1), the printed x5/x6 signs do not; the panel's `lp_dif` and `ls_exp_dif` equal a direct recomputation (max difference 0 over 3,996 rows).

## 5. Stage-2 arms on the heterogeneous world

`known_truth_stage2_arms.R`: `estimate_all_fixed_sigma()` on the prepared panel with the pass-3 lookups, 12 goods, within_sd 0.7, Stage-1 sigma as shipped unless stated. Readings on published estimated rows against the true gammas: R1 = within-cell r of cell-demeaned ln gamma (cells with >= 3 rows), R2 = cor(ln opt_tariff, ln tau*) with tau* from the true gammas, the true sigma and the arm's mean-trade weights; the Tier-1 column reads the rows that are Tier 1 in arm A (1,676 of 1,850; mean gamma_shrink_wt there 0.997) in every arm.

| arm | R1 all rows | R1 Tier-1 rows | R2 | row med \|log err\| | cell-mean med \|log err\| | tariff med \|log err\| |
|---|---|---|---|---|---|---|
| A shipped | 0.074 | 0.102 | 0.074 | 0.521 | 0.327 | 0.475 |
| B import-only (every exporter Tier 2, no reference export row) | -0.015 | 0.178 | 0.145 | 0.525 | 0.327 | 0.455 |
| C V = most periods, ties by value | 0.090 | 0.143 | 0.105 | 0.522 | 0.327 | 0.474 |
| E shipped structure, true sigma, lambda 0 | 0.233 | 0.282 | 0.170 | 1.415 | 5.96 | 0.855 |
| G V rule, true sigma, lambda 0 | 0.225 | 0.278 | 0.121 | 1.058 | 4.25 | 0.818 |

Arm B's all-rows R1 is the ~170 small exporters that are Tier 2 in arm A (few periods, noisy import rows, large deviations); the Tier-1 column is the like-for-like comparison. Arm C changes nothing else: it finds an exporter-specific gamma_V for 1,869 export rows against 1,829 (regional-median fallbacks 10 against 51). The lambda-0 arms show the ridge setting the levels: ordering improves, cell means are off by 4-6 log points.

**Reading (rule 4): C beats A; B beats A on the Tier-1 rows and on the tariff; neither is worse than A anywhere measured.** On the first structured world (`good`, 4 goods, seed 20261015, wrapper smoke run) the same pattern: Tier-1 within-cell r 0.054 shipped, 0.152 import-only; tariff error 0.330 against 0.327.

## 6. Arm D, H and S on the heterogeneous world

Three further arms on the world of section 5 (sandbox): **D** hybrid -- Eq. (11) only for the reference exporter's own row, every other exporter Tier 2; **H** as D with the import constant forced on (the cell estimator concentrates fn. 14's constant out only when M >= 2, so B and D run without it as a side effect); **S** sigma update -- sigma re-solved per cell from the Eq. (10) block at the shipped Stage-2b gamma-hats (every cell with import rows, fallback cells included), then Stage 2b re-run at the updated sigma and sigma_V, one update, no iteration. A `sigma_med_abs_lr` column (cells, published sigma against the truth) is added.

| arm | sigma med \|lr\| | R1 all rows | R1 Tier-1 rows | R2 | tariff med \|log err\| |
|---|---|---|---|---|---|
| A shipped | 0.188 | 0.074 | 0.102 | 0.074 | 0.475 |
| B import-only | 0.188 | -0.015 | 0.178 | 0.145 | 0.455 |
| D hybrid | 0.188 | 0.012 | 0.185 | 0.118 | 0.455 |
| H hybrid, constant on | 0.188 | 0.035 | 0.137 | 0.127 | 0.470 |
| S sigma update | 0.118 | 0.053 | 0.088 | 0.072 | 0.478 |

The tariff does not respond to the sigma update because at the shipped lambda every gamma_j in a cell is the product prior, and with equal gammas Eq. (15) collapses to tau* = gamma-bar whatever sigma is: under the ridge the tariff *is* the prior. S improves the published sigma column, which is a result in its own right.

## 7. The arms across nine worlds

`known_truth_eq11_worlds.R`: seeds 20261015, 20261016, 20261017 x structures none (within_sd 0.7), good (good_sd 0.7, within_sd 0.35), good_importer (good_sd 0.7, importer_sd 0.5, within_sd 0.35), 12 goods, 15 countries, pipeline as shipped on each world, arms A, B, C, D, H, S. Medians over the nine worlds, then the paired median difference against A.

| arm | sigma med \|lr\| | R1 all rows | R1 Tier-1 rows | R2 | row med \|log err\| | cell-mean med \|log err\| | tariff med \|log err\| |
|---|---|---|---|---|---|---|---|
| A shipped | 0.188 | 0.045 | 0.101 | 0.670 | 0.454 | 0.327 | 0.386 |
| B import-only | 0.188 | -0.005 | 0.128 | 0.672 | 0.454 | 0.327 | 0.371 |
| C V = most periods | 0.188 | 0.051 | 0.095 | 0.671 | 0.453 | 0.327 | 0.389 |
| D hybrid | 0.188 | 0.010 | 0.133 | 0.671 | 0.455 | 0.327 | 0.372 |
| H hybrid, constant on | 0.188 | 0.028 | 0.101 | 0.679 | 0.453 | 0.328 | 0.385 |
| S sigma update | 0.133 | 0.053 | 0.090 | 0.663 | 0.452 | 0.335 | 0.385 |

| arm minus A (paired, median over worlds) | sigma med \|lr\| | R1 all rows | R1 Tier-1 rows | R2 | tariff med \|log err\| |
|---|---|---|---|---|---|
| B | 0.000 | -0.060 | +0.033 | +0.002 | 0.000 |
| C | 0.000 | -0.001 | 0.000 | 0.000 | 0.000 |
| D | 0.000 | -0.041 | +0.032 | 0.000 | -0.002 |
| H | 0.000 | -0.034 | +0.014 | +0.001 | -0.001 |
| S | -0.053 | -0.010 | -0.009 | -0.002 | -0.001 |

By structure: in the unstructured worlds (within_sd 0.7) B and D cut the tariff error in all three (0.455 against 0.475, 0.371/0.372 against 0.386, 0.545-0.548 against 0.548) and raise R2 (0.142/0.086 against 0.074); in the structured worlds, where the product prior carries the signal (R2 0.67-0.91 for every arm), every Eq. (11) variant is within +/-0.006 of A on the tariff. S lowers the sigma error in all nine worlds (0.167->0.113, 0.223->0.137, 0.193->0.146, 0.168->0.122, 0.208->0.155, 0.185->0.178, 0.188->0.118, 0.224->0.126, 0.159->0.133) and leaves everything else within +/-0.01; its one visible cost is a cell-mean gamma error of 0.335 against 0.327.

**Readings (rule 5).**
- **C: closed.** Zero paired effect on every reading; wins and loses the Tier-1 comparison in four worlds each. The selection effect on E[q^J] (section 3) is real but does not reach the published gammas under the ridge; the one-world gain of section 5 was noise.
- **D: advances, with a caveat.** Tier-1 within-cell r improves in 8 of 9 worlds (+0.032); the tariff improves where the within-cell heterogeneity is high and is unchanged where it is low. The all-rows r falls in every world (-0.041): the thin exporters (Tier 2 and the reference in the shipped arm, 9% of rows here, a larger share on BACI) are helped by the other exporters' export rows through the joint fit, even as those rows hurt the exporters they belong to. H shows the import-constant guard explains little of that (-0.034 with the constant on) and costs more than half the Tier-1 gain, so H is closed and D is the only Eq. (11) variant left. D redistributes accuracy from thin exporters to Tier-1 exporters; whether that is wanted is a product decision, and the 2% A/B should read the Tier-1 and thin rows separately.
- **S: advances.** The sigma column's error falls by a third at known truth in every world, with no cost elsewhere beyond 0.01. As a pipeline flag: after the third gamma_V pass, profile sigma per cell from the Eq. (10) block at that pass's gamma-hats (every cell with import rows), re-run Stage 2b at the updated sigma with sigma_V from the same table, label `sigma_source` accordingly, and leave the fallback to cells without import rows; optionally iterate. The known-truth harness of section 2 is the acceptance test.

## 8. The sigma update on BACI: the two-window census (patch 0153)

The flag built as patch 0152 (`--stage2-sigma-update import`, default off), measured on independent data the way the M3 record measures sigma: two runs of the whole pipeline on the 2% product subsample (`--product-sample 0.02 --product-seed 20260926`; 25 of 1,240 goods, 228 importers), 1995-2009 and 2010-2024, both under the flag, on the author's machine 2026-10-27 (about 50 min a window at 10 cores: Stage 1 2 min, Stage 2a 2 min, four Stage-2b passes of 10-11 min); `analysis/sigma_update_window_census.R`, record `docs/results/sigma_update_window_census.md`. **Rule, fixed before the numbers (the script's header):** the update advances if the updated sigma's cross-window median |d ln(sigma - 1)| is lower than the Stage-1 sigma's on the common cells AND lower than the global median's, with r not lower than the Stage-1 sigma's.

| window | cells | updated | Stage-1 estimated | at the floor | at the cap |
|---|---|---|---|---|---|
| 1995-2009 | 4,455 | 3,685 | 2,207 | 2 | 230 |
| 2010-2024 | 4,654 | 4,045 | 2,399 | 0 | 221 |

| predictor of the other window's ln(sigma - 1) | cells | median abs cross-window diff | r |
|---|---|---|---|
| updated sigma (cell) | 3,390 | 0.474 | 0.145 |
| global median of the window | 3,390 | 0.364 | -- |
| Stage-1 sigma (cell), cells with a Stage-1 estimate in both windows | 1,189 | 0.965 | 0.041 |
| updated sigma (cell), the same cells | 1,189 | 0.481 | 0.111 |
| global median of the window, the same cells | 1,189 | 0.378 | -- |

**Reading: does not advance under the rule** -- the second bar is not cleared. Two facts are established on the way. The published cell-level sigma has no cross-period reproducibility on BACI (r 0.04; a median error of 0.965 in ln(sigma - 1) is a factor of 2.6 in sigma - 1), which sharpens the M3 reading from "weakly reproducible" to "not reproducible". And the update halves that error and nearly triples the correlation on the same cells while covering 70% more cells: a strictly better cell-level sigma than the incumbent, which still predicts the other window worse than one number does (Spearman-Brown on the half-window correlations: full-panel reliability about 0.08 for the Stage-1 sigma, about 0.20 for the update). The rule conflated "better than the incumbent" (true) with "cell sigma is informative across periods" (still false); it is kept as written. **Decision (MC, 2026-10-28): hold.** The default stays off, the README's caveat stands, and the next step is the shrunk sigma of section 9 -- measured from the same two windows, no new runs.

## 9. The shrunk sigma: census and known truth (patches 0153-0154)

The shrinkage block of `analysis/sigma_update_window_census.R` (rule in its header: the shrunk updated sigma advances if its out-of-sample median |d ln(sigma - 1)| beats the level predictor on all common cells and the shrunk Stage-1 sigma on the Stage-1 common cells; two random halves of the cells, a and b fitted on one and applied on the other, both directions pooled), on the same two BACI windows as section 8:

| predictor | mode | cells | b | median abs out-of-sample diff | r |
|---|---|---|---|---|---|
| updated sigma | level (b = 0) | 3,390 | 0 | 0.376 | -- |
| updated sigma | cell (b = 1) | 3,390 | 1 | 0.472 | 0.145 |
| updated sigma | shrunk (b fitted) | 3,390 | 0.146 | 0.365 | 0.142 |
| Stage-1 sigma, Stage-1 common cells | shrunk (b fitted) | 1,189 | 0.042 | 0.690 | 0.023 |
| Stage-1 sigma, Stage-1 common cells | level (b = 0) | 1,189 | 0 | 0.688 | -- |
| updated sigma, Stage-1 common cells | shrunk (b fitted) | 1,189 | 0.113 | 0.379 | 0.081 |

**Reading: advances**, and the gain is robust -- 0.011 over the level predictor, paired bootstrap 95% CI [0.004, 0.016], the shrunk sigma closer in 55.7% of cell-directions, b 0.142-0.146 and the gain positive under all ten fold seeds. The Stage-1 sigma gains nothing from shrinkage (0.690 against 0.688): the incumbent cell sigma carries no cross-period information. The gain is small and one-sided; it is what the rule asked for.

**Decision (MC, 2026-10-28): build it** -- patch 0154, `--stage2-sigma-shrink B` with `--stage2-sigma-update import`: B is the half-window reliability from the census, the runner applies Spearman-Brown (b_full = 2B / (1 + B); 0.255 for B = 0.146) and publishes sigma = 1 + exp(L + b_full (ln(sigma_update - 1) - L)) with L the median of ln(sigma_update - 1) over the updated cells of the full panel, before the final Stage-2b run so the gammas condition on the published sigma; cells with no updated sigma (profile at the cap or the floor, no import rows) take the level 1 + exp(L), which is also the fallback and the sigma_V default (the Stage-1 sigma is the worse choice for them, section 8); `sigma_update` and `sigma_stage1` are kept beside `sigma`; `sigma_source` reads `updated_import_shrunk` or `updated_level`; `sigma_se`, `sigma_robust`, `gamma_se_total` are NA/FALSE on updated rows. The two 2% window runs become part of any release that touches sigma, since B comes from them.

**Known truth (sandbox world, arm T of the harness):** the shrunk sigma does *not* beat the unshrunk update there -- sigma median |lr| 0.135 against S's 0.118 (mean 0.166 against 0.165), with B = 0.44 from the synthetic two-window census and b_full = 0.61 -- because on that world the updated sigma correlates 0.82 with the truth and the truth-optimal slope is 0.74: Spearman-Brown's extrapolation from the half-window reliability is conservative (0.61 against 0.74), and on a world where the cell signal is strong, shrinkage is neutral in the mean and costs a little in the median. On BACI the half-window reliability is 0.146, the cell signal is weak, and the same shrinkage is what makes the cell sigma beat the level. The right b is the data's own reliability, which the census measures per release; the known-truth reading says the adjustment errs on the conservative side.

## 10. As it will ship: the 2% re-measurement (patch 0155)

Two full-panel runs of the 2% subsample (seed 20260926; 25 goods, 233 importers, ~4,860 cells; about 60 min each at 10 cores), current defaults against `--stage2-sigma-update import --stage2-sigma-shrink 0.146`, read by `analysis/ship_config_census.R` (`docs/results/ship_config_census.md`): sigma moves in 99.7% of cells (median |d ln(sigma - 1)| 0.25; r between the two sigmas 0.29), the fallback population falls from 2,328 cells to 356, 189 capped-profile cells sit at the level, `sigma_robust` goes to 0; gamma moves by more than 1% in 49% of rows (median 0.9%, p90 35%); opt_tariff moves by more than 1% in 91% of cells (median |d ln tau| 0.089; median 0.666 -> 0.692). The known-truth grid's "gamma and tariff unchanged" was a property of worlds where every gamma was 99.7% prior; on BACI the data-weighted rows re-estimate against the new sigma. So the gamma side was read on BACI with the repo's parity A/B -- odd/even halves under both configurations, `analysis/stage2_reliability.R --boot-goods 2000 --boot-seed 20261015 --base base` (`docs/results/stage2_reliability_ship.md`):

| config | keys | cells | r_within | rho_rank | r_raw | sd_within (A / B) |
|---|---|---|---|---|---|---|
| base (current defaults) | 85,100 | 4,020 | 0.357 [0.332, 0.377] | 0.358 | 0.543 | 0.619 / 0.619 |
| ship | 85,400 | 3,990 | 0.380 [0.358, 0.400] | 0.367 | 0.591 | 0.465 / 0.468 |

delta +0.023, goods-bootstrap 95% interval [0.007, 0.040], share of draws with delta <= 0: 0.0015. **Reading: no loss on the within-cell gamma -- a gain, below the +0.03 bar a gamma change would need on its own, which this is not.** Both halves of the pre-registered rule are met on BACI. **Decision (MC, 2026-10-29): ship.** Patch 0155 flips the defaults (`--stage2-sigma-update import`, `--stage2-sigma-shrink 0.146`; 0 turns the shrinkage off; the shrink is ignored when the update is off), makes the profile parallel over goods (forked with the patch-0150 guard on Unix, PSOCK through the estimator's provisioning on Windows -- serial it would take hours on the full data), carries `gamma_v_resid` into the update-pass table, and counts `updated_*` rows out of the fallback share everywhere; the README template, the card and the column notes are written from the censuses in the release patch.

## 11. The full-data release (v0.12.0, 2026-11-08)

One Stage-2b run on the box (r7a.16xlarge, 62 cores; Stage 1 and 2a loaded) under the defaults since patch 0155: the three gamma_V passes (about 36 min each) reproduced v0.11.4's final table exactly -- 6,801,742 published rows, gamma 0.804 -- before the update touched it; the sigma profile took 20.6 min for 211,313 cells (199,857 updated, 11,395 at the cap, 61 at the floor; level sigma 2.678; B 0.146, b_full 0.255); the fourth pass 33 min. Published: 6,829,595 rows (+0.41%; the sigma-low trim 42,853 -> 12,123 rows), sigma median 2.664 (IQR 2.53-2.81), gamma median 0.822, opt_tariff median 0.898; sigma_source updated_import_shrunk 97.0%, updated_level 2.2%, fallback_* 0.8%, estimated 4,646 rows; sigma_robust 0%; non-converged cells 1,775 -> 646. On the 4.8 million shared directly estimated rows gamma moved by a median 3.6% (p90 48%). Release gate PASS under the update's rules (`docs/results/gate_v0120.md`; `analysis/gate_release.R --profile --update-log`, patch 0157). Records: `docs/hf_dataset_card.md` (the v0.12.0 entry), the README's sigma rows, `data/derived/stage2b/..._sigma_update_passes.csv` published beside the table.

## 12. D on BACI (patch 0159): closed

`--stage2-tier1-min-dests Inf` (every exporter but the reference import-only; the hybrid arm D) on the 2% subsample, odd/even parity halves against the shipped configuration's, read on two populations defined by the shipped halves alone (`analysis/reliability_tier_split.R`; `analysis/stage2_reliability.R --boot-goods 2000 --boot-seed 20261015 --base ship`; records `docs/results/stage2_reliability_D_tier1.md` and `_other.md`). Rule, fixed before the numbers: D advances if r_within on the keys that are Tier 1 in both shipped halves rises by >= 0.03 with the goods-bootstrap interval above zero AND on the other estimated keys falls by no more than 0.03.

| population | keys | cells | ship r_within | D r_within | delta (95% goods bootstrap) |
|---|---|---|---|---|---|
| Tier 1 in both shipped halves | 82,165 | 3,710 | 0.358 [0.334, 0.378] | 0.332 [0.310, 0.352] | -0.025 [-0.038, -0.011]; 99.9% of draws <= 0 |
| other (Tier 0 / 2, or Tier 1 in one half) | 4,970 | 685 | 0.043 | -0.076 | -0.119 [-0.194, -0.034] |

**Reading: D fails both halves of the rule and is closed.** The grid's Tier-1 gain (+0.032 in eight of nine worlds, section 7) does not carry to BACI: there the exporter's own export row carries reproducible information about its gamma that the synthetic worlds lack -- a biased moment at known truth (section 3) but a stable one across odd and even years -- and the shipped estimator's wider within-cell spread with it (sd 0.44) is more reliable than D's tighter one without it (0.37; D's raw r is higher, 0.64 against 0.60, its within-cell r lower). The flag stays for experiments; the Eq. (11) line of work is closed at the pipeline level, and the open question that remains is section 3's: what the unexplained half of E[q^J eps^J] is.

## 13. The `2a2b` scope and a standard error for the profile sigma (patch 0160)

**Arm Q (the `2a2b` scope).** The update as in S, then Stage 2a re-estimated at the region medians of the updated cell sigma, the good-level priors and the regional gamma_V medians rebuilt from that Stage 2a, and Stage 2b at the updated sigma with those priors. Rule: Q advances over S if better by >= 0.01 on at least one of sigma error, all-rows within-cell r, Tier-1 r and tariff error over the nine worlds, worse by more than 0.01 on none. Pooled over the nine worlds (medians; `results/known_truth_eq11_arms_by_world.csv`):

| arm | sigma med \|lr\| | R1 all rows | R1 Tier-1 rows | tariff med \|log err\| | paired vs A: Tier-1 r |
|---|---|---|---|---|---|
| S | 0.133 | 0.053 | 0.090 | 0.663 | -0.009 |
| Q | 0.133 | 0.053 | 0.101 | 0.663 | +0.001 |

Per world, Q equals S within 0.004 in seven worlds and is better in the two `good_importer` worlds with importer-level sigma structure (seeds 20261016 and 20261017): Tier-1 r 0.116 against 0.011 and 0.070 against 0.025, all-rows r 0.076 against 0.014 and 0.042 against 0.009, sigma error 0.150 against 0.155 and 0.165 against 0.178, with the tariff unchanged; nowhere is Q worse by more than 0.001. In those two worlds S had lowered the Tier-1 r below the shipped arm's (A: 0.151 and 0.034), and Q recovers most or all of it. The mechanism reads cleanly: when sigma differs systematically by importer, Stage 2a's priors built on the Stage-1 sigma are misaligned with the updated sigma Stage 2b conditions on, and re-running Stage 2a at the updated sigma removes the mismatch; where sigma has no importer structure the priors do not move and Q is S.

**Reading: Q advances under the rule (+0.011 on Tier-1 r pooled, worse nowhere) -- as weak dominance rather than a uniform gain: equal in seven worlds, materially better in the two whose structure BACI may well share.** It is also the consistent block-coordinate step (section D of the flag's design). The `2a2b` scope therefore goes back to open as a candidate: `--stage2-sigma-update-scope 2a2b` implemented in the pipeline (Stage 2a re-run at the updated sigma between the profile and the final pass; minutes, not hours, on the box), measured on the 2% subsample by the parity A/B against the shipped configuration with the usual rule (no loss on r_within; a gain is not required), and only then a release.

**A sandwich standard error for the profile sigma** (`sigma_profile_import()$se_ln`: scores from single-row objective calls at the minimiser over the curvature by a second difference; the import block is separable with the import constant off). Rule: ships if its 95% intervals cover the true sigma on 90-98% of cells at known truth and its median ratio to an exporter-bootstrap SE lies within 0.8-1.25. `validation/known_truth_sigma_se.R` on the sandbox world (180 cells; bootstrap on 30 cells, B = 40):

| reading | value |
|---|---|
| median se_ln (sandwich) | 0.058 |
| median \|ln(sigma_update - 1) - ln(sigma_true - 1)\| | 0.118 |
| coverage of the truth, 95% interval | 45.6% (90% interval 41.7%); z median +1.42 |
| sandwich / exporter-bootstrap ratio | median 0.69 (p25 0.44, p75 0.87); bootstrap sd 0.075 |

**Reading: fails both halves of the rule, for two separate reasons.** The median z of +1.42 is the update's residual heterogeneity bias (section 2: +0.085 in ln(sigma - 1) at within_sd 0.7), which no standard error covers; and the sandwich understates even the sampling part by a third against the bootstrap (a one-parameter asymptotic over J ~ 10 rows). The sampling part could be had cheaply -- the block is separable, so an exact exporter bootstrap follows from per-row objective values on the grid at about twice the profile's cost -- but on this world the error against the truth (0.118) exceeds any sampling SE of the estimator (0.075): the uncertainty of the published sigma is dominated by a bias the data cannot estimate. The table therefore stays as v0.12.0 publishes it -- `sigma_se` NA, `sigma_robust` FALSE and `gamma_se_total` NA on updated rows -- and the per-cell `se_ln` is kept in the run's `_sigma_update_pass1.csv` as a diagnostic only. A labelled sampling-only column is possible; not recommended, because it would be read as the whole uncertainty.

## 14. Open, and next

Open: the `2a2b` scope of the update as a candidate (section 13: implement, then the 2% parity A/B against the shipped configuration); the unexplained half of E[q^J eps^J] (section 3); an export-side constant arm; whether B should be read per good; the residual heterogeneity bias of the update (+0.085 at within_sd 0.7), which is the dominant uncertainty of the published sigma and would need a different estimator, not a standard error. The Eq. (11) variants (sections 1-12) are closed at the pipeline level.
