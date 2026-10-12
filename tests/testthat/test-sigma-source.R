# ============================================================================
# test-sigma-source.R  (patch 0103, 2026-10-12)
#
# stage2_sigma_clean() is the runner's clean-set construction (identity with
# the pre-0103 inline code) plus each cell's sigma provenance;
# attach_sigma_source() labels a table's rows; scripts/add_sigma_source.R
# reconstructs the column on an existing table, verifies it against the
# table's sigma column, and refuses (writes nothing) when the rules given do
# not reproduce the table.
# ============================================================================

.ss_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.ss_stage1 <- function() data.table(
  importer = as.character(1:8), good = "0101",
  sigma       = c(3.0, 4.0, 50.0, 1.05, 0.9, 2.5, 6.0, 1.30),
  sigma_se    = c(0.5, 0.6, NA,   0.20, 0.3, NA,  1.0, 0.10),
  sigma_capped = c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
  convergence = c(0L, 0L, 0L, 0L, 0L, 1L, 0L, 0L), status = "ok", gamma = 0.5)
# cells: 1,2,7,8 estimated (8: 0.30 >= 0.10); 3 edge; 4 pole (0.05 < 0.20); 5 sigma <= 1 and 6 not converged -> no estimate

test_that("stage2_sigma_clean() reproduces the runner's inline construction and labels every cell", {
  .ss_setup()
  s1 <- .ss_stage1()
  sc <- stage2_sigma_clean(s1, "fallback", "fallback", 1)
  manual <- apply_sigma_pole_rule(apply_sigma_edge_rule(s1[!is.na(sigma) & sigma > 1 & convergence == 0], "fallback"), "fallback", 1)
  expect_identical(as.data.frame(sc$clean), as.data.frame(manual))
  expect_equal(sc$n_edge_dropped, 1L); expect_equal(sc$n_pole_dropped, 1L)
  expect_equal(sc$source[order(as.integer(importer))]$sigma_source,
               c("estimated", "estimated", "fallback_sigma_edge", "fallback_sigma_pole", "estimated", "estimated"))
  expect_equal(sc$source[order(as.integer(importer))]$importer, c("1", "2", "3", "4", "7", "8"))
  # the v0.9.1 rules: no pole drop, so cell 4 is estimated
  sc91 <- stage2_sigma_clean(s1, "fallback", "none", 1)
  expect_equal(sc91$source[importer == "4"]$sigma_source, "estimated")
  # attach: cells 5, 6 and a cell absent from Stage 1 are fallback_no_estimate; flagged rows are labelled but not counted
  tb <- data.table(importer = as.character(c(1:8, 9L, 1L)), exporter = "e", good = "0101", sigma = 1,
                   trim_reason = c(rep(NA_character_, 9), "gamma_hi"))
  cen <- attach_sigma_source(tb, sc$source)
  expect_equal(tb$sigma_source, c("estimated", "estimated", "fallback_sigma_edge", "fallback_sigma_pole",
                                  "fallback_no_estimate", "fallback_no_estimate", "estimated", "estimated", "fallback_no_estimate", "estimated"))
  expect_equal(cen$estimated, 4L); expect_equal(cen$fallback_no_estimate, 3L); expect_equal(cen$fallback_sigma_edge, 1L); expect_equal(cen$fallback_sigma_pole, 1L)
})

test_that("scripts/add_sigma_source.R verifies the reconstruction and refuses a wrong rule set", {
  .ss_setup()
  script <- file.path(locate_source_dir(), "..", "scripts", "add_sigma_source.R"); skip_if_not(file.exists(script))
  s1 <- .ss_stage1()
  sc <- stage2_sigma_clean(s1, "fallback", "fallback", 1); fb <- median(sc$clean$sigma)
  tb <- data.table(importer = as.character(c(1:9)), exporter = "e", good = "0101", gamma = 0.6, tier = 1L, convergence = 0L)
  s1_sig <- setNames(s1$sigma, s1$importer)
  tb[, sigma := ifelse(importer %in% sc$source[sigma_source == "estimated"]$importer, s1_sig[importer], fb)]
  p_s1 <- tempfile(fileext = ".rds"); p_in <- tempfile(fileext = ".rds"); p_out <- tempfile(fileext = ".rds"); p_bad <- tempfile(fileext = ".rds")
  saveRDS(s1, p_s1); saveRDS(tb, p_in)
  rs <- function(...) system2(file.path(R.home("bin"), "Rscript"), c(script, ...), stdout = TRUE, stderr = TRUE)
  out <- rs("--stage1", p_s1, "--in", p_in, "--out", p_out)
  expect_true(file.exists(p_out), info = paste(out, collapse = "\n"))
  got <- readRDS(p_out); setDT(got)
  expect_true("sigma_source" %in% names(got)); expect_equal(sum(got$sigma_source == "estimated"), 4L)
  expect_true(any(grepl("off their Stage-1 sigma 0 \\| fallback rows off the fallback 0", out)))
  # idempotent: running on its own output reproduces it
  out2 <- rs("--stage1", p_s1, "--in", p_out, "--out", p_out); got2 <- readRDS(p_out); setDT(got2)
  expect_identical(got2, got)
  # the v0.9.1 rules do not reproduce this table (cell 4 would be "estimated" at its own sigma): refuse, write nothing
  bad <- suppressWarnings(rs("--stage1", p_s1, "--in", p_in, "--out", p_bad, "--pole-rule", "none"))   # the refusal exits 1 by design
  expect_false(file.exists(p_bad)); expect_true(any(grepl("do not reproduce", bad)))
})
