# Closed-form inversion census (patch 0043 input)

Input: `baci_hs92_v202601_elast_country_hs4_feenstra_sigma.rds` (280,649 cells; 182,385 ok). Generated 2026-09-01 22:58:40 EDT.

## Q1 final_source x closed-form inversion status x omega_floored

| dest | cf_inv | floored | N |
|---|---|---|---|
| all_inversions_failed | eta1_nonpositive | FALSE | 24076 |
| all_inversions_failed | constraint_violated | FALSE |  1765 |
| all_inversions_failed | ok | FALSE |    25 |
| all_inversions_failed | omega_div_zero | FALSE |     2 |
| fail_too_few_exporters | cf_NA | FALSE |  4944 |
| hliml | ok | FALSE | 78523 |
| hliml | constraint_violated |  TRUE | 36914 |
| hliml | ok |  TRUE |     3 |
| hliml_boundary | eta1_nonpositive | FALSE | 12729 |
| hliml_boundary | eta1_nonpositive |  TRUE | 11365 |
| hliml_boundary | ok | FALSE |  1627 |
| hliml_boundary | constraint_violated | FALSE |  1457 |
| hliml_boundary | constraint_violated |  TRUE |   101 |
| hliml_boundary | omega_div_zero | FALSE |    13 |
| hliml_boundary | ok |  TRUE |     4 |
| hliml_boundary | cf_NA | FALSE |     1 |
| prep_thin_n0 | cf_NA | FALSE | 34332 |
| prep_thin_n1 | cf_NA | FALSE |  7538 |
| prep_thin_n2 | cf_NA | FALSE |  4931 |
| prep_thin_n3 | cf_NA | FALSE |  3769 |
| prep_thin_n4 | cf_NA | FALSE |  3076 |
| step1_fail_singular_QWW | cf_NA | FALSE |  1658 |
| step2_fail_singular_QWW_fellback_to_step1 | cf_NA | FALSE |   645 |
| step2_weighted | eta1_nonpositive | FALSE | 14111 |
| step2_weighted | constraint_violated |  TRUE |  8213 |
| step2_weighted | eta1_nonpositive |  TRUE |  6740 |
| step2_weighted | ok | FALSE |  5037 |
| step2_weighted | constraint_violated | FALSE |  4179 |
| step2_weighted | ok |  TRUE |  1359 |
| step2_weighted | omega_div_zero | FALSE |     9 |
| thin_panel_e10_t1 | cf_NA | FALSE |     1 |
| thin_panel_e11_t1 | cf_NA | FALSE |     1 |
| thin_panel_e12_t2 | cf_NA | FALSE |     1 |
| thin_panel_e13_t2 | cf_NA | FALSE |     1 |
| thin_panel_e15_t2 | cf_NA | FALSE |     1 |
| thin_panel_e18_t2 | cf_NA | FALSE |     1 |
| thin_panel_e19_t2 | cf_NA | FALSE |     1 |
| thin_panel_e1_t1 | cf_NA | FALSE |  4808 |
| thin_panel_e1_t10 | cf_NA | FALSE |    71 |
| thin_panel_e1_t11 | cf_NA | FALSE |    66 |
| thin_panel_e1_t12 | cf_NA | FALSE |    55 |
| thin_panel_e1_t13 | cf_NA | FALSE |    44 |
| thin_panel_e1_t14 | cf_NA | FALSE |    40 |
| thin_panel_e1_t15 | cf_NA | FALSE |    35 |
| thin_panel_e1_t16 | cf_NA | FALSE |    28 |
| thin_panel_e1_t17 | cf_NA | FALSE |    39 |
| thin_panel_e1_t18 | cf_NA | FALSE |    27 |
| thin_panel_e1_t19 | cf_NA | FALSE |    21 |
| thin_panel_e1_t2 | cf_NA | FALSE |  1340 |
| thin_panel_e1_t20 | cf_NA | FALSE |    21 |
| thin_panel_e1_t21 | cf_NA | FALSE |    15 |
| thin_panel_e1_t22 | cf_NA | FALSE |    22 |
| thin_panel_e1_t23 | cf_NA | FALSE |    20 |
| thin_panel_e1_t24 | cf_NA | FALSE |     9 |
| thin_panel_e1_t25 | cf_NA | FALSE |    23 |
| thin_panel_e1_t26 | cf_NA | FALSE |     5 |
| thin_panel_e1_t27 | cf_NA | FALSE |     5 |
| thin_panel_e1_t28 | cf_NA | FALSE |     3 |
| thin_panel_e1_t29 | cf_NA | FALSE |     3 |
| thin_panel_e1_t3 | cf_NA | FALSE |   628 |
| thin_panel_e1_t30 | cf_NA | FALSE |     2 |
| thin_panel_e1_t4 | cf_NA | FALSE |   412 |
| thin_panel_e1_t5 | cf_NA | FALSE |   266 |
| thin_panel_e1_t6 | cf_NA | FALSE |   204 |
| thin_panel_e1_t7 | cf_NA | FALSE |   147 |
| thin_panel_e1_t8 | cf_NA | FALSE |   114 |
| thin_panel_e1_t9 | cf_NA | FALSE |   106 |
| thin_panel_e25_t2 | cf_NA | FALSE |     1 |
| thin_panel_e26_t2 | cf_NA | FALSE |     1 |
| thin_panel_e2_t1 | cf_NA | FALSE |   172 |
| thin_panel_e2_t2 | cf_NA | FALSE |  2454 |
| thin_panel_e3_t1 | cf_NA | FALSE |    17 |
| thin_panel_e3_t2 | cf_NA | FALSE |   211 |
| thin_panel_e4_t1 | cf_NA | FALSE |     6 |
| thin_panel_e4_t2 | cf_NA | FALSE |    28 |
| thin_panel_e5_t1 | cf_NA | FALSE |     3 |
| thin_panel_e5_t2 | cf_NA | FALSE |    10 |
| thin_panel_e6_t1 | cf_NA | FALSE |     2 |
| thin_panel_e6_t2 | cf_NA | FALSE |     4 |
| thin_panel_e7_t2 | cf_NA | FALSE |     4 |
| thin_panel_e8_t2 | cf_NA | FALSE |     3 |
| thin_panel_e9_t2 | cf_NA | FALSE |     1 |

## Q2 Interior-HLIML cells whose closed form was constraint_violated (omega clamped from negative)

- n = 36,914 = 13.2% of the universe, 20.2% of ok cells, 32.0% of interior-HLIML cells; all floored: TRUE
- sigma quartiles on these cells: 2.782 / 4.195 / 6.216; share at the sigma cap: 0.0%
- omega_floored cells in total: 64,699 -- interior-HLIML 36,917, Step-2 16,312, boundary omega_floor edge 11,470

## Q3 Projected destination under --stage1-cf-admissibility strict

| proj | N |
|---|---|
| step2_clean | 26636 |
| boundary_or_failed (edge needs raw data) |  5831 |
| step2_capped |  4447 |

- Step-2 omega on the step2_clean re-routes: quartiles 0.000 / 0.000 / 0.346; floored share 68.2%

## Q4 Geometry sanity: shipped boundary cells by adjust code x inversion status

| adjust | cf_inv | N |
|---|---|---|
| 6 | eta1_nonpositive | 11365 |
| 6 | constraint_violated |   101 |
| 6 | ok |     4 |
| 7 | eta1_nonpositive |  5356 |
| 7 | ok |   945 |
| 7 | constraint_violated |   124 |
| 7 | omega_div_zero |    13 |
| 8 | eta1_nonpositive |  7373 |
| 8 | constraint_violated |  1333 |
| 8 | ok |   682 |
| 8 | cf_NA |     1 |

## Q5 sigma movement where Step 2 takes over

- n = 26,636; median |dsigma|/sigma = 0.203 (p75 0.448, p90 0.709); > 10%: 69.1%

