# ============================================================================
# tests/testthat.R
#
# Standard testthat entry point. Run from project root with:
#   Rscript -e "testthat::test_dir('tests/testthat')"
# or, after the refactor to package structure:
#   devtools::test()
# ============================================================================

library(testthat)

# When sourced directly (not via R CMD check), point test_dir at testthat/
if (sys.nframe() == 0L) {
  test_dir(file.path(dirname(sys.frame(1)$ofile %||% "."), "testthat"))
}
