# ============================================================================
# test-output-hygiene.R
#
# Locks for finalize_saved_output(): saved estimator outputs must hash on
# content, not on wall-clock metadata or parallel completion order. The
# lambda-sweep anchor adjudication established that byte-level RDS
# divergence between identical runs was confined entirely to the run_meta
# attribute plus row order; this helper is the fix, applied at every
# production saveRDS site (Stage 1 LIML wrapper, Stage 1 translate,
# Stage 2a regional, Stage 2b country).
# ============================================================================

test_that("finalize_saved_output strips volatile attrs and sorts canonically", {
  skip_if_not_installed("data.table")
  library(data.table)
  src_dir <- locate_source_dir()
  ug <- new.env()
  source(file.path(src_dir, "utils_general.R"), local = ug)

  mk <- function() {
    x <- data.table(
      good     = c("8504", "8501", "8504", "8501"),
      importer = c("276",  "840",  "840",  "276"),
      exporter = c("156",  "410",  "036",  "156"),
      sigma    = c(4, 3, 5, 2),
      gamma    = c(.1, .2, .3, .4))
    setattr(x, "run_meta", list(qlog = list("step"), t_elapsed = 12.3,
                                timestamp = Sys.time()))
    setattr(x, "timing",   list(a = 1))
    setattr(x, "failures", list())
    setattr(x, "keep_me",  "custom")
    x
  }

  x <- mk()
  out <- ug$finalize_saved_output(x)

  # Volatile attrs gone; unrelated custom attrs preserved.
  expect_null(attr(out, "run_meta"))
  expect_null(attr(out, "timing"))
  expect_null(attr(out, "failures"))
  expect_identical(attr(out, "keep_me"), "custom")

  # Canonical order: good, then importer, then exporter.
  expect_identical(out$good,     c("8501", "8501", "8504", "8504"))
  expect_identical(out$importer, c("276",  "840",  "276",  "840"))
  expect_identical(out$exporter, c("156",  "410",  "156",  "036"))

  # Data content identical to the input's (as key-sorted sets).
  expect_identical(out[order(sigma)]$gamma, x[order(sigma)]$gamma)
  expect_identical(sort(names(out)), sort(names(x)))
  expect_identical(nrow(out), nrow(x))

  # The INPUT is untouched: attrs intact, row order intact — summary
  # generation still sees run_meta on the live object.
  expect_identical(attr(x, "run_meta")$t_elapsed, 12.3)
  expect_identical(x$good, c("8504", "8501", "8504", "8501"))

  # Idempotent, and byte-stable across repeat calls on the same content.
  expect_identical(ug$finalize_saved_output(out), out)

  # Two objects with identical content but different attrs and row order
  # finalize to identical objects — the sha256-certifies-content claim.
  y <- mk()[c(3, 1, 4, 2)]
  setattr(y, "run_meta", list(t_elapsed = 99, timestamp = Sys.time() + 1))
  expect_identical(ug$finalize_saved_output(y), out)

  # Missing sort columns are skipped; none present means order untouched.
  z <- data.table(a = c(2, 1), b = c("x", "y"))
  setattr(z, "run_meta", list(t = 1))
  zo <- ug$finalize_saved_output(z)
  expect_null(attr(zo, "run_meta"))
  expect_identical(zo$a, c(2, 1))

  # Partial key: sorts on whatever canonical columns exist.
  w <- data.table(importer = c("840", "276"), v = c(1, 2))
  expect_identical(ug$finalize_saved_output(w)$importer, c("276", "840"))
})
