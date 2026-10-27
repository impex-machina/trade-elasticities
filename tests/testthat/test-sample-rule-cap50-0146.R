# ============================================================================
# test-sample-rule-cap50-0146.R  (patch 0146)
#
# The Stage-1 sample-rule decision was re-run at the shipped sigma cap (patch
# 0145): results/sigma_uv_trim_sensitivity_cap50_t{3,2,15}.json. Locks:
#   1. the decision doc's cap-10 column is the September record (2% subsample);
#   2. its cap-50 column, the methodology paragraph and the card are the cap-50
#      records, every one of which passed the shipped check against one
#      untrimmed baseline;
#   3. .renvignore keeps renv's dependency discovery out of the data trees.
# The strings are formatted the way the script's own markdown prints them, so
# the doc can only say what the records say.
# ============================================================================

.sr_root <- function() dirname(locate_source_dir())
.sr_read <- function(...) paste(readLines(file.path(.sr_root(), ...), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
.sr_json <- function(tag) {
  p <- file.path(.sr_root(), "results", sprintf("sigma_uv_trim_sensitivity%s.json", tag))
  if (file.exists(p)) jsonlite::fromJSON(p) else NULL
}
.f3 <- function(x) sprintf("%.3f", x)
.f2 <- function(x) sprintf("%.2f", x)
.pc <- function(x) sprintf("%.1f%%", 100 * x)

test_that("the cap-10 column is the September record", {
  skip_if_not_installed("jsonlite")
  doc <- .sr_read("docs", "methodology", "sample_rule_decision.md")
  for (tag in c("_t3", "_obs", "_t15")) {
    j <- .sr_json(tag)
    expect_false(is.null(j), info = tag)
    expect_equal(j$frac, 0.02)
    expect_equal(j$n_cells, 5613L)
    expect_true(grepl(.f3(j$sigma_median$trimmed), doc, fixed = TRUE), info = tag)
  }
  expect_true(grepl(.f3(.sr_json("_obs")$sigma_median$shipped), doc, fixed = TRUE))
})

test_that("the cap-50 column, the methodology paragraph and the card are the cap-50 records", {
  skip_if_not_installed("jsonlite")
  js <- lapply(c(t3 = "_cap50_t3", t2 = "_cap50_t2", t15 = "_cap50_t15"), .sr_json)
  skip_if(any(vapply(js, is.null, TRUE)), "the cap-50 records are not committed yet")
  doc  <- .sr_read("docs", "methodology", "sample_rule_decision.md")
  meth <- .sr_read("docs", "methodology", "stage1_liml.md")
  card <- .sr_read("docs", "hf_dataset_card.md")
  base <- js$t2$sigma_median$shipped
  rises_in_doc <- regmatches(doc, gregexpr("\\+[0-9]+%", doc))[[1]]
  for (k in names(js)) {
    j <- js[[k]]
    expect_equal(j$sigma_cap, 50)
    expect_equal(j$n_cells, 8419L)
    expect_equal(j$seed, 20260921L)
    expect_gte(j$shipped_check$sigma_match_share, 0.99)
    expect_gte(j$shipped_check$status_agree_share, 0.99)
    expect_equal(j$sigma_median$shipped, base)                       # one untrimmed baseline
    for (s in c(.f3(j$sigma_median$trimmed), .pc(j$rel_dsigma$share_gt_10pct), .pc(j$route_changed_share),
                .pc(j$sigma_se_finite_share$trimmed), .pc(j$sigma_cap_share$trimmed),
                sprintf("%s / %s", .f3(j$sigma_quartiles$trimmed[1]), .f3(j$sigma_quartiles$trimmed[3]))))
      expect_true(grepl(s, doc, fixed = TRUE), info = paste(k, s))
    expect_true(grepl(.f2(j$sigma_median$trimmed), meth, fixed = TRUE), info = k)
    rise <- round(100 * (j$sigma_median$trimmed / base - 1))         # the doc rounds from the printed medians: +-1 point
    expect_true(any(sprintf("+%d%%", rise + (-1:1)) %in% rises_in_doc), info = paste(k, rise))
  }
  expect_true(grepl(.f3(base), doc, fixed = TRUE))
  expect_true(grepl(paste(.f2(js$t3$sigma_median$trimmed), .f2(js$t2$sigma_median$trimmed), .f2(js$t15$sigma_median$trimmed),
                          sep = " / "), card, fixed = TRUE))
  expect_true(grepl(sprintf("from %s to %s", .f2(base), .f2(js$t2$sigma_median$trimmed)), card, fixed = TRUE))
  expect_true(grepl(sprintf("from %s to %s", .pc(js$t2$sigma_se_finite_share$shipped), .pc(js$t15$sigma_se_finite_share$trimmed)),
                    gsub("\\s+", " ", card), fixed = TRUE))
  expect_true(grepl("re-run at the shipped", card, fixed = TRUE))
})

test_that(".renvignore keeps renv's dependency discovery out of the data trees", {
  ri <- trimws(readLines(file.path(.sr_root(), ".renvignore"), warn = FALSE))
  for (e in c("data/", "grid/", "te_*/", "inst/legacy_verification/")) expect_true(e %in% ri, info = e)
})
