# HLIML closed-form census (v0.6.0-rc A/B input)

Input: `baci_hs92_v202601_elast_country_hs4_feenstra_sigma_liml.rds` (280,649 cells; 208,253 reached Step 3). Generated 2026-08-19 14:42:11 EDT.

## Q1 BFGS path x closed form (cells reaching Step 3)

| bfgs_class | cf_class | N |
|---|---|---|
| bfgs_noconv | cf_admissible | 63040 |
| bfgs_noconv | cf_fail |     1 |
| bfgs_noconv | cf_inadmissible | 87388 |
| bfgs_ok | cf_admissible | 52400 |
| bfgs_ok | cf_inadmissible |  5424 |

## Q2 Re-routes: BFGS failed/inadmissible but closed form admissible, by shipped destination

| shipped_dest | N |
|---|---|
| step2_clean | 41783 |
| all_inversions_failed | 13442 |
| capped |  7815 |

Reverse (BFGS ok, closed form not admissible):

| cf_class | N |
|---|---|
| cf_inadmissible | 5424 |

## Q3 Agreement where both admissible

- n = 52,293; median |delta sigma| = 0.0001; within 1%: 95.1%; within 10%: 97.5%
- Q_cf <= Q_bfgs in 99.99% of cells (closed form is the global minimiser; exceptions are eigen/inversion edge cases)
- median sigma: BFGS 1.932 vs closed form 1.914

## Q4 Projected Stage-1 composition under 'closed' routing

| dest | shipped | projected |
|---|---|---|
| step2_clean | 66843 |  24776 |
| all_inversions_failed | 66429 |  52880 |
| hliml_interior | 51038 | 115999 |
| capped | 23943 |  14598 |

sigma-bearing cells (Stage-2 fallback denominator): shipped 141,824 -> projected 155,373 (+13549)

## Q5 Boundary (hybrid) search among closed-form-inadmissible cells

- closed-form-inadmissible cells reaching Step 3: 92,813

Best edge:

| edge | N |
|---|---|
| sigma_floor | 39225 |
| omega_floor | 23047 |
| sigma_cap | 15399 |
| omega_cap | 15142 |

Usable boundary estimate (omega_floor / omega_cap / sigma_cap) by shipped destination:

| shipped_dest | N |
|---|---|
| all_inversions_failed | 29909 |
| step2_clean | 14931 |
| capped |  8415 |
| hliml_interior |   333 |

- all_inversions_failed cells with a usable boundary estimate: 29,909 (median sigma 3.306; at sigma cap 36.9%; on the omega floor 46.3%)

