# ============================================================================
# test-release-v0120-0158.R  (patch 0158, release v0.12.0)
#
# v0.12.0 ships the Stage-2b sigma update (patches 0152-0155): the card's top
# entry is v0.12.0 with the release's numbers and v0.11.4 pinned; the manifest
# publishes the update's pass log beside the table and pins one tag; the
# README template documents the three new columns and the new labels.
# ============================================================================

.rv120_root <- function() dirname(locate_source_dir())

test_that("the card's top entry is v0.12.0, with the release numbers, and v0.11.4 pinned", {
  card <- readLines(file.path(.rv120_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  heads <- grep("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+ \\(", card, value = TRUE)
  expect_match(heads[1], "^> \\*\\*v0\\.12\\.0 \\(2026-11-0[89]\\)\\.\\*\\*")
  i0 <- grep("^> \\*\\*v0\\.12\\.0 ", card); i1 <- grep("^> \\*\\*v0\\.11\\.4 ", card)
  entry <- paste(sub("^> ?", "", card[i0:(i1 - 1L)]), collapse = " ")
  for (s in c("6,801,742", "6,829,595", "2.473", "2.664", "0.804", "0.822", "0.852", "0.898", "B = 0.146", "b_full = 0.255",
              "211,313", "199,857", "11,395", "updated_import_shrunk", "updated_level", "`sigma_update`", "`sigma_stage1`",
              "`sigma_source_stage1`", "_sigma_update_passes.csv", "1,775", "646", "28"))
    expect_true(grepl(s, entry, fixed = TRUE), info = s)
  expect_match(entry, "Data revision: `(<fill>|[0-9a-f]{40})`. \\*\\*v0\\.11\\.4 remains available pinned at revision `3397d5e60f1ea8a9c62b0e2268581945bc9a042b`\\.\\*\\*")
})

test_that("the manifest publishes the update's pass log beside the Stage-2b table and pins one tag", {
  man <- utils::read.csv(file.path(.rv120_root(), "data", "manifest.csv"), stringsAsFactors = FALSE)
  expect_true("data/derived/stage2b/baci_hs92_v202601_elast_country_hs4_sigma_update_passes.csv" %in% man$local_path)
  tags <- unique(sub("^.*/resolve/([^/]+)/.*$", "\\1", man$hf_url))
  expect_length(tags, 1L); expect_match(tags, "^v[0-9]+\\.[0-9]+\\.[0-9]+$")
})

test_that("the README template documents the update's columns and labels", {
  tpl <- paste(readLines(file.path(.rv120_root(), "README.template.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  for (s in c("| `sigma_update` |", "| `sigma_stage1` |", "| `sigma_source_stage1` |", "`updated_import_shrunk`", "`updated_level`",
              "su_num(r$stage2b, \"shrink_b_full\")", "docs/results/sigma_update_window_census.md"))
    expect_true(grepl(s, tpl, fixed = TRUE), info = s)
})
