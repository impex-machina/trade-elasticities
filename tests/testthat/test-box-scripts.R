# ============================================================================
# test-box-scripts.R  (patch 0114)
#
# scripts/box/setup.sh and preflight.sh check the Stage-1 table against
# data/manifest.csv. Through patch 0113 both read the sha with
# awk -F'","' '{print $3}', which never matched the manifest (its size column
# is unquoted, so field 3 ran to the end of the row); the first box session to
# use them (v0.11.0) failed setup.sh's check and needed an in-place fix. Both
# now take the row's one 64-hex string; every manifest row must carry exactly
# one, equal to its sha256 column.
# ============================================================================

test_that("box scripts read the manifest sha with a pattern that matches its format", {
  root <- dirname(locate_source_dir())
  for (f in c("setup.sh", "preflight.sh")) {
    src <- readLines(file.path(root, "scripts", "box", f), warn = FALSE)
    expect_false(any(grepl("awk -F'\",\"'", src, fixed = TRUE)), info = f)
    expect_true(any(grepl("grep -o '[0-9a-f]\\{64\\}'", src, fixed = TRUE)), info = f)
  }
  man <- readLines(file.path(root, "data", "manifest.csv"), warn = FALSE)[-1]
  hits <- regmatches(man, gregexpr("[0-9a-f]{64}", man))
  expect_true(all(lengths(hits) == 1L))
  m <- utils::read.csv(file.path(root, "data", "manifest.csv"), stringsAsFactors = FALSE)
  expect_identical(unlist(hits), tolower(m$sha256))
})
