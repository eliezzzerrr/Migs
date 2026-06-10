# Migs — XAUUSD 5m Trading Agent

This project hosts Claude Code subagents that work on the Migs trading system:

- **`migs-trader`** — grades XAUUSD chart screenshots against the **Migs Hybrid Strategy** doctrine and issues structured signals or NO-TRADE calls.
- **`pine-writer`** — Pine Script v6 specialist. **Auto-route here for ANY mention of Pine Script, TradingView, .pine files, indicators, strategies, request.security, ta.*, plotshape, alertcondition, etc.** Always loads the `pine-script-expert` skill before writing code. Completely separate from MT5/EA work.

## Routing rules (orchestrator: read these first)

| User mentions | Route to |
|---|---|
| Chart screenshot of XAUUSD, "Migs", "grade this", "scout this", trade outcome, weekly review | `migs-trader` subagent |
| Pine Script, TradingView, `.pine`, indicator, strategy, `ta.*`, `request.security`, compile errors (CE10088 etc.), v5→v6 migration | `pine-writer` subagent |
| MT5, MetaTrader 5, MQL5, Expert Advisor, EA, `.mq5`/`.mqh` files | `mt5-ea-writer` skill (no dedicated subagent — use the skill directly) |
| General project questions, doctrine reading, file management | Handle directly without invoking a subagent |

**Do not write Pine Script code inline as the orchestrator.** Always delegate to the `pine-writer` subagent so the `pine-script-expert` skill is loaded and the v6 hard rules are applied. The Pine domain has too many version-specific footguns to write from memory.

## How to invoke

Drop a 5m + 1H chart screenshot into the conversation (or `screenshots/`) and say:

> "Migs — grade this setup"           ← full pipeline, writes a journal entry
> "Migs scout this"  /  "scout"        ← analysis only, NO journal entry

The agent activates when the message contains "Migs" or a chart image is provided. Two modes:

- **Default (grade + log)** — runs the full Migs Hybrid pipeline AND writes a journal entry to `journal/YYYY/MM/NNNN-...md`. Use when you actually take the trade or want a permanent record.
- **Scout (analyze only)** — include the word **"scout"** anywhere in the message. Runs the same pipeline so you see verdict + grade + invalidation conditions, but **skips the journal write entirely**. Use for exploratory chart reads where you don't want to clutter the journal.

If a scout reveals a tradeable setup and you decide to take it, follow up with "log this" or "log the scout" and the agent will write the entry.

## Directory layout

```
Migs/
├── CLAUDE.md                       ← you are here
├── .claude/agents/
│   ├── migs-trader.md              ← XAUUSD strategy agent
│   └── pine-writer.md              ← Pine Script v6 specialist (TradingView)
├── TradingView/                    ← .pine source files
│   └── BG-Golden-Signal-15m-SMC.pine   ← THE strategy (sole survivor, 2026-06-10)
├── EA/                             ← MT5 Expert Advisor (see EA/README.md)
│   └── Experts/BG/BG-Golden-Signal-15m-SMC.mq5  ← Pine-parity EA (magic 20261505)
├── doctrine/                       ← strategy reference (loaded on demand)
│   ├── migs-hybrid-strategy.md     ← full doctrine
│   ├── grading-rubric.md           ← 12-point quality rubric (A+ → F, journaling only)
│   └── checklists.md               ← 6-check binary acceptance (mirror of §9) + killflags
├── workflows/                      ← step-by-step procedures
│   ├── signal-generation.md        ← the main pipeline
│   ├── news-check.md               ← ForexFactory gate
│   ├── pattern-tagging.md          ← how patterns get #NN
│   ├── outcome-update.md           ← how to log TP/SL hits
│   └── weekly-review.md            ← weekly pattern adjustment
├── patterns/                       ← pattern library + stats
│   ├── stats.json                  ← aggregated WR per pattern
│   ├── 01-buy-base.md
│   └── 02-sell-base.md
├── journal/                        ← one .md per trade, YYYY/MM/
├── reviews/                        ← weekly review files
├── scripts/
│   └── update_stats.py             ← recompute stats.json from journal
└── screenshots/                    ← chart images go here (gitignored)
```

## Phase

- **DEMO** — 1% risk per trade. Target ≥30 resolved Migs trades, WR ≥40%, +10R total to graduate to LIVE.
- Every signal is tagged `Phase: DEMO` until graduation criteria are met.

## Core rules the agent obeys (hard)

1. **Two-pass chart reading** — first extract observable primitives (OB bounds, structure levels, DOL prices, swing wick references) as structured JSON. Only then reason about the setup. Never invent levels.
2. **News gate: DISABLED** (as of 2026-05-21, per user). Trader assumes responsibility for news awareness. Re-enable by reverting this rule and `workflows/news-check.md`.
3. **Pattern WR gate** — if direction (BUY or SELL) has ≥5 closed trades AND win-rate <40% ⇒ NO TRADE that direction.
4. **One strategy.** Migs Hybrid is the only strategy. Don't invent setup types. The trader identifies the structural entry; the doctrine prescribes SL/TP/management.
5. **3-TP / thirds management.** Every trade: TP1=+1R, TP2=+2R, TP3=+3R, 1/3 size at each. Blended +2R when all fill. See `doctrine/migs-hybrid-strategy.md`.
6. **One signal per invocation** — fresh context every time. Persist learning to files, not to chat history.

## Weekly review

Every Sunday (or on request), run the `weekly-review` workflow. The agent reads all journal entries from the last 7 days, recomputes `patterns/stats.json`, clusters novel setups into refined patterns, and proposes doctrine adjustments to a new `reviews/YYYY-Www.md`.

## When the EA comes later

The journal schema is intentionally rich (MFE/MAE in R, ATR, spread, chart_features_json) so it doubles as training data for a future MT5 Expert Advisor. Don't drop fields even if they look unused now.
