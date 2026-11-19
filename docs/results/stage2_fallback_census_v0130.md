# Stage-2 optimizer fallback census (universe)

Table: `..\te_release\v0.13.0rc1\baci_hs92_v202601_elast_country_hs4_stage2_fallbacks_pass6.csv` (rule: best; rev 215a579, 2026-11-19 01:08:02 EST).

- 834 cells' L-BFGS-B fits did not converge and ran the Nelder-Mead restart (J median 6, p90 31.7, max 149).
- L-BFGS-B codes on those cells: 52 = 834 (1 the iteration cap, 51 a warning, 52 an error -- typically a failed line search; patch 0118).
- On the 834 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 660 (79.1%), lower on 174, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.000 / 0.000 / 0.084 / 1.591.
- The restart reported convergence (simplex collapsed, code 0) on 689 cells; on 535 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 660 cells, Nelder-Mead on 174.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
