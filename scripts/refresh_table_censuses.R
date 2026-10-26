#!/usr/bin/env Rscript
# ============================================================================
# scripts/refresh_table_censuses.R  (patch 0144)
#
# Re-runs, on the shipped tables, every census whose only inputs are those
# tables (plus, for the Stage-2 restart census, the fallback table the shipped
# run wrote), and checks each against the census it supersedes. No EC2: none of
# these censuses reads the raw cache or re-estimates anything.
#
# Why. build_readme.R's pick_census() treats a census as the shipped table's
# only if it was computed on the file data/manifest.csv pins (the census's
# meta$<table>_sha256). A release that rewrites a table file without
# re-estimating -- v0.11.1 to v0.11.3 added copies and two columns, "every
# existing column is unchanged" -- changes that sha256, and the README then
# quotes every census of the earlier file as "census of the v0.11.0 table, not
# yet re-run on the shipped table" although no number the census reads moved.
#
# What it does.
#   1. Reads the manifest's release tag (v0.11.3 -> suffix v0113) and the three
#      table files it pins, and checks each local copy's sha256 against the
#      manifest (fetch a missing or different copy: scripts/download_outputs.R).
#   2. Runs each census script in its own Rscript process with the options its
#      predecessor recorded, writing results/<census>_<suffix>.json and
#      docs/results/<census>_<suffix>.md.
#   3. Compares each new JSON with the newest earlier census of the same name,
#      ignoring provenance (timestamp, git_rev, label, input paths and their
#      sha256). A census marked `same` must reproduce its predecessor exactly,
#      because no column it reads changed; the Stage-2a handoff census predates
#      the v0.11.0 re-estimation and is reported, not required to match.
#
# Usage (repo root):
#   Rscript scripts/refresh_table_censuses.R [--fallback-csv PATH] [--only a,b] [--dry-run]
#     --fallback-csv PATH  the <prefix>_stage2_fallbacks*.csv the shipped run wrote
#                          beside its checkpoint; without it the restart census is
#                          skipped and stays dated
#     --only a,b           run only these censuses (names as in census_plan())
#     --dry-run            check the tables and print the plan; run nothing
# Exit status: 0 every census ran and every `same` census reproduced its
# predecessor; 1 a table is missing or differs from the manifest, an argument is
# wrong, or a census failed; 2 a `same` census moved -- stop and report, do not
# commit its output.
# ============================================================================

suppressPackageStartupMessages(library(jsonlite))

# --- refresh helpers (patch 0144) --------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a

# the manifest's one release tag, from its resolve/<tag>/ segments (as
# manifest_release_tag() in build_readme.R, patch 0141)
release_tag_of <- function(hf_url) {
  hf_url <- as.character(hf_url)
  if (!length(hf_url) || !all(grepl("/resolve/[^/]+/", hf_url)))
    stop("manifest: an hf_url carries no resolve/<tag>/ segment", call. = FALSE)
  tags <- unique(sub("^.*/resolve/([^/]+)/.*$", "\\1", hf_url))
  if (length(tags) != 1L) stop("manifest: more than one tag: ", paste(tags, collapse = ", "), call. = FALSE)
  if (!grepl("^v[0-9]+\\.[0-9]+\\.[0-9]+$", tags)) stop("manifest: '", tags, "' is not a release tag (vX.Y.Z)", call. = FALSE)
  tags
}

# v0.11.3 -> v0113, v0.9.1 -> v091: the suffix build_readme.R's pick_census()
# reads back (results/<prefix>_v<3 or 4 digits>.json)
suffix_of_tag <- function(tag) {
  d <- gsub(".", "", sub("^v", "", tag), fixed = TRUE)
  if (!nchar(d) %in% 3:4) stop("release ", tag, " gives a ", nchar(d), "-digit suffix; pick_census() reads 3 or 4", call. = FALSE)
  paste0("v", d)
}
release_of_suffix <- function(s) {          # as build_readme.R: "v090" -> "v0.9.0", "v0101" -> "v0.10.1"
  d <- sub("^v", "", s)
  if (nchar(d) == 3L) return(sprintf("v%s.%s.%s", substr(d, 1, 1), substr(d, 2, 2), substr(d, 3, 3)))
  if (nchar(d) == 4L) return(sprintf("v%s.%s.%s", substr(d, 1, 1), substr(d, 2, 3), substr(d, 4, 4)))
  s
}
suffix_rank <- function(s) {
  r <- release_of_suffix(s)
  if (!grepl("^v[0-9]+\\.[0-9]+\\.[0-9]+$", r)) return(-Inf)
  sum(as.numeric(strsplit(sub("^v", "", r), ".", fixed = TRUE)[[1]]) * c(1e6, 1e3, 1))
}

# the three table files the manifest pins (the same patterns as shipped_sha256()
# in build_readme.R)
shipped_tables <- function(manifest) {
  pats <- c(stage1  = "^data/derived/stage1/.*_feenstra_sigma\\.rds$",
            stage2a = "^data/derived/stage2a/.*_fixed_sigma\\.rds$",
            stage2b = "^data/derived/stage2b/.*_fixed_sigma\\.rds$")
  out <- lapply(names(pats), function(k) {
    i <- grep(pats[[k]], manifest$local_path)
    if (length(i) != 1L) stop(sprintf("manifest: expected one %s table, found %d", k, length(i)), call. = FALSE)
    list(path = manifest$local_path[i], sha256 = tolower(manifest$sha256[i]), url = manifest$hf_url[i])
  })
  stats::setNames(out, names(pats))
}

sha256_file <- function(p) {
  if (!requireNamespace("openssl", quietly = TRUE)) stop("the openssl package is needed to check sha256", call. = FALSE)
  con <- file(p, "rb"); on.exit(close(con), add = TRUE)
  tolower(unclass(as.character(openssl::sha256(con))))
}

# problems, one line each; character(0) when every table is present and pinned
verify_tables <- function(tabs) {
  bad <- character(0)
  for (k in names(tabs)) {
    p <- tabs[[k]]$path
    if (!file.exists(p)) { bad <- c(bad, sprintf("%s: %s is missing", k, p)); next }
    h <- sha256_file(p)
    if (!identical(h, tabs[[k]]$sha256))
      bad <- c(bad, sprintf("%s: %s has sha256 %s..., the manifest pins %s...", k, p, substr(h, 1, 12), substr(tabs[[k]]$sha256, 1, 12)))
  }
  bad
}

# the newest earlier release-tagged census of a name, else its untagged file
predecessor <- function(name, sfx, dir = "results") {
  fs <- list.files(dir, pattern = sprintf("^%s_v[0-9]{3,4}\\.json$", name))
  fs <- fs[fs != sprintf("%s_%s.json", name, sfx)]
  if (length(fs)) {
    rk <- vapply(sub(sprintf("^%s_(v[0-9]+)\\.json$", name), "\\1", fs), suffix_rank, 0)
    return(file.path(dir, fs[which.max(rk)]))
  }
  legacy <- file.path(dir, paste0(name, ".json"))
  if (file.exists(legacy)) legacy else NA_character_
}

# provenance, not results: dropped before two censuses are compared
VOLATILE_META <- c("timestamp", "git_rev", "label", "csv", "stage1", "stage2a", "stage2b",
                   "stage1_sha256", "stage2a_sha256", "stage2b_sha256")
strip_volatile <- function(j) {
  if (is.list(j$meta)) {
    j$meta[intersect(names(j$meta), VOLATILE_META)] <- NULL
    if (!length(j$meta)) j$meta <- NULL
  }
  j
}

.fmt_leaf <- function(x) {
  if (is.null(x)) return("null")
  s <- paste(format(unlist(x), digits = 10), collapse = ",")
  if (nchar(s) > 40) paste0(substr(s, 1, 37), "...") else s
}
# the differences between two parsed JSON values, one line per path ("$q1$shrink_wt$p50: a -> b");
# a field present only in b is reported as "<path>: added"
json_diff <- function(a, b, path = "") {
  if (is.list(a) && is.list(b)) {
    na <- names(a); nb <- names(b)
    if (is.null(na) && is.null(nb)) {
      if (length(a) != length(b)) return(sprintf("%s: length %d -> %d", path, length(a), length(b)))
      return(unlist(lapply(seq_along(a), function(i) json_diff(a[[i]], b[[i]], sprintf("%s[%d]", path, i)))))
    }
    na <- na %||% character(0); nb <- nb %||% character(0)
    c(if (length(setdiff(na, nb))) sprintf("%s$%s: removed", path, setdiff(na, nb)),
      if (length(setdiff(nb, na))) sprintf("%s$%s: added", path, setdiff(nb, na)),
      unlist(lapply(intersect(na, nb), function(k) json_diff(a[[k]], b[[k]], paste0(path, "$", k)))))
  } else if (is.list(a) || is.list(b)) {
    sprintf("%s: type changed", path)
  } else {
    same <- if (is.numeric(a) && is.numeric(b)) identical(as.numeric(a), as.numeric(b)) else identical(a, b)
    if (same) character(0) else sprintf("%s: %s -> %s", path, .fmt_leaf(a), .fmt_leaf(b))
  }
}

compare_census <- function(new_path, prev_path, expect) {
  if (is.na(prev_path)) return(list(verdict = "new (no predecessor)", detail = character(0), moved = FALSE))
  a <- strip_volatile(jsonlite::fromJSON(prev_path, simplifyVector = FALSE))
  b <- strip_volatile(jsonlite::fromJSON(new_path, simplifyVector = FALSE))
  d <- json_diff(a, b)
  added <- d[grepl(": added$", d)]; changed <- setdiff(d, added)
  if (!length(changed))
    return(list(verdict = if (length(added)) sprintf("same (+%d new field(s))", length(added)) else "same",
                detail = added, moved = FALSE))
  list(verdict = sprintf("%s: %d value(s) differ", if (identical(expect, "same")) "MOVED" else "changed", length(changed)),
       detail = changed, moved = identical(expect, "same"))
}

# every census to refresh, with the options its v0.11.0 predecessor recorded
census_plan <- function(sfx, tabs, fallback_csv = "") {
  t <- lapply(tabs, `[[`, "path")
  P <- function(name, script, args, expect, needs = "") list(name = name, script = script, args = args, expect = expect, needs = needs)
  plan <- list(
    P("stage2_shrinkage_census", "analysis/stage2_shrinkage_census.R",
      c("--stage2b", t$stage2b, "--stage2a", t$stage2a, "--shrink-wt-def", "half"), "same"),
    P("stage2b_convergence_census", "analysis/stage2b_convergence_census.R",
      c("--stage2b", t$stage2b, "--label", sfx), "same"),
    P("sigma_fallback_hierarchy_census", "analysis/sigma_fallback_hierarchy_census.R",
      c("--stage1", t$stage1, "--stage2b", t$stage2b, "--min-cells", "3", "--label", sfx), "same"),
    P("pole_na_se_census", "analysis/pole_na_se_census.R",
      c("--stage1", t$stage1, "--stage2b", t$stage2b, "--pole-se", "1", "--label", sfx), "same"),
    P("stage2_fallback_census", "analysis/stage2_fallback_census.R",
      c("--csv", fallback_csv, "--stage2b", t$stage2b, "--label", "universe"), "same", needs = "fallback_csv"),
    P("stage2a_handoff_census", "analysis/handoff_rows_census.R",
      c("--stage2a", t$stage2a), "reported"))
  lapply(plan, function(p) {
    p$out <- sprintf("results/%s_%s.json", p$name, sfx)
    p$md  <- sprintf("docs/results/%s_%s.md", p$name, sfx)
    p$args <- c(p$args, "--out", p$out, "--md", p$md)
    p
  })
}

parse_refresh_args <- function(args) {
  opt <- list(fallback_csv = "", only = character(0), dry_run = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[i]
    if (identical(a, "--dry-run")) { opt$dry_run <- TRUE; i <- i + 1L; next }
    if (a %in% c("--fallback-csv", "--only")) {
      if (i == length(args) || startsWith(args[i + 1L], "--")) stop(a, " needs a value", call. = FALSE)
      v <- args[i + 1L]
      if (identical(a, "--fallback-csv")) opt$fallback_csv <- v else opt$only <- strsplit(v, ",", fixed = TRUE)[[1]]
      i <- i + 2L; next
    }
    stop("unknown argument: ", a, call. = FALSE)
  }
  opt
}
# --- end refresh helpers (patch 0144) ----------------------------------------

run_census <- function(p) {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rscript, c(shQuote(p$script), shQuote(p$args)), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(status = if (is.null(st)) 0L else as.integer(st), log = out)
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (!file.exists("data/manifest.csv") || !dir.exists("analysis"))
    stop("run from the repository root (data/manifest.csv and analysis/ not found)", call. = FALSE)
  opt <- parse_refresh_args(args)
  man <- utils::read.csv("data/manifest.csv", stringsAsFactors = FALSE)
  tag <- release_tag_of(man$hf_url); sfx <- suffix_of_tag(tag)
  tabs <- shipped_tables(man)
  cat(sprintf("Release %s (census suffix %s). Tables:\n", tag, sfx))
  for (k in names(tabs)) cat(sprintf("  %-8s %s\n", k, tabs[[k]]$path))
  bad <- verify_tables(tabs)
  if (length(bad)) {
    cat("TABLES NOT READY:\n", paste0("  ", bad, "\n"), sep = "")
    cat("Fetch the shipped files with: Rscript scripts/download_outputs.R   (add --force to replace a copy that differs)\n")
    quit(status = 1L)
  }
  cat("  all three match the manifest's sha256\n\n")
  plan <- census_plan(sfx, tabs, opt$fallback_csv)
  if (length(opt$only)) {
    unknown <- setdiff(opt$only, vapply(plan, `[[`, "", "name"))
    if (length(unknown)) stop("--only: unknown census name(s): ", paste(unknown, collapse = ", "), call. = FALSE)
    plan <- Filter(function(p) p$name %in% opt$only, plan)
  }
  dir.create("results", showWarnings = FALSE); dir.create(file.path("docs", "results"), showWarnings = FALSE, recursive = TRUE)
  rows <- list(); failed <- FALSE; moved <- FALSE
  for (p in plan) {
    prev <- predecessor(p$name, sfx)
    if (identical(p$needs, "fallback_csv") && (!nzchar(opt$fallback_csv) || !file.exists(opt$fallback_csv))) {
      why <- if (nzchar(opt$fallback_csv)) paste("not found:", opt$fallback_csv) else "not given"
      cat(sprintf("SKIP %s (--fallback-csv %s); it stays dated\n\n", p$name, why))
      rows[[length(rows) + 1L]] <- c(p$name, "skipped", "-", "stays dated"); next
    }
    cat(sprintf("%s %s\n  Rscript %s %s\n  predecessor: %s\n", if (opt$dry_run) "PLAN" else "RUN ", p$name, p$script,
                paste(shQuote(p$args), collapse = " "), prev %||% "(none)"))
    if (opt$dry_run) { cat("\n"); next }
    unlink(c(p$out, p$md))
    t0 <- Sys.time(); r <- run_census(p)
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
    if (r$status != 0L || !file.exists(p$out)) {
      failed <- TRUE
      cat(sprintf("  FAILED (exit %d, %d s); last lines:\n", r$status, secs), paste0("    ", utils::tail(r$log, 12), "\n"), "\n", sep = "")
      rows[[length(rows) + 1L]] <- c(p$name, "FAILED", basename(prev %||% "-"), "-"); next
    }
    v <- compare_census(p$out, prev, p$expect)
    moved <- moved || v$moved
    cat(sprintf("  ok (%d s) -> %s; against %s: %s\n", secs, p$out, basename(prev %||% "-"), v$verdict))
    if (length(v$detail)) cat(paste0("    ", utils::head(v$detail, 15), "\n"), sep = "")
    if (length(v$detail) > 15L) cat(sprintf("    ... %d more\n", length(v$detail) - 15L))
    cat("\n")
    rows[[length(rows) + 1L]] <- c(p$name, "ran", basename(prev %||% "-"), v$verdict)
  }
  if (opt$dry_run) { cat("DRY RUN: nothing was run.\n"); quit(status = 0L) }
  cat("SUMMARY\n")
  for (x in rows) cat(sprintf("  %-32s %-8s vs %-42s %s\n", x[1], x[2], x[3], x[4]))
  if (failed) { cat("\nA census FAILED: do not commit; report the lines above.\n"); quit(status = 1L) }
  if (moved)  { cat("\nA census that should reproduce its predecessor MOVED: do not commit; report the lines above.\n"); quit(status = 2L) }
  cat("\nREFRESH OK: regenerate the README (Rscript scripts/build_readme.R) and commit results/, docs/results/ and the two generated files.\n")
  quit(status = 0L)
}

main()
