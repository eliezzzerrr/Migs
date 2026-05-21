"""
Recompute patterns/stats.json from all journal entries.

Idempotent: deletes nothing, just rewrites stats.json from scratch by reading
every journal/**/*.md frontmatter. Safe to run any time.

Usage:
    python scripts/update_stats.py

Reads:
    journal/**/*.md            (frontmatter only)
    patterns/stats.json        (existing, for pattern metadata: name, status)
    patterns/*.md              (for any patterns not yet in stats.json)

Writes:
    patterns/stats.json
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml  # PyYAML — install via `pip install pyyaml`
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "[FATAL] PyYAML is required. Install with: pip install pyyaml\n"
    )
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
JOURNAL = ROOT / "journal"
PATTERNS = ROOT / "patterns"
STATS_PATH = PATTERNS / "stats.json"

WIN_GATE_MIN_TRADES = 5
WIN_GATE_THRESHOLD = 0.40
GRADUATION_TARGET = 30


def parse_frontmatter(text: str) -> dict | None:
    """Extract YAML frontmatter between leading `---` fences and parse with PyYAML.

    Handles nested fields (grade, chart_features, etc.) which the previous
    regex parser silently truncated.
    """
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not m:
        return None
    try:
        data = yaml.safe_load(m.group(1))
    except yaml.YAMLError as exc:
        sys.stderr.write(f"[WARN] YAML parse failed: {exc}\n")
        return None
    if not isinstance(data, dict):
        return None
    return data


def load_existing_stats() -> dict:
    if STATS_PATH.exists():
        return json.loads(STATS_PATH.read_text(encoding="utf-8"))
    return {}


def load_pattern_files() -> dict[str, dict]:
    """Return {id: {name, status}} from patterns/*.md frontmatter."""
    out: dict[str, dict] = {}
    for path in PATTERNS.glob("*.md"):
        if path.name == "README.md":
            continue
        text = path.read_text(encoding="utf-8")
        fm = parse_frontmatter(text) or {}
        pid = fm.get("id")
        if pid:
            out[pid] = {
                "name": fm.get("name", pid),
                "status": fm.get("status", "active"),
            }
    return out


def iter_journal_entries():
    if not JOURNAL.exists():
        return
    for path in sorted(JOURNAL.rglob("*.md")):
        if path.name == "README.md":
            continue
        text = path.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        if not fm:
            continue
        yield path, fm


def to_float(v, default=0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def empty_pattern(name: str, status: str = "active") -> dict:
    return {
        "name": name,
        "status": status,
        "trades": 0,
        "wins": 0,
        "losses": 0,
        "be": 0,
        "open": 0,
        "tp1_hit": 0,
        "tp2_hit": 0,
        "sl_hit": 0,
        "total_r": 0.0,
        "win_rate": None,
        "avg_r": None,
        "last_5_outcomes": [],
        "gated": False,
        "gate_reason": None,
    }


def main() -> int:
    existing = load_existing_stats()
    pattern_files = load_pattern_files()

    patterns: dict[str, dict] = {}
    for pid, meta in pattern_files.items():
        patterns[pid] = empty_pattern(meta["name"], meta["status"])
    # Carry over buckets from existing stats only if they have data — drops
    # zombie buckets left by renames/deletions (e.g. old "01"/"02" after rename).
    for pid, meta in existing.get("patterns", {}).items():
        if pid in patterns:
            continue
        has_data = any(meta.get(k, 0) > 0 for k in ("trades", "wins", "losses", "be", "open"))
        if has_data:
            patterns[pid] = empty_pattern(meta.get("name", pid), meta.get("status", "active"))

    global_wins = 0
    global_losses = 0
    global_be = 0
    global_total_r = 0.0
    resolved_outcomes_chrono: list[tuple[str, str]] = []

    for path, fm in iter_journal_entries():
        # Direction: PyYAML may parse `null` → None. Coerce to upper-string.
        direction = str(fm.get("direction") or "").upper()
        # Skip non-trade entries: explicit NO-TRADE, blank direction, or any
        # entry whose outcome is NA (resolution-not-applicable).
        if direction in ("NO-TRADE", "", "NULL", "NONE"):
            continue
        outcome_pre = str(fm.get("outcome") or "").upper()
        if outcome_pre == "NA":
            continue
        # Pattern ID: coerce to str (PyYAML may parse bare "01" as int 1).
        raw_pid = fm.get("pattern")
        raw_pid = str(raw_pid) if raw_pid is not None else None
        if raw_pid == "01": raw_pid = "buy"
        elif raw_pid == "02": raw_pid = "sell"
        pid = raw_pid or ("buy" if direction == "BUY" else "sell" if direction == "SELL" else None)
        if pid is None:
            continue
        if pid not in patterns:
            patterns[pid] = empty_pattern(name=f"Pattern {pid}")

        outcome = (fm.get("outcome") or "OPEN").upper()
        r = to_float(fm.get("r_realized"), 0.0)

        p = patterns[pid]
        p["trades"] += 1

        if outcome == "OPEN":
            p["open"] += 1
            continue

        if outcome == "TP1_HIT":
            p["tp1_hit"] += 1
            p["wins"] += 1
            global_wins += 1
        elif outcome == "TP2_HIT":
            p["tp2_hit"] += 1
            p["wins"] += 1
            global_wins += 1
        elif outcome == "TP3_HIT":
            p.setdefault("tp3_hit", 0)
            p["tp3_hit"] += 1
            p["wins"] += 1
            global_wins += 1
        elif outcome == "SL_HIT":
            p["sl_hit"] += 1
            p["losses"] += 1
            global_losses += 1
        elif outcome == "BE":
            p["be"] += 1
            global_be += 1
        else:
            continue

        p["total_r"] += r
        global_total_r += r
        # PyYAML parses `2026-05-18 21:00` as a datetime object; coerce to ISO
        # string so chronological sort is uniform across mixed YAML types.
        ts = fm.get("timestamp_pht") or fm.get("timestamp_utc") or ""
        ts = ts.isoformat() if hasattr(ts, "isoformat") else str(ts)
        resolved_outcomes_chrono.append((ts, outcome))
        p.setdefault("_chron", []).append((ts, outcome))

    for pid, p in patterns.items():
        resolved = p["wins"] + p["losses"] + p["be"]
        decisive = p["wins"] + p["losses"]
        p["win_rate"] = round(p["wins"] / decisive, 4) if decisive else None
        p["avg_r"] = round(p["total_r"] / resolved, 4) if resolved else None
        chron = sorted(p.pop("_chron", []), key=lambda x: x[0])
        p["last_5_outcomes"] = [o for _, o in chron[-5:]]

        if decisive >= WIN_GATE_MIN_TRADES and (p["win_rate"] or 0) < WIN_GATE_THRESHOLD:
            p["gated"] = True
            p["gate_reason"] = (
                f"WR {p['win_rate']:.0%} over {decisive} decisive trades (<{int(WIN_GATE_THRESHOLD*100)}%)"
            )
            if p["status"] == "active":
                p["status"] = "gated"
        else:
            p["gated"] = False
            p["gate_reason"] = None

    resolved_outcomes_chrono.sort(key=lambda x: x[0])
    consecutive_losses = 0
    for _, o in reversed(resolved_outcomes_chrono):
        if o == "SL_HIT":
            consecutive_losses += 1
        else:
            break

    total_resolved = global_wins + global_losses + global_be
    decisive_global = global_wins + global_losses
    global_wr = round(global_wins / decisive_global, 4) if decisive_global else None
    avg_r = round(global_total_r / total_resolved, 4) if total_resolved else None

    out = {
        "schema_version": 1,
        "updated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "global": {
            "total_resolved": total_resolved,
            "wins": global_wins,
            "losses": global_losses,
            "be": global_be,
            "win_rate": global_wr,
            "total_r": round(global_total_r, 4),
            "avg_r": avg_r,
            "consecutive_losses": consecutive_losses,
            "graduation": {
                "trades_required": GRADUATION_TARGET,
                "wr_required": WIN_GATE_THRESHOLD,
                "r_required": 10.0,
                "trades_progress": total_resolved,
                "ready": (
                    total_resolved >= GRADUATION_TARGET
                    and (global_wr or 0) >= WIN_GATE_THRESHOLD
                    and global_total_r >= 10.0
                ),
            },
        },
        "patterns": patterns,
        "gate_rules": {
            "wr_gate_min_trades": WIN_GATE_MIN_TRADES,
            "wr_gate_threshold": WIN_GATE_THRESHOLD,
            "consecutive_loss_modifier_threshold": 3,
        },
    }

    STATS_PATH.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(
        f"stats.json updated: {total_resolved} resolved, "
        f"WR {global_wr if global_wr is not None else '—'}, "
        f"R {global_total_r:+.2f}, consecutive_losses={consecutive_losses}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
