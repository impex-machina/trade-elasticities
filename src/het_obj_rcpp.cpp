// =========================================================================
// het_obj_rcpp.cpp
//
// Rcpp implementation of the joint nonlinear SUR objective function
// for Soderbery (2018) Eqs. (10) and (11).
//
// Drop-in replacement for het_obj() in het_obj.R.
// Compile via Rcpp::sourceCpp("het_obj_rcpp.cpp") or automatically
// from feen94_het_baci.R.
//
// CITATION:
//   Soderbery, Anson, "Trade Elasticities, Heterogeneity, and Optimal
//   Tariffs," JIE, 114, 2018, pp. 44-62.
//
// Last updated: 2026-03-28
// =========================================================================

#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export]]
double het_obj_rcpp(NumericVector d,
                    NumericVector imp_Y, NumericMatrix imp_X,
                    NumericVector exp_Y, NumericMatrix exp_X,
                    IntegerVector exp_jmap,
                    NumericVector exp_sig_V, NumericVector exp_gam_V,
                    NumericVector wt_imp, NumericVector wt_exp,
                    bool paper_exact_eq11 = false) {

  double sig   = d[0];
  double gam_k = d[1];
  int J = d.size() - 2;

  // --- Enforce constraints ---
  if (sig <= 1.0 || gam_k <= 0.0) return 1e12;
  for (int j = 0; j < J; j++) {
    if (d[j + 2] <= 0.0) return 1e12;
  }

  double sm1 = sig - 1.0;

  // ===========================================================
  //  IMPORT-SIDE RESIDUALS — Eq (10)
  // ===========================================================

  double SSR_imp = 0.0;

  // G6 FIX (v0.4.1 hotfix): bound the import loop by the ROW count, not the
  // parameter count. The validation harness (Test D) legitimately calls this
  // objective with an empty import block (export-only residuals); the old
  // J-bounded loop then read imp_Y/imp_X/wt_imp out of bounds -- benign on
  // Linux heaps, an access violation (silent Rscript death) on Windows.
  // Production always supplies one import row per gamma_j, so behaviour
  // there is unchanged.
  int N_imp = imp_Y.size();
  if (N_imp > J) stop("het_obj_rcpp: imp_Y has more rows than gamma parameters");

  for (int j = 0; j < N_imp; j++) {
    double gam_j = d[j + 2];
    double inv_1pgj = 1.0 / (1.0 + gam_j);

    double pred = (gam_j * inv_1pgj / sm1)                             * imp_X(j, 0) +
                  (gam_j * inv_1pgj)                                    * imp_X(j, 1) +
                  (-1.0 / sm1)                                          * imp_X(j, 2) +
                  // F1 FIX (v0.4.0): Soderbery (2018) Eq. (10) term 4 is
                  // gam_j*(1+gam_k)/(gam_k*(1+gam_j)*(sigma-1)); previous form
                  // was a transcription error (see stage2_derivation.md).
                  (gam_j * (1.0 + gam_k) * inv_1pgj / (gam_k * sm1))    * imp_X(j, 3) +
                  ((gam_j - gam_k) * inv_1pgj / gam_k)                 * imp_X(j, 4);

    double resid = imp_Y[j] - pred;
    SSR_imp += wt_imp[j] * resid * resid;
  }

  // ===========================================================
  //  EXPORT-SIDE RESIDUALS — Eq (11)
  // ===========================================================

  int N_exp = exp_Y.size();

  if (N_exp == 0) return SSR_imp;

  double SSR_exp = 0.0;

  for (int m = 0; m < N_exp; m++) {
    // exp_jmap uses 1-based R indexing into d
    double gam_I = d[exp_jmap[m] - 1];
    double gam_V = exp_gam_V[m];
    double sig_V = exp_sig_V[m];

    double inv_1pgI = 1.0 / (1.0 + gam_I);
    double inv_1pgV = 1.0 / (1.0 + gam_V);

    // G1 FIX (v0.4.1): printed Eq. (11) x5/x6 signs are wrong -- the product
    // of the paper's own Eq. (8) and Eq. (9) residuals yields these two
    // coefficients NEGATED (all seven others and the stated error term match
    // exactly). s56 = -1.0 applies the correction; paper_exact_eq11 = true
    // reproduces the printed (v0.4.0) behaviour.
    // See docs/methodology/eq11_sign_correction.md.
    const double s56 = paper_exact_eq11 ? 1.0 : -1.0;

    double pred = (gam_I * inv_1pgI / sm1)                                         * exp_X(m, 0) +
                  ((gam_I * (sig - 2.0) - 1.0) * inv_1pgI / sm1)                   * exp_X(m, 1) +
                  (gam_V * inv_1pgV / sm1)                                          * exp_X(m, 2) +
                  ((1.0 - gam_V * (sig - 2.0)) * inv_1pgV / sm1)                   * exp_X(m, 3) +
                  (s56 * (1.0 - gam_V * (sig_V - 2.0)) * inv_1pgV / sm1)           * exp_X(m, 4) +
                  (s56 * (gam_I * (sig_V - 2.0) - 1.0) * inv_1pgI / sm1)           * exp_X(m, 5) +
                  (-(gam_V * (1.0 + gam_I) + gam_I * (1.0 + gam_V)) *
                     inv_1pgI * inv_1pgV / sm1)                                     * exp_X(m, 6) +
                  ((sig - sig_V) / sm1)                                             * exp_X(m, 7) +
                  ((sig_V - sig) / sm1)                                             * exp_X(m, 8);

    double resid = exp_Y[m] - pred;
    SSR_exp += wt_exp[m] * resid * resid;
  }

  return SSR_imp + SSR_exp;
}
