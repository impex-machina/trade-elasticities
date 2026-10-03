# Stage-2 optimizer fallback census (subsample)

Table: `C:\Users\maxxj\te_grid\fallback_legacy\baci_hs92_v202601_elast_country_hs4_stage2_fallbacks.csv` (rule: legacy; rev 924b734, 2026-10-02 21:03:15 EDT).

- 138 cells reached the L-BFGS-B cap and ran the Nelder-Mead restart (J median 17, p90 49.2, max 88).
- On the 138 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 123 (89.1%), lower on 15, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.000 / 0.080 / 0.707 / 1.566.
- The restart reported convergence (simplex collapsed, code 0) on 77 cells; on 63 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 0 cells, Nelder-Mead on 138.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
