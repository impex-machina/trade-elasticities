# Sandwich standard errors for Stage 2b fixed-sigma estimator

## Goal

Compute publication-grade standard errors for $\gamma_k$ and each $\gamma_j$ produced by `feen94_het_baci.R`'s per-cell fixed-sigma optimizer, accounting for trade-value weighting and heteroskedasticity in the residual variance.

## Statistical setup

The objective at cell level is (ignoring shrinkage penalty for now; see §6):

$$
Q(\theta) = \underbrace{\sum_{j=1}^{J} w^{imp}_j \, r^{imp}_j(\theta)^2}_{\text{import side}}
          + \underbrace{\sum_{m=1}^{N_{exp}} w^{exp}_m \, r^{exp}_m(\theta)^2}_{\text{export side}}
$$

where $\theta = (\gamma_k, \gamma_1, \ldots, \gamma_J)$ has $K = J+1$ parameters. The optimizer returns $\hat\theta = \arg\min Q$.

For weighted nonlinear least squares, the heteroskedasticity-robust ("sandwich") covariance estimator is:

$$
\widehat{\text{Var}}(\hat\theta)
  = A^{-1} \, B \, A^{-1}
$$

where

$$
A = \sum_{i=1}^{n} w_i \, \nabla r_i \, \nabla r_i^\top
$$

$$
B = \sum_{i=1}^{n} w_i^2 \, r_i^2 \, \nabla r_i \, \nabla r_i^\top
$$

The sum runs over all $n = J + N_{exp}$ residuals (imports + exports), $r_i = r_i(\hat\theta)$ are the residuals at the optimum, and $\nabla r_i = \partial r_i / \partial \theta$ is the $K$-vector of partial derivatives at $\hat\theta$.

This is the standard White (1980) sandwich generalized to weighted NLS. It reduces to the inverse-Hessian "Option A" estimator when residuals are homoskedastic and weights are uniform.

The standard errors are $\text{SE}(\hat\theta_k) = \sqrt{[\widehat{\text{Var}}(\hat\theta)]_{kk}}$.

## What we need to compute

The expensive object is the residual Jacobian:

$$
\mathbf{J} = \frac{\partial \mathbf{r}}{\partial \theta} \in \mathbb{R}^{n \times K}
$$

Once we have $\mathbf{J}$ and the residual vector $\mathbf{r}$, both $A$ and $B$ are simple weighted outer-product sums:

$$
A = \mathbf{J}^\top W \, \mathbf{J}, \quad
B = \mathbf{J}^\top W^2 R^2 \, \mathbf{J}
$$

where $W = \text{diag}(w_i)$ and $R = \text{diag}(r_i)$.

## Sparsity structure

The Jacobian is sparse:

- **Import row $j$** depends on $\gamma_j$ (the row's own gamma) and $\gamma_k$ (the reference gamma). So row $j$ of $\mathbf{J}$ has at most 2 nonzero entries: in columns 0 (the $\gamma_k$ column) and $j$ (the $\gamma_j$ column).

- **Export row $m$** depends on $\gamma_I$, where $I$ is determined by `exp_jmap[m]`. Either $I = k$ (the reference exporter) or $I = j$ for some $j$. The export prediction does NOT depend on $\gamma_k$ unless the row's $I$ index happens to equal $k$, and never depends on more than one parameter. So row $m$ has exactly 1 nonzero entry.

Both $\gamma_V$ and $\sigma_V$ on the export side are treated as **fixed exogenous data** (looked up from Stage 2a regional outputs and Stage 1 LIML), not as parameters to differentiate against. This matches the existing objective function (line 96-98 of `het_obj_fixed_sigma_rcpp.cpp`), which receives them as `NumericVector` arguments rather than parts of `d`.

## Derivation: import-side residual gradient

The import prediction is (from `het_obj_fixed_sigma_rcpp.cpp` lines 69-73):

$$
\text{pred}^{imp}_j =
  \frac{\gamma_j}{(1+\gamma_j)(\sigma-1)} \cdot X^{imp}_{j,0}
+ \frac{\gamma_j}{1+\gamma_j} \cdot X^{imp}_{j,1}
+ \frac{-1}{\sigma-1} \cdot X^{imp}_{j,2}
+ \frac{\gamma_j (1+\gamma_k)}{\gamma_k (1+\gamma_j)(\sigma-1)} \cdot X^{imp}_{j,3}
+ \frac{\gamma_j - \gamma_k}{\gamma_k (1+\gamma_j)} \cdot X^{imp}_{j,4}
$$

The residual is $r^{imp}_j = Y^{imp}_j - \text{pred}^{imp}_j$, so $\partial r / \partial \theta = -\partial \text{pred} / \partial \theta$.

Differentiating each coefficient with respect to $\gamma_j$ (symbolic verification via sympy, see commit notes):

| Term | Coefficient | $\partial / \partial \gamma_j$ |
|---|---|---|
| $X_0$ | $\gamma_j / ((1+\gamma_j)(\sigma-1))$ | $1 / ((1+\gamma_j)^2 (\sigma-1))$ |
| $X_1$ | $\gamma_j / (1+\gamma_j)$ | $1 / (1+\gamma_j)^2$ |
| $X_2$ | $-1 / (\sigma-1)$ | $0$ |
| $X_3$ | $\gamma_j (1+\gamma_k) / (\gamma_k (1+\gamma_j)(\sigma-1))$ | $(1+\gamma_k) / (\gamma_k (1+\gamma_j)^2 (\sigma-1))$ |
| $X_4$ | $(\gamma_j - \gamma_k) / (\gamma_k (1+\gamma_j))$ | $(1+\gamma_k) / (\gamma_k (1+\gamma_j)^2)$ |

So:

$$
\frac{\partial \text{pred}^{imp}_j}{\partial \gamma_j}
= \frac{X^{imp}_{j,0}}{(1+\gamma_j)^2 (\sigma-1)}
+ \frac{X^{imp}_{j,1}}{(1+\gamma_j)^2}
+ \frac{(1+\gamma_k) \, X^{imp}_{j,3}}{\gamma_k (1+\gamma_j)^2 (\sigma-1)}
+ \frac{(1+\gamma_k) X^{imp}_{j,4}}{\gamma_k (1+\gamma_j)^2}
$$

Differentiating each coefficient with respect to $\gamma_k$:

| Term | Coefficient | $\partial / \partial \gamma_k$ |
|---|---|---|
| $X_0$ | (same) | $0$ |
| $X_1$ | (same) | $0$ |
| $X_2$ | (same) | $0$ |
| $X_3$ | (same) | $-\gamma_j / (\gamma_k^2 (1+\gamma_j)(\sigma-1))$ |
| $X_4$ | (same) | $-\gamma_j / (\gamma_k^2 (1+\gamma_j))$ |

So:

$$
\frac{\partial \text{pred}^{imp}_j}{\partial \gamma_k}
= -\frac{\gamma_j \, X^{imp}_{j,3}}{\gamma_k^2 (1+\gamma_j) (\sigma-1)}
- \frac{\gamma_j \, X^{imp}_{j,4}}{\gamma_k^2 (1+\gamma_j)}
$$

## Derivation: export-side residual gradient

The export prediction is (from `het_obj_fixed_sigma_rcpp.cpp` lines 103-112):

$$
\text{pred}^{exp}_m =
  \frac{\gamma_I}{(1+\gamma_I)(\sigma-1)} \cdot X^{exp}_{m,0}
+ \frac{\gamma_I (\sigma-2) - 1}{(1+\gamma_I)(\sigma-1)} \cdot X^{exp}_{m,1}
+ \frac{\gamma_V}{(1+\gamma_V)(\sigma-1)} \cdot X^{exp}_{m,2}
$$

$$
+ \frac{1 - \gamma_V (\sigma-2)}{(1+\gamma_V)(\sigma-1)} \cdot X^{exp}_{m,3}
+ \frac{1 - \gamma_V (\sigma_V-2)}{(1+\gamma_V)(\sigma-1)} \cdot X^{exp}_{m,4}
+ \frac{\gamma_I (\sigma_V-2) - 1}{(1+\gamma_I)(\sigma-1)} \cdot X^{exp}_{m,5}
$$

$$
- \frac{\gamma_V (1+\gamma_I) + \gamma_I (1+\gamma_V)}{(1+\gamma_I)(1+\gamma_V)(\sigma-1)} \cdot X^{exp}_{m,6}
+ \frac{\sigma - \sigma_V}{\sigma-1} \cdot X^{exp}_{m,7}
+ \frac{\sigma_V - \sigma}{\sigma-1} \cdot X^{exp}_{m,8}
$$

Where $\gamma_I$ is the parameter at index `exp_jmap[m]` in $\theta$. Differentiate with respect to $\gamma_I$:

| Term | Coefficient | $\partial / \partial \gamma_I$ |
|---|---|---|
| $X_0$ | $\gamma_I / ((1+\gamma_I)(\sigma-1))$ | $1 / ((1+\gamma_I)^2 (\sigma-1))$ |
| $X_1$ | $(\gamma_I (\sigma-2) - 1) / ((1+\gamma_I)(\sigma-1))$ | $1 / (1+\gamma_I)^2$ |
| $X_2$ | $\gamma_V / ((1+\gamma_V)(\sigma-1))$ | $0$ |
| $X_3$ | $(1 - \gamma_V (\sigma-2)) / ((1+\gamma_V)(\sigma-1))$ | $0$ |
| $X_4$ | $(1 - \gamma_V (\sigma_V-2)) / ((1+\gamma_V)(\sigma-1))$ | $0$ |
| $X_5$ | $(\gamma_I (\sigma_V-2) - 1) / ((1+\gamma_I)(\sigma-1))$ | $(\sigma_V-1) / ((1+\gamma_I)^2 (\sigma-1))$ |
| $X_6$ | $-(\gamma_V (1+\gamma_I) + \gamma_I (1+\gamma_V)) / ((1+\gamma_I)(1+\gamma_V)(\sigma-1))$ | $-1 / ((1+\gamma_I)^2 (\sigma-1))$ |
| $X_7$ | $(\sigma - \sigma_V) / (\sigma-1)$ | $0$ |
| $X_8$ | $(\sigma_V - \sigma) / (\sigma-1)$ | $0$ |

The non-obvious entries (X1, X5, X6) have been verified symbolically: X1 simplifies to $1/(1+\gamma_I)^2$ (the $\sigma-2$ terms cancel out neatly); X5 to $(\sigma_V-1)/((1+\gamma_I)^2 (\sigma-1))$; X6 to $-1/((1+\gamma_I)^2 (\sigma-1))$ after expanding the numerator $\gamma_I + \gamma_V + 2 \gamma_I \gamma_V$.

Combining:

$$
\frac{\partial \text{pred}^{exp}_m}{\partial \gamma_I}
= \frac{X^{exp}_{m,0}}{(1+\gamma_I)^2 (\sigma-1)}
+ \frac{X^{exp}_{m,1}}{(1+\gamma_I)^2}
+ \frac{(\sigma_V - 1) X^{exp}_{m,5}}{(1+\gamma_I)^2 (\sigma-1)}
- \frac{X^{exp}_{m,6}}{(1+\gamma_I)^2 (\sigma-1)}
$$

Note $\partial \text{pred}^{exp}_m / \partial \gamma_k$ is zero unless $\gamma_I = \gamma_k$ (i.e., `exp_jmap[m]` points to the reference exporter slot), in which case the formula above applies with $\gamma_I = \gamma_k$.

## Algorithm

1. Run optim, get $\hat\theta$.
2. Compute residual vector $\mathbf{r}(\hat\theta)$ — vector of length $J + N_{exp}$.
3. Compute Jacobian $\mathbf{J}$ — sparse $(J + N_{exp}) \times K$ matrix using the formulas above, evaluated at $\hat\theta$. Store only the nonzero entries.
4. Compute $A = \mathbf{J}^\top W \mathbf{J}$ and $B = \mathbf{J}^\top \text{diag}(w_i^2 r_i^2) \mathbf{J}$ via outer-product accumulation.
5. Invert $A$. Compute $A^{-1} B A^{-1}$.
6. Extract diagonal, take square roots, get $\text{SE}(\gamma_k)$ and $\text{SE}(\gamma_j)$ for each $j$.

## Implementation notes

- **All quantities are evaluated at $\hat\theta$.** No re-optimization.
- **Sparse $\mathbf{J}$.** With $K = J+1$ parameters and $n = J + N_{exp}$ residuals, the dense Jacobian would be $n \times K$. Sparsity: each import row has 2 nonzeros, each export row has 1 nonzero. We can compute $A$ and $B$ directly via row-wise contribution without materializing $\mathbf{J}$ at all — this is the C++ implementation strategy.
- **Edge case: $A$ singular.** If the Hessian-equivalent $A$ is singular, the cell is underidentified. Return `gamma_se = NA` for all parameters in that cell. Detected via `solve()` failure or via tiny minimum eigenvalue.
- **Edge case: $B$ near zero.** Means all residuals are near zero or all weights are zero. SE → 0. Treat as NA for safety.
- **Cost.** Per-cell: ~$(J + N_{exp}) \cdot K$ flops for Jacobian + $K^2$ for $A$ inversion. For a cell with $J = 30, N_{exp} = 200$: a few thousand flops per cell. Stage 2b runs ~290K cells. Total cost dominated by the existing optim() call; SE computation adds maybe 5–10% overhead.

## What's NOT yet handled

- **Shrinkage penalty.** The current objective includes $\lambda \sum_i (\ln \gamma_i - \ln \bar\gamma)^2$. This shifts the optimum away from the unpenalized MLE. The honest treatment is to compute Bayesian credible intervals from the posterior (intractable in closed form) or to add the prior's Hessian into $A$: $A \to A + \lambda \cdot H_{\text{prior}}$ where $H_{\text{prior}} = \text{diag}(1/\gamma_i^2)$ at the optimum. This is the next refinement; first version ignores it (i.e., treats SE as if the unpenalized MLE were the estimator).
- **Tier 3.** Tier 3 rows have prior-assigned $\gamma$ (not optimized). Their SE is the SE of the prior, not computable here. Set $\gamma_{se} = NA$ for Tier 3.

## Verification plan

Before integrating into Stage 2b:

1. **Numerical differentiation cross-check** on a synthetic cell. Generate small synthetic $(imp_X, exp_X, Y)$ data with known $\gamma$, fit, compute analytic $\mathbf{J}$, compare to `numDeriv::jacobian` on the residual function. Tolerance 1e-8.
2. **Single-cell spot check** on a real cell from current Stage 2b output. Refit with both the analytic Jacobian and `numDeriv`, confirm SEs match.
3. **Sandwich vs inverse-Hessian comparison.** Should agree to within ~10% on well-identified cells; sandwich should be larger on weakly-identified ones.

## Output schema additions

For Stage 2b output (`*_fixed_sigma.rds`), add:

- `gamma_se` — sandwich-robust SE for the row's $\gamma$, NA for Tier 3.
- `vcov_singular` — boolean flag, TRUE if $A$ was numerically singular.

Optionally also add:

- `gamma_se_naive` — inverse-Hessian (Option A) SE for comparison; useful as a safety net since it's cheap.
