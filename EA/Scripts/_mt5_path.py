"""Shared helper for locating the active MT5 terminal's MQL5\\Files directory.

Used by sync_stats_to_ea.py, sync_journal_from_ea.py, and fetch_ff_calendar.py.
Three copies of this lookup used to live inline — keep this the single source
of truth.
"""

from __future__ import annotations

import os
from pathlib import Path


def find_mt5_files() -> Path | None:
    """Return the most-recently-touched terminal's `MQL5\\Files` path, or None.

    Walks `%APPDATA%\\MetaQuotes\\Terminal\\<hash>\\MQL5\\Files` and picks the
    terminal directory with the newest mtime — that's usually the one the
    user has open right now.
    """
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
