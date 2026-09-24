# ============================================================================
# test-readme-se-clauses.R  (patch 0064, 2026-09-24)
#
# The v0.7.3 README plumbing. Locks:
#   1. analysis/00_setup.R's bootstrap block (extracted by its markers and
#      evaluated against a synthetic branch-tagged per-cell file) emits
#      results/bootstrap_se_summary.json with the by-route / by-F medians it
#      claims, excludes the nexp_NA and F_NA cells from the core medians, and
#      emits nothing for a pre-0063 (July-schema) file or a missing file.
#   2. scripts/build_readme.R's step2_vce_clause() and bootstrap_clause()
#      (extracted the same way) are empty on old JSONs -- the README lock
#      stays byte-identical until the v0.7.3 numbers exist -- and render the
#      numbers when the blocks are present.
# ============================================================================

.rc_extract <- function(path, start_pat, end_pat) {
  src <- readLines(path, warn = FALSE)
  i0 <- grep(start_pat, src, fixed = TRUE); i1 <- grep(end_pat, src, fixed = TRUE)
  expect_length(i0, 1L); expect_true(length(i1) >= 1L)
  i1 <- i1[i1 > i0][1]
  src[i0:(i1 - 1L)]
}

.rc_cells <- function(seed = 1L) {
  set.seed(seed)
  n <- 60L
  routes <- rep(c("hliml", "hliml_boundary", "step2_weighted"), each = 20L)
  nexp <- rep(c("4-9", "10-19", "50+", "nexp_NA"), 15L)
  fbin <- rep(c("F<2", "F2-7", "F>=7", "F_NA", "F<2"), 12L)
  data.table::data.table(
    importer = seq_len(n), good = "0202", nexp_bin = nexp, f_bin = fbin, final_source = routes,
    n_exporters = 10L, fstat_kp = 3, sigma_pub = 3, sigma_se_pub = 0.3, sigma_base = 3,
    boot_n_ok = 300L, boot_yield = 300 / 399, boot_med = 3, boot_sd = 0.9, boot_mad_sd = 0.45,
    base_source = routes, boot_share_same = runif(n, 0.2, 0.9),
    boot_share_hliml = 0.3, boot_share_step2 = 0.3, boot_share_boundary = 0.4,
    boot_n_same = 150L, boot_med_same = 3, boot_sd_same = 0.6, boot_mad_sd_same = 0.3, boot_med_se_same = 0.28,
    ratio_sd = runif(n, 1, 6), ratio_mad = runif(n, 0.5, 3),
    ratio_sd_same = runif(n, 1, 4), ratio_mad_same = runif(n, 0.5, 2), ratio_se_same = 0.93)
}

test_that("00_setup's bootstrap block emits the by-route JSON and is silent on old or missing files", {
  suppressPackageStartupMessages(library(data.table))
  root <- dirname(locate_source_dir())
  block <- .rc_extract(file.path(root, "analysis", "00_setup.R"),
                       "# --- Exporter-cluster bootstrap benchmark (patch 0064)", "emit_json(stage1_summary,")
  run_block <- function(cells) {
    td <- tempfile(); dir.create(file.path(td, "validation"), recursive = TRUE); dir.create(file.path(td, "results"))
    if (!is.null(cells)) data.table::fwrite(cells, file.path(td, "validation", "bootstrap_se_cells.csv"))
    env <- new.env()
    env$DERIVED_VAL <- file.path(td, "validation")
    env$emit_json <- function(obj, name) {
      jsonlite::write_json(obj, file.path(td, "results", paste0(name, ".json")), auto_unbox = TRUE, pretty = TRUE, digits = NA)
    }
    msgs <- character(0)
    withCallingHandlers(eval(parse(text = block), envir = env),
                        message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    out <- file.path(td, "results", "bootstrap_se_summary.json")
    list(json = if (file.exists(out)) jsonlite::fromJSON(out, simplifyVector = FALSE) else NULL, msgs = msgs)
  }
  cells <- .rc_cells()
  r <- run_block(cells)
  expect_false(is.null(r$json))
  j <- r$json
  expect_equal(j$n_cells, 60L); expect_equal(j$B, 399L)
  core <- cells[!(nexp_bin %in% "nexp_NA") & !(f_bin %in% "F_NA")]
  expect_equal(j$n_cells_core, nrow(core))
  expect_equal(j$n_excluded_nexp_na, sum(cells$nexp_bin == "nexp_NA"))
  expect_setequal(names(j$by_route), c("hliml", "hliml_boundary", "step2_weighted"))
  h <- core[final_source == "hliml"]
  expect_equal(j$by_route$hliml$n_cells, nrow(h))
  expect_equal(j$by_route$hliml$ratio_mad_same_median, median(h$ratio_mad_same))
  expect_equal(j$by_route$hliml$ratio_sd_median, median(h$ratio_sd))
  expect_equal(j$by_route$hliml$share_same_route_median, median(h$boot_share_same))
  expect_true(all(c("F<2", "F2-7", "F>=7") %in% names(j$step2_by_f)))
  expect_false("F_NA" %in% names(j$step2_by_f))
  s7 <- core[final_source == "step2_weighted" & f_bin == "F>=7"]
  expect_equal(j$step2_by_f[["F>=7"]]$ratio_mad_same_median, median(s7$ratio_mad_same))
  expect_equal(j$baseline_match_rate, 1)
  # July-schema file (no branch tags): no JSON, a message
  july <- cells[, .(importer, good, nexp_bin, f_bin, final_source, n_exporters, fstat_kp, sigma_pub, sigma_se_pub,
                    sigma_base, boot_n_ok, boot_yield, boot_med, boot_sd, boot_mad_sd, ratio_sd, ratio_mad)]
  r2 <- run_block(july)
  expect_null(r2$json); expect_true(any(grepl("predates the branch tags", r2$msgs)))
  r3 <- run_block(NULL)
  expect_null(r3$json); expect_true(any(grepl("no bootstrap_se_cells.csv", r3$msgs)))
})

test_that("README clauses are empty on old JSONs and render the v0.7.3 numbers when present", {
  root <- dirname(locate_source_dir())
  src <- readLines(file.path(root, "scripts", "build_readme.R"), warn = FALSE)
  pick <- function(fn) {
    i0 <- grep(paste0("^", fn, " <- function"), src); expect_length(i0, 1L)
    i1 <- i0 + which(grepl("^}", src[(i0 + 1L):length(src)]))[1]
    src[i0:i1]
  }
  env <- new.env()
  env$format_int <- function(x) formatC(as.integer(x), big.mark = ",", format = "d")
  eval(parse(text = c(pick("step2_vce_clause"), pick("bootstrap_clause"))), envir = env)
  expect_identical(env$step2_vce_clause(NULL), "")
  expect_identical(env$step2_vce_clause(list(method = "legacy", n_step2 = 5)), "")
  expect_identical(env$bootstrap_clause(NULL), "")
  expect_identical(env$bootstrap_clause(list(n_cells = 1)), "")
  sv <- list(method = "kclass", n_step2 = 47479, rel_se_median_step2 = 0.239, rel_se_median_hliml = 0.252, rel_se_median_boundary = 0.298)
  s1 <- env$step2_vce_clause(sv)
  expect_true(grepl("47,479 Step-2", s1, fixed = TRUE)); expect_true(grepl("0.24 on Step-2", s1, fixed = TRUE))
  bs <- list(n_cells = 750, B = 399, n_cells_core = 653,
             by_route = list(hliml = list(share_same_route_median = 0.646, ratio_mad_same_median = 0.951, ratio_sd_median = 4.568),
                             hliml_boundary = list(share_same_route_median = 0.574, ratio_mad_same_median = 1.287, ratio_sd_median = 3.252),
                             step2_weighted = list(share_same_route_median = 0.337, ratio_mad_same_median = 1.337, ratio_sd_median = 3.621)),
             step2_by_f = list(`F>=7` = list(ratio_mad_same_median = 5.576)))
  s2 <- env$bootstrap_clause(bs)
  expect_true(grepl("750 cells", s2, fixed = TRUE)); expect_true(grepl("0.95", s2, fixed = TRUE))
  expect_true(grepl("medians over the 653 cells", s2, fixed = TRUE))
  bs_all <- bs; bs_all$n_cells_core <- NULL
  expect_false(grepl("medians over", env$bootstrap_clause(bs_all), fixed = TRUE))
  expect_true(grepl("65%, 57% and 34%", s2, fixed = TRUE)); expect_true(grepl("5.58", s2, fixed = TRUE))
  bs$step2_by_f <- NULL
  expect_false(grepl("strong instruments", env$bootstrap_clause(bs), fixed = TRUE))
})
