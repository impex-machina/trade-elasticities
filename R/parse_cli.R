#' R/parse_cli.R
#'
#' CLI argument parsing for the three-stage estimation pipeline. Returns a
#' named list of options that build_config() consumes. Exposes only the
#' run-to-run values a user varies; methodological knobs stay versioned in
#' source. Uses optparse (declared in R/dependencies.R).
#'
#' Exported functions:
#'   parse_cli(args)                  — parse command-line args into an options list
#'   validate_cli_opts(opts, parser)  — validate parsed options
#'
#' Depends on: optparse (via dependencies.R)


#' Parse command-line arguments for the estimation pipeline.
#'
#' @param args Character vector of arguments. Defaults to
#'   `commandArgs(trailingOnly = TRUE)`, which is what you want when called
#'   from a real `Rscript` invocation. Pass an explicit vector in tests.
#' @return A named list of options. Components:
#'   \describe{
#'     \item{data}{Path to BACI directory (required).}
#'     \item{out_dir}{Output directory (default ".").}
#'     \item{agg_level}{One of "hs4" or "hs6".}
#'     \item{minyear}{Earliest year of data to include.}
#'     \item{maxyear}{Latest year (NULL means use all data).}
#'     \item{ncores}{Number of worker cores.}
#'     \item{shrinkage_lambda}{Penalty weight on the ln(gamma) shrinkage
#'       term at Stages 2a and 2b.}
#'     \item{stage}{One of "all", "1", "2a", "2b".}
#'   }
#' @export
parse_cli <- function(args = commandArgs(trailingOnly = TRUE)) {

  if (!requireNamespace("optparse", quietly = TRUE)) {
    stop("Package 'optparse' is required. Install with: ",
         "install.packages('optparse')")
  }

  default_ncores <- max(1L, parallel::detectCores() - 2L)

  option_list <- list(
    optparse::make_option(
      c("-d", "--data"),
      type = "character", default = NULL,
      help = paste("Path to BACI data directory (required).",
                   "Must be a directory containing BACI_HS*_Y####_V*.csv files."),
      metavar = "DIR"
    ),
    optparse::make_option(
      c("-o", "--out-dir"),
      type = "character", default = ".",
      help = "Output directory for .rds, .csv, and summary files. Default: %default",
      metavar = "DIR"
    ),
    optparse::make_option(
      c("--agg-level"),
      type = "character", default = "hs4",
      help = "Product aggregation level: 'hs4' or 'hs6'. Default: %default",
      metavar = "LEVEL"
    ),
    optparse::make_option(
      c("--minyear"),
      type = "integer", default = 1995L,
      help = "Earliest year of BACI data to include. Default: %default",
      metavar = "YEAR"
    ),
    optparse::make_option(
      c("--maxyear"),
      type = "integer", default = NA_integer_,
      help = paste("Latest year of BACI data to include.",
                   "Default: use all available data."),
      metavar = "YEAR"
    ),
    optparse::make_option(
      c("-n", "--ncores"),
      type = "integer", default = default_ncores,
      help = paste("Number of worker cores. Default:",
                   "detectCores() - 2 (= %default on this machine)"),
      metavar = "N"
    ),
    optparse::make_option(
      c("--shrinkage-lambda"),
      type = "double", default = 0.1,
      help = paste("Shrinkage penalty weight on ln(gamma) at Stages 2a/2b.",
                   "Higher = stronger pull toward prior. Default: %default"),
      metavar = "LAMBDA"
    ),
    optparse::make_option(
      c("--bw-lag"),
      type = "character", default = "calendar",
      help = paste("BW weight lag policy: 'legacy' (previous retained row",
                   "via positional shift; reproduces published v0.4.x",
                   "output bit-for-bit) or 'calendar' (previous calendar",
                   "year from the cell panel, per Soderbery p. 50 fn 14).",
                   "Default: %default"),
      metavar = "MODE"
    ),
    optparse::make_option(
      c("--stage1-hliml"),
      type = "character", default = "closed",
      help = paste("Stage 1 HLIML estimator: 'closed' (HLIM eigenvector closed",
                   "form, O(n); inadmissible cells fall through the Step-2",
                   "cascade and, failing that, to a flagged boundary optimum --",
                   "v0.6.0 default), 'bfgs' (wall-penalized BFGS; reproduces",
                   "v0.5.x output bit-for-bit), or 'both' (route as bfgs, also",
                   "report the closed form in *_cf columns -- census mode).",
                   "Default: %default"),
      metavar = "METHOD"
    ),
    optparse::make_option(
      c("--stage1-cf-admissibility"),
      type = "character", default = "legacy",
      help = paste("Closed-form HLIML admissibility rule (only with",
                   "--stage1-hliml closed/both): 'legacy' (a point whose",
                   "inversion clamped a negative omega up to the 1e-4 floor",
                   "is accepted as an interior HLIML estimate -- reproduces",
                   "v0.6.x bit-for-bit) or 'strict' (such points are",
                   "inadmissible and take the Step-2 -> boundary cascade;",
                   "see hliml_closed_form()). Default: %default"),
      metavar = "RULE"
    ),
    optparse::make_option(
      c("--stage1-negative-omega"),
      type = "character", default = "reject",
      help = paste("Treatment of a NEGATIVE algebraic omega in the Feenstra",
                   "inversion (rho beyond (sigma-1)/sigma: the continuation of",
                   "the admissible interval past omega = +Inf): 'reject' (v0.7.0",
                   "default: omega = NA at every inversion; the closed form is",
                   "inadmissible, Step 2 carries no omega, and the boundary",
                   "search takes the cell) or 'floor' (clamp to 1e-4 as",
                   "GS_Estimation.do does -- reproduces v0.6.1 bit-for-bit).",
                   "Default: %default"),
      metavar = "RULE"
    ),
    optparse::make_option(
      c("--stage1-edge-se"),
      type = "character", default = "hncs",
      help = paste("Standard errors for constrained boundary (edge) optima:",
                   "'hncs' (v0.7.1 default: the HNCS sandwich projected onto",
                   "the edge tangent; the pinned coordinate stays NA) or",
                   "'none' (v0.7.0: boundary cells ship without SEs). Point",
                   "estimates and routing are identical either way.",
                   "Default: %default"),
      metavar = "RULE"
    ),
    optparse::make_option(
      c("--stage1-step2-vce"),
      type = "character", default = "kclass",
      help = paste("Sandwich behind the Step-2 (weighted Fuller LIML) standard",
                   "errors: 'kclass' (v0.7.3 default: the k-class meat",
                   "X_k'diag(u^2)X_k implied by the estimating equations) or",
                   "'legacy' (OLS meat X'diag(u^2)X; reproduces every release",
                   "through v0.7.2 bit-for-bit). Changes only the SEs of",
                   "step2_weighted cells; points, routing and HLIML/boundary",
                   "SEs are identical. Default: %default"),
      metavar = "RULE"
    ),
    optparse::make_option(
      c("--stage1-uv-trim"),
      type = "double", default = NA_real_,
      help = paste("Apply Stage 2's unit-value trim inside Stage 1: drop",
                   "differenced observations with |d ln p| >= THRESH before",
                   "the reference-exporter join (Stage 2 uses 2.0). Off by",
                   "default (v0.7.x behaviour). Default: off"),
      metavar = "THRESH"
    ),
    optparse::make_option(
      c("--stage1-sigma-cap"),
      type = "double", default = 10,
      help = paste("Stage-1 sigma cap (estimate_cell_liml's sigma_start_cap):",
                   "closed-form HLIML admissibility, the sigma edge of the",
                   "boundary box and the Step-2 clamp. 10 reproduces every",
                   "release through v0.8.3 (patch 0084). Default: %default"),
      metavar = "CAP"
    ),
    optparse::make_option(
      c("--stage1-capped-omega"),
      type = "character", default = "keep",
      help = paste("Whether a sigma-capped Stage-1 cell's omega enters the",
                   "Stage-2a good-level priors: 'keep' (through v0.8.3) or",
                   "'drop' (patch 0084). Default: %default"),
      metavar = "RULE"
    ),
    optparse::make_option(
      c("--stage2-sigma-fallback-pin"),
      type = "double", default = NA_real_,
      help = paste("Pin the Stage-2 fallback sigma (the clean-cell median)",
                   "to this value, for experiments that change the clean-cell",
                   "population (patch 0084). Default: computed"),
      metavar = "SIGMA"
    ),
    optparse::make_option(
      c("--stage2-gradient"),
      type = "character", default = "numeric",
      help = paste("Stage 2 L-BFGS-B gradient: 'numeric' (optim's finite",
                   "differences; reproduces v0.5.x Stage 2b bit-for-bit) or",
                   "'analytic' (exact gradient from the Rcpp Jacobian).",
                   "Default: %default"),
      metavar = "MODE"
    ),
    optparse::make_option(
      c("--stage2-ridge-domain"),
      type = "character", default = "all",
      help = paste("Domain of the Stage-2 log-ridge penalty: 'legacy' (penalize",
                   "only gamma coordinates above 1e-5 -- the band down to the",
                   "1e-6 optimizer bound is penalty-free; reproduces every",
                   "release through v0.7.3 bit-for-bit) or 'all' (penalize every",
                   "coordinate; v0.7.4 default -- closes the hole that parked",
                   "16.6% of directly estimated rows at the 1e-6 floor). Default: %default"),
      metavar = "MODE"
    ),
    optparse::make_option(
      c("--stage2-se"),
      type = "character", default = "sandwich",
      help = paste("Stage-2 gamma variance formula: 'legacy' (s^2 (J'WJ +",
                   "2 lambda/gamma^2)^-1; every release through v0.7.3),",
                   "'posterior' (s^2 (J'WJ + lambda/gamma^2)^-1, consistent",
                   "half-objective curvature) or 'sandwich' (s^2 A^-1 J'WJ A^-1,",
                   "A = J'WJ + lambda/gamma^2: the sampling variance of the",
                   "penalized estimator). Also sets the ridge curvature used by",
                   "dgamma_dsigma. Points and routing are identical. Default: %default"),
      metavar = "FORM"
    ),
    optparse::make_option(c("--stage2-prior"), type = "character", default = "log", metavar = "FORM",
      help = paste("Stage-2 shrinkage prior form (patches 0071/0074): 'log' (ridge on ln gamma; shipped),",
                   "'level' (lambda ((gamma - g)/g)^2), 'share' (lambda (s(gamma) - s(g))^2, s(x) = x/(1+x))",
                   "or 'shiftlog' (lambda (ln(gamma + eps) - ln(g + eps))^2, finite curvature at 0). Default: %default")),
    optparse::make_option(c("--stage2-prior-eps"), type = "double", default = 0.01, metavar = "EPS",
      help = "Shift of the 'shiftlog' prior (patch 0074). Default: %default"),
    optparse::make_option(c("--t-parity"), type = "character", default = "all", metavar = "MODE",
      help = paste("Keep 'odd' or 'even' differenced observations (by t) after prepare_data, for same-period",
                   "split-half experiments (patch 0074); 'all' keeps every observation. Default: %default")),
    optparse::make_option(c("--stage2-maxit"), type = "integer", default = 5000L, metavar = "N",
      help = "L-BFGS-B iteration cap for the Stage-2 cell fit (Nelder-Mead fallback gets 2N); 500 reproduces v0.8.0 and earlier. Default: %default"),
    optparse::make_option(c("--stage2-fallback"), type = "character", default = "best", metavar = "RULE",
      help = "Stage-2 Nelder-Mead fallback rule when L-BFGS-B does not converge: 'best' (v0.8.3 default, patch 0080: keep the lower objective of the two) or 'legacy' (the NM result replaces the L-BFGS-B result whatever its objective; reproduces every release through v0.8.2). Either way <prefix>_stage2_fallbacks.csv records both outcomes per cell (patch 0077). Default: %default"),
    optparse::make_option(c("--stage2-gamma-v-source"), type = "character", default = "regional", metavar = "SRC",
      help = "Where Eq. (11)'s reference-destination gamma_V comes from at Stage 2b: 'regional' (the Stage-2a regional median; every release through v0.8.3) or 'table' (exporter-specific gamma_jV from the Stage-2b table given by --stage2-gamma-v-table, regional median where absent; patch 0085). Default: %default"),
    optparse::make_option(c("--stage2-gamma-v-table"), type = "character", default = "", metavar = "PATH",
      help = "A previous Stage-2b country table (.rds) for --stage2-gamma-v-source table (patch 0085)."),
    optparse::make_option(c("--stage2-export-period-count"), type = "character", default = "rows", metavar = "MODE",
      help = "The Broda-Weinstein T of an export-side row: 'rows' (post-filter row count; every release through v0.8.3) or 'panel' (the pair's period_count, the import side's definition; patch 0085). Default: %default"),
    optparse::make_option(c("--stage2-trim"), type = "character", default = "legacy", metavar = "MODE",
      help = "Stage-2 tail-trim semantics: 'legacy' (sigma bounds as row quantiles although sigma is cell-level; Stage-2a plateau replacement on; every release through v0.8.3) or 'v2' (sigma bounds over cells, plateau replacement off; patch 0083). Both record the removed rows in <prefix>_stage2_trimmed.csv. Default: %default"),
    optparse::make_option(c("--stage2b-prior-source"), type = "character", default = "estimated", metavar = "ROWS",
      help = "Stage-2a rows behind the Stage-2b good-level prior and gamma_V medians: 'estimated' (v0.8.3 default, patch 0080: directly estimated rows only) or 'all' (every row with gamma > 0, incl. Stage-2a's own Tier-3 imputations; reproduces every release through v0.8.2). Default: %default"),
    optparse::make_option(c("--stage2-ref-export-moment"), type = "character", default = "on", metavar = "MODE",
      help = "'on' (v0.8.0 default) adds the reference exporter's own Eq. (11) export row mapped to gamma_k; 'off' reproduces v0.7.x. Default: %default"),
    optparse::make_option(c("--stage2-import-constant"), type = "character", default = "on", metavar = "MODE",
      help = "'on' (v0.8.0 default) concentrates an importer-exporter constant out of the import block (Soderbery fn. 14); 'off' reproduces v0.7.x. Default: %default"),
    optparse::make_option(c("--product-sample"), type = "double", default = 1, metavar = "FRAC",
      help = "Keep a deterministic fraction of HS4 goods from the raw cache before prepare_data (exact for Stage 2; patch 0071). Default: %default"),
    optparse::make_option(c("--product-seed"), type = "integer", default = 20260926L, metavar = "N",
      help = "Seed for --product-sample. Default: %default"),
    optparse::make_option(
      c("--stage"),
      type = "character", default = "all",
      help = paste("Which stage(s) to run: 'all', '1', '2a', '2b'.",
                   "'all' runs whatever isn't already cached on disk;",
                   "specific stages require upstream outputs to exist.",
                   "Default: %default"),
      metavar = "STAGE"
    )
  )

  parser <- optparse::OptionParser(
    usage = "%prog [options] --data DIR",
    option_list = option_list,
    description = paste(
      "Three-stage estimation pipeline for Soderbery (2018) heterogeneous",
      "trade elasticities. See feen94_het_baci.R for methodology details."
    )
  )

  # parse_args() will call quit() on --help or on parse failure when
  # positional_arguments = FALSE and convert_hyphens_to_underscores = TRUE.
  opts <- optparse::parse_args(
    parser, args = args,
    convert_hyphens_to_underscores = TRUE
  )

  validate_cli_opts(opts, parser)

  opts
}


#' Validate parsed CLI options. Stops with a clear error on invalid input.
#'
#' Runs *before* any data is loaded so the user gets immediate feedback
#' on typos, missing required args, and out-of-range values — instead of
#' a cryptic downstream failure 30 minutes into a Stage 1 run.
#'
#' @keywords internal
validate_cli_opts <- function(opts, parser = NULL) {

  fail <- function(msg) {
    if (!is.null(parser)) optparse::print_help(parser)
    stop(msg, call. = FALSE)
  }

  # --- Required ---
  if (is.null(opts$data) || !nzchar(opts$data)) {
    fail("--data is required. Specify the BACI data directory.")
  }
  if (!dir.exists(opts$data)) {
    fail(sprintf("--data='%s' is not a directory (or does not exist).",
                 opts$data))
  }

  # --- Output dir (create if missing) ---
  if (!nzchar(opts$out_dir)) {
    fail("--out-dir cannot be empty.")
  }
  if (!dir.exists(opts$out_dir)) {
    created <- dir.create(opts$out_dir, recursive = TRUE,
                          showWarnings = FALSE)
    if (!created && !dir.exists(opts$out_dir)) {
      fail(sprintf("--out-dir='%s' does not exist and could not be created.",
                   opts$out_dir))
    }
  }

  # --- Enumerated values ---
  if (!opts$agg_level %in% c("hs4", "hs6")) {
    fail(sprintf("--agg-level must be 'hs4' or 'hs6', got: '%s'",
                 opts$agg_level))
  }
  if (!opts$stage %in% c("all", "1", "2a", "2b")) {
    fail(sprintf("--stage must be one of 'all', '1', '2a', '2b', got: '%s'",
                 opts$stage))
  }
  if (!opts$bw_lag %in% c("legacy", "calendar")) {
    fail(sprintf("--bw-lag must be 'legacy' or 'calendar', got: '%s'",
                 opts$bw_lag))
  }
  if (!opts$stage2_gradient %in% c("numeric", "analytic")) {
    fail(sprintf("--stage2-gradient must be 'numeric' or 'analytic', got: '%s'",
                 opts$stage2_gradient))
  }
  if (!opts$stage2_se %in% c("legacy", "posterior", "sandwich")) {
    fail(sprintf("--stage2-se must be 'legacy', 'posterior' or 'sandwich', got: '%s'",
                 opts$stage2_se))
  }
  if (!opts$stage2_prior %in% c("log", "level", "share", "shiftlog")) fail(sprintf("--stage2-prior must be 'log', 'level', 'share' or 'shiftlog', got: '%s'", opts$stage2_prior))
  if (!is.numeric(opts$stage2_prior_eps) || opts$stage2_prior_eps <= 0) fail("--stage2-prior-eps must be positive")
  if (!opts$t_parity %in% c("all", "odd", "even")) fail(sprintf("--t-parity must be 'all', 'odd' or 'even', got: '%s'", opts$t_parity))
  if (!is.numeric(opts$stage2_maxit) || opts$stage2_maxit < 1) fail("--stage2-maxit must be a positive integer")
  if (!opts$stage2_ref_export_moment %in% c("off", "on")) fail(sprintf("--stage2-ref-export-moment must be 'off' or 'on', got: '%s'", opts$stage2_ref_export_moment))
  if (!opts$stage2_import_constant %in% c("off", "on")) fail(sprintf("--stage2-import-constant must be 'off' or 'on', got: '%s'", opts$stage2_import_constant))
  if (!opts$stage2_fallback %in% c("legacy", "best")) fail(sprintf("--stage2-fallback must be 'legacy' or 'best', got: '%s'", opts$stage2_fallback))   # patch 0077
  if (!opts$stage2b_prior_source %in% c("all", "estimated")) fail(sprintf("--stage2b-prior-source must be 'all' or 'estimated', got: '%s'", opts$stage2b_prior_source))   # patch 0079
  if (!opts$stage2_trim %in% c("legacy", "v2")) fail(sprintf("--stage2-trim must be 'legacy' or 'v2', got: '%s'", opts$stage2_trim))   # patch 0083
  if (!opts$stage2_gamma_v_source %in% c("regional", "table")) fail(sprintf("--stage2-gamma-v-source must be 'regional' or 'table', got: '%s'", opts$stage2_gamma_v_source))   # patch 0085
  if (identical(opts$stage2_gamma_v_source, "table") && !(nzchar(opts$stage2_gamma_v_table) && file.exists(opts$stage2_gamma_v_table))) fail(sprintf("--stage2-gamma-v-source table needs --stage2-gamma-v-table pointing at an existing .rds, got: '%s'", opts$stage2_gamma_v_table))   # patch 0085
  if (!opts$stage2_export_period_count %in% c("rows", "panel")) fail(sprintf("--stage2-export-period-count must be 'rows' or 'panel', got: '%s'", opts$stage2_export_period_count))   # patch 0085
  if (!(is.finite(opts$stage1_sigma_cap) && opts$stage1_sigma_cap > 1)) fail(sprintf("--stage1-sigma-cap must be a number > 1, got: '%s'", opts$stage1_sigma_cap))   # patch 0084
  if (!opts$stage1_capped_omega %in% c("keep", "drop")) fail(sprintf("--stage1-capped-omega must be 'keep' or 'drop', got: '%s'", opts$stage1_capped_omega))   # patch 0084
  if (!is.na(opts$stage2_sigma_fallback_pin) && !(is.finite(opts$stage2_sigma_fallback_pin) && opts$stage2_sigma_fallback_pin > 1)) fail(sprintf("--stage2-sigma-fallback-pin must be a number > 1 or omitted, got: '%s'", opts$stage2_sigma_fallback_pin))   # patch 0084
  if (!is.numeric(opts$product_sample) || opts$product_sample <= 0 || opts$product_sample > 1) fail("--product-sample must be in (0, 1]")
  if (!opts$stage2_ridge_domain %in% c("legacy", "all")) {
    fail(sprintf("--stage2-ridge-domain must be 'legacy' or 'all', got: '%s'",
                 opts$stage2_ridge_domain))
  }
  if (!opts$stage1_hliml %in% c("bfgs", "closed", "both")) {
    fail(sprintf("--stage1-hliml must be 'bfgs', 'closed' or 'both', got: '%s'",
                 opts$stage1_hliml))
  }
  if (!is.na(opts$stage1_uv_trim) && !(is.finite(opts$stage1_uv_trim) && opts$stage1_uv_trim > 0)) {
    fail(sprintf("--stage1-uv-trim must be a positive number or omitted, got: '%s'", opts$stage1_uv_trim))
  }
  if (!opts$stage1_edge_se %in% c("none", "hncs")) {
    fail(sprintf("--stage1-edge-se must be 'none' or 'hncs', got: '%s'", opts$stage1_edge_se))
  }
  if (!opts$stage1_step2_vce %in% c("legacy", "kclass")) {
    fail(sprintf("--stage1-step2-vce must be 'legacy' or 'kclass', got: '%s'", opts$stage1_step2_vce))
  }
  if (!opts$stage1_negative_omega %in% c("floor", "reject")) {
    fail(sprintf("--stage1-negative-omega must be 'floor' or 'reject', got: '%s'",
                 opts$stage1_negative_omega))
  }
  if (!opts$stage1_cf_admissibility %in% c("legacy", "strict")) {
    fail(sprintf("--stage1-cf-admissibility must be 'legacy' or 'strict', got: '%s'",
                 opts$stage1_cf_admissibility))
  }

  # --- Year range ---
  if (!is.numeric(opts$minyear) || opts$minyear < 1900L ||
      opts$minyear > 2100L) {
    fail(sprintf("--minyear must be a reasonable year, got: %s",
                 as.character(opts$minyear)))
  }
  # NA = unset = use all data; only validate when actually provided
  if (!is.na(opts$maxyear)) {
    if (opts$maxyear < opts$minyear) {
      fail(sprintf("--maxyear (%d) must be >= --minyear (%d).",
                   opts$maxyear, opts$minyear))
    }
  }

  # --- Numeric ranges ---
  if (opts$ncores < 1L) {
    fail(sprintf("--ncores must be >= 1, got: %d", opts$ncores))
  }
  if (opts$shrinkage_lambda < 0) {
    fail(sprintf("--shrinkage-lambda must be >= 0, got: %g",
                 opts$shrinkage_lambda))
  }

  invisible(TRUE)
}
