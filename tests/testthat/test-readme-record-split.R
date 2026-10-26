# ============================================================================
# test-readme-record-split.R  (patch 0143, fresh-eyes audit #9)
#
# The README's Known limitations are the short form; the long form -- the same
# bullets with every measurement and release note, as README.md carried them
# through patch 0142 -- is docs/known_limitations_record.md, rendered by
# scripts/build_readme.R from docs/known_limitations_record.template.md with
# the same environment and under the same lock (hook + CI compare both). Locks:
#   1. both generated files match a fresh build (the lock, in-suite);
#   2. the record carries the eleven numbered sections and the clause-generated
#      bullets, and nothing rendered contains a leftover placeholder;
#   3. the README's section is short, links to the record, and keeps the
#      current headline numbers;
#   4. the hook, the CI step and the e2e smoke test know the second output.
# ============================================================================

.rs_root <- function() dirname(locate_source_dir())

.rs_build <- function(root) {
  out <- tempfile(fileext = ".md"); rec <- tempfile(fileext = ".md")
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  prev <- Sys.getenv(c("README_BUILD_OUTPUT", "README_RECORD_BUILD_OUTPUT"), unset = NA)
  Sys.setenv(README_BUILD_OUTPUT = out, README_RECORD_BUILD_OUTPUT = rec)
  on.exit({ for (i in 1:2) if (is.na(prev[i])) Sys.unsetenv(names(prev)[i]) else do.call(Sys.setenv, as.list(prev[i])) }, add = TRUE)
  rs <- file.path(R.home("bin"), "Rscript")
  st <- system2(rs, "scripts/build_readme.R", stdout = TRUE, stderr = TRUE)
  list(status = attr(st, "status") %||% 0L, out = out, rec = rec, log = st)
}

.rs_norm <- function(path) paste(gsub("\r$", "", readLines(path, warn = FALSE, encoding = "UTF-8")), collapse = "\n")

test_that("README.md and docs/known_limitations_record.md both match a fresh build", {
  skip_if_not_installed("glue"); skip_if_not_installed("jsonlite")
  root <- .rs_root()
  b <- .rs_build(root)
  expect_equal(b$status, 0L, info = paste(utils::tail(b$log, 10), collapse = "\n"))
  expect_identical(.rs_norm(b$out), .rs_norm(file.path(root, "README.md")))
  expect_identical(.rs_norm(b$rec), .rs_norm(file.path(root, "docs", "known_limitations_record.md")))
})

test_that("the record is complete and placeholder-free", {
  root <- .rs_root()
  rec <- readLines(file.path(root, "docs", "known_limitations_record.md"), warn = FALSE, encoding = "UTF-8")
  expect_false(any(grepl("{{", rec, fixed = TRUE)))
  expect_true(any(grepl("^# Known limitations", rec)))
  expect_true(any(grepl("GENERATED FILE", rec, fixed = TRUE)))
  secs <- grep("^- \\*\\*\u00a7[0-9]+\\. ", rec, value = TRUE)
  expect_length(secs, 11L)
  expect_identical(as.integer(sub("^- \\*\\*\u00a7([0-9]+)\\. .*$", "\\1", secs)), 1:11)
  # the clause-generated bullets the README cites by name
  expect_true(any(grepl("^- \\*\\*What the published \u03b3 and `opt_tariff` track at known truth", rec)))
  expect_true(any(grepl("^- \\*\\*Stage 1's Step-2 route overstates", rec)))
  expect_true(any(grepl("^- \\*\\*A ridge that does not scale with price volatility", rec)))
  # signature long-form sentences the README no longer carries
  txt <- paste(rec, collapse = "\n")
  expect_true(grepl("The Broda\u2013Weinstein row weights are not fn. 14 as printed", txt, fixed = TRUE))
  expect_true(grepl("Stated forthrightly:", txt, fixed = TRUE))
  expect_true(grepl("docs/hf_dataset_card.md", txt, fixed = TRUE))
})

test_that("the README's Known limitations are the short form and point to the record", {
  root <- .rs_root()
  readme <- readLines(file.path(root, "README.md"), warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^## Known limitations", readme); i1 <- grep("^## License", readme)
  expect_length(i0, 1L); expect_length(i1, 1L); expect_lt(i0, i1)
  sec <- readme[i0:(i1 - 1L)]
  words <- sum(lengths(strsplit(sec[nzchar(sec)], "\\s+")))
  expect_lt(words, 1400L)                                  # the long form ran to ~2,900 words through patch 0142
  txt <- paste(sec, collapse = "\n")
  expect_true(grepl("[`docs/known_limitations_record.md`](docs/known_limitations_record.md)", txt, fixed = TRUE))
  expect_true(grepl("Read the product-level table and the structural ratios as the result", txt, fixed = TRUE))
  for (phrase in c("of Stage-2b rows carry it (`sigma_source`)", "`sigma_robust` is `TRUE` on", "(record \u00a7"))
    expect_true(grepl(phrase, txt, fixed = TRUE), info = phrase)
  expect_false(grepl("{{", txt, fixed = TRUE))
  bullets <- grep("^- \\*\\*", sec, value = TRUE)
  expect_length(bullets, 8L)
})

test_that("the hook, the CI step and the e2e smoke test build the record too", {
  root <- .rs_root()
  hook <- paste(readLines(file.path(root, "scripts", "hooks", "pre-commit"), warn = FALSE), collapse = "\n")
  ci   <- paste(readLines(file.path(root, ".github", "workflows", "test.yml"), warn = FALSE), collapse = "\n")
  e2e  <- paste(readLines(file.path(root, "tests", "testthat", "test-runner-e2e-smoke.R"), warn = FALSE), collapse = "\n")
  for (txt in list(hook, ci, e2e)) expect_true(grepl("README_RECORD_BUILD_OUTPUT", txt, fixed = TRUE))
  expect_true(grepl("docs/known_limitations_record.md", ci, fixed = TRUE))
  tpl <- paste(readLines(file.path(root, "scripts", "build_readme.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl("RECORD_TEMPLATE_PATH <- \"docs/known_limitations_record.template.md\"", tpl, fixed = TRUE))
})
