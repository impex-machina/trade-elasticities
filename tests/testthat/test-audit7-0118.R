# ============================================================================
# test-audit7-0118.R  (patch 0118, fresh-eyes audit #7: records and wording)
#
# The v0.11.0 convergence census showed the Nelder-Mead restart running for
# every L-BFGS-B fit that did not converge -- 93% of the non-converged rows a
# failed line search (code 52), 7% the iteration cap (code 1) -- while the
# README (since v0.8.3), the fallback census and the 0116 sentence said
# "reached the cap". Locks:
#   1. build_readme.R: the convergence clause reads the code split and no
#      longer says "at the iteration cap"; the fallback clause says "did not
#      converge" and adds the codes when the census has them; the M1 / M2
#      clauses are empty without their JSONs and render from them;
#   2. the template's v0.8.3 sentence no longer says "reaches that cap";
#   3. analysis/stage2_fallback_census.R tabulates the L-BFGS-B codes;
#   4. analysis/stage2b_convergence_census.R counts the cells whose
#      non-converged rows the tail trim flagged;
#   5. the card keeps v0.11.0 as its top entry (hf_upload_release.py's Gate 0)
#      and carries the corrections note.
# ============================================================================

.a18_root <- function() dirname(locate_source_dir())
.a18_readme_env <- function() {
  path <- file.path(.a18_root(), "scripts", "build_readme.R"); skip_if_not(file.exists(path))
  env <- new.env()
  for (e in parse(path, keep.source = FALSE))
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function")))
      eval(e, env)
  env
}

test_that("README phrases (0118): convergence split, fallback wording, M1 and M2 clauses", {
  env <- .a18_readme_env()
  conv <- list(data = list(census = list(n_nonconverged = 35825L, n_estimated = 4982259L, n_cells_nonconverged = 1775L,
                                         n_cells_estimated = 210098L, codes_estimated = list(`0` = 4946434L, `1` = 2397L, `52` = 33428L))),
               key = "stage2b_convergence_census_v0110", fresh = TRUE)
  cl <- env$convergence_clause(conv)
  expect_match(cl, "0.7% of directly estimated rows (1,775 of 210,098 fitted cells; a failed L-BFGS-B line search on 93.3% of those rows, the iteration cap on 6.7%)", fixed = TRUE)
  expect_false(grepl("at the iteration cap and", cl, fixed = TRUE))
  fb <- list(data = list(n_cells = 2370L, n_nm_worse = 1868L, share_nm_worse = 0.788, n_nm_converged = 1561L),
             key = "stage2_fallback_census_v0110", fresh = TRUE, vintage = "v0.11.0")
  f1 <- env$fallback_clause(fb)
  expect_match(f1, "the L-BFGS-B fit did not converge on 2,370 cells and the restart ran", fixed = TRUE)
  expect_false(grepl("reached that cap", f1, fixed = TRUE))
  fb$data$lbfgsb_codes <- list(`1` = 160L, `52` = 2210L)
  expect_match(env$fallback_clause(fb), "2,370 cells (code 52, a failed line search, on 2,210; code 1, the iteration cap, on 160)", fixed = TRUE)
  expect_identical(env$pole_accuracy_clause(NULL), "")
  pa <- list(by_sigma = list(
    list(sigma_true = 1.2, tariff_err_P1 = 0.034, tariff_err_P2 = 0.059, pole_drop_share_of_usable = 0.599),
    list(sigma_true = 2,   tariff_err_P1 = 0.038, tariff_err_P2 = 0.030, pole_drop_share_of_usable = 0.319),
    list(sigma_true = 3,   tariff_err_P1 = 0.070, tariff_err_P2 = 0.054, pole_drop_share_of_usable = 0.240),
    list(sigma_true = 8,   tariff_err_P1 = 1.916, tariff_err_P2 = 2.284, pole_drop_share_of_usable = 0.275)))
  pc <- env$pole_accuracy_clause(pa)
  expect_match(pc, "higher with the rule at \u03c3 = 1.2, 8 and lower at \u03c3 = 2, 3", fixed = TRUE)
  expect_match(pc, "drops 24.0%\u201327.5% of usable fits", fixed = TRUE)
  expect_identical(env$fallback_hierarchy_clause(NULL), "")
  hier <- list(data = list(census = list(r2_good = 0.057, loo = list(err_global = 0.693, err_good = 0.674, err_ladder = 0.699))),
               key = "sigma_fallback_hierarchy_census_v0110", fresh = TRUE)
  hc <- env$fallback_hierarchy_clause(hier)
  expect_match(hc, "the good explains 5.7% of the variance", fixed = TRUE)
  expect_match(hc, "(median error 0.699 against 0.693;", fixed = TRUE)
})

test_that("the template's v0.8.3 sentence no longer says the restart is for cells at the cap", {
  tpl <- readLines(file.path(.a18_root(), "README.template.md"), warn = FALSE, encoding = "UTF-8")
  expect_false(any(grepl("a cell that reaches that cap", tpl, fixed = TRUE)))
  expect_true(any(grepl("whose L-BFGS-B fit does not converge", tpl, fixed = TRUE)))
  expect_true(any(grepl("{{pole_accuracy_clause(r$pole_rule_accuracy)}}", tpl, fixed = TRUE)))
  expect_true(any(grepl("{{fallback_hierarchy_clause(HIER)}}", tpl, fixed = TRUE)))
})

test_that("stage2_fallback_census.R tabulates the L-BFGS-B codes behind the restarts", {
  skip_if_not_installed("jsonlite")
  script <- file.path(.a18_root(), "analysis", "stage2_fallback_census.R"); skip_if_not(file.exists(script))
  d <- tempfile("fb_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  fb <- data.table::data.table(importer = as.character(1:5), good = "0101", J = 10L, M = 8L,
                               lbfgsb_convergence = c(52L, 52L, 52L, 1L, 51L), lbfgsb_value = c(1, 2, 3, 4, 5),
                               nm_convergence = c(0L, 1L, 0L, 0L, 0L), nm_value = c(1.5, 1.8, 3.2, 3.9, 5.1),
                               chosen = c("lbfgsb", "nelder_mead", "lbfgsb", "nelder_mead", "lbfgsb"), rule = "best")
  csv <- file.path(d, "fb.csv"); data.table::fwrite(fb, csv)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c(script, "--csv", csv, "--label", "test", "--out", file.path(d, "f.json"), "--md", file.path(d, "f.md")), stdout = TRUE, stderr = TRUE))
  expect_true(file.exists(file.path(d, "f.json")), info = paste(out, collapse = "\n"))
  j <- jsonlite::fromJSON(file.path(d, "f.json"))
  expect_identical(j$lbfgsb_codes$`52`, 3L); expect_identical(j$lbfgsb_codes$`1`, 1L); expect_identical(j$lbfgsb_codes$`51`, 1L)
  md <- readLines(file.path(d, "f.md"))
  expect_true(any(grepl("did not converge and ran the Nelder-Mead restart", md, fixed = TRUE)))
  expect_true(any(grepl("L-BFGS-B codes on those cells: 1 = 1, 51 = 1, 52 = 3", md, fixed = TRUE)))
})

test_that("stage2b_convergence_census.R counts cells whose non-converged rows were all flagged", {
  skip_if_not_installed("jsonlite"); skip_if_not_installed("openssl")
  script <- file.path(.a18_root(), "analysis", "stage2b_convergence_census.R"); skip_if_not(file.exists(script))
  x <- data.table::data.table(importer = c("1", "1", "2", "2", "3", "3"), exporter = c("a", "b", "a", "b", "a", "b"), good = "0101",
                              tier = 1L, convergence = c(52L, 52L, 1L, 1L, 0L, 0L),
                              gamma_se_status = c("non_converged", "non_converged", "non_converged", "non_converged", "ok", "ok"),
                              trim_reason = c(NA, NA, "gamma_hi", "gamma_lo", NA, NA))
  d <- tempfile("cc_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  p <- file.path(d, "t.rds"); saveRDS(x, p)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c(script, "--stage2b", p, "--label", "vT", "--out", file.path(d, "c.json"), "--md", file.path(d, "c.md")), stdout = TRUE, stderr = TRUE))
  j <- jsonlite::fromJSON(file.path(d, "c.json"))
  expect_identical(j$census$n_cells_nonconverged, 1L)                 # cell 2's rows are all flagged
  expect_identical(j$n_cells_nonconverged_incl_flagged, 2L)
  md <- readLines(file.path(d, "c.md"))
  expect_true(any(grepl("2 cells with a non-converged directly estimated row (1 whose non-converged rows were all flagged)", md, fixed = TRUE)))
  expect_true(any(grepl("52 L-BFGS-B error, typically a failed line search", md, fixed = TRUE)))
})

test_that("the card keeps v0.11.0 as its top entry and carries the corrections note", {
  card <- readLines(file.path(.a18_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  heads <- regmatches(card, regexpr("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+", card))   # hf_upload_release.py's Gate 0 pattern
  expect_identical(heads[1], "> **v0.11.0")
  expect_true(any(grepl("^\\*\\*Corrections \\(2026-10-15", card)))
  expect_true(any(grepl("0.72% of directly estimated rows", card, fixed = TRUE)))
  expect_true(any(grepl("colClasses = list(character = \"good\")", card, fixed = TRUE)))
})
