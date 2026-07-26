#!/usr/bin/env python3
"""Gated, atomic HF release upload.

Replaces the ad-hoc per-file upload one-liners whose PowerShell guard
could throw while the upload lines still ran (the v0.4.1 Step-8
incident: gate and action lived in separate statements). Here the gate
and the action are one program: nothing is uploaded unless every check
passes, and the upload itself is a single atomic hub commit.

Checks, in order, all fatal:
  1. Census (set comparison): the on-disk file set under data/derived
     (dotfiles included, .gitkeep exempt) must EQUAL the manifest's
     local_path set — extras and missing are both reported by name.
  2. Hash gate: every file's sha256 must match its manifest row, which
     forces scripts/rehash_manifest.R to have been run after the last
     content change.
  3. Size cross-check against the manifest's size_bytes column.

Default is a dry run that prints the verified plan. Pass --execute plus
a --message to perform the upload as ONE create_commit (all files, one
hub revision). Hub layout matches prior releases: path_in_repo strips
the data/derived/ prefix (the repo's .gitkeep landed at the hub root in
5493c51f under this mapping).

Usage (PowerShell, from the repo root):
  py scripts\\hf_upload_release.py                       # dry run
  py scripts\\hf_upload_release.py --execute --message "data: v0.5.0 rerun"

Auth: uses the cached HF token (or HF_TOKEN env var).
"""

import argparse
import csv
import hashlib
import sys
from pathlib import Path

REPO_ID = "impex-machina/trade-elasticities"
REPO_TYPE = "dataset"
MANIFEST = Path("data/manifest.csv")
DATA_ROOT = Path("data/derived")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(msg: str) -> None:
    print(f"ABORT: {msg}")
    sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--execute", action="store_true",
                    help="perform the upload (default: dry run)")
    ap.add_argument("--message", default=None,
                    help="hub commit message (required with --execute)")
    args = ap.parse_args()

    if args.execute and not args.message:
        fail("--execute requires --message")

    if not MANIFEST.exists():
        fail(f"{MANIFEST} not found — run from the repo root")

    with open(MANIFEST, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for col in ("local_path", "sha256", "size_bytes"):
        if rows and col not in rows[0]:
            fail(f"manifest lacks column '{col}'")

    manifest_paths = {r["local_path"].replace("\\", "/") for r in rows}

    # --- Gate 1: census, dotfiles included, .gitkeep exempt -------------
    disk_paths = {
        p.as_posix() for p in DATA_ROOT.rglob("*")
        if p.is_file() and p.name != ".gitkeep"
    }
    extra = sorted(disk_paths - manifest_paths)
    missing = sorted(manifest_paths - disk_paths)
    if extra or missing:
        for p in extra:
            print(f"  untracked on disk: {p}")
        for p in missing:
            print(f"  missing on disk:   {p}")
        fail("census mismatch between data/derived and the manifest")

    # --- Gates 2 + 3: hashes and sizes vs the manifest ------------------
    bad = []
    total_bytes = 0
    for r in rows:
        p = Path(r["local_path"])
        size = p.stat().st_size
        total_bytes += size
        if str(size) != str(r["size_bytes"]):
            bad.append(f"size drift: {p} disk={size} manifest={r['size_bytes']}")
            continue
        digest = sha256_of(p)
        if digest != r["sha256"].lower():
            bad.append(f"hash drift: {p}")
    if bad:
        for b in bad:
            print(f"  {b}")
        fail("manifest is stale — run scripts/rehash_manifest.R, review, retry")

    # --- Verified plan ---------------------------------------------------
    print(f"verified {len(rows)} files, {total_bytes / 1e6:.1f} MB, "
          f"against {MANIFEST}")
    ops_plan = sorted(
        (r["local_path"].replace("\\", "/"),
         Path(r["local_path"]).relative_to(DATA_ROOT).as_posix())
        for r in rows
    )
    for local, in_repo in ops_plan:
        print(f"  {local}  ->  {in_repo}")

    if not args.execute:
        print("dry run only — re-run with --execute --message '...' to upload")
        return

    # --- Action: one atomic hub commit ----------------------------------
    from huggingface_hub import CommitOperationAdd, HfApi

    api = HfApi()
    ops = [CommitOperationAdd(path_in_repo=in_repo, path_or_fileobj=local)
           for local, in_repo in ops_plan]
    info = api.create_commit(
        repo_id=REPO_ID,
        repo_type=REPO_TYPE,
        operations=ops,
        commit_message=args.message,
    )
    print(f"uploaded in one commit: {info.commit_url}")
    print(f"hub oid: {info.oid}")


if __name__ == "__main__":
    main()
