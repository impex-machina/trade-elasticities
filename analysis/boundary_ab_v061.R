#!/usr/bin/env Rscript
# Boundary A/B: shipped v0.6.0 vs v0.6.1 (patch 0038 fixed boundary search).
# Read-only comparison; writes a markdown report to out_ab/.
#
# Run from the repo root:
#   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" analysis\boundary_ab_v061.R
#
# Expects the two generations side by side:
#   data\derived_v060\  = shipped v0.6.0   (preserved before the v0.6.1 pull)
#   data\derived\       = fresh   v0.6.1
suppressPackageStartupMessages({library(data.table)})

# The two generations may use different on-disk layouts (v0.6.0 nested in
# stage1/stage2a/stage2b canonical subfolders; a fresh S3 pull often flat),
# so locate each file by name under its generation root rather than assuming
# a fixed path. Country-level files only (the A/B is country-scoped).
find_one <- function(root, pattern) {
  if (!dir.exists(root)) stop("no such folder: ", root)
  hits <- list.files(root, pattern = pattern, recursive = TRUE, full.names = TRUE)
  hits <- hits[!grepl("regional", hits)]          # country, not regional
  if (length(hits) == 0L) stop("not found under ", root, ": ", pattern)
  if (length(hits) > 1L)
    stop("ambiguous under ", root, " (", length(hits), " matches): ",
         paste(basename(hits), collapse = ", "))
  normalizePath(hits, winslash = "/")
}
root060 <- "data/derived_v060"
root061 <- "data/derived"
v060_s1 <- find_one(root060, "_country_hs4_feenstra_sigma\\.rds$")
v061_s1 <- find_one(root061, "_country_hs4_feenstra_sigma\\.rds$")
v060_2b <- find_one(root060, "_country_hs4_fixed_sigma\\.rds$")
v061_2b <- find_one(root061, "_country_hs4_fixed_sigma\\.rds$")
cat("resolved paths:\n",
    " v0.6.0 S1:", v060_s1, "\n", " v0.6.1 S1:", v061_s1, "\n",
    " v0.6.0 2b:", v060_2b, "\n", " v0.6.1 2b:", v061_2b, "\n\n")

dir.create("out_ab", showWarnings = FALSE)
con <- file("out_ab/boundary_ab_v061.md", open = "wt")
say <- function(...) { cat(..., "\n"); cat(..., "\n", file = con) }
tbl <- function(x) { print(x); writeLines(capture.output(print(x)), con) }

s0 <- setDT(readRDS(v060_s1)); s1 <- setDT(readRDS(v061_s1))

# --- schema probe: find the cell-key, final_source, edge, sigma columns ----
say("## Stage 1 schema")
say("v0.6.0 cols:", paste(names(s0), collapse = ", "))
say("v0.6.1 cols:", paste(names(s1), collapse = ", "))

key_cands <- list(c("importer","good"), c("importer","product"),
                  c("imp","good"), c("i","good"))
key <- Find(function(k) all(k %in% names(s0)) && all(k %in% names(s1)), key_cands)
if (is.null(key)) stop("no shared cell key found; inspect the cols above")
say("cell key:", paste(key, collapse = " x "))

src_col  <- intersect(c("final_source","source","route"), names(s0))[1]
edge_col <- intersect(c("hliml_boundary_edge","boundary_edge","edge"), names(s0))[1]
sig_col  <- intersect(c("sigma","sigma_hat"), names(s0))[1]
st_col   <- intersect(c("status"), names(s0))[1]
say("using: source=", src_col, " edge=", edge_col, " sigma=", sig_col,
    " status=", st_col)
if (is.na(src_col) || is.na(sig_col) || is.na(st_col))
  stop("could not resolve source/sigma/status columns; inspect the cols above")

# Prefer the explicit edge column; fall back to adjust-code mapping if absent.
edge_of <- function(dt) {
  if (!is.na(edge_col) && edge_col %in% names(dt)) return(dt[[edge_col]])
  if ("adjust" %in% names(dt))
    return(c(`6`="omega_floor",`7`="sigma_cap",`8`="omega_cap")[as.character(dt$adjust)])
  rep(NA_character_, nrow(dt))
}
s0[, `:=`(.src = get(src_col), .edge = edge_of(s0), .sig = get(sig_col))]
s1[, `:=`(.src = get(src_col), .edge = edge_of(s1), .sig = get(sig_col))]

b0 <- s0[.src == "hliml_boundary"]
b1 <- s1[.src == "hliml_boundary"]
say("\n## Boundary set sizes")
say("v0.6.0 boundary:", nrow(b0), " | v0.6.1 boundary:", nrow(b1))

m <- merge(s0[, c(key, ".src", ".edge", ".sig"), with = FALSE],
           s1[, c(key, ".src", ".edge", ".sig"), with = FALSE],
           by = key, suffixes = c("0","1"), all = TRUE)

# --- 1. edge-flip matrix (v0.6.0 boundary edge x v0.6.1 outcome) -----------
say("\n## 1. Edge-flip matrix: v0.6.0 boundary edge (rows) x v0.6.1 outcome")
m[, out1 := fifelse(is.na(.src1), "dropped_from_output",
              fifelse(.src1 == "hliml_boundary", paste0("boundary:", .edge1), .src1))]
flip <- m[.src0 == "hliml_boundary", .N, keyby = .(v060_edge = .edge0, v061 = out1)]
tbl(dcast(flip, v060_edge ~ v061, value.var = "N", fill = 0))

# --- 2. fate of the sigma-pole cells (v0.6.0 boundary, sigma <= 1.001) -----
say("\n## 2. Fate of the 3,286 v0.6.0 sigma-pole cells")
pole <- m[.src0 == "hliml_boundary" & .sig0 <= 1.001]
say("pole cells identified in v0.6.0:", nrow(pole))
tbl(pole[, .N, keyby = out1][order(-N)])
say("of those now boundary, sigma summary:")
if (nrow(pole[out1 %like% "boundary"]))
  tbl(pole[out1 %like% "boundary", as.list(round(summary(.sig1), 4))])

# --- 3. routed-set churn ---------------------------------------------------
say("\n## 3. Routed-set churn (boundary membership)")
say("stayed boundary:",
    m[.src0=="hliml_boundary" & .src1=="hliml_boundary", .N])
say("left boundary:",
    m[.src0=="hliml_boundary" & (is.na(.src1) | .src1!="hliml_boundary"), .N])
say("entered boundary:",
    m[(is.na(.src0) | .src0!="hliml_boundary") & .src1=="hliml_boundary", .N])

# --- 4. sigma-median decomposition ----------------------------------------
say("\n## 4. Sigma-median decomposition (clean cells, sigma > 1)")
clean_med <- function(dt) median(dt[get(st_col)=="ok" & .sig > 1, .sig])
med0 <- clean_med(s0); med1 <- clean_med(s1)
# counterfactual: v0.6.0 clean set with the pole cells removed
poleset <- unique(pole[, ..key])
poleset[, .pole := TRUE]
s0c <- merge(s0, poleset, by = key, all.x = TRUE)
med0_excl <- median(s0c[get(st_col)=="ok" & .sig > 1 & is.na(.pole), .sig])
say(sprintf("v0.6.0 shipped median:            %.4f", med0))
say(sprintf("v0.6.0 median, pole cells removed: %.4f  (artifact-removal component: %+.4f)",
            med0_excl, med0_excl - med0))
say(sprintf("v0.6.1 median:                    %.4f  (re-estimation component: %+.4f)",
            med1, med1 - med0_excl))
say(sprintf("total shift v0.6.0 -> v0.6.1:     %+.4f", med1 - med0))

# --- 5. downstream: 2b gamma / opt_tariff shift ---------------------------
say("\n## 5. Stage 2b downstream (country gamma, opt_tariff)")
g0 <- setDT(readRDS(v060_2b)); g1 <- setDT(readRDS(v061_2b))
gcol <- intersect(c("gamma","gamma_hat"), names(g0))[1]
tcol <- intersect(c("opt_tariff","optimal_tariff","tariff"), names(g0))[1]
gst  <- intersect(c("convergence","conv"), names(g0))[1]
say("2b cols:", paste(names(g0), collapse = ", "))
say(sprintf("rows:        v0.6.0 %d  ->  v0.6.1 %d  (%+d)",
            nrow(g0), nrow(g1), nrow(g1) - nrow(g0)))
if (!is.na(gcol))
  say(sprintf("gamma median: %.4f  ->  %.4f  (%+.4f)",
      median(g0[[gcol]], na.rm=TRUE), median(g1[[gcol]], na.rm=TRUE),
      median(g1[[gcol]], na.rm=TRUE) - median(g0[[gcol]], na.rm=TRUE)))
if (!is.na(tcol))
  say(sprintf("opt_tariff median: %.4f  ->  %.4f  (%+.4f)",
      median(g0[[tcol]], na.rm=TRUE), median(g1[[tcol]], na.rm=TRUE),
      median(g1[[tcol]], na.rm=TRUE) - median(g0[[tcol]], na.rm=TRUE)))
if (!is.na(gst))
  say(sprintf("convergence (code 0): %.1f%%  ->  %.1f%%",
      100*mean(g0[[gst]]==0, na.rm=TRUE), 100*mean(g1[[gst]]==0, na.rm=TRUE)))

close(con)
cat("\n>>> wrote out_ab/boundary_ab_v061.md\n")
