# ============================================================================
# test-bw-weight-gaps.R
#
# Locks for the BW weight lag policy (post-v0.4.1 audit, deferred item).
# fn 14 (Soderbery 2018, p. 50) defines the weight from x_t and x_{t-1},
# the previous CALENDAR year's customs value. The four estimation sites
# historically obtained that lag with a positional shift() over the
# post-filter moment table, so after a filtered-out year the "lag" is a
# stale x_{t-2+}. cfg$bw_lag now selects the policy:
#
#   "legacy"   (absent-flag behaviour; the CLI default before v0.5.0) —
#              the positional shift, reproducing published v0.4.x
#              output bit-for-bit.
#   "calendar" (CLI default since v0.5.0) — calendar_lag() applied to
#              the pre-filter panel; rows
#              whose calendar t-1 is genuinely unobserved fall to
#              bw_weight()'s NA -> 1 fallback.
#
# Four locks, per the implementation plan:
#   (i)   calendar mode uses the true t-1 customs value across a gap;
#   (ii)  legacy mode reproduces the stale-lag value — a permanent
#         negative control, mirroring test-feenstra-homogeneity-limit.R's
#         pre-F1 lock;
#   (iii) NA-lag rows in calendar mode are exactly the rows whose
#         calendar t-1 is absent from the pre-filter panel: the
#         panel-first rows per exporter, plus — when the prepared panel
#         itself carries a hole (raw gap or UV-trimmed t-1, both dropped
#         upstream by prepare_data()) — the first row after the hole.
#         That second set takes the weight-1 fallback by design; on a
#         hole-free panel the NA set is exactly the panel-first rows.
#         (NOTE: a DIFFERENT set from legacy's retained-first rows — the
#         NA counts differing between modes is correct, not a bug.)
#   (iv)  on gapless data the two modes are bit-identical, from the
#         helper all the way through the Stage 2b pipeline.
#
# Plus: CLI/config plumbing for --bw-lag, and pipeline-level integration
# on a gapped fixture (legacy vs calendar diverge only there; the default
# path stays bit-identical to explicit legacy).
#
# Expected runtime: ~30-90s. The integration block sources the full
# wrapper (Rcpp compile is cached after the first sourceCpp of the
# session) and runs the small Stage 2b fixture five times.
# ============================================================================


# ---------------------------------------------------------------------------
# Block 1 — calendar_lag() unit behaviour (locks i and iii at helper level)
# ---------------------------------------------------------------------------

test_that("calendar_lag matches on calendar t-1, not the previous row", {
  skip_if_not_installed("data.table")
  src_dir <- locate_source_dir()
  ug <- new.env()
  source(file.path(src_dir, "utils_general.R"), local = ug)

  # Single series with a hole at t = 4 (mimics a prepared-panel hole:
  # prepare_data() drops both a missing raw year and its gap-spanning
  # successor before the estimators ever see the panel).
  d <- data.table::data.table(t = c(2L, 3L, 5L, 6L),
                              cusval = c(10, 20, 50, 60))
  got <- ug$calendar_lag(d, value = "cusval", t = "t")
  # (i): t = 6 gets the true t-1 value (50), t = 3 gets 10;
  # t = 5 has no calendar t-1 in the panel -> NA (fallback path), and the
  # positional previous-row value (20) must NOT appear anywhere.
  expect_identical(got, c(NA, 10, NA, 50))
  expect_false(20 %in% got[3])

  # Grouped panel: groups are independent.
  p <- data.table::data.table(
    exporter = c("A", "A", "A", "B", "B", "B", "B"),
    t        = c(2L,  3L,  4L,  2L,  3L,  5L,  6L),
    cusval   = c(1,   2,   3,   10,  20,  50,  60))
  gp <- ug$calendar_lag(p, value = "cusval", t = "t", by = "exporter")
  expect_identical(gp, c(NA, 1, 2, NA, 10, NA, 50))

  # Multi-column `by` gives the same answer when the extra key is constant.
  p2 <- data.table::copy(p)[, good := "8501"]
  expect_identical(ug$calendar_lag(p2, value = "cusval", t = "t",
                                   by = c("good", "exporter")), gp)

  # The input table is not modified.
  expect_identical(ncol(p), 3L)
})


test_that("calendar-mode NA-lag rows are exactly the no-t-1 rows (iii)", {
  skip_if_not_installed("data.table")
  src_dir <- locate_source_dir()
  ug <- new.env()
  source(file.path(src_dir, "utils_general.R"), local = ug)

  # Hole-free panel: the NA set is exactly the panel-first rows.
  clean <- data.table::data.table(
    exporter = rep(c("A", "B"), times = c(5L, 4L)),
    t        = c(2:6, 3:6),
    cusval   = as.numeric(1:9))
  lag_clean <- ug$calendar_lag(clean, value = "cusval", t = "t",
                               by = "exporter")
  first_rows <- clean[, .I[which.min(t)], by = exporter]$V1
  expect_setequal(which(is.na(lag_clean)), first_rows)
  expect_identical(sum(is.na(lag_clean)), 2L)

  # Panel with an internal hole (exporter B missing t = 5): the NA set is
  # the panel-first rows PLUS the first row after the hole — the counted
  # census from the plan's survivorship check. Those extra rows take
  # bw_weight()'s weight-1 fallback rather than a stale lag.
  holed <- clean[!(exporter == "B" & t == 5L)]
  lag_holed <- ug$calendar_lag(holed, value = "cusval", t = "t",
                               by = "exporter")
  first_holed <- holed[, .I[which.min(t)], by = exporter]$V1
  post_hole   <- holed[, .I[exporter == "B" & t == 6L]]
  expect_setequal(which(is.na(lag_holed)), c(first_holed, post_hole))
  expect_identical(sum(is.na(lag_holed)), 3L)
})


# ---------------------------------------------------------------------------
# Block 2 — the site recipe: stale-lag negative control (ii) and the
#            calendar contrast (i), with exact fn-14 arithmetic
# ---------------------------------------------------------------------------

test_that("legacy positional shift reproduces the stale lag; calendar does not", {
  skip_if_not_installed("data.table")
  library(data.table)
  src_dir <- locate_source_dir()
  ug <- new.env()
  source(file.path(src_dir, "utils_general.R"), local = ug)

  # Pre-filter cell panel for one exporter: t = 2..10, cusval = 100 * t.
  panel <- data.table(exporter = "156", t = 2:10,
                      cusval = 100 * (2:10), period_count = 9L)

  # Face 2 of the bug — cell-level filtering: the moment filter drops
  # t = 5 and 6 (e.g. the reference exporter's diffs are missing there)
  # while the panel still holds their customs values.
  retained <- panel[!t %in% c(5L, 6L)]

  # The exact legacy site recipe (setorder + positional shift + weight).
  leg <- copy(retained)
  setorder(leg, exporter, t)
  leg[, cusval_lag := shift(cusval, 1L), by = exporter]
  leg[, bw_w := ug$bw_weight(cusval, cusval_lag, period_count)]

  # (ii) PERMANENT NEGATIVE CONTROL: the t = 7 row's "lag" is the t = 4
  # customs value — fn 14's x_{t-1} silently became x_{t-3} — and the
  # weight is the stale-but-finite fn-14 value, so the row keeps
  # material influence. If a future change makes this stop reproducing,
  # the legacy path is no longer the published v0.4.x behaviour.
  expect_identical(leg[t == 7L]$cusval_lag, 400)
  expect_identical(leg[t == 7L]$bw_w,
                   9L^1.5 * (1 / 700 + 1 / 400)^(-0.5))

  # (i) calendar mode, computed on the pre-filter panel, finds the true
  # t-1 value instead, and the resulting weight differs from legacy's.
  cal <- copy(retained)
  cal[, cusval_lag := ug$calendar_lag(panel, value = "cusval", t = "t",
                                      by = "exporter")[match(cal$t, panel$t)]]
  cal[, bw_w := ug$bw_weight(cusval, cusval_lag, period_count)]
  expect_identical(cal[t == 7L]$cusval_lag, 600)
  expect_identical(cal[t == 7L]$bw_w,
                   9L^1.5 * (1 / 700 + 1 / 600)^(-0.5))
  expect_false(isTRUE(all.equal(leg[t == 7L]$bw_w, cal[t == 7L]$bw_w)))

  # Face 1 -> fallback: when the panel itself lacks t-1 (raw gap or
  # UV-trimmed year, dropped upstream), calendar mode yields NA and the
  # weight falls to exactly 1 — the same near-zero-influence path first
  # rows already take. Legacy still manufactures the stale fn-14 weight.
  panel_holed <- panel[!t %in% c(5L, 6L)]
  lag_holed <- ug$calendar_lag(panel_holed, value = "cusval", t = "t",
                               by = "exporter")
  expect_true(is.na(lag_holed[panel_holed$t == 7L]))
  expect_identical(
    ug$bw_weight(panel_holed[t == 7L]$cusval,
                 lag_holed[panel_holed$t == 7L],
                 panel_holed[t == 7L]$period_count),
    1)

  # (iv) at recipe level: on a gapless retained table the two modes are
  # bit-identical, including the leading-row NA -> 1 fallback.
  dense <- panel  # nothing filtered
  leg_d <- copy(dense)
  setorder(leg_d, exporter, t)
  leg_d[, cusval_lag := shift(cusval, 1L), by = exporter]
  cal_lag_d <- ug$calendar_lag(dense, value = "cusval", t = "t",
                               by = "exporter")
  expect_identical(leg_d$cusval_lag, cal_lag_d)
  expect_identical(
    ug$bw_weight(dense$cusval, leg_d$cusval_lag, dense$period_count),
    ug$bw_weight(dense$cusval, cal_lag_d, dense$period_count))
})


# ---------------------------------------------------------------------------
# Block 3 — CLI and config plumbing for --bw-lag
# ---------------------------------------------------------------------------

test_that("--bw-lag plumbs through parse_cli, build_config, validate_config", {
  src_dir <- locate_source_dir()
  env <- new.env()
  source(file.path(src_dir, "parse_cli.R"), local = env)
  source(file.path(src_dir, "build_config.R"), local = env)
  source(file.path(src_dir, "validate_config.R"), local = env)

  data_dir <- file.path(tempdir(), paste0("bw_lag_fake_baci_",
                                          sample.int(1e6, 1)))
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(data_dir, recursive = TRUE))

  # CLI default is calendar since v0.5.0 (the shipped behaviour); an
  # ABSENT cfg key still runs legacy at the estimators — locked below in
  # the integration block.
  opts_default <- env$parse_cli(args = c("--data", data_dir))
  expect_identical(opts_default$bw_lag, "calendar")
  cfg_default <- env$build_config(opts_default)
  expect_identical(cfg_default$bw_lag, "calendar")

  # Explicit calendar flows through to cfg.
  opts_cal <- env$parse_cli(args = c("--data", data_dir,
                                     "--bw-lag", "calendar"))
  expect_identical(opts_cal$bw_lag, "calendar")
  expect_identical(env$build_config(opts_cal)$bw_lag, "calendar")

  # A typo fails loudly at the CLI instead of silently running legacy.
  expect_error(
    env$parse_cli(args = c("--data", data_dir, "--bw-lag", "monthly")),
    regexp = "--bw-lag must be")

  # validate_config: absent stays valid (hand-built cfg lists predate the
  # flag); both modes pass; junk fails loudly.
  cfg_default$bw_lag <- NULL
  expect_true(env$validate_config(cfg_default))
  cfg_default$bw_lag <- "calendar"
  expect_true(env$validate_config(cfg_default))
  cfg_default$bw_lag <- "positional"
  expect_error(env$validate_config(cfg_default),
               regexp = "bw_lag must be")
})


# ---------------------------------------------------------------------------
# Block 4 — pipeline integration: the four production sites behind the flag
# ---------------------------------------------------------------------------

test_that("bw_lag modes: bit-identical on gapless data, divergent on gaps", {
  skip_if_not_installed("data.table")
  library(data.table)

  src_dir <- locate_source_dir()
  cpp_dir <- locate_cpp_dir()
  assert_cpp_files_present(cpp_dir)

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(src_dir)

  sink_file <- tempfile(fileext = ".log")
  sink(sink_file)
  on.exit({
    if (sink.number() > 0L) sink()
    if (file.exists(sink_file)) file.remove(sink_file)
  }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  sink()

  # The estimator return carries a run_meta attribute with wall-clock
  # metadata (qlog, timings, t_elapsed), so identical() on the raw
  # return differs run-to-run by construction. Compare the DATA: column
  # names, row count, and every column bit-for-bit — the same criterion
  # the lambda-sweep anchor adjudication used.
  data_of <- function(x) c(list(.names = names(x), .nrow = nrow(x)),
                           as.list(x))

  run_2b <- function(dt_in, mode) {
    cfg <- make_synthetic_cfg()
    if (!is.null(mode)) cfg$bw_lag <- mode
    res <- NULL
    capture.output(res <- estimate_all_fixed_sigma(
      cfg, ncores = 1L, prepared_dt = copy(dt_in)))
    res
  }

  # ---- (iv) gapless fixture: all three flag states bit-identical -------
  clean_dt <- make_synthetic_baci(seed = 42L)
  r_default  <- run_2b(clean_dt, NULL)      # absent flag (hand-built cfg)
  r_legacy   <- run_2b(clean_dt, "legacy")
  r_calendar <- run_2b(clean_dt, "calendar")
  expect_identical(data_of(r_default), data_of(r_legacy))
  expect_identical(data_of(r_legacy),  data_of(r_calendar))

  # ---- Gapped fixture ---------------------------------------------------
  # Mimic prepare_data() when raw year 2019 (t = 5) is missing from the
  # (importer 840, exporter 156, good 8501) panel: the t = 5 row and the
  # gap-spanning t = 6 diff both drop upstream, and the panel's raw
  # period count falls to 9. Exporter 156's prepared series in that cell
  # is then t = {2, 3, 4, 7, 8, 9, 10}: legacy hands t = 7 the stale
  # t = 4 customs value; calendar finds no t = 6 in the panel and falls
  # to weight 1.
  gapped_dt <- make_synthetic_baci(seed = 42L)
  gapped_dt <- gapped_dt[!(importer == "840" & exporter == "156" &
                             good == "8501" & t %in% c(5L, 6L))]
  gapped_dt[importer == "840" & exporter == "156" & good == "8501",
            period_count := 9L]

  g_default  <- run_2b(gapped_dt, NULL)
  g_legacy   <- run_2b(gapped_dt, "legacy")
  g_calendar <- run_2b(gapped_dt, "calendar")

  # An ABSENT cfg key still runs legacy, bit-for-bit, gaps included:
  # hand-built cfg lists (this fixture's make_synthetic_cfg, the
  # validation harnesses) keep reproducing published v0.4.x even after
  # the v0.5.0 CLI default flip — CLI-built configs carry an explicit
  # "calendar".
  expect_identical(data_of(g_default), data_of(g_legacy))

  # The modes genuinely diverge once a gap exists: the weight change
  # reaches the published estimates (this is why flipping the default
  # takes the full v0.5 release train).
  expect_false(identical(data_of(g_legacy), data_of(g_calendar)))
  cell_l <- g_legacy[importer == "840" & good == "8501"][order(exporter)]
  cell_c <- g_calendar[importer == "840" & good == "8501"][order(exporter)]
  expect_false(identical(cell_l[exporter == "156"]$gamma,
                         cell_c[exporter == "156"]$gamma))

  # ---- Direct cell calls: homogeneous import site ----------------------
  cfg_l <- make_synthetic_cfg(); cfg_l$bw_lag <- "legacy"
  cfg_c <- make_synthetic_cfg(); cfg_c$bw_lag <- "calendar"

  gap_g   <- gapped_dt[good == "8501"]
  clean_g <- clean_dt[good == "8501"]

  h_gap_l <- estimate_importer_product(copy(gap_g), "840", copy(gap_g), cfg_l)
  h_gap_c <- estimate_importer_product(copy(gap_g), "840", copy(gap_g), cfg_c)
  expect_s3_class(h_gap_l, "data.table")
  expect_s3_class(h_gap_c, "data.table")
  expect_identical(h_gap_l$convergence[1], 0L)
  expect_false(identical(h_gap_l$gamma, h_gap_c$gamma))

  h_clean_l <- estimate_importer_product(copy(clean_g), "840",
                                         copy(clean_g), cfg_l)
  h_clean_c <- estimate_importer_product(copy(clean_g), "840",
                                         copy(clean_g), cfg_c)
  expect_identical(h_clean_l, h_clean_c)

  # ---- Direct cell calls: legacy Feenstra site -------------------------
  f_gap_l <- estimate_feenstra_sigma_cell(copy(gap_g), "840", cfg_l)
  f_gap_c <- estimate_feenstra_sigma_cell(copy(gap_g), "840", cfg_c)
  expect_false(identical(f_gap_l$sigma, f_gap_c$sigma))

  f_clean_l <- estimate_feenstra_sigma_cell(copy(clean_g), "840", cfg_l)
  f_clean_c <- estimate_feenstra_sigma_cell(copy(clean_g), "840", cfg_c)
  expect_identical(f_clean_l, f_clean_c)
})
