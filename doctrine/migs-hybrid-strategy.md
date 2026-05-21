# Migs Hybrid Strategy — XAUUSD

One strategy. Two directions (BUY, SELL). Same management every trade.

This is the authoritative doctrine. All 7 journaled trades to date follow this exact playbook.

## 1. Setup

- **Instrument:** XAUUSD
- **Execution TF:** 5m (primary)
- **Context TFs:** 15m, 1H (mandatory for bias and structure)
- **Direction:** trade in the direction HTF bias favors
- **Activation:** discretionary — the trader identifies a valid structural level on the chart

## 2. Entry

Buy or sell at a structural level identified on the chart, aligned with HTF (1H) bias.

The structural level is whatever the trader recognises as a valid entry zone — supply OB, demand OB, swept liquidity + reclaim, retest of broken structure, range retest, etc. The strategy does not prescribe which structure to use; it prescribes how to size, place stops, and take profit once an entry is identified.

**Requirement:** the structure must give a definable invalidation level (where SL goes). If you can't anchor SL to structure, no trade.

## 3. Stop Loss — defines 1R

SL goes beyond the structural level plus a small buffer (typically 2–5 pts on XAUUSD).

**The distance from entry to SL is the 1R reference unit for this trade.**

Observed range across 7 journaled trades: 5 pts (tightest) to 25 pts (widest). The strategy does not impose a min/max SL distance — it adapts to the structure.

## 4. Take Profit — Mechanical 1R / 2R / 3R Ladder

Three targets, computed mechanically from entry and SL distance:

| Target | Formula |
|---|---|
| **TP1** | Entry ± 1R |
| **TP2** | Entry ± 2R |
| **TP3** | Entry ± 3R |

TPs are not anchored to chart levels. They are pure RR multiples. Sometimes TP3 happens to land at a structural level (prior swing extreme, range high/low) — that's geometry, not placement.

## 5. Position Management — Thirds

Size in thirds. Close 1/3 of the position at each TP fill.

- **At TP1 fill:** close 1/3. (Optional: move SL to BE for the remaining 2/3.)
- **At TP2 fill:** close 1/3.
- **At TP3 fill:** close the final 1/3.

**Blended R outcomes:**

| Scenario | Realized R |
|---|---|
| TP1 only, then SL on remaining | (1/3 × 1R) + (2/3 × –1R) = **–0.33R** |
| TP1 + TP2, then SL on remaining | (1/3 × 1R) + (1/3 × 2R) + (1/3 × –1R) = **+0.67R** |
| TP1 + TP2 + TP3 (all fill) | (1+2+3) / 3 = **+2.0R** |
| SL hit before any TP | **–1.0R** |

When BE move is used after TP1 (recommended), the worst-case after TP1 fill is –0.0R on remaining = +0.33R blended.

## 6. Sessions

**Any session.** No restriction. Observed entries across the 7 trades: NY-AM, transition, off-session (Asia pre-London).

## 7. News

**Trader-managed.** Deterministic news gate is disabled (2026-05-21). The trader is responsible for situational awareness around high-impact USD/Gold events.

## 8. Risk per trade

**1% of equity (DEMO phase).** Position size = whatever quantity produces a –1% equity loss at SL.

Graduation criteria (DEMO → LIVE):
- ≥30 resolved Migs trades
- WR ≥40%
- ≥+10R cumulative

## 9. Grade / acceptance

The strategy doesn't use a 0–18 rubric. Acceptance is binary:

| Check | Pass condition |
|---|---|
| **Direction matches HTF bias** | 1H bias agrees with trade direction |
| **Structural entry level** | Entry anchored to a visible chart feature (OB, sweep, broken structure, etc.) |
| **Definable SL** | SL has a structural anchor; 1R distance computable |
| **TP3 has runway** | No major opposing DOL inside the 3R distance that would block TP3 |
| **No erratic candles in last 4 bars** | Volatility check |
| **Extraction confidence ≥0.6** | LLM read of the chart is clear, not ambiguous |

Any fail → NO TRADE.

## 10. Signal output format

```
XAUUSD — [BUY/SELL] · Migs Hybrid
Entry:   [price]
SL:      [price]   (1R = [X] pts)
TP1:     [price]   (+1R)
TP2:     [price]   (+2R)
TP3:     [price]   (+3R)
Structure: [one line on what structural level anchors the entry]
HTF bias:  [bullish | bearish] (1H)
Size:      1/3 / 1/3 / 1/3 (thirds at each TP)
Phase:     DEMO (1% risk)
```

## 11. Journal entry format

`journal/YYYY/MM/NNNN-YYYY-MM-DD-[buy|sell|no-trade].md` with the schema currently used in journals 0004–0007. Key fields:

- `direction`, `entry`, `sl`, `tp1`, `tp2`, `tp3`
- `risk_pips`, `tp1_rr`, `tp2_rr`, `tp3_rr` (always 1.0 / 2.0 / 3.0)
- `outcome` (TP1_HIT / TP2_HIT / TP3_HIT / SL_HIT / BE / OPEN)
- `r_realized` (blended R per partial-fill table above)
- `mfe_r`, `mae_r`
- `htf_bias_1h`
- `chart_features` (structural levels visible at entry)
- `screenshot_path`

## 12. Open questions (pending more data)

- **Pip convention:** SL distances reported as "price units" — should the canonical pip be 1.0 (1 price unit) or 0.10 (MT5 5-digit default)? Affects downstream pip-based stats only; R-based stats are unaffected.
- **BE rule:** is SL→BE after TP1 mandatory or discretionary? Reference trades varied.
- **Re-entry after SL:** are re-entries on the same structural level allowed in the same session? No data yet.
- **Concurrent positions:** more than one Hybrid trade open at a time — allowed? No data yet.

These get resolved at weekly review as more closed trades come in.

## 13. Strategy track record (through trade #7, 2026-05-22)

| Metric | Value |
|---|---|
| Resolved trades | 7 |
| Wins | 5 |
| Losses | 2 |
| WR | 71% |
| Total R | +10R (or +8R blended if all winners used thirds) |
| Avg R per trade | +1.4R |
| Graduation progress | 7 / 30 |

## 14. Hard rules (non-negotiable)

1. **Never invent levels.** Every OB / structure / DOL you claim must trace to a visible feature on the chart. If you can't anchor it, it doesn't exist.
2. **Two-pass chart reading.** First extract observable primitives (JSON). Then reason over the JSON. Don't re-look at the chart during reasoning for new features.
3. **One strategy.** This is the Migs Hybrid. There are no other Migs strategies. Don't invent setup types.
4. **Pattern WR gate.** If `patterns/stats.json` shows the direction (BUY or SELL) with ≥5 closed trades AND WR <40%, emit NO TRADE for that direction.
5. **One signal per invocation.** Fresh context every time. Persist learning to files, not chat history.
6. **No outside patterns.** Doctrine evolves only from journaled trade data. Never seed sub-patterns, rules, or doctrine tweaks from training-data priors.
