# Stage-2 optimizer fallback census (universe)

Table: `C:\Users\maxxj\te_runs\v0110rel_run_20261014\out_I\baci_hs92_v202601_elast_country_hs4_stage2_fallbacks_pass3.csv` (rule: best; rev ed066cb, 2026-10-14 21:56:59 EDT).

- 2,370 cells' L-BFGS-B fits did not converge and ran the Nelder-Mead restart (J median 13, p90 46, max 180).
- L-BFGS-B codes on those cells: 1 =     7, 52 = 2,363 (1 the iteration cap, 51 a warning, 52 an error -- typically a failed line search; patch 0118).
- On the 2,370 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 1,868 (78.8%), lower on 502, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.002 / 0.013 / 0.285 / 1.300.
- The restart reported convergence (simplex collapsed, code 0) on 1,561 cells; on 1,119 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 1,868 cells, Nelder-Mead on 502.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
