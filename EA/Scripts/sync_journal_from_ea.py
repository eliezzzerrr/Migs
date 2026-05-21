r"""
sync_journal_from_ea.py — copy EA-written journal entries into project journal/

The EA writes journal entries to MQL5\Files\Migs\journal\YYYY\MM\NNNN-*.md.
After a trading session (or on demand), run this to mirror them into the
project's journal/ folder. Then run scripts/update_stats.py to refresh stats.

Behavior:
  - Mirrors directory structure
  - Skips files that already exist with identical content
  - Renumbers IDs if they collide with existing project journal entries
    (very unlikely if the EA is the sole writer, but defensive)

Usage:
    python EA/Scripts/sync_journal_from_ea.py
    python EA/Scripts/sync_journal_from_ea.py --mt5-files "C:\Path\To\MQL5\Files"
"""  # noqa

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEST_BASE = PROJECT_ROOT / "journal"


def find_mt5_files() -> Path | None:
    base = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal"
    if not base.exists():
        return None
    candidates = [
        p for p in base.iterdir()
        if p.is_dir() and (p / "MQL5" / "Files").exists()
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] / "MQL5" / "Files"


def existing_ids() -> set[int]:
    ids: set[int] = set()
    if not DEST_BASE.exists():
        return ids
    for p in DEST_BASE.rglob("*.md"):
        m = re.match(r"^(\d{4})-", p.name)
        if m:
            ids.add(int(m.group(1)))
    return ids


def max_id() -> int:
    ids = existing_ids()
    return max(ids) if ids else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mt5-files", type=Path, default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    src_base = args.mt5_files or find_mt5_files()
    if src_base is None:
        print("[ERR] Could not auto-detect MT5 Files.", file=sys.stderr)
        return 2

    src_journal = src_base / "Migs" / "journal"
    if not src_journal.exists():
        print(f"[INFO] No EA journal found at {src_journal}; nothing to sync.")
        return 0

    next_id = max_id() + 1
    copied = 0
    renamed = 0
    skipped = 0
    taken = existing_ids()

    for src in sorted(src_journal.rglob("*.md")):
        rel = src.relative_to(src_journal)
        m = re.match(r"^(\d{4})-(\d{4}-\d{2}-\d{2})-(.*)\.md$", src.name)
        if not m:
            continue
        cur_id = int(m.group(1))
        date = m.group(2)
        suffix = m.group(3)

        out_id = cur_id
        if cur_id in taken:
            out_id = next_id
            next_id += 1
            renamed += 1
        taken.add(out_id)

        out_dir = DEST_BASE / rel.parent
        out_name = f"{out_id:04d}-{date}-{suffix}.md"
        out_path = out_dir / out_name

        if out_path.exists():
            if out_path.read_bytes() == src.read_bytes():
                skipped += 1
                continue

        if args.dry_run:
            print(f"[DRY] {src} -> {out_path}")
            continue

        out_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, out_path)
        copied += 1

    print(f"[OK] Copied {copied}, renamed-on-collision {renamed}, skipped {skipped}")
    print("Next step: python scripts/update_stats.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
