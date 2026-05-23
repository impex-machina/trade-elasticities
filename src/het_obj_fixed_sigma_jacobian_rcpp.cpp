// =========================================================================
// het_obj_fixed_sigma_jacobian_rcpp.cpp
//
// Companion to het_obj_fixed_sigma_rcpp.cpp.
//
// Evaluates the residual vector r(theta_hat) and the residual Jacobian
// dr/dtheta at theta_hat, for the fixed-sigma Stage 2 estimator. Returns
// data the R caller assembles into the sandwich covariance matrix
//
//     V = A^{-1} B A^{-1}
//
// where
//     A = sum_i w_i  J_i J_i'
//     B = sum_i w_i^2 r_i^2  J_i J_i'
//
// J_i is the i-th row of the residual Jacobian (gradient of r_i wrt theta).
//
// The Jacobian is SPARSE:
//   - Import row j: nonzero in columns 0 (gamma_k) and j (gamma_j)
//   - Export row m: nonzero in column (exp_jmap[m] - 2) only
//     (the 1-based index minus 2 because we dropped sigma from d)
//
// Returns a List with:
//   - residuals: NumericVector of length J + N_exp
//   - weights:   NumericVector of length J + N_exp
//   - jac_row:   IntegerVector of triplets (0-based row indices)
//   - jac_col:   IntegerVector of triplets (0-based col indices in theta)
//   - jac_val:   NumericVector of triplet values
//
// Derivation: see derivation.md. All terms verified symbolically.
//
// CITATION:
//   Soderbery (2018), JIE 114, pp. 44-62.
//
// Last updated: 2026-05-14
// =========================================================================

#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

// [[Rcpp::export]]
List het_residuals_and_jacobian_fixed_sigma_rcpp(
    NumericVector d,
    double sigma,
    NumericVector imp_Y, NumericMatrix imp_X,
    NumericVector exp_Y, NumericMatrix exp_X,
    IntegerVector exp_jmap,
    NumericVector exp_sig_V, NumericVector exp_gam_V,
    NumericVector wt_imp, NumericVector wt_exp) {

  // d[0]    = gamma_k
  // d[1..J] = gamma_j
  // K       = J + 1   = length(d)  = number of parameters
  int K = d.size();
  int J = K - 1;
  int N_imp = imp_Y.size();
  int N_exp = exp_Y.size();
  int N_total = N_imp + N_exp;

  double sig = sigma;
  double sm1 = sig - 1.0;

  double gam_k = d[0];
  // For numerical safety; should be enforced by the optimizer's bounds
  // but we don't want to silently produce garbage if a Tier 3 fallback
  // is somehow passed in.
  if (gam_k <= 0.0 || sig <= 1.0) {
    return List::create(
      _["residuals"] = NumericVector(0),
      _["weights"]   = NumericVector(0),
      _["jac_row"]   = IntegerVector(0),
      _["jac_col"]   = IntegerVector(0),
      _["jac_val"]   = NumericVector(0),
      _["status"]    = "invalid_input"
    );
  }

  double inv_1pgk     = 1.0 / (1.0 + gam_k);
  double inv_1pgk_sq  = inv_1pgk * inv_1pgk;
  double inv_gk       = 1.0 / gam_k;
  double inv_gk_sq    = inv_gk * inv_gk;

  // Pre-allocate output vectors.
  // Jacobian sparsity: 2 nonzeros per import row + 1 nonzero per export row.
  int nnz = 2 * N_imp + N_exp;

  NumericVector residuals(N_total);
  NumericVector weights(N_total);
  IntegerVector jac_row(nnz);
  IntegerVector jac_col(nnz);
  NumericVector jac_val(nnz);

  int triplet = 0;  // running index into jac_* triplet arrays

  // ====================================================================
  //  IMPORT SIDE
  //  Row j of the residual vector corresponds to import obs j.
  //  Two Jacobian entries per row: column 0 (d/dgamma_k) and column (j+1)? NO.
  //  Wait — column indexing: d[0] = gamma_k, d[1..J] = gamma_j.
  //  So gamma_j for the j-th import row sits at d[j+1]? No!
  //  Looking at the existing objective (line 66): "gam_j = d[j+1]".
  //  So yes, for the j-th import obs (0-indexed), gamma_j = d[j+1].
  //  Column index in theta = j+1, NOT j.
  // ====================================================================
  for (int j = 0; j < N_imp; j++) {
    double gam_j        = d[j + 1];
    double inv_1pgj     = 1.0 / (1.0 + gam_j);
    double inv_1pgj_sq  = inv_1pgj * inv_1pgj;

    // --- Prediction (same as objective function) ---
    double pred =
        (gam_j * inv_1pgj / sm1)                                * imp_X(j, 0) +
        (gam_j * inv_1pgj)                                       * imp_X(j, 1) +
        (-1.0 / sm1)                                             * imp_X(j, 2) +
        (gam_j * gam_k * inv_1pgj * inv_1pgk / sm1)              * imp_X(j, 3) +
        ((gam_j - gam_k) * inv_1pgj * inv_gk)                    * imp_X(j, 4);

    double r_j = imp_Y[j] - pred;
    residuals[j] = r_j;
    weights[j]   = wt_imp[j];

    // --- Derivatives ---
    // d pred / d gamma_j
    double dpred_dgj =
        imp_X(j, 0) * inv_1pgj_sq / sm1 +
        imp_X(j, 1) * inv_1pgj_sq +
        imp_X(j, 3) * gam_k * inv_1pgj_sq * inv_1pgk / sm1 +
        imp_X(j, 4) * (1.0 + gam_k) * inv_gk * inv_1pgj_sq;

    // d pred / d gamma_k
    double dpred_dgk =
        imp_X(j, 3) * gam_j * inv_1pgj * inv_1pgk_sq / sm1 -
        imp_X(j, 4) * gam_j * inv_gk_sq * inv_1pgj;

    // d residual / d theta = -d pred / d theta
    // Store column gamma_k (index 0)
    jac_row[triplet] = j;
    jac_col[triplet] = 0;
    jac_val[triplet] = -dpred_dgk;
    triplet++;
    // Store column gamma_j (index j+1)
    jac_row[triplet] = j;
    jac_col[triplet] = j + 1;
    jac_val[triplet] = -dpred_dgj;
    triplet++;
  }

  // ====================================================================
  //  EXPORT SIDE
  //  Row (N_imp + m) of the residual vector corresponds to export obs m.
  //  ONE Jacobian entry per row at column (exp_jmap[m] - 2).
  //  Reason: exp_jmap is 1-based into the full-d (sigma, gamma_k, gamma_j...).
  //  Subtract 1 for 0-based, then 1 more because sigma was removed.
  // ====================================================================
  for (int m = 0; m < N_exp; m++) {
    int col_I = exp_jmap[m] - 2;  // 0-based column index in theta
    double gam_I = d[col_I];
    double gam_V = exp_gam_V[m];
    double sig_V = exp_sig_V[m];

    double inv_1pgI    = 1.0 / (1.0 + gam_I);
    double inv_1pgI_sq = inv_1pgI * inv_1pgI;
    double inv_1pgV    = 1.0 / (1.0 + gam_V);

    // --- Prediction (same as objective function) ---
    double pred =
        (gam_I * inv_1pgI / sm1)                                              * exp_X(m, 0) +
        ((gam_I * (sig - 2.0) - 1.0) * inv_1pgI / sm1)                        * exp_X(m, 1) +
        (gam_V * inv_1pgV / sm1)                                               * exp_X(m, 2) +
        ((1.0 - gam_V * (sig - 2.0)) * inv_1pgV / sm1)                        * exp_X(m, 3) +
        ((1.0 - gam_V * (sig_V - 2.0)) * inv_1pgV / sm1)                      * exp_X(m, 4) +
        ((gam_I * (sig_V - 2.0) - 1.0) * inv_1pgI / sm1)                      * exp_X(m, 5) +
        (-(gam_V * (1.0 + gam_I) + gam_I * (1.0 + gam_V)) *
            inv_1pgI * inv_1pgV / sm1)                                        * exp_X(m, 6) +
        ((sig - sig_V) / sm1)                                                  * exp_X(m, 7) +
        ((sig_V - sig) / sm1)                                                  * exp_X(m, 8);

    double r_m = exp_Y[m] - pred;
    int row_idx = N_imp + m;
    residuals[row_idx] = r_m;
    weights[row_idx]   = wt_exp[m];

    // --- Derivative wrt gamma_I (the only nonzero column) ---
    // Verified symbolic forms:
    //   X0:  1 / ((1+gI)^2 (sigma-1))
    //   X1:  1 / (1+gI)^2
    //   X5:  (sigma_V - 1) / ((1+gI)^2 (sigma-1))
    //   X6: -1 / ((1+gI)^2 (sigma-1))
    //   X2,X3,X4,X7,X8: 0
    double dpred_dgI =
        exp_X(m, 0) * inv_1pgI_sq / sm1 +
        exp_X(m, 1) * inv_1pgI_sq +
        exp_X(m, 5) * (sig_V - 1.0) * inv_1pgI_sq / sm1 -
        exp_X(m, 6) * inv_1pgI_sq / sm1;

    jac_row[triplet] = row_idx;
    jac_col[triplet] = col_I;
    jac_val[triplet] = -dpred_dgI;  // d residual / d gamma_I
    triplet++;
  }

  return List::create(
    _["residuals"] = residuals,
    _["weights"]   = weights,
    _["jac_row"]   = jac_row,
    _["jac_col"]   = jac_col,
    _["jac_val"]   = jac_val,
    _["K"]         = K,
    _["status"]    = "ok"
  );
}
