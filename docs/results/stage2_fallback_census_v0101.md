# Stage-2 optimizer fallback census (universe)

Table: `C:\Users\maxxj\AppData\Local\Temp\v0100_stage2_fallbacks_pass3.csv` (rule: best; rev 1e5d5ac, 2026-10-13 19:38:31 EDT).

- 2,730 cells reached the L-BFGS-B cap and ran the Nelder-Mead restart (J median 13, p90 45, max 176).
- On the 2,730 cells with both objectives finite, the restart's objective was higher than the discarded L-BFGS-B point on 2,167 (79.4%), lower on 563, tied on 0; L-BFGS-B errored on 0, Nelder-Mead on 0.
- Restart objective relative to the L-BFGS-B point (ratio - 1), quantiles p10 / p50 / p90 / p99: -0.003 / 0.013 / 0.315 / 1.569.
- The restart reported convergence (simplex collapsed, code 0) on 1,794 cells; on 1,306 of them the L-BFGS-B point is better, so under `best` those rows publish that point and read `non_converged` where legacy read `ok` at a stalled point.
- Published point: L-BFGS-B on 2,167 cells, Nelder-Mead on 563.

Rule: `--stage2-fallback best` (v0.8.3 default, patch 0080) keeps the lower objective; `legacy` (through v0.8.2) published the restart unconditionally. The table records both outcomes under either rule.
