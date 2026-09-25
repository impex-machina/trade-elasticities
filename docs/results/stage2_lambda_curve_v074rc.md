# Stage-2b γ against the shrinkage λ — full-universe curve (v0.7.4-rc, 2026-09-25)

Five Stage-2b passes on the box session `v074rc_run_20260925/` (Stage 1 and the Stage-2a priors held at the rc values, `--stage2-ridge-domain all`, legacy SE form), each read with `analysis/stage2_shrinkage_census.R` (`docs/results/stage2_shrinkage_census_v074rc_lambda<λ>.md`; the λ = 0.1 row is the rc census). Directly estimated rows only (tier 0/1/2, fitted).

| λ | rows (2b) | `shrink_wt` p50 | data share p50 / trade-wt | var(log γ) | exporter-within-cell share (unw / tw) | \|dev\| p50 / p90 | within-cell sd(log γ) p50 | \|log opt_tariff − ln prior\| p50 |
|---|---|---|---|---|---|---|---|---|
| 0.1 (shipped) | 6,811,822 | 0.962 | 0.072 / 0.227 | 0.689 | 0.599 / 0.396 | 0.101 / 1.185 | 0.635 | 0.356 |
| 0.01 | 6,812,379 | 0.867 | 0.234 / 0.347 | 1.337 | 0.693 / 0.464 | 0.211 / 1.784 | 1.051 | 0.489 |
| 0.001 | 6,812,090 | 0.522 | 0.646 / 0.522 | 2.191 | 0.746 / 0.528 | 0.201 / 2.307 | 1.469 | 0.474 |
| 0.0001 | 6,832,756 | 0.106 | 0.944 / 0.719 | 5.443 | 0.724 / 0.556 | 0.228 / 3.429 | 2.037 | 0.506 |
| 0 | 6,744,736 | 0 | 1 / 1 | 26.877 | 0.810 / 0.590 | 0.271 / 12.525 | 5.682 | 0.555 |

`shrink_wt` and the data share are in the legacy definition (2λ/γ²; data share 2(1−s)/(2−s)); dev = log γ − ln prior, prior = median log γ by good over the rc Stage-2a table (across-good sd of ln prior 0.427).

Reading. The median row's distance from the prior is essentially captured by λ ≈ 0.01 (0.21) and hardly moves below it (0.27 at λ = 0), while every tail statistic explodes: |dev| p90 1.8 → 2.3 → 3.4 → 12.5, var(log γ) 1.3 → 2.2 → 5.4 → 26.9, within-cell sd 1.05 → 1.47 → 2.04 → 5.68. That is the signature of noise amplification, not of signal being released. Two further features: (i) at λ ≤ 10⁻³ a population of ~140k rows heads toward γ ≈ 0 (`shrink_wt` ≈ 1 with |dev| ≈ 7 in the λ = 10⁻⁴ census's top bin, because the ridge Hessian 2λ/γ² blows up as γ → 0) — exporters whose moments say near-perfectly-elastic supply, plausible for a small exporter in a large market, which a prior on **log** γ cannot represent at any λ and which the v0.7.3 hole used to dump at the floor; (ii) the σ-side and tier structure are untouched by λ (tiers depend on the data only), so the row-count differences are trim membership.

Decision. λ stays at 0.1 for v0.7.4. The λ question is entangled with the prior's form (level-space or bounded pass-through-share prior that allows γ → 0), the measurement-error treatment (Soderbery fn. 14) and the reference-exporter export moment; those are the v0.8.0 items, with a split-half reliability criterion on a product subsample as the decision-grade test for λ once they are in.
