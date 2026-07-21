# Eq. (11) sign correction (G1, v0.4.1)

## Finding

The export-side moment equation as **printed** in Soderbery (2018, JIE 114,
Eq. 11) carries the wrong sign on two of its nine coefficients — the terms on
$\Delta\ln s^J_{Vjgt}\,\Delta\ln p^J_{Vjgt}$ (x5) and
$\Delta\ln s^J_{ijgt}\,\Delta\ln p^J_{Vjgt}$ (x6). The proof is internal to
the published paper: Eq. (11) is stated to follow from "multiplying our error
terms from Eqs. (8) and (9) together," and carrying out exactly that
multiplication with the paper's own printed Eqs. (8)–(9) reproduces the
printed Eq. (11) term-for-term on the other seven coefficients **and** on its
stated error term $u = q\varepsilon/(\sigma-1)$, but yields x5 and x6
negated. No appendix or external material is needed to establish the
inconsistency.

From v0.4.1 the pipeline implements the derivation-consistent signs by
default. `paper_exact_eq11 = TRUE` (threaded through `cfg$paper_exact_eq11`
and available on every objective/Jacobian entry point) reproduces the printed
(≤ v0.4.0) behaviour for comparison runs.

## Derivation

The paper's printed export-side curves, with $g_x \equiv \gamma_x/(1+\gamma_x)$
and $\Delta^v z \equiv \Delta z_i - \Delta z_V$ (focal destination $i$ minus
reference destination $V$):

**Supply (Eq. 8):**
$\Delta^v \ln p = g_I \,\Delta\ln s_i - g_V\, \Delta\ln s_V + q$

**Demand (Eq. 9):**
$\Delta^v \ln s = (1-\sigma)\,\Delta\ln p_i - (1-\sigma_V)\,\Delta\ln p_V + \varepsilon$

So the residuals are
$q = \Delta p_i - \Delta p_V - g_I \Delta s_i + g_V \Delta s_V$ and
$\varepsilon = \Delta s_i - \Delta s_V + (\sigma-1)\Delta p_i - (\sigma_V-1)\Delta p_V$
(dropping "ln" for brevity). Expanding $q\varepsilon$, collecting the nine
monomials, pulling $(\sigma-1)\,Y$ with $Y=(\Delta p_i - \Delta p_V)^2$ out of
the price terms, and imposing $E[q\varepsilon]=0$ gives
$Y = \sum_m c_m x_m + q\varepsilon/(\sigma-1)$ with:

| term | regressor | derived $c_m$ | printed (2018) | match |
|---|---|---|---|---|
| x1 | $\Delta s_i^2$ | $\gamma_I/[(1+\gamma_I)(\sigma-1)]$ | same | ✓ |
| x2 | $\Delta s_i \Delta p_i$ | $[\gamma_I(\sigma-2)-1]/[(1+\gamma_I)(\sigma-1)]$ | same | ✓ |
| x3 | $\Delta s_V^2$ | $\gamma_V/[(1+\gamma_V)(\sigma-1)]$ | same | ✓ |
| x4 | $\Delta s_V \Delta p_i$ | $[1-\gamma_V(\sigma-2)]/[(1+\gamma_V)(\sigma-1)]$ | same | ✓ |
| **x5** | $\Delta s_V \Delta p_V$ | $[\gamma_V(\sigma_V-2)-1]/[(1+\gamma_V)(\sigma-1)]$ | $[1-\gamma_V(\sigma_V-2)]/[\cdot]$ | **sign** |
| **x6** | $\Delta s_i \Delta p_V$ | $[1-\gamma_I(\sigma_V-2)]/[(1+\gamma_I)(\sigma-1)]$ | $[\gamma_I(\sigma_V-2)-1]/[\cdot]$ | **sign** |
| x7 | $\Delta s_i \Delta s_V$ | $-[\gamma_V(1+\gamma_I)+\gamma_I(1+\gamma_V)]/[(1+\gamma_I)(1+\gamma_V)(\sigma-1)]$ | same | ✓ |
| x8 | $\Delta p_V^2$ | $(\sigma-\sigma_V)/(\sigma-1)$ | same | ✓ |
| x9 | $\Delta p_V \Delta p_i$ | $(\sigma_V-\sigma)/(\sigma-1)$ | same | ✓ |

The derived set additionally satisfies
$(\sigma-1)Y - \sum_m (\sigma-1) c_m x_m \equiv q\varepsilon$ **identically**
(verified symbolically with sympy), i.e. the corrected equation's error term
is exactly the $u = q\varepsilon/(\sigma-1)$ the paper states for Eq. (11).
The printed x5/x6 cannot produce that error term.

## Likely mechanism

The printed x5 continues x4's visual template $[1-\gamma_V(\cdot-2)]$ and the
printed x6 continues x2's template $[\gamma_I(\cdot-2)-1]$, each with
$\sigma \to \sigma_V$. The algebra flips both when the substitution moves from
the $\Delta p_i$ cross-terms to the $\Delta p_V$ cross-terms. A
pattern-continuation slip in typesetting or transcription is the most
parsimonious explanation.

## Numerical evidence

The structural-DGP harness (`validation/stage2_structural_dgp.R`, Test D)
writes the DGP directly from Eqs. (8)–(9) and evaluates the production
objective at truth:

- corrected signs: residual / outcome scale ≈ 0.002–0.004 at $T=10^5$
  (pure Monte Carlo noise), across a $(\sigma,\sigma_V)$ grid;
- printed signs (`paper_exact_eq11 = TRUE`): 0.32–1.56 of the outcome
  scale — a ≥ 80× separation. The printed equation is Test D's permanent
  negative control, so any regression toward it fails CI.

## Scope and open item

This establishes an inconsistency in the **published display**. Whether
Soderbery's own 2018 *estimation code* used the printed or the corrected
signs is not determinable from the G&S (2024) replication package (the 2024
system is the homogeneous case and contains no Eq. 11); his 2018 Stata code
(Purdue "Elasticities" page) would settle it, and a courteous query to the
author is the intended next step. If the published heterogeneous-elasticity
dataset was produced with the printed signs, its $\gamma$ estimates inherit
the issue; the import-side $\sigma$ estimates are unaffected either way.

Releases ≤ v0.4.0 of this repository implemented the printed signs; v0.4.1
switches the default to the derivation-consistent signs. Stage-2b outputs
must be regenerated after upgrading.
