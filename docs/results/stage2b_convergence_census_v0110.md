# Stage-2b optimizer convergence census (v0110)

Table `data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (sha256 88bc67f5be0dcc35...; rev ed066cb, 2026-10-14 21:56:58 EDT). Published rows only.

- Directly estimated rows (tier 0-2, fitted): 4,982,259 of 6,801,742 published rows.
- **Optimizer non-convergence**: 35,825 rows (0.72% of directly estimated rows) in 1,775 of 210,098 fitted cells -- the cells whose published point is not a converged optimum: L-BFGS-B stopped without converging (code 52, typically a failed line search, or 1, the iteration cap) and the Nelder-Mead restart did no better or was published without converging.
- Codes among directly estimated rows: 0 = 4,946,434, 1 =     2,397, 52 =    33,428 (0 converged; 1 iteration cap; 10 Nelder-Mead degeneracy; 51 L-BFGS-B warning; 52 L-BFGS-B error, typically a failed line search).
- Counting the rows the tail trim flagged too: 1,928 cells with a non-converged directly estimated row (153 whose non-converged rows were all flagged).
- `gamma_se_status == "non_converged"` on directly estimated rows: 35,825 (equal to the code count).
- Imputed reference rows (tier 0, convergence -1: the reference of a cell whose other exporters are all Tier 3): 20,895, 0.42% of tier < 3 rows -- the figure the release gates reported as optimizer non-convergence through patch 0115.
- Tier 3: 1,798,588 rows (26.44% of published rows).

| tier | rows | directly estimated | optimizer non-converged | imputed (-1) |
|---|---|---|---|---|
| 0 |   222,765 |   201,870 |  1,626 | 20,895 |
| 1 | 4,765,628 | 4,765,628 | 34,026 |      0 |
| 2 |    14,761 |    14,761 |    173 |      0 |

