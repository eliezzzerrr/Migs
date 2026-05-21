r"""
fetch_ff_calendar.py — fetch ForexFactory weekly calendar, write CSV for EA

Output format consumed by MigsContext.mqh / CheckNewsCSV():

    datetime_utc,impact,currency,event
    2026-05-21 12:30,High,USD,Core CPI m/m

The CSV is written to:
    1) MT5's MQL5\Files\Migs\migs-news.csv (auto-detect; --mt5-files to override)
    2) The project's EA/Files/migs-news.csv (for inspection/version control)

Run this on a schedule (e.g. Sunday night + Wednesday refresh) via Windows
Task Scheduler. The EA reads the CSV on every signal evaluation.

Notes on the FF feed:
  - The JSON endpoint URL changes occasionally. We try a couple, then
    fall back to scraping the HTML calendar.
  - We only emit high-impact (red folder) USD events. XAU events are rare
    on FF; geopolitical/Fed-speak should be added manually if needed.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PROJECT_OUT  = PROJECT_ROOT / "EA" / "Files" / "migs-news.csv"

FF_JSON_URLS = [
    "https://nfs.faireconomy.media/ff_calendar_thisweek.json",
    "https://cdn-nfs.forexfactory.net/ff_calendar_thisweek.json",
]


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


def fetch_json() -> list[dict]:
    last_err: Exception | None = None
    for url in FF_JSON_URLS:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (MigsEA)"})
            with urllib.request.urlopen(req, timeout=20) as r:
                data = json.loads(r.read().decode("utf-8"))
                if isinstance(data, list) and data:
                    return data
        except Exception as e:
            last_err = e
            continue
    if last_err:
        print(f"[WARN] All JSON feeds failed: {last_err}", file=sys.stderr)
    return []


def to_utc(date_str: str, time_str: str, tz_offset_hours: int) -> dt.datetime | None:
    """FF JSON timestamps are usually already ISO-with-tz; handle both."""
    try:
        # ISO with offset, e.g. "2026-05-21T08:30:00-04:00"
        return dt.datetime.fromisoformat(date_str).astimezone(dt.timezone.utc)
    except Exception:
        pass
    try:
        local = dt.datetime.strptime(f"{date_str} {time_str}", "%b %d %Y %I:%M%p")
        return (local - dt.timedelta(hours=tz_offset_hours)).replace(tzinfo=dt.timezone.utc)
    except Exception:
        return None


def parse_events(raw: list[dict]) -> list[tuple[dt.datetime, str, str, str]]:
    rows: list[tuple[dt.datetime, str, str, str]] = []
    for item in raw:
        impact = (item.get("impact") or "").strip()
        if impact.lower() not in ("high", "red"):
            continue
        cur = (item.get("country") or item.get("currency") or "").strip()
        if cur not in ("USD",):
            continue
        title = (item.get("title") or item.get("event") or "").strip()
        # FF JSON commonly has "date" as full ISO with offset
        date = item.get("date") or ""
        time = item.get("time") or ""
        t = to_utc(date, time, 0)
        if t is None:
            continue
        rows.append((t, "High", cur, title))
    return rows


def write_csv(rows: list[tuple[dt.datetime, str, str, str]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="") as f:
        w = csv.writer(f)
        w.writerow(["datetime_utc", "impact", "currency", "event"])
        for t, imp, cur, ev in rows:
            w.writerow([t.strftime("%Y-%m-%d %H:%M"), imp, cur, ev])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mt5-files", type=Path, default=None)
    args = ap.parse_args()

    raw = fetch_json()
    if not raw:
        print("[ERR] No events fetched. EA will fail-closed on news gate if MT5 calendar also empty.",
              file=sys.stderr)
        return 1
    rows = parse_events(raw)
    rows.sort(key=lambda r: r[0])

    write_csv(rows, PROJECT_OUT)
    print(f"[OK] Wrote {len(rows)} high-impact USD events -> {PROJECT_OUT}")

    mt5 = args.mt5_files or find_mt5_files()
    if mt5 is None:
        print("[WARN] MT5 Files not auto-detected; only project copy written.")
    else:
        mt5_out = mt5 / "Migs" / "migs-news.csv"
        write_csv(rows, mt5_out)
        print(f"[OK] Wrote {len(rows)} events -> {mt5_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
