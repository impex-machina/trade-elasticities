# ============================================================================
# test-run-hygiene-0092.R  (patch 0092, 2026-10-10)
#
# Three independent items, none changing a published number:
#   1. an estimation run that produces no estimates leaves no checkpoint and
#      no stale fallback / trim record behind, so the next run under another
#      config is not refused by the resume guard;
#   2. stage2a_gamma_v_default(): 'clean' (every release) is the median omega
#      over the whole clean set, 'priors' the median over the priors' rows;
#      absent == clean; bad rule / no finite gamma error; CLI, build_config
#      and validate_config accept the flag and keep the default;
#   3. scripts/hf_upload_release.py's card parser: a <fill> placeholder is
#      "not released", a 40-hex oid is (python needed; skipped without one).
# ============================================================================

.h92_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  invisible(TRUE)
}
.h92_run <- function(cfg, dt) {
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  estimate_all_fixed_sigma(cfg, ncores = 1L, prepared_dt = dt)
}

test_that("a run with no estimates leaves no checkpoint or stale record, and the next run is not refused", {
  .h92_setup()
  skip_if_not(exists(".het_jac_rcpp_loaded") && isTRUE(.het_jac_rcpp_loaded))
  dt <- make_synthetic_baci(seed = 42L); cfg <- make_synthetic_cfg()
  prefix <- build_output_prefix(cfg)
  ckpt <- paste0(prefix, "_fs_checkpoint.rds"); fb <- paste0(prefix, "_stage2_fallbacks.csv"); tr <- paste0(prefix, "_stage2_trimmed.csv")
  on.exit(unlink(c(ckpt, fb, tr)), add = TRUE)
  unlink(c(ckpt, fb, tr))
  writeLines("stale,record", fb); writeLines("stale,record", tr)           # planted stale records from an "earlier run"
  empty <- cfg; empty$min_exporters <- 100L                                  # every cell fails: no estimates
  out <- .h92_run(empty, dt)
  expect_null(out)
  expect_false(file.exists(ckpt)); expect_false(file.exists(fb)); expect_false(file.exists(tr))
  ok <- .h92_run(cfg, dt)                                                    # a different config: no resume-guard error
  expect_true(is.data.table(ok)); expect_gt(nrow(ok), 0L)
  expect_false(file.exists(ckpt))
})

test_that("stage2a_gamma_v_default(): clean vs priors rows, absent == clean, errors", {
  .h92_setup()
  clean  <- data.table(importer = 1:6, good = "0101", gamma = c(1e-4, 0.5, 0.7, 10, 0.9, 1.1), sigma = c(3, 3, 3, 3, 50, 3))
  priors <- clean[gamma > 1e-4 & gamma < 10 & sigma < 50]                   # unfloored, uncapped, no sigma-edge cell
  expect_equal(stage2a_gamma_v_default(clean, priors, "clean"), median(clean$gamma))
  expect_equal(stage2a_gamma_v_default(clean, priors, "priors"), median(priors$gamma))
  expect_equal(stage2a_gamma_v_default(clean, priors, NULL), median(priors$gamma))   # patch 0101: absent == priors
  expect_equal(stage2a_gamma_v_default(clean, priors), median(priors$gamma))
  expect_false(stage2a_gamma_v_default(clean, priors, "clean") == stage2a_gamma_v_default(clean, priors, "priors"))
  expect_error(stage2a_gamma_v_default(clean, priors, "all"), "rule")
  expect_error(stage2a_gamma_v_default(clean, priors[0], "priors"), "finite gamma")
  skip_if_not_installed("optparse")
  source(file.path(locate_source_dir(), "parse_cli.R"), local = FALSE)
  source(file.path(locate_source_dir(), "build_config.R"), local = FALSE)
  fake <- file.path(tempdir(), paste0("fake_baci_h92_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  base <- c("--data", fake)
  cfg <- build_config(parse_cli(base)); expect_identical(cfg$stage2a_gamma_v_default, "priors"); expect_silent(validate_config(cfg))   # patch 0101 default
  r <- build_config(parse_cli(c(base, "--stage2a-gamma-v-default", "clean"))); expect_identical(r$stage2a_gamma_v_default, "clean")
  e <- build_config(parse_cli(c(base, "--stage2a-gamma-v-default", "priors"))); expect_identical(e$stage2a_gamma_v_default, "priors"); expect_silent(validate_config(e))
  expect_error(parse_cli(c(base, "--stage2a-gamma-v-default", "all")), "stage2a-gamma-v-default")
  bad <- cfg; bad$stage2a_gamma_v_default <- "all"; expect_error(validate_config(bad), "stage2a_gamma_v_default")
})

test_that("hf_upload_release.py reads the card's top entry: <fill> is unreleased, a 40-hex oid is released", {
  py <- Sys.which("python3"); if (!nzchar(py)) py <- Sys.which("python"); if (!nzchar(py)) py <- Sys.which("py")
  skip_if(!nzchar(py), "no python on PATH")
  script <- normalizePath(file.path(locate_source_dir(), "..", "scripts", "hf_upload_release.py"), mustWork = FALSE)
  skip_if_not(file.exists(script))
  card <- tempfile(fileext = ".md")
  writeLines(c("---", "license: cc-by-4.0", "---", "", "> **v0.9.1 (2026-10-XX).** Correction.", "> Data revision: `<fill at the card step after the HF upload>`. **v0.9.0 remains available**",
               ">", "> **v0.9.0 (2026-10-10).** Methodology release. Data revision:", "> `af5d7c659f2a17e1c3e3ce8765d75731616a292c`. **v0.8.3 remains available pinned**"), card)
  code <- sprintf("import importlib.util, pathlib; s = importlib.util.spec_from_file_location('h', r'%s'); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); c = pathlib.Path(r'%s'); print(m.card_top_entry(c)); t = c.read_text(encoding='utf-8'); i = t.find('> **v0.9.0 ('); c.write_text(t[:t.find('> **v0.9.1 (')] + t[i:], encoding='utf-8'); print(m.card_top_entry(c))", script, card)
  out <- system2(py, c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE)
  expect_true(any(grepl("('0.9.1', None)", out, fixed = TRUE)), info = paste(out, collapse = "\n"))
  expect_true(any(grepl("('0.9.0', 'af5d7c659f2a17e1c3e3ce8765d75731616a292c')", out, fixed = TRUE)), info = paste(out, collapse = "\n"))
})
