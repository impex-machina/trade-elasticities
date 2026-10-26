# ============================================================================
# test-refresh-table-censuses.R  (patch 0144)
#
# scripts/refresh_table_censuses.R re-runs, on the shipped tables, the
# censuses whose only inputs are those tables, and checks each against the one
# it supersedes. Locks:
#   1. the helpers: tag -> suffix, suffix ordering, the predecessor pick, the
#      provenance-blind comparison, the table check, the argument parser;
#   2. coverage: every census build_readme.R picks through pick_census() or
#      pick_census_opt() is in the tool's plan;
#   3. interface: every flag the plan passes is a flag its census script reads
#      (a typo would otherwise surface only on the full tables);
#   4. a dry run in a scratch repo: the plan, the suffix, the predecessors,
#      and exit 1 on a table that differs from the manifest;
#   5. build_readme.R names the tool when it renders a dated census.
# A full run of all six census scripts on the synthetic tables of the runner
# (both outcomes: MOVED against different tables, `same` against the same
# ones) was done when the patch was written; it needs the runner, so it is not
# repeated here.
# ============================================================================

.rc_root <- function() dirname(locate_source_dir())

.rc_env <- function() {
  src <- readLines(file.path(.rc_root(), "scripts", "refresh_table_censuses.R"), warn = FALSE)
  i0 <- grep("# --- refresh helpers (patch 0144)", src, fixed = TRUE)
  i1 <- grep("# --- end refresh helpers (patch 0144)", src, fixed = TRUE)
  expect_length(i0, 1L); expect_length(i1, 1L)
  env <- new.env(parent = globalenv())
  eval(parse(text = src[i0:i1]), envir = env)
  env
}

.rc_write_json <- function(x, path) jsonlite::write_json(x, path, auto_unbox = TRUE, digits = NA, null = "null")

test_that("tag, suffix and ordering helpers", {
  e <- .rc_env()
  expect_identical(e$suffix_of_tag("v0.11.3"), "v0113")
  expect_identical(e$suffix_of_tag("v0.9.1"), "v091")
  expect_identical(e$suffix_of_tag("v0.10.2"), "v0102")
  expect_error(e$suffix_of_tag("v0.12.10"), "5-digit suffix")
  expect_identical(e$release_tag_of(c("https://h/d/resolve/v0.11.3/a.rds", "https://h/d/resolve/v0.11.3/b/c.csv")), "v0.11.3")
  expect_error(e$release_tag_of(c("https://h/resolve/v0.11.2/a", "https://h/resolve/v0.11.3/b")), "more than one tag")
  expect_error(e$release_tag_of("https://h/resolve/main/a"), "not a release tag")
  rk <- vapply(c("v090", "v091", "v0102", "v0110", "v0113"), e$suffix_rank, 0)
  expect_identical(order(rk), 1:5)
  expect_identical(e$suffix_rank("vXYZ"), -Inf)
})

test_that("predecessor(): the newest earlier tagged census, else the untagged file, else NA", {
  e <- .rc_env()
  d <- tempfile("res_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  for (f in c("foo_census_v090.json", "foo_census_v0110.json", "foo_census_v0102.json", "foo_census_v0113.json", "bar_census.json"))
    writeLines("{}", file.path(d, f))
  expect_identical(basename(e$predecessor("foo_census", "v0113", dir = d)), "foo_census_v0110.json")
  expect_identical(basename(e$predecessor("foo_census", "v0114", dir = d)), "foo_census_v0113.json")
  expect_identical(basename(e$predecessor("bar_census", "v0113", dir = d)), "bar_census.json")
  expect_true(is.na(e$predecessor("baz_census", "v0113", dir = d)))
})

test_that("compare_census(): provenance is ignored, a moved number is not, a new field is reported", {
  e <- .rc_env()
  d <- tempfile("cmp_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  base <- list(meta = list(n_rows_2b = 10L, shrink_wt_def = "half", timestamp = "t0", git_rev = "aaa", label = "v0110",
                           stage2b = "data\\derived\\x.rds", stage2b_sha256 = "s0"),
               q1 = list(p50 = 0.924, by = list(list(bin = "1", v = 0.364), list(bin = ">10", v = 0.030))))
  a <- file.path(d, "a.json"); .rc_write_json(base, a)
  same <- base; same$meta$timestamp <- "t1"; same$meta$git_rev <- "bbb"; same$meta$label <- "v0113"
  same$meta$stage2b <- "data/derived/x.rds"; same$meta$stage2b_sha256 <- "s1"
  b <- file.path(d, "b.json"); .rc_write_json(same, b)
  v <- e$compare_census(b, a, "same")
  expect_identical(v$verdict, "same"); expect_false(v$moved)
  moved <- same; moved$q1$by[[2]]$v <- 0.031
  m <- file.path(d, "m.json"); .rc_write_json(moved, m)
  v <- e$compare_census(m, a, "same")
  expect_true(v$moved); expect_match(v$verdict, "^MOVED: 1 value")
  expect_match(v$detail, "\\$q1\\$by\\[2\\]\\$v: 0.03 -> 0.031", fixed = FALSE)
  expect_false(e$compare_census(m, a, "reported")$moved)
  expect_match(e$compare_census(m, a, "reported")$verdict, "^changed")
  meta_moved <- same; meta_moved$meta$n_rows_2b <- 11L          # a data-derived meta field is compared
  mm <- file.path(d, "mm.json"); .rc_write_json(meta_moved, mm)
  expect_true(e$compare_census(mm, a, "same")$moved)
  added <- same; added$q2 <- list(x = 1)
  ad <- file.path(d, "ad.json"); .rc_write_json(added, ad)
  v <- e$compare_census(ad, a, "same")
  expect_false(v$moved); expect_identical(v$verdict, "same (+1 new field(s))")
  expect_identical(e$compare_census(b, NA_character_, "same")$verdict, "new (no predecessor)")
})

test_that("verify_tables() and the argument parser", {
  skip_if_not_installed("openssl")
  e <- .rc_env()
  d <- tempfile("tab_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, c("s1.rds", "s2a.rds", "s2b.rds")); for (i in 1:3) writeLines(sprintf("table %d", i), f[i])
  sha <- vapply(f, e$sha256_file, "")
  tabs <- list(stage1 = list(path = f[1], sha256 = sha[[1]]), stage2a = list(path = f[2], sha256 = sha[[2]]),
               stage2b = list(path = f[3], sha256 = sha[[3]]))
  expect_identical(e$verify_tables(tabs), character(0))
  tabs$stage2a$sha256 <- strrep("0", 64)
  expect_match(e$verify_tables(tabs), "^stage2a: .* the manifest pins 000000000000")
  tabs$stage2b$path <- file.path(d, "gone.rds")
  expect_length(e$verify_tables(tabs), 2L)
  expect_identical(e$parse_refresh_args(character(0)), list(fallback_csv = "", only = character(0), dry_run = FALSE))
  o <- e$parse_refresh_args(c("--only", "a,b", "--dry-run", "--fallback-csv", "C:\\x\\f.csv"))
  expect_identical(o$only, c("a", "b")); expect_true(o$dry_run); expect_identical(o$fallback_csv, "C:\\x\\f.csv")
  expect_error(e$parse_refresh_args("--frob"), "unknown argument")
  expect_error(e$parse_refresh_args(c("--only", "--dry-run")), "needs a value")
})

test_that("the plan covers every census the README picks, and passes only flags its scripts read", {
  e <- .rc_env()
  root <- .rc_root()
  tabs <- list(stage1 = list(path = "S1.rds"), stage2a = list(path = "S2A.rds"), stage2b = list(path = "S2B.rds"))
  plan <- e$census_plan("v0113", tabs, "F.csv")
  names_ <- vapply(plan, `[[`, "", "name")
  expect_length(plan, 6L)
  br <- paste(readLines(file.path(root, "scripts", "build_readme.R"), warn = FALSE), collapse = "\n")
  picked <- unique(regmatches(br, gregexpr("pick_census(_opt)?\\(\"[a-z0-9_]+\"", br))[[1]])
  picked <- sub("^pick_census(_opt)?\\(\"", "", sub("\"$", "", picked))
  expect_gte(length(picked), 4L)
  expect_true(all(picked %in% names_), info = paste(setdiff(picked, names_), collapse = ", "))
  for (p in plan) {
    expect_true(file.exists(file.path(root, p$script)), info = p$script)
    expect_identical(p$out, sprintf("results/%s_v0113.json", p$name))
    expect_identical(p$md, sprintf("docs/results/%s_v0113.md", p$name))
    src <- paste(readLines(file.path(root, p$script), warn = FALSE), collapse = "\n")
    flags <- unique(grep("^--", p$args, value = TRUE))
    for (fl in flags) expect_true(grepl(sprintf("get_arg(\"%s\"", fl), src, fixed = TRUE), info = paste(p$script, fl))
  }
  fb <- plan[[which(names_ == "stage2_fallback_census")]]
  expect_identical(fb$needs, "fallback_csv"); expect_true("F.csv" %in% fb$args)
  expect_identical(vapply(plan, `[[`, "", "expect")[names_ == "stage2a_handoff_census"], "reported")
  expect_true(all(vapply(plan, `[[`, "", "expect")[names_ != "stage2a_handoff_census"] == "same"))
})

test_that("a dry run in a scratch repo prints the plan, and a table that differs stops it", {
  skip_if_not_installed("openssl"); skip_if_not_installed("jsonlite")
  root <- .rc_root()
  w <- tempfile("rc_repo_"); dir.create(w); on.exit(unlink(w, recursive = TRUE), add = TRUE)
  for (d in c("scripts", "analysis", "results", file.path("data", "derived", c("stage1", "stage2a", "stage2b"))))
    dir.create(file.path(w, d), recursive = TRUE)
  file.copy(file.path(root, "scripts", "refresh_table_censuses.R"), file.path(w, "scripts"))
  paths <- c("data/derived/stage1/x_feenstra_sigma.rds", "data/derived/stage2a/x_fixed_sigma.rds", "data/derived/stage2b/x_fixed_sigma.rds")
  for (i in 1:3) writeLines(sprintf("tbl %d", i), file.path(w, paths[i]))
  sha <- vapply(file.path(w, paths), function(p) { con <- file(p, "rb"); on.exit(close(con)); tolower(as.character(openssl::sha256(con))) }, "")
  utils::write.csv(data.frame(local_path = paths, hf_url = paste0("https://h/d/resolve/v0.11.3/", basename(paths)), sha256 = sha),
                   file.path(w, "data", "manifest.csv"), row.names = FALSE)
  writeLines("{}", file.path(w, "results", "stage2_shrinkage_census_v0110.json"))
  rs <- file.path(R.home("bin"), "Rscript")
  old <- setwd(w); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rs, c(shQuote("scripts/refresh_table_censuses.R"), "--dry-run", "--fallback-csv", shQuote(file.path(w, "nope.csv"))),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); txt <- paste(out, collapse = "\n")
  expect_true(is.null(st) || st == 0L, info = txt)
  expect_match(txt, "Release v0.11.3 (census suffix v0113)", fixed = TRUE)
  expect_match(txt, "all three match the manifest's sha256", fixed = TRUE)
  expect_match(txt, "results/stage2_shrinkage_census_v0113.json", fixed = TRUE)
  expect_match(txt, "predecessor: results/stage2_shrinkage_census_v0110.json", fixed = TRUE)
  expect_match(txt, "SKIP stage2_fallback_census (--fallback-csv not found:", fixed = TRUE)
  expect_match(txt, "DRY RUN: nothing was run.", fixed = TRUE)
  expect_length(list.files(file.path(w, "results"), pattern = "_v0113\\.json$"), 0L)
  writeLines("changed", file.path(w, paths[3]))
  out2 <- suppressWarnings(system2(rs, c(shQuote("scripts/refresh_table_censuses.R"), "--dry-run"), stdout = TRUE, stderr = TRUE))
  expect_identical(attr(out2, "status"), 1L)
  expect_match(paste(out2, collapse = "\n"), "TABLES NOT READY", fixed = TRUE)
  expect_match(paste(out2, collapse = "\n"), "scripts/download_outputs.R", fixed = TRUE)
})

test_that("build_readme.R names the tool when it picks a dated census", {
  root <- .rc_root()
  src <- readLines(file.path(root, "scripts", "build_readme.R"), warn = FALSE)
  i0 <- grep("# --- Freshness helpers (patch 0109)", src, fixed = TRUE)
  i1 <- grep("# --- end freshness helpers (patch 0109)", src, fixed = TRUE)
  env <- new.env(parent = globalenv())
  mf <- tempfile(fileext = ".csv"); on.exit(unlink(mf), add = TRUE)
  utils::write.csv(data.frame(local_path = c("data/derived/stage1/x_feenstra_sigma.rds", "data/derived/stage2a/x_fixed_sigma.rds",
                                             "data/derived/stage2b/x_fixed_sigma.rds"),
                              hf_url = "u", sha256 = c("aa", "bb", "cc")), mf, row.names = FALSE)
  assign("MANIFEST_PATH", mf, envir = env)
  eval(parse(text = src[i0:i1]), envir = env)
  res <- list(foo_census_v0110 = list(meta = list(stage2b_sha256 = "old")), foo_census_v0113 = list(meta = list(stage2b_sha256 = "cc")))
  expect_message(p <- env$pick_census("foo_census", res = res[1]), "refresh_table_censuses.R")
  expect_false(p$fresh)
  expect_silent(p <- env$pick_census("foo_census", res = res))
  expect_true(p$fresh); expect_identical(p$key, "foo_census_v0113")
})
