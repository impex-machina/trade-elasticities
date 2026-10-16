# Stage-1 sigma accuracy by route, at known truth (patch 0127)

18 known-truth worlds from `validation/known_truth_stage2.R` under `C:\Users\maxxj\te_known_truth` (2,542 cells with an estimate); rev d62301a, 2026-10-16 09:40:49 EDT. Errors on ln(sigma - 1): bias is the median of ln((s_hat - 1)/(s - 1)), error the median of its absolute value; published is the sigma Stage 2 uses (own if in the clean set, else the fallback).

## All worlds

| route | cells | bias (raw) | error (raw) | within 1.5x | in clean set | bias (published) | error (published) |
|---|---|---|---|---|---|---|---|
| hliml | 1913 | 0.066 | 0.224 | 71.0% | 85.2% | 0.077 | 0.186 |
| hliml_boundary | 345 | 0.106 | 0.347 | 54.5% | 69.0% | 0.044 | 0.186 |
| step2_weighted | 284 | 0.338 | 0.343 | 56.3% | 66.5% | 0.184 | 0.224 |

## Shock scale x1

| route | cells | bias (raw) | error (raw) | within 1.5x | in clean set | bias (published) | error (published) |
|---|---|---|---|---|---|---|---|
| hliml | 948 | 0.074 | 0.230 | 68.2% | 84.1% | 0.086 | 0.185 |
| hliml_boundary | 192 | 0.120 | 0.360 | 53.1% | 68.8% | 0.081 | 0.168 |
| step2_weighted | 135 | 0.384 | 0.384 | 54.1% | 67.4% | 0.179 | 0.241 |

## Shock scale x3

| route | cells | bias (raw) | error (raw) | within 1.5x | in clean set | bias (published) | error (published) |
|---|---|---|---|---|---|---|---|
| hliml | 965 | 0.057 | 0.216 | 73.8% | 86.2% | 0.066 | 0.187 |
| hliml_boundary | 153 | 0.021 | 0.291 | 56.2% | 69.3% | 0.004 | 0.200 |
| step2_weighted | 149 | 0.320 | 0.329 | 58.4% | 65.8% | 0.184 | 0.212 |

## Real cells by route (shipped Stage-1 table)

| route | cells with an estimate | share | in the clean set |
|---|---|---|---|
| hliml | 81,146 | 44.4% | 53,136 |
| hliml_boundary | 56,461 | 30.9% | 29,913 |
| step2_weighted | 45,305 | 24.8% | 30,657 |

**Reading (fixed in patch 0127): biased** -- Step-2 raw bias > +0.2 AND raw error >= 1.5x the hliml route's, at every shock scale.
