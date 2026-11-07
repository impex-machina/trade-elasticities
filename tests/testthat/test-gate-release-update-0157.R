# ============================================================================
# test-gate-release-update-0157.R
#
# (patch 0157) analysis/gate_release.R under the sigma update (the default
# since patch 0155): on a real small run the gate PASSes with --profile and
# --update-log; a tampered sigma fails H4, a tampered label fails H6, a
# sigma_robust TRUE on an updated row fails H5; without --profile the gate
# fails H4 rather than reading the old rules against an updated table.
# ============================================================================

.gr_root <- function() dirname(locate_source_dir())
.gr_run <- function(args, wd) {
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(wd); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, args, stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

test_that("the release gate reads the sigma update's rules", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "Rcpp")) skip_if_not_installed(p)
  root <- .gr_root()
  td <- normalizePath(tempfile("te_gr_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  sb$make_synthetic_baci_dir(baci, n_goods = 3L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L),
                             years = 1995:2014, seed = 20261015L)
  runner <- shQuote(file.path(root, "scripts", "run_estimation.R"))
  out0 <- file.path(td, "out0"); dir.create(out0)      # the predecessor: the update off (v0.11.4's rules)
  r0 <- .gr_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(out0), "--ncores", "1", "--stage2-sigma-update", "off"), wd = td)
  expect_equal(r0$status, 0L, info = paste(utils::tail(r0$out, 20), collapse = "\n"))
  out1 <- file.path(td, "out1"); dir.create(out1)      # the defaults: the shrunk update
  r1 <- .gr_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(out1), "--ncores", "1"), wd = td)
  expect_equal(r1$status, 0L, info = paste(utils::tail(r1$out, 20), collapse = "\n"))
  pre0 <- file.path(out0, "baci_hs92_v202601_elast_country_hs4"); pre1 <- file.path(out1, "baci_hs92_v202601_elast_country_hs4")
  old <- paste0(pre0, "_fixed_sigma.rds"); new <- paste0(pre1, "_fixed_sigma.rds"); s1 <- paste0(pre1, "_feenstra_sigma.rds")
  prof <- paste0(pre1, "_sigma_update_pass1.csv"); ulog <- paste0(pre1, "_sigma_update_passes.csv"); plog <- paste0(pre1, "_gamma_v_passes.csv")
  gate <- shQuote(file.path(root, "analysis", "gate_release.R"))
  run_gate <- function(new_path, label, extra = character()) {
    md <- file.path(td, paste0("gate_", label, ".md"))
    r <- .gr_run(c(gate, "--old", shQuote(old), "--new", shQuote(new_path), "--stage1", shQuote(s1), "--pass-log", shQuote(plog),
                   "--max-row-change", "0.2", "--out", shQuote(md), "--label", label, extra), wd = root)
    list(status = r$status, md = if (file.exists(md)) readLines(md) else character(), out = r$out)
  }
  # PASS with the update's inputs
  g <- run_gate(new, "upd", c("--profile", shQuote(prof), "--update-log", shQuote(ulog)))
  expect_equal(g$status, 0L, info = paste(utils::tail(g$out, 15), collapse = "\n"))
  expect_true(any(grepl("^\\*\\*PASS\\*\\*", g$md)))
  expect_true(any(grepl("Sigma \\(the update", g$md)))
  # without the profile: H4, not a silent read of the old rules
  g0 <- run_gate(new, "noprof")
  expect_equal(g0$status, 1L); expect_true(any(grepl("H4 .*--profile", g0$md)))
  # tampering
  t <- readRDS(new); data.table::setDT(t)
  i <- which(t$sigma_source == "updated_import_shrunk")[1]
  t4 <- data.table::copy(t); t4$sigma[i] <- t4$sigma[i] * 1.01; f4 <- file.path(td, "t4.rds"); saveRDS(t4, f4)
  g4 <- run_gate(f4, "h4", c("--profile", shQuote(prof), "--update-log", shQuote(ulog)))
  expect_equal(g4$status, 1L); expect_true(any(grepl("^- H4 ", g4$md)))
  t5 <- data.table::copy(t); t5$sigma_robust[i] <- TRUE; f5 <- file.path(td, "t5.rds"); saveRDS(t5, f5)
  g5 <- run_gate(f5, "h5", c("--profile", shQuote(prof), "--update-log", shQuote(ulog)))
  expect_equal(g5$status, 1L); expect_true(any(grepl("^- H5 ", g5$md)))
  t6 <- data.table::copy(t); t6$sigma_source[i] <- "updated_level"; f6 <- file.path(td, "t6.rds"); saveRDS(t6, f6)
  g6 <- run_gate(f6, "h6", c("--profile", shQuote(prof), "--update-log", shQuote(ulog)))
  expect_equal(g6$status, 1L); expect_true(any(grepl("^- H6 ", g6$md)))
  # the old rules still read a table without the update (the predecessor against itself)
  gold <- run_gate(old, "old")
  expect_equal(gold$status, 0L, info = paste(utils::tail(gold$out, 15), collapse = "\n"))
})
