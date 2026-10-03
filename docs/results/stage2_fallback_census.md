# Stage-2 optimizer fallback census (universe)

Table: `C:\Users\maxxj\te_rc\v083\baci_hs92_v202601_elast_country_hs4_stage2_fallbacks.csv` (rule: best; rev 6c70557, 2026-10-02 22:48:20 EDT).

- 7,295 cells reached the L-BFGS-B cap and ran the Nelder-Mead restart (J median 20, p90 52, max 178).
- On the 7,295 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 6,274 (86.0%), lower on 1,021, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.000 / 0.083 / 0.644 / 2.134.
- The restart reported convergence (simplex collapsed, code 0) on 3,672 cells; on 2,768 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 6,274 cells, Nelder-Mead on 1,021.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
