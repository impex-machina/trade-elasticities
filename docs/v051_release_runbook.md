# v0.5.1 release runbook — validation-only (2026-08-18)

**Outcome.** GitHub tag `v0.5.1` = 65b06c5 (release commit) with card commits
5c40adc + c7be39f; HF data revision `3b796a6db8a6fa1caabb37acb1e51480a3cbcaf4`
(one commit, 11 files verified against the rehashed manifest; only the two
Pillar-2 CSVs new, the three RDS files deduped); hub card 821ffe4b, superseded
by 2a89ca98 (oid fill-up). Stage 1 sigma and Stage 2b gamma are bit-identical
to v0.5.0 (`ea1c3ea464ca1ac114bf9b6c518325e8135bdc41`).

This was the first release with **no EC2 leg**: it corrected the synthetic
validation harness and its downstream artifacts, so the whole run sheet is
local PowerShell. It also carried three code fixes that do not touch estimates.

## What shipped, in order

| # | commit | content |
|---|---|---|
| 0020 | (in f896164 chain) | `validation/validate_liml.R::simulate_one_cell()` built y/x1/x2 time-major (`as.vector(t(sapply(...)))`) while the exporter/t labels were exporter-major -- every labeled exporter was a mixture of true exporters and the estimator was benchmarked on a no-signal design. Fix drops the transpose; adds `tests/testthat/test-stage1-harness-alignment.R` (equal-t cross-exporter correlation of y ~0.26 aligned vs ~0 scrambled; seed-locked recovery). Suite 325 -> 332. `test-stage1-harness-dgp.R` (label-invariant identity) still passes -- it never had power against this. Production `prepare_cell_moments()` builds moments row-wise and was never affected. |
| 0021 | (in f896164 chain) | `R/load_outputs.R::verify_checksum()` and the `scripts/run_estimation.R` tail check could never pass: (a) `as.character(openssl::sha256(x))` keeps class `hash/sha256` so `identical()` against the plain manifest string is FALSE on equal digests; (b) text-mode `file(path)` gunzips compressed .rds transparently, so the digest was of the decompressed stream on every platform (Windows adds CRLF) -- the platform-independent root cause behind the v0.4.x manifest hashes. Fix: `"rb"` + `unclass` + case-normalized compare. `download_outputs.R` (README Quick Start step 3) now verifies all 11 files. |
| 0022 | f896164 | README bullet 1 and `capture_liml_validation.R` prose made data-driven (yield direction from tier1b, bias sign as a grid-point count); README regenerated so the CI lock stayed green. |
| 0023 | 88b0fbe | Capture generator names the parameter/grid point behind the worst-bias figure (0022 read the omega bias at (8, 3) as a sigma bias). |
| release | 65b06c5 | Re-captured Pillar 2 (`capture_liml_validation.R`, 200 reps): Tier 1a yield 40.5-95.5% (median 71.8%), sigma median bias within +/-3% for sigma <= 3, worst corner (8, 3) sigma -46% / omega -89%, median coverage 91%; Tier 1b (3, 1) yield RISES 72% -> 99% (n 150 -> 3000), sigma bias -8.8% -> -2.3%; Tier 2 all PASS incl. 2.2/2.3. Refreshed `docs/methodology/liml_validation{.md,_20260818.md,_console.txt,_tier1a.csv,_tier1b.csv}`, copied tier1 CSVs to `data/derived/validation/`, `master.R` (no `--rerun-pillars`), `build_readme.R`, `rehash_manifest.R` (exactly 2 rows), 5-anchor scripted rewrite of `validation_section_draft.md` Section 2 (coverage no longer "bias-bound"). |
| card | 5c40adc, c7be39f | v0.5.1 entry above v0.5.0 in house blockquote style; oid filled in a second commit (see lesson 3). |

## The sequence that worked (for the next validation-only release)

1. `git am` the patches; suite; README lock (`README_BUILD_OUTPUT` to a temp
   file, CR-normalized compare); `download_outputs.R` end-to-end; push.
2. `Rscript validation\capture_liml_validation.R` (~10 min on the box at 200
   reps). READ Tier 1b: yield must rise with n. Copy the two tier1 CSVs to
   `data\derived\validation\`; refresh the undated `liml_validation.md` from the
   dated twin.
3. `Rscript analysis\master.R` (NO `--rerun-pillars`, which would also re-run
   Pillar 3) -> `build_readme.R` -> `rehash_manifest.R` (expect exactly the
   tier1 rows).
4. Release commit (no card) -> tag -> push.
5. `py scripts\hf_upload_release.py` dry -> `--execute --message ...` -> oid.
6. Card entry WITH the oid substituted, one commit, push, HfApi README upload
   with a verify list that includes the new oid.

## Observed / lessons (PowerShell 5.1)

1. **[OBSERVED 2026-08-18] Pasting a console transcript executes nothing.**
   Lines that begin with `PS C:\...>` are parsed as `Get-Process` (alias
   `PS`) with a bogus positional argument; the rest of the pasted lines
   error one by one and nothing in the tree changes. Paste only the code
   block, never the prompt lines.
2. **[OBSERVED 2026-08-18] A patch file can be applied from a here-string.**
   `@' ... '@ | Set-Content -Encoding ASCII $env:TEMP\NNNN.patch` then
   `git am $env:TEMP\NNNN.patch` applied 0023 identically to the Downloads
   route (git am strips the CR that Set-Content adds; ASCII is fine for an
   ASCII-only patch -- check the patch has no non-ASCII bytes first).
3. **[OBSERVED 2026-08-18] A bare `throw` at the console does not stop the
   following pasted lines.** `if ($oid -notmatch '^[0-9a-f]{40}$') { throw
   'oid not set' }` threw, and every later line still ran with the
   placeholder -- the card entry shipped as commit 5c40adc / hub 821ffe4b
   reading "Data revision: PASTE_40_HEX_OID_HERE" and needed the c7be39f /
   2a89ca98 fill-up. Any guard-then-act sequence must live inside one
   scriptblock: `& { ...guard...; ...actions... }` -- a `throw` inside `& { }`
   aborts the whole block. (Same family as the v0.4.1 upload-gate lesson:
   gate and action must share one statement.)
4. **[OBSERVED 2026-08-18] Verify lists must name the thing being filled.**
   The first hub-card verify passed on six patterns none of which was the
   new oid, so it certified a placeholder. Include the new pin in the verify
   list and assert the placeholder is absent.
5. `Rscript -e` quoting rule re-confirmed: PS double quotes outside, R single
   quotes inside, no `$` in the code.
6. Multi-line file edits are safer as `[regex]::Replace` with a match-count
   guard (`Matches(...).Count -eq 1`) than in notepad; write back with
   `[IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($false)))`
   to stay BOM-free.

## Follow-ups opened by this release

- F3 (roadmap, v0.6.0): closed-form / hybrid HLIML in Stage 1, O(n) group-sum
  forms for the HLIML objective and HNCS pieces, analytic gradient for the
  Stage-2 L-BFGS-B. Start with a census of how many `step2_clean` /
  `all_inversions_failed` cells the closed form re-routes, run against the
  raw cache archived at `s3://trade-elast-baci-hs92-v202601-hs4/v050rc_run_20260818/`.
- All-Tier-3 early return should populate the full Stage-2b schema
  (`gamma_se_status = "tier3_prior"`, `sigma_robust = NA`) so the two README
  Tier-3 shares agree (25.7% vs 26.7%).
- `docs/methodology/README.md` Pillar-1 headline numbers are the May legacy
  run; its Tier-4 "cut from scope" note is stale.
- Soderbery fn 14 "importer-exporter specific constant" absent from the
  Stage-2 objective: sensitivity study, not a release.
