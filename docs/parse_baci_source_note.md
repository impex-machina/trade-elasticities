# The BACI source identifier and the input-path requirement

**Audience:** anyone re-running the pipeline from raw BACI data, or
relocating the BACI input directory.

## What happens

Output and checkpoint filenames embed a *source identifier* derived from
the input path. The chain is:

```
cfg$filepath  →  parse_baci_source()  →  source_id  →  build_output_prefix()  →  every output + checkpoint filename
```

`parse_baci_source()` (in `R/output_paths.R`) does **not** read the file.
It regex-matches the token `BACI_HS<dd>_V<dddddd>` (case-insensitive)
**anywhere in the filepath string**, lowercases it, and returns it — e.g.
`baci_hs92_v202601`. If no such token appears in the path, it falls back
to the bare string `"baci"`.

`build_output_prefix()` then composes the prefix as:

```
<source_id>_elast_<scope>_<agg_level>
```

so a correct run produces files like
`baci_hs92_v202601_elast_country_hs4_fixed_sigma.rds`, while a run whose
input path lacks the token produces `baci_elast_country_hs4_fixed_sigma.rds`.

## The requirement (and the footgun)

**The input directory's path must contain the `BACI_HS92_V202601` token.**
The identifier comes from the *path*, not the data. Consequences if it
doesn't:

- **Silent generic naming.** Every output is named with the generic
  `baci` prefix instead of the versioned one. No error, no warning — the
  fallback is by design. The outputs are numerically correct but
  mislabeled, which is a reproducibility hazard for a publication
  artifact: the filename no longer records which BACI release produced it.
- **Checkpoint mismatch across relocations.** Checkpoint files
  (`*_checkpoint.rds`, `*_fs_checkpoint.rds`, `*_feenstra_checkpoint.rds`)
  use the same prefix. If you move the BACI directory mid-project such
  that the token presence changes, a resumed run looks for a
  differently-prefixed checkpoint and won't find the prior one — it
  restarts instead of resuming.

## How to satisfy it

Keep the canonical directory name somewhere in the path you pass as the
data argument. Any of these work because the token appears in the path:

```
/data/BACI_HS92_V202601/                        ✓ token in final dir
/mnt/baci/BACI_HS92_V202601/csv/                 ✓ token mid-path
~/BACI_HS92_V202601                              ✓
/data/baci_hs92_v202601/                         ✓ (case-insensitive match)
/data/trade/2026/                                ✗ → outputs prefixed "baci"
```

If you must use a path without the token, the clean fix is a symlink (or
on Windows a junction) whose name carries the token, and point the runner
at that.

## Verification

After a run, confirm the output prefix is versioned, not generic:

```bash
ls <out-dir>/*_elast_*  # filenames should start with baci_hs92_v202601_, not baci_
```

If you see a bare `baci_elast_...` prefix, the input path was missing the
token; rename/symlink and re-run (or rename outputs if the run is
otherwise complete and you are certain of the source release).

---
*N+7 deliverable. Documents existing behavior of `parse_baci_source()` /
`build_output_prefix()` in `R/output_paths.R`; no code change. Resolves
the N+5 punch-list item "document parse_baci_source sentinel-dir
requirement."*
