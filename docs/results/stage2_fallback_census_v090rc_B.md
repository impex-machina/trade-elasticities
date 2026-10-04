# Stage-2 optimizer fallback census (v090rc_B)

Table: `C:\Users\maxxj\te_rc\v090\out_B\baci_hs92_v202601_elast_country_hs4_stage2_fallbacks.csv` (rule: best; rev 57df7d4, 2026-10-04 01:23:43 EDT).

- 8,975 cells reached the L-BFGS-B cap and ran the Nelder-Mead restart (J median 20, p90 55, max 197).
- On the 8,975 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 7,593 (84.6%), lower on 1,382, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.001 / 0.049 / 0.537 / 2.076.
- The restart reported convergence (simplex collapsed, code 0) on 4,531 cells; on 3,344 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 7,593 cells, Nelder-Mead on 1,382.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
