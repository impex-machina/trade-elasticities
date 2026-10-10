# Stage-2 optimizer fallback census (universe)

Table: `C:\Users\maxxj\te_rc\v090rel\out_G2\baci_hs92_v202601_elast_country_hs4_stage2_fallbacks_pass3.csv` (rule: best; rev 7af3f5a, 2026-10-10 03:04:07 EDT).

- 7,710 cells reached the L-BFGS-B cap and ran the Nelder-Mead restart (J median 20, p90 53, max 197).
- On the 7,710 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 6,641 (86.1%), lower on 1,069, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.000 / 0.074 / 0.668 / 2.457.
- The restart reported convergence (simplex collapsed, code 0) on 3,925 cells; on 2,983 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 6,641 cells, Nelder-Mead on 1,069.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
