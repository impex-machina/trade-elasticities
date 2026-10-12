# ============================================================================
# test-gate-release.R  (patch 0104)
#
# analysis/gate_release.R on synthetic tables built to the rules: PASS when
# the sigma column is what stage2_sigma_clean() implies; FAIL (exit 1) when
# one estimated cell carries a wrong sigma (H4), when a fallback row
# publishes sigma_robust TRUE (H5), or when optimizer non-convergence among
# directly estimated rows rises (H3); a Tier-3 share change alone passes.
# ============================================================================

test_that("gate_release.R: PASS on a table built to the rules; FAIL on H3 / H4 / H5", {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(); sink(sink_file); on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE); sink()
  script <- file.path(src_dir, "..", "analysis", "gate_release.R"); skip_if_not(file.exists(script))
  set.seed(11)
  s1 <- data.table(importer = as.character(1:40), good = "0101", sigma = c(runif(30, 1.6, 6), rep(1.05, 6), rep(50, 2), 0.9, 2),
                   sigma_se = c(rep(0.2, 30), rep(0.2, 6), NA, NA, 0.1, 0.1), sigma_capped = c(rep(FALSE, 36), TRUE, TRUE, FALSE, FALSE),
                   convergence = c(rep(0L, 39), 1L), status = "ok")
  sc <- stage2_sigma_clean(s1, "fallback", "fallback", 1); fb <- median(sc$clean$sigma)
  mk <- function(n_t3 = 40L, n_nc = 2L) {
    x <- data.table(importer = as.character(rep(1:40, each = 10)), exporter = as.character(rep(1:10, 40)), good = "0101",
                    gamma = exp(rnorm(400, -0.3, 0.5)), gamma_se = 0.1, tier = 1L, convergence = 0L, opt_tariff = 0.7, sigma_robust = FALSE)
    est_cells <- sc$source[sigma_source == "estimated"]$importer
    x[, sigma := ifelse(importer %in% est_cells, s1$sigma[match(importer, s1$importer)], fb)]
    x[importer %in% est_cells[1:5], sigma_robust := TRUE]
    x[seq_len(n_t3), `:=`(tier = 3L, convergence = -1L)]
    if (n_nc > 0L) x[(n_t3 + 1L):(n_t3 + n_nc), convergence := -1L]
    x
  }
  old <- mk(); old[importer %in% c("31", "32"), sigma := s1$sigma[match(importer, s1$importer)]]   # the old table had no pole rule
  run <- function(new) {
    p <- replicate(4, tempfile(fileext = ".rds")); md <- tempfile(fileext = ".md")
    saveRDS(old, p[1]); saveRDS(new, p[2]); saveRDS(s1, p[3])
    out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(script, "--old", p[1], "--new", p[2], "--stage1", p[3], "--out", md), stdout = TRUE, stderr = TRUE))
    list(status = attr(out, "status"), md = if (file.exists(md)) readLines(md) else out)
  }
  ok <- run(mk(n_t3 = 60L))                                                    # Tier 3 grows, optimizer share flat
  expect_true(any(grepl("\\*\\*PASS\\*\\*", ok$md)), info = paste(ok$md, collapse = "\n"))
  n4 <- mk(); n4[importer == sc$source[sigma_source == "estimated"]$importer[1], sigma := sigma + 0.5]
  r4 <- run(n4); expect_true(any(grepl("^- H4", r4$md)), info = paste(r4$md, collapse = "\n")); expect_identical(r4$status, 1L)
  n5 <- mk(); n5[importer == "31", sigma_robust := TRUE]
  r5 <- run(n5); expect_true(any(grepl("^- H5", r5$md)))
  r3 <- run(mk(n_nc = 30L)); expect_true(any(grepl("^- H3", r3$md)))
})
