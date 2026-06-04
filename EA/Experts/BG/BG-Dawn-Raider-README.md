# BG Dawn Raider 5m — MT5 Expert Advisor

A **new, standalone** XAUUSD strategy — unrelated to `BG-Golden-Signal-5m.mq5`. It trades an
**HTF-bias + confirmed Asian-range breakout** on the 5m chart, during the London-open window, in the
Asian session (PHT) to dodge NY red-folder news.

> **Status: v0.1.0 — forward-test build. Compiles clean (0 errors).**
> Every rule traces to [`docs/research/2026-06-03-xauusd-asian-htf-5m-deep-research.md`](../../../docs/research/2026-06-03-xauusd-asian-htf-5m-deep-research.md).
> **There is no gold-specific backtest of this design** — performance numbers in the research are
> borrowed from oil/equities/trend-following. This is a **hypothesis to forward-test in DEMO**, not a
> validated edge. The built-in CSV log exists to produce the missing gold numbers.

## How it trades (times = PHT / GMT+8)

1. **HTF bias** — EMA(`20`)/EMA(`50`) stack + close gate on **H1 *and* H4** (both must agree). An
   **ADX(`14`) ≥ `22`** regime gate on H1 must also hold. Ranging or low-ADX ⇒ **no trade**.
2. **Asian box** — track the Tokyo high/low over the **range window `08:00–15:00`**.
3. **Execution** — only inside the **exec window `15:00–17:00`** (London open; still before NY news).
4. **Entry (gold variant, `RETEST`)** — a 5m **body close** beyond the box on the bias side, **then a
   pullback that retests and holds** the level. `InpEntryMode=RAW` enters on the breakout close instead.
5. **Stop** — beyond the retest swing ± `0.3×ATR`, floored at `InpMinStopUSD` ($3). Defines 1R.
6. **Management** — SL→**break-even at +1R**, then **ATR-trail** (`2.5×ATR`) the runner. No fixed TP by
   default (ride the trail). *(BE-at-1R replaces a "partial at 1R" because a 0.01-lot position is indivisible.)*
7. **Caps** — ≤ **3 trades/day** + a **−2R daily kill**.
8. **News** — blocks new entries ±15 min around **USD/EUR/GBP** high-impact events (calendar live, CSV in tester).

## Install

1. **Copy into MT5:** `File → Open Data Folder` → drop `BG-Dawn-Raider-5m.mq5` into `MQL5\Experts\BG\`.
2. **Compile:** MetaEditor (F4) → open the file → **F7** (0 errors; one cosmetic version warning).
3. **Attach:** **XAUUSD, M5 chart** → drag from Navigator → enable *Allow live trading*. (Algo Trading lit.)

## ⚠️ CRITICAL first step — calibrate the clock

The whole strategy is session-timed, so the broker server offset **must** be right:

- Set **`InpServerGMTOffset`** to your broker's server UTC offset (GMT+3 broker → `3`, GMT+2 → `2`, UTC → `0`).
- **Calibrate on the panel:** it shows live **MT5 time** and **Manila time** — nudge `InpServerGMTOffset`
  until the Manila clock matches real Manila. If it's wrong, the box/exec windows shift and it won't trade right.

## Key tunables (all defaults are starting points — optimize in DEMO)

| Input | Default | Why it matters |
|---|---|---|
| `InpEntryMode` | `RETEST` | **The big A/B test:** RETEST vs RAW. Research couldn't settle which is better for gold. |
| `InpHTFFastEMA` / `InpHTFSlowEMA` | 20 / 50 | HTF bias sensitivity (on H1 & H4). |
| `InpADXMin` | 22 | Regime gate. Higher = only stronger trends (research: edge lives in high-vol). |
| `InpRangeWindow` / `InpExecWindow` | 08:00-15:00 / 15:00-17:00 | Box build vs execution (PHT). |
| `InpRetestTolATR` / `InpRetestMaxBars` | 0.5 / 8 | How strict/patient the retest is. |
| `InpSLBufferATR` / `InpMinStopUSD` | 0.3 / 3.0 | Stop tightness. |
| `InpMoveBEAtR` / `InpTrailATRmult` | 1.0 / 2.5 | The expectancy engine — when to go risk-free, how loose to trail. |
| `InpFinalTPR` | 0 (ride) | Set >0 to cap winners at a fixed R instead of trailing. |
| `InpMaxTradesPerDay` / `InpDailyMaxLossR` | 3 / 2.0 | Throttle + daily kill. |

## The DEMO test plan (what this build is FOR)

Each closed trade appends a row to **`MQL5\Files\BGDR\bgdr_trades.csv`** with:
`open/close (UTC), dir, mode, bias, ADX, box hi/lo/size, entry, SL, risk$, exit, R, MFE(R), outcome`.

That CSV answers the research's open questions directly:
1. **Real gold WR / expectancy / max losing streak** for this design.
2. **RAW vs RETEST** — run a stretch on each, compare expectancy.
3. **Target management** — `MFE(R)` tells you how far winners ran vs where you exited (trail too tight? cap too low?).

## Known limitations

- **Unproven on gold** — forward-test before trusting; small sample early.
- **Account size:** at ~$369, 0.01 lots already over-risks 1% on gold. The EA **warns** in the log and
  caps at min lot; consider funding more or a cent account before going live.
- **News filter fails *open*** (allows trading) if the broker's calendar API errors — by design, so a
  calendar outage doesn't silently halt all trading. The exec window already avoids US news.
- **In-memory state:** restarting the EA with a position open won't re-adopt it for BE/trail (the broker
  SL still protects it). Avoid restarting mid-trade.
- **Single position**, sequential up to 3/day. No concurrent trades.
