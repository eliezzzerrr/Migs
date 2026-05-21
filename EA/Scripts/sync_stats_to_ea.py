r"""
sync_stats_to_ea.py — copy patterns/stats.json into MT5 Files folder

The EA reads its WR-gate decisions from MQL5\Files\Migs\migs-stats.json.
After every weekly review (when stats may change), run this script to
push the latest stats into MT5's reach.

Usage:
    python EA/Scripts/sync_stats_to_ea.py
    # or override MT5 Files path:
    python EA/Scripts/sync_stats_to_ea.py --mt5-files "C:\Path\To\MQL5\Files"

Auto-detects the MT5 Files folder by looking for the most-recent terminal
directory under %APPDATA%\MetaQuotes\Terminal\<hash>\MQL5\Files. If that
fails, pass --mt5-files explicitly.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SRC = PROJECT_ROOT / "patterns" / "stats.json"


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
    # most recently modified terminal dir
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] / "MQL5" / "Files"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mt5-files", type=Path, default=None,
                    help="Path to MT5 Files dir (default: auto-detect)")
    args = ap.parse_args()

    if not SRC.exists():
        print(f"[ERR] Source stats not found: {SRC}", file=sys.stderr)
        return 1

    target_base = args.mt5_files or find_mt5_files()
    if target_base is None:
        print("[ERR] Could not auto-detect MT5 Files. Pass --mt5-files.", file=sys.stderr)
        return 2

    target_dir = target_base / "Migs"
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / "migs-stats.json"
    shutil.copy2(SRC, target)
    print(f"[OK] Copied {SRC} -> {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
