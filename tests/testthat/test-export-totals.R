# ============================================================================
# test-export-totals.R  (patch 0107)
#
# --stage2-export-total all on synthetic BACI CSVs carrying both kinds of
# value-only flow: an HS6 line without a quantity inside an HS4 flow that has
# other lines with one, and a flow with no quantity at all. Locks:
# scripts/build_export_totals.R's value_all / value_qobs and census; under
# 'all' prepare_data() carries value_all as exp_total (numerators, unit values
# and the import side unchanged); under 'quantity' (and with the key absent)
# exp_total is value_qobs and the panel is bit-identical to every release; a
# table whose value_qobs does not reproduce the panel, or that misses a cell,
# is refused; the regional mapping sums member countries; CLI / config /
# validation / checkpoint-stamp plumbing.
# ============================================================================

.et_setup <- function() {
  src_dir <- locate_source_dir()
  sink_file <- tempfile(fileext = ".log"); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  source(file.path(src_dir, "parse_cli.R"), local = FALSE)
  source(file.path(src_dir, "build_config.R"), local = FALSE)
  invisible(TRUE)
}
.et_baci <- function() {
  dir <- file.path(tempdir(), paste0("baci_et_", sample.int(1e6, 1))); dir.create(dir)
  for (yr in 2015:2017) {
    k <- yr - 2014
    d <- data.table(t = yr,
                    i = c(156L, 156L, 156L, 410L, 410L, 410L),
                    j = c(840L, 840L, 276L, 840L, 392L, 276L),
                    k = c("850110", "850120", "850110", "850110", "850110", "300490"),
                    v = c(100 * k, 10 * k^2, 50, 80, 30 * k, 40),
                    q = c(10 * k, NA, 5, 8, NA, 4))                        # 850120 line and 410->392 have no quantity
    fwrite(d, file.path(dir, sprintf("BACI_HS92_Y%d_V202601.csv", yr)))
  }
  dir
}

test_that("build_export_totals.R: value_all / value_qobs and the census", {
  .et_setup()
  script <- file.path(locate_source_dir(), "..", "scripts", "build_export_totals.R"); skip_if_not(file.exists(script))
  skip_if_not_installed("optparse")
  dir <- .et_baci(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  p <- tempfile(fileext = ".rds"); md <- tempfile(fileext = ".md"); js <- tempfile(fileext = ".json")
  out <- system2(file.path(R.home("bin"), "Rscript"), c(script, "--data", dir, "--out", p, "--census-md", md, "--census-json", js, "--minyear", "2015"), stdout = TRUE, stderr = TRUE)
  expect_true(file.exists(p), info = paste(out, collapse = "\n"))
  tot <- readRDS(p); setDT(tot)
  r <- tot[year == 2016L & good == "8501" & exporter == "156"]
  expect_equal(r$value_all, 200 + 40 + 50); expect_equal(r$value_qobs, 200 + 50)        # the 850120 line (40) counts in value_all only
  r2 <- tot[year == 2017L & good == "8501" & exporter == "410"]
  expect_equal(r2$value_all, 80 + 90); expect_equal(r2$value_qobs, 80)                   # the 410->392 flow (90) has no quantity
  expect_true(all(tot$value_all >= tot$value_qobs))
  expect_true(file.exists(md)); expect_true(file.exists(js))
  cen <- jsonlite::fromJSON(js); expect_gt(cen$share_value_without_quantity, 0); expect_gt(cen$abs_dln1m$n, 0L)
})

test_that("prepare_data(): 'all' carries value_all; 'quantity'/absent is bit-identical; refusals; regions; plumbing", {
  .et_setup()
  script <- file.path(locate_source_dir(), "..", "scripts", "build_export_totals.R"); skip_if_not(file.exists(script))
  skip_if_not_installed("optparse")
  dir <- .et_baci(); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  p <- tempfile(fileext = ".rds")
  invisible(system2(file.path(R.home("bin"), "Rscript"), c(script, "--data", dir, "--out", p, "--census-md", tempfile(), "--census-json", tempfile(), "--minyear", "2015"), stdout = TRUE, stderr = TRUE))
  tot <- readRDS(p); setDT(tot)
  cfg <- build_config(parse_cli(c("--data", dir, "--minyear", "2015")))
  cfg$use_regions <- FALSE                                                               # as the runner sets it for the country panel
  expect_identical(cfg$stage2_export_total, "quantity")
  sink_file <- tempfile(); sink(sink_file); on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  raw <- prepare_raw_data(cfg)
  q  <- prepare_data(cfg, raw_cache = raw)$dt
  c0 <- cfg; c0$stage2_export_total <- NULL
  q0 <- prepare_data(c0, raw_cache = raw)$dt
  ca <- cfg; ca$stage2_export_total <- "all"; ca$export_totals_tbl <- tot
  a  <- prepare_data(ca, raw_cache = raw)$dt
  sink()
  expect_identical(q, q0)                                                                # absent == quantity, bit for bit
  key <- c("year", "good", "importer", "exporter")
  setkeyv(q, key); setkeyv(a, key)
  expect_identical(a$cusval, q$cusval); expect_identical(a$lp, q$lp); expect_identical(a$ls_imp, q$ls_imp)
  m <- merge(a[, .(year, good, exporter, exp_total)], tot, by = c("year", "good", "exporter"))
  expect_equal(m$exp_total, m$value_all)
  mq <- merge(q[, .(year, good, exporter, exp_total)], tot, by = c("year", "good", "exporter"))
  expect_equal(mq$exp_total, mq$value_qobs)
  expect_equal(a$ls_exp, log(a$cusval / a$exp_total))
  expect_true(any(abs(a$ls_exp - q$ls_exp) > 1e-12))                                     # the export shares do move
  expect_gt(attr(a, "export_totals_census")$cells_raised, 0L)
  # refusals: a table built with other rules, and a table missing a cell
  bad <- copy(tot)[, value_qobs := value_qobs * 1.01]; cb <- ca; cb$export_totals_tbl <- bad
  sink(sink_file); expect_error(prepare_data(cb, raw_cache = raw), "not built with the cache's rules"); sink()
  short <- copy(tot)[-1L]; cs <- ca; cs$export_totals_tbl <- short
  sink(sink_file); expect_error(prepare_data(cs, raw_cache = raw), "has no row"); sink()
  # regions: member countries' totals summed
  cr <- ca; cr$use_regions <- TRUE
  cr$custom_region_map <- data.table(cty_code = c(156L, 410L, 840L, 276L, 392L), region = c("EAS", "EAS", "NAM", "EUR", "EAS"))
  sink(sink_file); ar <- prepare_data(cr, raw_cache = raw)$dt; sink()
  want <- tot[good == "8501" & exporter %in% c("156", "410"), .(v = sum(value_all)), by = year]
  got <- unique(ar[good == "8501" & exporter == "EAS", .(year, exp_total)])
  expect_gt(nrow(got), 0L)                                                               # the panel keeps differenced years only
  expect_equal(got[order(year)]$exp_total, want[year %in% got$year][order(year)]$v)
  # plumbing
  e <- build_config(parse_cli(c("--data", dir, "--minyear", "2015", "--stage2-export-total", "all", "--export-totals-path", p)))
  expect_identical(e$stage2_export_total, "all"); expect_silent(validate_config(e))
  expect_error(parse_cli(c("--data", dir, "--stage2-export-total", "full")), "export-total")
  vb <- cfg; vb$stage2_export_total <- "full"; expect_error(validate_config(vb), "stage2_export_total")
  dts <- make_synthetic_baci(seed = 42L); s0 <- make_synthetic_cfg(); s1 <- s0; s1$stage2_export_total <- "quantity"; s2 <- s0; s2$stage2_export_total <- "all"
  expect_identical(.fs_cfg_stamp(s0, dts), .fs_cfg_stamp(s1, dts))
  expect_false(identical(.fs_cfg_stamp(s0, dts), .fs_cfg_stamp(s2, dts)))
})
