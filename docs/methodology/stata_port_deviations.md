# Stata port deviation ledger (G5, v0.4.1)

Stage 1 of this pipeline is a port of the Grant & Soderbery (2024)
replication package (`GS_Data.do`, `GS_Estimation.do`,
`mata_LIMLhybrid_hetero.do`). This ledger records every place where the port
**deliberately deviates** from the Stata source, with file/line citations to
the replication package, so parity expectations against Stata outputs are
explicit. Line numbers refer to the 2024 package as distributed.

## A. Confirmed Stata defects the port corrects

| # | Stata source | Behaviour there | Port behaviour | Basis |
|---|---|---|---|---|
| A1 | `GS_Estimation.do:78` (Step 2) and `:186` (HLIML) | Delta-method matrix is the elementwise-absolute **transpose** of the correct $\partial(\sigma,\rho)/\partial(\eta_1,\eta_2)$ Jacobian with dropped cross-term signs; the two steps also disagree with each other on where the transpose sits (`d*V*d` at `:80` vs `d'*V*d` at `:188` — neither is $JVJ'$) | Correct closed-form Jacobian, standard $JVJ'$ sandwich (B4, v0.3.0) | Re-derived analytically; verified against numerical differentiation |
| A2 | `GS_Estimation.do:80,188` (`/(n-l)`) and `:175` (`(1/n)`) | SE quadratic forms divided by $n-l$ (Step 2 and HLIML) and $v\_bar$ additionally scaled by $1/n$ (HLIML) | Both divisions dropped | `e(V)` and $H^{-1}\Sigma H^{-1}$ are already properly scaled; synthetic bootstrap shows corrected SEs match bootstrap SDs while the Stata-scaled versions are too small by ~$\sqrt{n(n-l)}$ (~500× at HLIML cell sizes) |
| A3 | `GS_Estimation.do:65` | `omega_w = rho_w/(sigma - 1 - sigma*rho_w)` uses the **Step-1** `sigma` variable (already capped at 10 by `:37`) instead of `sigma_w` | `invert_structural()` computes $\omega$ from the same step's $\sigma$ | Internal consistency of the Feenstra inversion |
| A4 | `GS_Estimation.do:178` | `F = l*(e'P_diff e)/(e' * e:^2)` — denominator is $\sum_i e_i^3$ (odd-power, sign-sensitive) | `fstat_het` uses $\sum_i e_i^4$ | Dimensional consistency with the fourth-moment denominator of the companion J statistic (`:180`) |
| A5 | `mata_LIMLhybrid_hetero.do:17-18` | The `exp(log(d-1))` "constraint" mutates a local copy of `d` *after* the thetas are computed and never feeds back into `Q`; the Mata HLIML optimizer is therefore effectively **unconstrained** during optimization | `hliml_core()` returns a large finite penalty when $\sigma \le 1$ or $\omega \le 0$, so the optimizer genuinely respects the admissible region | Code reading; the Stata feasibility-adjust block (`:200-214`) only catches missing/negative results after the fact |
| A6 | `GS_Estimation.do:211-213` | HLIML-at-cap ($\sigma = 10$) falls back to `sigma_w`, which is **never capped** — Stata's final $\sigma$ can exceed 10 through the fallback | Fallback is capped at 10 with explicit `sigma_capped`/`omega_capped` flags (B9/A1 semantics, v0.3.0) | Downstream consumers need a bounded, flag-annotated schema |
| A7 | `GS_Estimation.do:31-33` | `global rho` is captured **between** the ceiling clamp and the floor clamp, so the $\sigma$ built at `:34` can use an un-floored $\rho$ | Both clamps applied before $\sigma$ is computed | Internal consistency |

## B. Documented statistic/convention divergences (not defects in either)

| # | Topic | Stata / G&S published protocol | Port | Notes |
|---|---|---|---|---|
| B1 | Weak-IV statistic | `ivreg2 ... robust`: `e(widstat)` = robust Kleibergen–Paap rk Wald F (`GS_Estimation.do:58`); `e(cdf)` also captured | Homoskedastic Cragg–Donald **minimum eigenvalue** (B7, v0.3.0), stored as `fstat_kp` for schema stability | SY critical values are tabulated for CD; the robust KP has no exact SY theory. Comparisons of F distributions to G&S Table 3 are approximate |
| B2 | Overidentification statistic | Step-2 `e(j)` under `robust` is the **Hansen J** (`:59`); the *published screening* uses the HLIML-residual Hausman–Newey J (`jstat`, `:225-227`) | `jstat` = homoskedastic **Sargan** in the Step-2 weighted metric (B8); `jstat_h` = the same HN J as Stata | v0.4.1 adds `sargan_pass_gs` reproducing G&S's published screen from `jstat_h` |
| B3 | Screening dof / CV rows | `error_construct.do`: J screened at $\chi^2(\text{suppliers}-3)$ with suppliers = total exporters incl. reference, CDF < 0.8; SY CVs merged from `StockYogo2005_2EndogRegFullerCritVals.dta` at total supplier count; `Step_5` (MC) uses suppliers − 2 | Headline screens use the **effective** excluded count $J_{nr}-1$ (dummies span the constant once reference rows are dropped; G3, v0.4.1); `gs25`/`sargan_pass_gs` reproduce the G&S row/dof conventions for comparability | ivreg2 itself drops one collinear dummy, so the effective count is also what Stata's *estimation* used; G&S's *post-hoc screening* conventions differ from both and from each other |
| B4 | SY table provenance | Their package file is the **Fuller** size-CV table | Same values (sourced from their package), previously mislabeled "LIML" in the header comment | Arguably correct for the Fuller(1) Step-2 screen; SY tabulate nothing for HLIML. TODO: verify values against SY (2005) directly |
| B5 | HLIML optimizer | Mata Newton–Raphson, `nr`, effectively unconstrained (A5) | BFGS on the penalized objective | Interior optima agree; boundary behaviour can differ (see A5/A6) |
| B6 | ω start floor | `:39` floors only **negative** ω at 0.001 | Floors ω < 0.001 as well | Immaterial for starts |
| B7 | Reference selection | `GS_Data.do:45-73`: longest panel ∧ `cusval ≥ max`, fallback `≥ p90`, fallback longest-only; remaining ties broken by `gsort -ref` (largest group id) | Longest panel, ties by cumulative trade value | Deterministic and value-based; differs from GS only in tie-break cascade |
| B8 | Unit-value aggregation | `GS_Data.do:11`: `collapse (mean) uv` — mean of unit values across sub-rows | $\ln(\text{value}/\text{quantity})$ on BACI aggregates | Data-source difference (BACI is already reconciled); ratio-of-sums vs mean-of-ratios |

## C. Confirmed faithful (spot-verified against the .do files)

Minimum-data gates (`_N < 5 | products < 3`, `GS_Estimation.do:3`); all-zero
row drop (`GS_Data.do:98`) — reference-exporter rows are excluded in both
implementations; Fuller(1) LIML in Steps 1–2 (`:18`, `:51`); per-exporter
residual-variance weighting and the $1/\hat{s}$ HLIML rescale (`:45-49`,
`:94-96`); the LIML2 jackknife objective $A'(P-\mathrm{diag}P)A/A'A$
(`mata:22`); the HNCS sandwich structure (`:156-174`); the HN J formula
(`:180`); starting-value caps ($\sigma$ at 10, $\omega$ in [0.001, 10],
`:37-41`); the feasibility-adjust cascade semantics (`:200-214`, extended by
B9 flags); $\rho = \omega(\sigma-1)/(1+\sigma\omega)$ (`:142`).

## D. Upstream issues flagged to the authors (not ported, not corrected here)

- `error_construct.do`: `gen double omega_FR = omega2/1+omega2` — operator
  precedence makes this $2\omega_2$, not $\omega_2/(1+\omega_2)$. Affects
  the Feenstra–Romalis comparison construction if that variable feeds the
  published comparison columns.
- Soderbery (2018) Eq. (11) printed x5/x6 signs — see
  `eq11_sign_correction.md`.
