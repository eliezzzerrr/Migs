# Checklists — Migs Hybrid Strategy

## Binary acceptance (mirrors `migs-hybrid-strategy.md` §9 — authoritative source)

ALL must pass before a trade is permitted. Any failure ⇒ NO TRADE.

| # | Check | Pass condition |
|---|---|---|
| 1 | **Direction allowed by HTF bias** | 1H bias agrees with trade direction (or 1H ranging, per pine gate defaults) |
| 2 | **Structural entry level** | Entry anchored to a visible BOS→OB retest (the pine's sequence) |
| 3 | **Definable SL** | SL = OB edge + 0.45×ATR buffer; 1R computable (≥$4 natural, $11.5 clamp) |
| 4 | **TP2 has runway** | No major opposing 1H/4H level inside the 2R distance that would block TP2 |
| 5 | **No erratic candles in last 4 bars** | Volatility check |
| 6 | **Extraction confidence ≥0.6** | LLM read of the chart is clear, not ambiguous |

When this checklist passes, the trade is taken. The 12-point rubric in `doctrine/grading-rubric.md` then assigns a quality letter (A+ → F) for the journal — it does not veto.

## Killflags (any one = NO TRADE, regardless of checklist)

- ~~High-impact USD/Gold news within ±30 min~~ **DISABLED 2026-05-21** — trader-managed
- Weekend (Sat 2 AM PHT onward) / Sunday open
- Erratic candles in last 4× 15m candles (also surfaced as binary check #5)
- Outside the London killzone 13:30–20:00 PHT Tue–Fri (pine session defaults, 2026-06-10)
- Chart resolution too low / key levels off-screen
- 1H bias not visible and not confidently inferable
- LLM confidence <0.6 in extracted chart features (also surfaced as binary check #6)

## Journal-grade modifier

| Modifier | Effect |
|---|---|
| 3rd+ consecutive Migs loss (from `patterns/stats.json`) | –1 letter on the journal grade (rubric only — does not veto) |

See `doctrine/grading-rubric.md` for the 12-point scoring table and letter-grade ladder.

## Rewrite history

- **2026-05-22:** rewrite from 7-point checklist. Old version required FVG presence, mandatory 5m BOS, DOL ≥100 pip floor, and session restriction (London / NY-AM / Transition only) — all removed by the unified-strategy consolidation. The 6 binary checks here mirror `migs-hybrid-strategy.md` §9 verbatim; if §9 changes, update both.
