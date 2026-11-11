# ============================================================================
# test-release-v0120-0158.R  (patch 0158, release v0.12.0)
#
# v0.12.0 ships the Stage-2b sigma update (patches 0152-0155): the card carries
# the v0.12.0 entry with the release's numbers, its data revision and v0.11.4
# pinned (the top entry until v0.12.1, patch 0164); the manifest
# publishes the update's pass log beside the table and pins one tag; the
# README template documents the three new columns and the new labels.
# ============================================================================

.rv120_root <- function() dirname(locate_source_dir())

# (patch 0164) v0.12.1 is the card's top entry since that release, so v0.12.0's
# entry is found by its head rather than required on top; and its data revision
# is now required filled -- patch 0162's card file had reverted it to <fill>,
# and this test allowed that.
test_that("the card carries the v0.12.0 entry, with the release numbers, its data revision and v0.11.4 pinned", {
  card <- readLines(file.path(.rv120_root(), "docs", "hf_dataset_card.md"), warn = FALSE, encoding = "UTF-8")
  heads <- grep("^> \\*\\*v[0-9]+\\.[0-9]+\\.[0-9]+ \\(", card, value = TRUE)
  expect_true(any(grepl("^> \\*\\*v0\\.12\\.0 \\(2026-11-0[89]\\)\\.\\*\\*", heads)))
  i0 <- grep("^> \\*\\*v0\\.12\\.0 ", card); i1 <- grep("^> \\*\\*v0\\.11\\.4 ", card)
  entry <- paste(sub("^> ?", "", card[i0:(i1 - 1L)]), collapse = " ")
  for (s in c("6,801,742", "6,829,595", "2.473", "2.664", "0.804", "0.822", "0.852", "0.898", "B = 0.146", "b_full = 0.255",
              "211,313", "199,857", "11,395", "updated_import_shrunk", "updated_level", "`sigma_update`", "`sigma_stage1`",
              "`sigma_source_stage1`", "_sigma_update_passes.csv", "1,775", "646", "28"))
    expect_true(grepl(s, entry, fixed = TRUE), info = s)
  expect_match(entry, "Data revision: `73cf5702564820d35260a87974aed2ceed9c4f45`. \\*\\*v0\\.11\\.4 remains available pinned at revision `3397d5e60f1ea8a9c62b0e2268581945bc9a042b`\\.\\*\\*")
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
