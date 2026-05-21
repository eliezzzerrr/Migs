# Migs — XAUUSD 5m Trading Agent

Discretionary + algorithmic trading system for XAUUSD on the 5-minute timeframe, executing the **Migs Hybrid Strategy**. The repo contains a Claude Code subagent (`migs-trader`) that grades chart screenshots and issues structured signals, a deterministic MT5 Expert Advisor (`MigsEA`) that runs the same doctrine autonomously, a TradingView Pine v6 indicator for visual confirmation, and the full rule-book + journal.

## Status

| | |
|---|---|
| Phase | **DEMO** (1% risk per trade) |
| Track record | 7 closed trades · 5W / 2L · 71% WR · **+10R** |
| Graduation target | ≥30 trades · WR ≥40% · ≥+10R · clean rules |
| Progress | 7 / 30 trades |

## Strategy at a glance

One strategy. Two directions (BUY, SELL). Same management every trade.

1. **Setup** — discretionary entry at a structural level on 5m, aligned with 1H bias (OB, swept liquidity, broken structure, range retest, etc.)
2. **SL** — beyond the structure + small buffer. The SL distance *defines* 1R.
3. **TPs** — mechanical 1R / 2R / 3R ladder (no DOL-anchored targets)
4. **Sizing** — thirds: close 1/3 at each TP. Blended outcome when all 3 fill = **+2.0R**. SL before any TP = **–1.0R**.
5. **Sessions** — any session permitted
6. **News** — trader-managed (no deterministic gate)

Full doctrine: [`doctrine/migs-hybrid-strategy.md`](doctrine/migs-hybrid-strategy.md)

## How trades are graded

Two layers — the binary one decides if you trade, the graded one tags conviction:

**§9 Binary acceptance** — 6 pass/fail checks. Any failure → NO TRADE. The only trade gate.

**12-point quality rubric** — 6 criteria × 0/1/2 each, mapped to A+ → F. Lives in journal frontmatter for analysis, weekly review, and future conviction-sizing. Does not veto a §9 pass.

| Score | Grade |
|---|---|
| 12 | A+ |
| 11 | A |
| 10 | A- |
| 9 | B+ |
| 7–8 | B |
| ≤6 | C / D / F |

Details: [`doctrine/grading-rubric.md`](doctrine/grading-rubric.md) · [`doctrine/checklists.md`](doctrine/checklists.md)

## Repository layout

```
Migs/
├── CLAUDE.md                       ← project instructions for Claude Code
├── doctrine/                       ← strategy + rules (single source of truth)
│   ├── migs-hybrid-strategy.md     ← full doctrine
│   ├── checklists.md               ← 6-check binary acceptance + killflags
│   └── grading-rubric.md           ← 12-point A+ → F quality rubric
├── workflows/                      ← step-by-step procedures
│   ├── signal-generation.md        ← the main pipeline
│   ├── outcome-update.md           ← logging TP/SL hits
│   ├── weekly-review.md            ← Sunday pattern adjustment
│   ├── pattern-tagging.md          ← how patterns get tagged
│   └── news-check.md               ← retained for re-enable; gate disabled 2026-05-21
├── patterns/                       ← directional buckets + live stats
│   ├── buy.md · sell.md            ← Hybrid BUY / SELL definitions
│   └── stats.json                  ← live WR per direction, WR-gate flags
├── journal/YYYY/MM/                ← one .md per signal (trade or no-trade)
├── reviews/                        ← weekly reviews (reviews/YYYY-Www.md)
├── scripts/update_stats.py         ← recompute stats.json from journal
├── screenshots/                    ← chart screenshots (gitignored except README)
├── .claude/
│   ├── agents/migs-trader.md       ← the discretionary subagent definition
│   └── skills/mt5-ea-writer/       ← project skill for MQL5 EA development
├── EA/                             ← MT5 Expert Advisor (DEMO-only by default)
│   ├── Experts/Migs/               ← MigsEA.mq5
│   ├── Include/Migs/               ← strategy modules
│   └── Scripts/                    ← stats sync + ForexFactory news fetch
└── TradingView/                    ← Pine v6 indicator
    └── Migs-Hybrid-v6.pine
```

## Components

### `migs-trader` (Claude Code subagent)
Discretionary execution. Drop a 5m + 1H XAUUSD chart screenshot into the conversation and say *"Migs — grade this setup"*. The agent runs the two-pass extraction → §9 acceptance → 12-point grade → journal entry pipeline.

Spec: [`.claude/agents/migs-trader.md`](.claude/agents/migs-trader.md)
Playbook: [`workflows/signal-generation.md`](workflows/signal-generation.md)

### `MigsEA` (MT5 Expert Advisor)
Autonomous execution of the same doctrine. Detects OB / structure / DOL algorithmically, sizes for 1% risk, manages the 3-TP thirds ladder, writes journal entries in the same schema as the discretionary agent. **Refuses live accounts unless `InpAllowLiveAccount=true`.**

Install + parameter reference: [`EA/README.md`](EA/README.md)

### Pine v6 indicator
Visual overlay on TradingView showing structural levels the doctrine cares about — OBs, swept liquidity, internal breakers, DOL ladder candidates.

[`TradingView/Migs-Hybrid-v6.pine`](TradingView/Migs-Hybrid-v6.pine) · [`TradingView/README.md`](TradingView/README.md)

## Working with the agent

```
# Grade a setup
Drop 5m + 1H chart into Claude Code. Say "Migs — grade this setup"
→ produces signal + journal entry

# Log an outcome
"Trade #0011 hit TP2"
→ updates frontmatter + recomputes stats.json

# Weekly review (Sundays)
"weekly review"
→ produces reviews/YYYY-Www.md with proposed pattern changes
```

The agent persists every decision to `journal/` — TRADE and NO-TRADE both. The journal is the audit trail *and* future EA training data.

## Hard rules (non-negotiable)

1. **Never invent levels.** Every OB / DOL / sweep wick claimed must trace to a visible chart feature.
2. **Two-pass chart reading.** Primitives JSON first, judgment over JSON second. No re-looking during reasoning.
3. **One strategy.** Migs Hybrid is the only strategy. No improvised setup types.
4. **§9 binary acceptance is the gate.** The rubric grades quality but never vetoes.
5. **Pattern WR gate.** A direction with ≥5 closed trades AND WR <40% auto-skips.
6. **No outside patterns.** Doctrine evolves only from journaled trade data — never from training-data priors.

## Phase + risk discipline

DEMO at 1% per trade until graduation criteria are met. `InpAllowLiveAccount` stays `false` on the EA. Every signal is tagged `phase: DEMO`. The user makes the LIVE switch after reviewing graduation criteria — the agent never promotes itself.

## License

Personal trading system. Not financial advice. Use at your own risk.
