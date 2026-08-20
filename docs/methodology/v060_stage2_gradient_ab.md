# Stage-2 gradient A/B: numeric vs analytic (v0.6.0-rc)

**Date:** 2026-08-19 · **Data:** `v060rc_run_20260819/` (S3), both legs at commit `e82f807` on identical inputs · **Decision:** `--stage2-gradient numeric` **retained** as the v0.6.0 default. The analytic leg's durable home is the S3 `stage2b_analytic/` prefix.

Patch 0028 added an analytic L-BFGS-B gradient for the Stage-2b fixed-sigma
estimation (from the Rcpp Jacobian, certified against central differences in
0029) behind `--stage2-gradient {numeric | analytic}`, with the flip left as a
production A/B decision. This document is that A/B.

## 1. Design

Two full Stage-2b passes on the v0.6.0-rc Stage-1/2a outputs: the numeric leg
(finite-difference gradient, the pre-0028 default) into `out_rc`, the analytic
leg into `out_grad` with Stage-1/2a files copied and the raw cache shared.
Reuse locks, both exact zeros on matched rows: max |Δσ| = 0 and max |Δγ| = 0 on
Tier-3 rows (shared Stage-1 and Stage-2a inputs confirmed). Reference exporters
identical per cell across both legs **and** the v0.5.1 baseline (231,582/231,582),
confirming identical prepared panels.

## 2. Headline marginals

| | v0.5.1 | rc numeric | rc analytic |
|---|---|---|---|
| γ median | 0.678 | **0.657** | 0.664 |
| opt_tariff median | 0.709 | **0.674** | 0.695 |
| Convergence (code = 0) | 70.8% | 68.9% | 61.0% |
| Rows | 6,830,718 | 6,860,437 | 6,861,359 |
| Tier shares 0/1/2/3 (%) | 3.3/70.1/0.2/26.4 | same | same |

The numeric–analytic Δγ of 0.007 is large by this project's standards (the
entire BW calendar-lag correction moved the γ median by 0.001), which made the
flip a live decision and the per-cell adjudication below necessary.

## 3. Optimizer mechanics that shape the comparison

The runner tries L-BFGS-B (maxit 500; `gr` supplied only under `analytic`) and
on **any** non-zero code discards that result and retries Nelder–Mead from the
original start (maxit 1000, gradient-free, hence identical across legs). The
reported `convergence` and `obj_value` come from whichever optimizer ran last.
Consequences: (i) the convergence-rate gap counts cells where the numeric
L-BFGS-B claimed code 0 but the analytic L-BFGS-B *and* the common NM retry did
not; (ii) `obj_value` (minimized; same objective, data, σ, priors in both legs)
is a clean adjudicator; (iii) an analytic L-BFGS-B point at maxit is thrown
away even when it is better than NM's — the cascade, not the gradient, is on
trial alongside the flip.

## 4. Per-cell adjudication (211,262 cells estimated in both legs)

Cell convergence-code cross-tab (numeric rows × analytic columns):

| | 0 | 1 | 10 | Σ |
|---|---|---|---|---|
| **0** | 184,620 | 20,043 | 9 | 204,672 |
| **1** | 914 | 5,671 | 0 | 6,585 |
| **10** | 4 | 0 | 1 | 5 |
| **Σ** | 185,538 | 25,714 | 10 | 211,262 |

**Open disagreements (numeric 0 / analytic non-0), n = 20,052:** analytic
objective *worse* in **96.3%**, better in 3.7%; the gaps are basin-scale, not
plateau-scale — Δobj p10/p50/p90 = +0.30/+4.71/+242, relative median **+33%**;
median |Δ cell-median γ| = 0.11. **Reverse rescues (numeric non-0 / analytic
0), n = 918:** analytic better in 99.5%. **Hidden damage inside the both-0
block (n = 184,620):** analytic worse by > 1e-4 in **12.49%** (~23,070 cells) —
NM rescuing at a worse point behind a matching code 0.

Net: roughly **42,400 cells materially worse under analytic vs ~1,650 materially
better — 22:1 against the flip.** On the ~87% of cells where both L-BFGS-B runs
genuinely converge, the two gradients agree to |Δγ| ~ 1e-5: the FD gradient was
not corrupting converged solutions, so the flip had almost no upside to buy.

Robustness: excluding every cell with any row-membership difference between the
legs (7.6% of cells; see §5) leaves the verdict unchanged — clean-subset open
disagreements 96.4% worse (41:1 with rescues), both-0 damage 11.6% worse vs
15.4% better. Full-sample and clean-subset agree.

**Diagnosis.** This is an indictment of *analytic-plus-the-current-cascade*,
not of the gradient (0029's certification stands). The exact gradient makes
L-BFGS-B honest about flat ridges — it hits maxit where FD false-converges —
and the cascade then discards its point and restarts NM from scratch, which
lands worse. Cascade repair (keep the best-objective result across attempts, or
warm-start NM from the L-BFGS-B abort point) is the v0.7 candidate, with this
A/B as its motivating evidence. Until then, numeric is the better production
estimator and remains the default.

## 5. The tail trim, and what it does to row membership

Reconciling the two legs row-by-row surfaced a pipeline behavior that predates
v0.6.0 and had never been diffed across runs: the **symmetric tail trim**
(`tail_trim_pct = 0.005`). After estimation, Stage 2b drops rows outside the
[0.5%, 99.5%] bands of γ and σ, with bands computed from tier<3 rows and
applied to all rows. Because the bands are **global quantiles of the whole
run's output**, row membership is non-local: any change anywhere — a gradient,
a σ regime — moves the bands and churns membership at the edges dataset-wide,
including in cells whose own estimates are bit-identical.

Evidence, all three artifacts:

* Each file's γ maximum is its own run's ceiling: 14.467 (v0.5.1), 18.391
  (numeric), 13.553 (analytic). σ max = 10.000 in all three (cap mass ≥ 0.5%
  makes the upper-σ cut toothless, as the floor mass at γ = 1e-6 does for the
  lower-γ cut); σ min shows both regimes — the lower cut bound in v0.5.1
  (1.0623) and went toothless in both rc legs (1.0000).
* **2.2–2.9% of cells lack their own reference exporter's row** in every
  artifact (v0.5.1: 5,593 cells, 2.415%) — upper-tail γ_ref rows trimmed. σ-tail
  trims remove whole cells.
* Between the rc legs, ±12k rows (0.17%) differ, concentrated in
  band-edge cells; between either leg and v0.5.1, ~10% of cells differ in
  membership, driven by the σ-regime change. Where the legs share config
  (same σ), their deviations from v0.5.1 are identical in 13,626 cells — the
  trim is deterministic given config; there is no run-to-run lottery
  (consistent with the v0.4.1 anchor's bit-identical reruns).

Membership deltas between the legs are therefore *part of the gradient's
measured effect*, transmitted through the trim — not a confound — which is why
§4 reports the full sample with the clean subset as robustness.

**Disclosure.** The trim ships silently in ≤ v0.6.0 artifacts: the drop count
lands in `run_meta`, which `finalize_saved_output` strips, and the 2b block
printed nothing (fixed in the v0.6.0 code — the log now states the count and
the kept bands). Consumers should know that per-row presence in the saved 2b
table depends on the full-run distribution, and that a cell's `ref_exporter`
may name an exporter with no row of its own.

**Parked for v0.7 (its own adjudication):** flag-don't-drop (a `trimmed`
column instead of removal) or fixed trim bands. Either would make membership
local and the artifact self-documenting; both change every downstream row
count and belong to a data-changing release.

## 6. Incident narrative and protocol lessons

The membership asymmetry was found by the A/B itself and initially
misdiagnosed — six hypotheses (NM parameter NaNs; a γ>0 save filter; SE-block
reassignment; input/cache divergence; bw-weight NAs; reference-exporter swaps)
were falsified in sequence by targeted probes before the trim was identified by
exhaustive read of the save path. Two prior releases carried the same behavior
undetected. Lessons, now encoded:

* **Fingerprint before comparing:** an A/B protocol must verify per-cell panel
  membership (cells × exporter-set hash) before attributing output differences
  to the treatment. Reference-exporter agreement is a cheap sufficient
  fingerprint of identical panels.
* **Echo every estimator flag** in the run header (patch 0034); two legs
  differing only in `--stage2-gradient` were indistinguishable from their logs.
* **Silent filters are landmines:** any row-dropping step must announce its
  count and bounds in the log (patch 0034) — and ideally in the artifact.
* **Eyes on the full log before pattern-grep:** three separate grep patterns
  missed the decisive lines (prep fingerprints, then the trim vocabulary) —
  twice by pattern, once by `tail` truncation.
