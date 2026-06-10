# Migs Hybrid Strategy — XAUUSD (BG Golden 15m SMC)

One strategy. Two directions (BUY, SELL). Same management every trade.

> **SOURCE OF TRUTH (2026-06-10):** `TradingView/BG-Golden-Signal-15m-SMC.pine` is the canonical
> definition of this strategy. This doctrine, the `migs-trader` agent, and the MT5 EA all conform
> to the pine's literal input defaults. When they disagree, the pine wins — update the downstream
> file, never the pine. (The pine is only changed by explicit trader decision, on data.)

This is the authoritative doctrine for discretionary execution. It mirrors the pine engine.

## 1. Setup

- **Instrument:** XAUUSD
- **Execution TF:** 15m (the pine's chart TF)
- **Context TF:** 1H (EMA 12/80 bias — the pine's HTF gate; counter-trend blocked when gate on, ranging allowed)
- **Direction:** trade in the direction HTF bias allows
- **Activation:** the pine's structural sequence (below), executed manually or by the EA

## 2. Entry — BOS → OB retest (the pine's engine)

The canonical entry is the pine's sequence:

1. **BOS** — a transition break of the last swing (pivot strength 1): close beyond the swing while the prior close wasn't. BOS stays valid for ≤20 bars.
2. **OB** — the last opposite-colour candle within 40 bars before the break, anchored when the BOS fires.
3. **Retest** — price returns to within **0.4 × ATR(14)** of the OB edge, evaluated at bar close.

All three at a qualifying bar close, inside an enabled killzone, with the bias gate satisfied → entry at that close. One trade per OB (no same-OB re-entry).

**Requirement:** the OB gives the invalidation level (where SL goes). No anchorable OB, no trade.

## 3. Stop Loss — defines 1R

SL goes beyond the OB edge plus **0.45 × ATR(14)** buffer (the pine's `i_sl_buf`).

- **Min-SL clamp $11.5:** if the natural OB stop is tighter, widen to $11.5 (trade still fires).
- **Min-SL filter $4:** if the natural stop is under $4, skip the trade entirely (all-spread setups).

**The distance from entry to SL is the 1R reference unit for this trade.**

## 4. Take Profit — Mechanical 1R / 2R / 3R Ladder

Three targets, computed mechanically from entry and SL distance:

| Target | Formula |
|---|---|
| **TP1** | Entry ± 1R |
| **TP2** | Entry ± 2R |
| **TP3** | Entry ± 3R |

TPs are not anchored to chart levels. They are pure RR multiples. Sometimes a TP happens to land at a structural level (prior swing extreme, range high/low) — that's geometry, not placement.

## 5. Position Management — Full size, TP2 final (pine defaults)

**Full position size rides to TP2.** No partials, no thirds. TP1 is informational (it marks +1R progress and feeds the panel's outcome anatomy); TP3 is off by default.

**R outcomes (default config):**

| Scenario | Realized R |
|---|---|
| TP2 fills | **+2.0R** |
| SL hit first | **–1.0R** |

Optional management toggles exist in the pine/EA (BE after TP1, TP1-lock after TP2, TP3 with trail) — all **off by default**. Enabling any of them is a strategy change: test it in the sim first, then flip the pine default, then sync downstream.

> *Historical note:* the doctrine prescribed thirds management (1/3 at each TP, blended +2R) through
> 2026-06-10. Superseded by the pine's full-size/TP2-final model when the pine became source of truth.
> Old journal entries with blended R stay as recorded.

## 6. Sessions — London killzone only

**London killzone, 13:30–20:00 PHT (GMT+8), Tuesday–Friday.** No other sessions.

Asia (08:00–13:00) and all NY killzones are **disabled** as of 2026-06-10 — session-stats analysis over 182 sim trades showed Asia entries ≈ breakeven churn (Asia→in-Asia bucket: 34% of all trades at 34% WR) while London entries carried the system. The killzone windows live in the pine's session inputs; if the pine changes, this section follows.

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
| **Direction allowed by HTF bias** | 1H bias agrees with trade direction (or 1H is ranging — counter-trend only with the gate off, per pine defaults) |
| **Structural entry level** | Entry anchored to a visible BOS→OB retest (the pine's sequence) |
| **Definable SL** | SL = OB edge + 0.45×ATR buffer; 1R distance computable (≥$4 natural, clamped to $11.5 min) |
| **TP2 has runway** | No major opposing 1H/4H level inside the 2R distance that would block TP2 |
| **No erratic candles in last 4 bars** | Volatility check |
| **Extraction confidence ≥0.6** | LLM read of the chart is clear, not ambiguous |

Any fail → NO TRADE.

## 10. Signal output format

```
XAUUSD — [BUY/SELL] · Migs Hybrid (BG Golden 15m SMC)
Entry:   [price]
SL:      [price]   (1R = [X] pts)
TP1:     [price]   (+1R, informational)
TP2:     [price]   (+2R — FINAL target, full size exits here)
Structure: [one line: the BOS and the OB anchoring the entry]
HTF bias:  [bullish | bearish | ranging] (1H)
Killzone:  London [time] PHT
Size:      full position to TP2
Phase:     DEMO (1% risk)
```

## 11. Journal entry format

`journal/YYYY/MM/NNNN-YYYY-MM-DD-[buy|sell|no-trade].md` with the schema currently used in journals 0004–0007. Key fields:

- `direction`, `entry`, `sl`, `tp1`, `tp2`, `tp3`
- `risk_pips`, `tp1_rr`, `tp2_rr`, `tp3_rr` (always 1.0 / 2.0 / 3.0)
- `outcome` (TP1_HIT / TP2_HIT / TP3_HIT / SL_HIT / BE / OPEN)
- `r_realized` (+2.0 on TP2 / −1.0 on SL under the default config; legacy entries may carry blended thirds values)
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
