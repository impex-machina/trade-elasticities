# The Stage-1 sample rule: tested, not adopted (2026-09-22)

## Question

Stage 2 drops differenced observations with |Δ ln p| ≥ 2.0 before estimating
γ; Stage 1 estimates σ on the untrimmed cache. Should Stage 1 use the same
sample? The consistency argument says yes — γ is estimated conditional on σ,
so identifying σ on observations the γ stage discards is incoherent. This
note records the test and why the answer is no.

## Evidence

**Universe A/B** (`v072_v080rc_compare_runs.md`; S3 `v080rc_run_20260922/`):
`--stage1-uv-trim 2.0` on the v0.7.2 command line.

| | v0.7.2 (untrimmed) | rc (trim 2.0) |
|---|---|---|
| differenced observations | 80.4M | 72.3M (−10.1%) |
| cells touched (lost ≥ 1 observation) | — | 71.5% |
| untouched cells: σ changed | — | **0** (effect is purely direct) |
| σ median (p25 / p75) | 2.462 (1.58 / 4.90) | 3.731 (2.06 / 7.72) |
| σ at the cap, clean cells | 13.7% | **19.0%** |
| σ-SE coverage / σ-robust rows | 89.8% / 17.6% | 84.2% / 14.9% |
| interior / boundary / Step 2 | 43.3 / 30.5 / 26.2% | 47.8 / 24.6 / 27.6% |
| ω at the cap | 20.6% | 12.3% |
| 2b γ median; γ > 1 | 0.650; 21.4% | 0.419; 7.1% |
| γ-SE ok; γ boundary status | 54.7%; 11.3% | 64.6%; 2.8% |
| opt_tariff median | 0.649 | 0.515 |
| tiers | 3.3 / 70.0 / 0.2 / 26.4 | 3.3 / 70.1 / 0.2 / 26.4 |
| σ coverage churn | — | 18,562 cells gain a σ, 18,463 lose one |
| structural ratios vs Soderbery (0.408 / 0.532 / 0.217) | 0.394 / 0.684 / 0.234 | 0.295 / 0.366 / 0.108 |

**Threshold curve** (same 5,613-cell subsample, seed 20260921, serial;
`docs/results/sigma_uv_trim_sensitivity_{obs,t3,t15}.md`):

| rule | σ median | p25 / p75 | cells identical | signed median Δσ/σ | route changed |
|---|---|---|---|---|---|
| untrimmed | 2.466 | 1.56 / 4.80 | — | — | — |
| \|Δ ln p\| < 3.0 | 3.003 | 1.78 / 5.67 | 14.9% | +2.9% | 39.5% |
| \|Δ ln p\| < 2.0 | 3.636 | 2.06 / 7.40 | 7.0% | +23.8% | 51.0% |
| \|Δ ln p\| < 1.5 | 4.536 | 2.31 / 9.23 | 4.9% | +46.6% | 54.3% |

The subsample's untrimmed median (2.466) matches the universe (2.462); its
2.0 result (3.636) matches the universe rc (3.731) to within the subsample's
noise.

## Reading

σ rises with every tightening and never plateaus: +22%, +47%, +84%. If the
rule were removing a distinct population of mismeasured unit values, σ
would move once and stabilise; instead it tracks the threshold. Feenstra's
estimator identifies σ from the variance of Δ ln p across exporters; any
rule that removes large price movements removes identifying variance,
signal and noise alike, and pushes σ up without limit — at 1.5 a quarter of
cells sit at or near the cap of 10. The universe rc shows the same thing
from the other side: the trimmed run pins 19.0% of clean cells at the cap
against 13.7%, and σ-SE coverage and the σ-robust screen fall with it.

The γ stage, by contrast, is healthier under the trim (γ-SE coverage up ten
points, boundary status down from 11.3% to 2.8%), which is why Stage 2
trims and should continue to.

## Decision

- The Stage-1 sample stays untrimmed. v0.7.2 remains the current release.
  No threshold can be defended as "the clean σ", so none is shipped as the
  headline.
- The asymmetry between the stages is a stated design choice: Stage 1
  needs the price variation; Stage 2's moment equations do not lean on it
  the same way and keep the inherited rule.
- The trimmed σ is a robustness result. `--stage1-uv-trim` stays in the
  pipeline; the subsample script and the rc artefacts are the record; the
  card carries a sentence pointing here.
- Consequence for readers: σ from HS4 BACI unit values is sensitive to
  cleaning rules, and any comparison with a σ estimated under a different
  rule (including Soderbery's) must say which rule.

## What was built and kept

`--stage1-uv-trim` (0057), `analysis/sigma_uv_trim_sensitivity.R` (0052,
0056, 0059: `--variant obs|row`, `--threshold`, cap-share and route-mix
lines). Not adopted: the per-cell `sigma_untrimmed` columns proposed for a
trimmed release (patch 0058, never applied).

## Paper paragraph (draft)

*We tested whether σ should be estimated on the same trimmed sample as γ.
Applying the |Δ ln p| < 2 rule inside the Feenstra stage raises the median
σ from 2.46 to 3.73 on the full universe and moves 84% of cells by more
than 10%; a threshold curve on a fixed subsample shows σ rising
monotonically as the rule tightens (3.00, 3.64, 4.54 at 3.0, 2.0, 1.5) with
no plateau, while the share of cells at the σ cap rises from 14% to 19%.
The rule removes identifying price variance rather than a distinct
population of mismeasured observations, so no threshold is privileged. We
therefore report σ on the untrimmed sample, treat the trimmed estimates as
a robustness check, and note that comparisons across studies must state
the unit-value cleaning rule under which σ was estimated.*
