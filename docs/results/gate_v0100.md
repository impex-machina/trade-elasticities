# v0.10.0 gate: baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds -> baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds

Stage 1: `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds`. Generated 2026-10-12 18:04 EDT.

## Stage-1 cell classes

| class | cells |
|---|---|
| no_estimate |  97,737 |
| other | 113,706 |
| sigma_edge |  13,810 |
| sigma_pole |  55,396 |

## Rows and schema

- old: 6,806,221 rows (6,806,221 published), 22 columns; new: 6,892,008 rows (6,801,807 published), 22 columns.
- flagged trimmed rows in new: 90,201 (gamma_hi 24,249, gamma_lo 23,099, sigma_lo 42,853).
- gamma_v_resid filled on 4,911,380 of 6,801,807 published rows (72.2%); p50 2.32e-04 p90 0.014 p99 0.245.

## Fallback sigma

- old: 2.3059 on 15.2% of published rows; new: 2.4728 on 41.0% of published rows.
- sigma-pole cells in new: 1,751,963 rows; share at the fallback 100.0%; sigma_robust TRUE on 0.0%.

## Headline (published rows)

| | old | new |
|---|---|---|
| gamma median | 0.6441 | 0.8064 |
| opt_tariff median | 0.7327 | 0.8687 |
| sigma median | 2.3059 | 2.4728 |
| ok share | 70.9% | 72.6% |
| optimizer non-converged (directly estimated rows) | 0.42% | 0.42% |
| Tier 3 | 26.4% | 26.4% |
| sigma_robust TRUE | 24.4% | 24.2% |
| gamma <= 0.01 (estimated) | 0.403% | 0.000% |
| gamma >= 10 (estimated) | 0.657% | 0.281% |

## |ln gamma_new - ln gamma_old| on shared directly estimated rows, by Stage-1 class

| class | rows | p50 | p90 | p99 | below 1e-2 |
|---|---|---|---|---|---|
| no_estimate |   488,980 | 1.82e-01 | 0.413 | 1.266 | 2.7% |
| other | 2,998,094 | 1.54e-01 | 0.393 | 1.101 | 4.6% |
| sigma_edge |   205,004 | 1.78e-01 | 0.416 | 1.337 | 3.0% |
| sigma_pole | 1,230,987 | 3.74e-01 | 1.733 | 3.931 | 1.6% |

## gamma_V pass log

        pass from_pass usable_rows tier1_rows abs_dlng_p50 abs_dlng_p90
       <int>     <int>       <int>      <int>        <num>        <num>
    1:     2         1     4935903    4691081 0.0013728993   0.06069580
    2:     3         2     4942220    4698517 0.0002126786   0.01315743
       abs_dlng_p99 abs_dlng_max share_lt_1e2
              <num>        <num>        <num>
    1:    0.6205624     6.170042    0.7341319
    2:    0.2322313     5.765834    0.8831282

## Result

**PASS**
