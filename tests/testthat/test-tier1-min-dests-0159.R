# ============================================================================
# test-tier1-min-dests-0159.R
#
# (patch 0159) --stage2-tier1-min-dests: the Tier-1 destination threshold as
# a flag (2 shipped; Inf = every exporter but the reference import-only, the
# hybrid arm D). The CLI parses and validates it, build_config carries it,
# the runner under Inf publishes no Tier-1 row and keeps the reference rows,
# and analysis/reliability_tier_split.R writes the two populations.
# ============================================================================

.t1_root <- function() dirname(locate_source_dir())
.t1_run <- function(args, wd) {
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(wd); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, args, stdout = TRUE, stderr = TRUE))
  list(out = out, status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"))
}

test_that("the flag parses, validates and reaches the config", {
  src_dir <- locate_source_dir()
  source(file.path(src_dir, "parse_cli.R"), local = TRUE); source(file.path(src_dir, "build_config.R"), local = TRUE)
  td <- tempfile("te_t1_"); dir.create(td); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  base <- c("--data", td, "--out-dir", td)
  o <- parse_cli(args = base); expect_equal(o$stage2_tier1_min_dests, 2L)
  expect_equal(parse_cli(args = c(base, "--stage2-tier1-min-dests", "3"))$stage2_tier1_min_dests, 3L)
  expect_equal(parse_cli(args = c(base, "--stage2-tier1-min-dests", "Inf"))$stage2_tier1_min_dests, .Machine$integer.max)
  expect_error(parse_cli(args = c(base, "--stage2-tier1-min-dests", "0")), "integer >= 1 or 'Inf'")
  expect_error(parse_cli(args = c(base, "--stage2-tier1-min-dests", "two")), "integer >= 1 or 'Inf'")
  expect_equal(build_config(parse_cli(args = c(base, "--stage2-tier1-min-dests", "Inf")))$tier1_min_dests, .Machine$integer.max)
  expect_equal(build_config(o)$tier1_min_dests, 2L)
})

test_that("under Inf the runner publishes no Tier-1 row; the tier split writes both populations", {
  skip_if(nzchar(Sys.getenv("TE_SKIP_E2E")), "TE_SKIP_E2E is set")
  for (p in c("data.table", "optparse", "Rcpp")) skip_if_not_installed(p)
  root <- .t1_root()
  td <- normalizePath(tempfile("te_t1e_"), winslash = "/", mustWork = FALSE); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  sb <- new.env(); sys.source(file.path(root, "validation", "synthetic_baci.R"), envir = sb)
  baci <- file.path(td, "BACI_HS92_V202601")
  sb$make_synthetic_baci_dir(baci, n_goods = 3L, countries = c(842L, 276L, 392L, 156L, 251L, 826L, 124L, 410L, 528L, 724L), years = 1995:2014, seed = 20261015L)
  runner <- shQuote(file.path(root, "scripts", "run_estimation.R"))
  outs <- list()
  for (cfg in c("ship_odd", "ship_even", "d_odd", "d_even")) {
    o <- file.path(td, cfg); dir.create(o)
    extra <- if (startsWith(cfg, "d_")) c("--stage2-tier1-min-dests", "Inf") else character()
    r <- .t1_run(c(runner, "--data", shQuote(baci), "--out-dir", shQuote(o), "--ncores", "1", "--t-parity", sub("^.*_", "", cfg), extra), wd = td)
    expect_equal(r$status, 0L, info = paste(utils::tail(r$out, 20), collapse = "\n"))
    if (startsWith(cfg, "d_")) expect_match(paste(r$out, collapse = "\n"), "Tier-1 min destinations: Inf", fixed = TRUE)
    outs[[cfg]] <- file.path(o, "baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds")
  }
  d <- readRDS(outs$d_odd); data.table::setDT(d)
  expect_equal(sum(d$tier %in% 1L), 0L); expect_gt(sum(d$tier %in% 0L), 0L); expect_gt(sum(d$tier %in% 2L), 0L)
  s <- readRDS(outs$ship_odd); data.table::setDT(s); expect_gt(sum(s$tier %in% 1L), 0L)
  split <- file.path(td, "split")
  r <- .t1_run(c(shQuote(file.path(root, "analysis", "reliability_tier_split.R")), "--ship-odd", shQuote(outs$ship_odd), "--ship-even", shQuote(outs$ship_even),
                 "--cand-odd", shQuote(outs$d_odd), "--cand-even", shQuote(outs$d_even), "--cand", "D", "--out", shQuote(split)), wd = root)
  expect_equal(r$status, 0L, info = paste(utils::tail(r$out, 10), collapse = "\n"))
  for (pop in c("tier1", "other")) {
    m <- data.table::fread(file.path(split, paste0("runs_", pop, ".csv")))
    expect_setequal(m$config, c("ship", "D")); expect_true(all(file.exists(m$path)))
  }
  t1 <- readRDS(file.path(split, "tier1", "ship_A_fixed_sigma.rds")); data.table::setDT(t1)
  expect_true(all(t1$tier %in% 1L)); expect_gt(nrow(t1), 0L)
  ot <- readRDS(file.path(split, "other", "ship_A_fixed_sigma.rds")); data.table::setDT(ot)
  expect_gt(nrow(ot), 0L)
  key <- function(t) paste(t$importer, t$exporter, t$good)
  expect_length(intersect(key(ot), key(t1)), 0L)        # the two populations are disjoint
  ot_b <- readRDS(file.path(split, "other", "ship_B_fixed_sigma.rds")); data.table::setDT(ot_b)
  both1 <- intersect(key(ot[tier %in% 1L]), key(ot_b[tier %in% 1L]))
  expect_length(both1, 0L)                               # no key Tier 1 in both shipped halves sits in "other"
})
