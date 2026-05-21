# Workflow — Signal Generation

The agent runs this pipeline **every time** a chart is provided. No shortcuts.

## Step 0 — Resolve "now"

- Resolve current time in PHT (UTC+8) and UTC.
- Identify current session for journal-tagging purposes (London / Transition / NY-AM / Off-session).
- No session-based grade cap under the unified strategy — sessions are informational only.

## Step 1 — News gate (DISABLED 2026-05-21)

The deterministic news gate has been removed from the pipeline per user. Do not WebFetch ForexFactory. Tag journal entries with `news_window: disabled`. Trader assumes responsibility for news awareness outside the agent.

Re-enable by reverting this section and restoring `workflows/news-check.md`.

## Step 2 — Two-pass chart extraction (anti-hallucination)

### Pass 1 — Primitives only (JSON, no judgment)

Read the chart screenshot. Emit a JSON object enumerating only **observable** features. Every feature must reference a visible anchor (candle wick, bar position relative to right edge, or annotated drawing).

```json
{
  "timeframe_visible": ["5m", "1h"],
  "rightmost_candle_time_pht": "YYYY-MM-DD HH:MM",
  "current_price": 0.0,
  "swings": [
    { "id": "s1", "type": "high|low", "price": 0.0, "bar_offset": -7, "evidence": "wick" }
  ],
  "order_blocks": [
    { "id": "ob1", "type": "demand|supply", "high": 0.0, "low": 0.0, "fresh": true, "bar_range": [-12, -10] }
  ],
  "fair_value_gaps": [
    { "id": "fvg1", "high": 0.0, "low": 0.0, "position_vs_ob": "inside|adjacent|stacked|separate", "bar_range": [-11, -9] }
  ],
  "bos_events": [
    { "id": "bos1", "direction": "bullish|bearish", "price": 0.0, "candle_strength": "decisive|small-range|absent", "bar_offset": -3 }
  ],
  "draws_on_liquidity": [
    { "id": "dol1", "price": 0.0, "tf": "5m|1h", "type": "equal-highs|equal-lows|session-extreme", "distance_pips_from_price": 0 }
  ],
  "sweep_wicks": [
    { "id": "sw1", "price": 0.0, "bar_offset": -8 }
  ],
  "htf_bias_1h": "bullish|bearish|ranging",
  "annotations_visible": ["money-bag at 3xxx.x", "yellow rectangle 3xxx.x–3xxx.x"],
  "confidence": 0.0
}
```

**Rules:**
- If you cannot fill a field with high confidence, set it to `null` or omit it. Never guess.
- `confidence` <0.6 ⇒ HARD KILLFLAG → NO TRADE with reason "low extraction confidence".
- If 1H bias is not visible on the screenshot, request it (`watch` field in output) and emit NO TRADE.

### Pass 2 — Judgment over JSON

Now reason **only** about the JSON from Pass 1. Do not re-look at the chart for new features. If you need a feature that isn't in the JSON, it doesn't exist for this decision.

- Map JSON → 4-element confluence (OB + FVG + BOS + DOL).
- Determine direction (LONG / SHORT).
- Compute entry candidate, SL, TP1, TP2 (pips and RR).

## Step 3 — Binary acceptance (the gate)

Run the 6-check binary acceptance from `doctrine/checklists.md` (which mirrors `doctrine/migs-hybrid-strategy.md` §9). Any failure ⇒ NO TRADE; cite which check failed. This is the **only** trade/no-trade gate.

## Step 4 — Quality grade (journaling only)

If §9 passed, run `doctrine/grading-rubric.md`. Score each of 6 criteria 0/1/2. Sum (0–12). Map to letter (A+ at 12). The grade is recorded in journal frontmatter as `grade: { letter: X, score: N }`. **It does not veto a §9 pass.**

Modifier:
- 3rd+ consecutive Migs losses → –1 letter on the journal grade (informational; still tradeable)

## Step 5 — Pattern match + WR gate

- Match the setup against `patterns/*.md`. Start with `buy` (Hybrid BUY) or `sell` (Hybrid SELL); use `novel` if the setup doesn't fit either cleanly.
- Read `patterns/stats.json`. For the matched pattern:
  - If `trades >= 5` AND `win_rate < 0.40` ⇒ **NO TRADE** with reason `"WR gate: pattern {id} at X% over N trades"`.
  - Otherwise continue.

## Step 6 — Self-critique pass

Before emitting a TRADE signal, list 3 reasons this setup could fail:

1. …
2. …
3. …

If any of those reasons trip a checklist item you'd previously marked pass, downgrade and re-evaluate.

## Step 7 — Emit signal or NO TRADE

Use the format in `doctrine/migs-hybrid-strategy.md` §9.

Required fields in output:
- Direction, Entry, SL, TP1, TP2, prices and pip distances
- Grade (letter + score)
- Pattern tag (#NN or novel)
- LLM confidence
- Top 3 invalidation conditions (from self-critique)

## Step 8 — Persist to journal

Write `journal/YYYY/MM/NNNN-YYYY-MM-DD-[buy|sell|no-trade].md` using the schema in §10 of the doctrine. NNNN is zero-padded sequential ID across all trades.

Find next ID: `Glob journal/**/*.md` then take max id + 1.

## Step 9 — Don't update stats yet

`patterns/stats.json` is updated only when an **outcome** is logged (TP1 hit, TP2 hit, SL hit, BE). Open signals do not move the counters. See `workflows/outcome-update.md`.
