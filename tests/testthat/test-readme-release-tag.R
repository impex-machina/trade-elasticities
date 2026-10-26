# ============================================================================
# test-readme-release-tag.R  (patch 0141, fresh-eyes audit #9)
#
# The README's Parquet example quotes the hub tag of the release the manifest
# pins (hf://datasets/.../trade-elasticities@<tag>/...). Through patch 0140 the
# template carried a typed `@v0.11.2`, which v0.11.3 (patch 0139) left behind:
# the example loaded the v0.11.2 Parquet, without the `total_trade` and
# `opt_tariff_total` columns the table above it documents. The tag is now
# derived from data/manifest.csv (manifest_release_tag() in
# scripts/build_readme.R) and rendered through {{release_tag}}. Three guards:
# the helper itself, the template (no typed tag), and the committed README
# against the committed manifest (a lock on the artifact a reader sees).
# ============================================================================

.rt_root <- function() dirname(locate_source_dir())

.rt_env <- function() {
  src <- readLines(file.path(.rt_root(), "scripts", "build_readme.R"), warn = FALSE)
  i0 <- grep("# --- Release tag (patch 0141", src, fixed = TRUE)
  i1 <- grep("# --- end release tag (patch 0141)", src, fixed = TRUE)
  expect_length(i0, 1L); expect_length(i1, 1L)
  env <- new.env(parent = globalenv())
  # the block ends by reading MANIFEST$hf_url; give it a two-row manifest
  assign("MANIFEST", data.frame(hf_url = c("https://h/x/resolve/v0.11.3/a.rds", "https://h/x/resolve/v0.11.3/b.parquet"),
                                stringsAsFactors = FALSE), envir = env)
  eval(parse(text = src[i0:i1]), envir = env)
  env
}

test_that("manifest_release_tag(): one vX.Y.Z tag from the resolve/<tag>/ segment, loud on anything else", {
  e <- .rt_env()
  expect_identical(e$release_tag, "v0.11.3")
  expect_identical(e$manifest_release_tag("https://huggingface.co/datasets/o/r/resolve/v0.9.0/stage1/f.rds"), "v0.9.0")
  expect_identical(e$manifest_release_tag(c("https://h/resolve/v1.0.0/a", "https://h/resolve/v1.0.0/b/c.csv")), "v1.0.0")
  expect_error(e$manifest_release_tag(c("https://h/resolve/v0.11.2/a", "https://h/resolve/v0.11.3/b")), "more than one tag")
  expect_error(e$manifest_release_tag("https://h/resolve/main/a"), "not a release tag")
  expect_error(e$manifest_release_tag("https://h/resolve/049aeb07a5f5fdeed289462743103f7c2b82facc/a"), "not a release tag")
  expect_error(e$manifest_release_tag(c("https://h/resolve/v0.11.3/a", "https://h/blob/v0.11.3/b")), "no resolve")
})

test_that("the template carries no typed hub tag; the committed README quotes the manifest's", {
  root <- .rt_root()
  tpl <- readLines(file.path(root, "README.template.md"), warn = FALSE)
  hf_tpl <- grep("trade-elasticities@", tpl, value = TRUE)
  expect_gte(length(hf_tpl), 2L)                       # the Python example and the DuckDB line
  expect_false(any(grepl("trade-elasticities@v[0-9]", hf_tpl)))
  expect_true(all(grepl("trade-elasticities@{{release_tag}}", hf_tpl, fixed = TRUE)))

  man <- utils::read.csv(file.path(root, "data", "manifest.csv"), stringsAsFactors = FALSE)
  tag <- unique(sub("^.*/resolve/([^/]+)/.*$", "\\1", man$hf_url))
  expect_length(tag, 1L)
  readme <- readLines(file.path(root, "README.md"), warn = FALSE)
  hf_md <- grep("trade-elasticities@", readme, value = TRUE)
  expect_length(hf_md, length(hf_tpl))
  tags_md <- unique(regmatches(hf_md, regexpr("(?<=trade-elasticities@)v[0-9]+\\.[0-9]+\\.[0-9]+", hf_md, perl = TRUE)))
  expect_identical(tags_md, tag)
})

test_that("the weight columns' README row states the differenced-panel basis", {
  readme <- readLines(file.path(.rt_root(), "README.md"), warn = FALSE)
  row <- grep("^\\| `avg_trade`, `total_trade` \\|", readme, value = TRUE)
  expect_length(row, 1L)
  expect_true(grepl("differenced", row))
  expect_true(grepl("29 values, not 30", row, fixed = TRUE))
  expect_true(grepl("not the pair's total trade over the period", row, fixed = TRUE))
})
