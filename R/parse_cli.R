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
