# Stage-2b optimizer convergence census (v0130)

Table `data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds` (sha256 c71ab4053a101b6c...; rev 215a579, 2026-11-19 01:07:05 EST). Published rows only.

- Directly estimated rows (tier 0-2, fitted): 5,011,870 of 6,841,382 published rows.
- **Optimizer non-convergence**: 9,494 rows (0.19% of directly estimated rows) in 678 of 211,119 fitted cells -- the cells whose published point is not a converged optimum: L-BFGS-B stopped without converging (code 52, typically a failed line search, or 1, the iteration cap) and the Nelder-Mead restart did no better or was published without converging.
- Codes among directly estimated rows: 0 = 5,002,376, 1 =       790, 52 =     8,704 (0 converged; 1 iteration cap; 10 Nelder-Mead degeneracy; 51 L-BFGS-B warning; 52 L-BFGS-B error, typically a failed line search).
- Counting the rows the tail trim flagged too: 680 cells with a non-converged directly estimated row (2 whose non-converged rows were all flagged).
- `gamma_se_status == "non_converged"` on directly estimated rows: 9,494 (equal to the code count).
- Imputed reference rows (tier 0, convergence -1: the reference of a cell whose other exporters are all Tier 3): 20,933, 0.42% of tier < 3 rows -- the figure the release gates reported as optimizer non-convergence through patch 0115.
- Tier 3: 1,808,579 rows (26.44% of published rows).

| tier | rows | directly estimated | optimizer non-converged | imputed (-1) |
|---|---|---|---|---|
| 0 |   220,119 |   199,186 |   588 | 20,933 |
| 1 | 4,797,808 | 4,797,808 | 8,849 |      0 |
| 2 |    14,876 |    14,876 |    57 |      0 |

