# ============================================================================
# test-config-partial-match.R  (patch 0103, 2026-10-12)
#
# R's `$` partial-matches list names: on a list WITHOUT `stage2_trim`,
# cfg$stage2_trim silently returns cfg$stage2_trim_action (patch 0101 found
# this when the synthetic fixture gained the longer key -- ten tests broke).
# Guard: no `cfg$` / `opts$` / `config$` / `config_2a$` / `config_2b$` read
# in R/ or scripts/ may use a key that is a strict prefix of another config
# key. Such keys must be read with [[ ]] (exact match).
# ============================================================================

test_that("no $-read of a config key that is a strict prefix of another config key", {
  src_dir <- locate_source_dir()
  skip_if_not_installed("optparse")
  sink_file <- tempfile(); sink(sink_file)
  on.exit({ if (sink.number() > 0L) sink(); unlink(sink_file) }, add = TRUE)
  source(file.path(src_dir, "feen94_het_baci.R"), local = FALSE)
  source(file.path(src_dir, "parse_cli.R"), local = FALSE)
  source(file.path(src_dir, "build_config.R"), local = FALSE)
  sink()
  fake <- file.path(tempdir(), paste0("fake_baci_pm_", sample.int(1e6, 1))); dir.create(fake, showWarnings = FALSE)
  on.exit(unlink(fake, recursive = TRUE), add = TRUE)
  opts <- parse_cli(c("--data", fake)); cfg <- build_config(opts)
  keys <- unique(c(names(opts), names(cfg)))
  prefix_keys <- keys[vapply(keys, function(k) any(startsWith(keys, k) & keys != k), logical(1))]
  files <- c(list.files(src_dir, pattern = "\\.R$", full.names = TRUE),
             list.files(file.path(src_dir, "..", "scripts"), pattern = "\\.R$", full.names = TRUE))
  pat <- "\\b(cfg|opts|config|config_2a|config_2b)\\$([A-Za-z_.][A-Za-z0-9_.]*)"
  hits <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    for (i in seq_along(lines)) {
      code <- sub("#.*$", "", lines[i])
      m <- regmatches(code, gregexpr(pat, code, perl = TRUE))[[1]]
      for (x in m) { key <- sub("^[^$]*\\$", "", x); if (key %in% prefix_keys) hits <- c(hits, sprintf("%s:%d %s", basename(f), i, x)) }
    }
  }
  expect_true(length(prefix_keys) > 0L)                     # the hazard exists in this config (stage2_trim / stage2_trim_action at least)
  expect_identical(hits, character(0), info = paste(c("prefix keys read with `$`:", hits), collapse = "\n"))
})
