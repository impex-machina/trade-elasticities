#' R/load_rcpp.R
#'
#' Loads the Rcpp objective/Jacobian implementations from an explicit cpp_dir.
#' Replaces three scattered getwd()-based tryCatch blocks from the original
#' monolith with one function taking the source directory as an argument —
#' decoupling 'where to source from' from the working directory.
#'
#' Exported functions:
#'   load_rcpp_objectives(cpp_dir)  — compile/load the .cpp objectives from cpp_dir
#'
#' Depends on: Rcpp

# Module-level flags. These exist as soon as the file is sourced; the loader
# function below toggles them to TRUE if the corresponding .cpp file
# successfully compiles and loads.
.het_obj_rcpp_loaded    <- FALSE
.het_obj_fs_rcpp_loaded <- FALSE
.het_jac_rcpp_loaded    <- FALSE


#' Load all three Rcpp objective implementations.
#'
#' Replaces the original module-level tryCatch blocks at lines 32-52,
#' 2339-2391 of feen94_het_baci.R, with the same logic but using an
#' explicit cpp_dir instead of file.path(getwd(), ...).
#'
#' If a .cpp file fails to compile (or is absent), the corresponding flag
#' stays FALSE and downstream code falls back to pure-R. The original
#' behaviour is preserved byte-for-byte.
#'
#' @param cpp_dir Directory containing the three .cpp files. Looked up by
#'   the wrapper from env var TRADE_ELAST_CPP, falling back to TRADE_ELAST_SRC.
#' @return Invisible list of the three logical flags.
#' @export
load_rcpp_objectives <- function(cpp_dir) {

  # --- 1. Base objective function: het_obj_rcpp ----------------------------
  # Used by the homogeneous estimator AND wrapped by the pure-R fallback for
  # het_obj_fixed_sigma. Has a pure-R fallback in het_obj.R.
  tryCatch({
    if (requireNamespace("Rcpp", quietly = TRUE)) {
      cpp_file <- file.path(cpp_dir, "het_obj_rcpp.cpp")
      if (file.exists(cpp_file)) {
        Rcpp::sourceCpp(cpp_file)
        # het_obj_rcpp is now in the global environment
        het_obj <<- het_obj_rcpp
        .het_obj_rcpp_loaded <<- TRUE
        cat("  Objective function: Rcpp (compiled C++)\n")
      }
    }
  }, error = function(e) {
    cat(sprintf("  Rcpp compilation failed: %s\n", conditionMessage(e)))
  })

  if (!.het_obj_rcpp_loaded) {
    # Pure-R fallback. het_obj.R lives alongside the .cpp files.
    r_file <- file.path(cpp_dir, "het_obj.R")
    if (file.exists(r_file)) {
      source(r_file)
      cat("  Objective function: pure R\n")
    } else {
      warning("Neither het_obj_rcpp.cpp nor het_obj.R found in: ", cpp_dir,
              "\nDownstream estimation will fail.")
    }
  }

  # --- 2. Fixed-sigma objective function: het_obj_fixed_sigma_rcpp ---------
  # Used by Stage 2a and 2b. Has a pure-R wrapper fallback below that wraps
  # the base het_obj.
  tryCatch({
    if (requireNamespace("Rcpp", quietly = TRUE)) {
      cpp_file <- file.path(cpp_dir, "het_obj_fixed_sigma_rcpp.cpp")
      if (file.exists(cpp_file)) {
        Rcpp::sourceCpp(cpp_file)
        het_obj_fixed_sigma <<- het_obj_fixed_sigma_rcpp
        .het_obj_fs_rcpp_loaded <<- TRUE
        cat("  Fixed-sigma objective: Rcpp (compiled C++)\n")
      }
    }
  }, error = function(e) {
    cat(sprintf("  Fixed-sigma Rcpp compilation failed: %s\n",
                conditionMessage(e)))
  })

  # --- 3. Residual-Jacobian: het_obj_fixed_sigma_jacobian_rcpp -------------
  # Used by compute_penalized_gn_se() for standard error computation. If
  # this fails to load, gamma_se is set to NA for all rows (status =
  # "not_computed"). This is the file the keep_cols bug specifically
  # affected — the test suite asserts SEs are populated for at least one
  # converged row.
  tryCatch({
    if (requireNamespace("Rcpp", quietly = TRUE)) {
      jac_cpp <- file.path(cpp_dir, "het_obj_fixed_sigma_jacobian_rcpp.cpp")
      if (file.exists(jac_cpp)) {
        Rcpp::sourceCpp(jac_cpp)
        .het_jac_rcpp_loaded <<- TRUE
        cat("  Jacobian/SE function: Rcpp (compiled C++)\n")
      } else {
        cat("  Jacobian/SE function: NOT loaded (file missing) — gamma_se will be NA\n")
      }
    }
  }, error = function(e) {
    cat(sprintf("  Jacobian Rcpp compilation failed: %s\n",
                conditionMessage(e)))
  })

  # --- 4. Pure-R wrapper fallback for fixed-sigma objective ----------------
  # Only defined if the Rcpp version didn't load. Wraps the base het_obj
  # (which itself may be Rcpp or pure-R), adding the shrinkage penalty
  # in R since the .cpp version has it baked in.
  if (!.het_obj_fs_rcpp_loaded) {
    het_obj_fixed_sigma <<- function(d, sigma, imp_Y, imp_X, exp_Y, exp_X,
                                     exp_jmap, exp_sig_V, exp_gam_V,
                                     wt_imp, wt_exp,
                                     ln_gamma_prior, shrinkage_lambda) {
      d_full <- c(sigma, d)
      ssr <- het_obj(d_full, imp_Y, imp_X, exp_Y, exp_X,
                     exp_jmap, exp_sig_V, exp_gam_V, wt_imp, wt_exp)
      if (ssr >= 1e12) return(1e12)
      if (shrinkage_lambda > 0 && !is.na(ln_gamma_prior)) {
        gam_vals <- d[d > 1e-5]
        if (length(gam_vals) > 0L) {
          ssr <- ssr + shrinkage_lambda * sum((log(gam_vals) - ln_gamma_prior)^2)
        }
      }
      ssr
    }
    cat("  Fixed-sigma objective: pure R (wrapper)\n")
  }

  invisible(list(
    het_obj    = .het_obj_rcpp_loaded,
    het_obj_fs = .het_obj_fs_rcpp_loaded,
    het_jac    = .het_jac_rcpp_loaded
  ))
}
