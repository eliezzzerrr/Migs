# Migs Hybrid — TradingView Pine Script v6 (Indicator)

Single-file Pine Script v6 **indicator** mirroring the MT5 EA. Works on any symbol, any timeframe (designed for M5 execution, H1 bias). Full on-chart display including session boxes (Asia / London / NY-AM) with H/L markers.

Visualizes setups and simulated trades — does NOT place orders. Use alerts to drive webhooks for live trading.

## Install

1. Open the chart in TradingView for your symbol.
2. Set the timeframe to **5m**.
3. Open `Pine Editor` at the bottom of the chart.
4. Open `Migs-Hybrid-v6.pine`, copy all contents, paste into the editor.
5. Click `Save`, name it (e.g. "Migs Hybrid Indicator"), then `Add to chart`.
6. Adjust inputs (especially `Session timezone`) to match your trading day.

## What's on the chart

| Element | When | How |
|---|---|---|
| **Session boxes** | Always (toggleable) | Asia (blue), London (red), NY-AM (teal) — semi-transparent rectangles with large watermark labels inside |
| **Session H/L labels** | After a session closes | `AS.H`/`AS.L`, `LO.H`/`LO.L`, `NYAM.H`/`NYAM.L` at the session extremes |
| **Session H/L lines** | After a session closes (toggleable) | Horizontal lines extending right at session high/low until the next same-type session begins |
| **OB box** | Whenever a fresh BOS triggers an OB | Semi-transparent rectangle, green = demand, red = supply |
| **BOS triangle** | On every confirmed bull/bear BOS bar | ▲ below bar (bull) / ▼ above bar (bear) |
| **Entry line** | While a simulated trade is open | Gray dashed horizontal |
| **SL line** | While a simulated trade is open | Red solid (turns cyan when moved to BE after TP1) |
| **TP1/TP2/TP3 lines** | While a simulated trade is open | Green solid; TP1 fades to gray once filled |
| **R-value labels** | On TP lines | `TP1 +1R`, `TP2 +2R`, `TP3 +3R` (toggle in Display group) |
| **Status table** | Always | Corner panel with state, current session, bias, ADX, chop, sim trade count + WR + R |

## Session boxes (matching the screenshot)

Defaults (in your selected `Session timezone`):

| Session | Window | Color | Labels |
|---|---|---|---|
| **Asia** | 00:00 – 07:00 | Light blue | `AS.H` / `AS.L` |
| **London** | 07:00 – 10:00 (Migs window) | Light red/pink | `LO.H` / `LO.L` |
| **NY-AM** | 12:30 – 15:30 (Migs window) | Mint teal | `NYAM.H` / `NYAM.L` |

While a session is active, the box grows in both width (each new bar) and height (tracking new H/L). When the session closes:
- H/L price labels are placed at the session start anchor
- Horizontal lines extend rightward at the H and L prices (toggle off via `Extend session H/L lines right`)
- The session's large watermark label ("Asia"/"London"/"NYAM") stays inside the box for reference

Lines persist until the next occurrence of the same session, at which point the old objects are deleted and fresh ones drawn.

Timezone is configurable: `UTC`, `America/New_York`, `Europe/London`, `Asia/Tokyo`, `Asia/Manila`, `Australia/Sydney`. Session-window strings can be edited directly to change times.

## Status table

```
MIGS HYBRID         INDICATOR v6
State               READY | SETUP | IN-LONG (sim) | IN-SHORT (sim) | COOLDOWN
Symbol              SYMBOL TF
Session             Asia | London | NY-AM | off-session
1H Bias             bullish | bearish | ranging
ADX(15)             24.3   (red if below threshold)
ATR ratio           1.04   (red if in squeeze)
Chop                OK | <reason>
Sim trades          12  W:9 L:3
Sim WR              75.0%
Sim total R         +18.50R
Day R               +2.00R

[when in sim trade]
Dir                 BUY | SELL
Entry               x.xxxxx
SL (BE)             x.xxxxx
TP1 ✓               x.xxxxx
TP2                 x.xxxxx
TP3                 x.xxxxx

[when idle]
Last bull BOS       12 bars ago
Last bear BOS       45 bars ago
```

## Strategy logic (mirrors the MT5 EA)

1. **M5 BOS detection** — close beyond the latest `i_swing_len`-strength pivot
2. **OB identification** — last opposite-color candle within `i_ob_age` bars before BOS
3. **HTF bias** — EMA20 vs EMA50 + close-vs-EMA20 on the `i_h1_tf` timeframe (default 60m)
4. **Entry proximity** — current price must be within `i_entry_atr × ATR` of the OB edge
5. **Chop filter** — strict H1 bias, ADX minimum, opposite-BOS whipsaw, ATR squeeze
6. **SL** — beyond OB edge + `i_sl_buf × ATR` buffer. Distance = 1R.
7. **TP ladder** — entry ± 1R / 2R / 3R (mechanical)
8. **Sim trade tracking** — when setup fires, project entry/SL/TPs, monitor price for TP1 fill (BE move) and TP3/SL close
9. **Outcome math** — TP3 reached = +2.0R blended (thirds with BE on remainders), SL before TP1 = –1.0R, SL after TP1 = +0.33R

## Input groups

- **Structure Detection** — swing strength, BOS/OB max age, entry proximity ATR, SL buffer
- **HTF Bias** — timeframe, fast/slow EMA, require-agreement toggle
- **Chop Filter** — toggle, strict H1, ADX, BOS conflict, ATR expansion
- **Simulated Trades** — track sim trades on/off, BE move toggle, cooldown
- **Session Boxes** — show toggle, timezone, three session windows, extend H/L lines, label size
- **On-Chart Display** — table position, what to draw, R-labels
- **Colors** — accents for BUY/SELL/OB/BE plus all three session fill/text colors

## Alerts

Six alert conditions are wired in. Right-click chart → Add Alert → Condition = "Migs Hybrid v6":

- `Migs BUY setup` — all filters passed, BUY-side opportunity
- `Migs SELL setup` — all filters passed, SELL-side opportunity
- `Sim LONG opened` — same as BUY setup but fires only when the simulated trade actually opens (respects cooldown)
- `Sim SHORT opened` — same as SELL setup but on actual sim open
- `Bullish BOS` — raw structure event (no filters)
- `Bearish BOS` — raw structure event (no filters)

For live trading via webhooks, set the alert message to your broker's JSON spec, e.g. for Bybit/Binance:
```json
{"side":"buy","symbol":"{{ticker}}","entry":{{close}}}
```
and route the alert webhook to your bridge service.

## Differences from the MT5 EA

| Item | MT5 EA | Pine v6 Indicator |
|---|---|---|
| Order placement | Yes (live or demo) | No — visualization + alerts only |
| HTF bias method | Last H1 BOS direction | H1 EMA20/50 crossover + close vs EMA20 |
| Position management | 3 separate MT5 positions, same magic | 3-position thirds simulated; outcome computed when TP3/SL hit |
| Journal | Writes markdown to `MQL5/Files/` | Sim stats kept in memory + alerts |
| Lot/qty sizing | `tick_value` / `tick_size` math | N/A — no real orders |
| Daily kill | `g_day_kill` state | `day_r_now` computed from sim outcomes since midnight |
| Status display | OBJ_LABEL panel | `table` cells |
| Session boxes | N/A | Asia / London / NY-AM with H/L lines |

Strategically identical signal logic: same BOS → OB → bias-aligned → chop-filtered → 3-TP thirds ladder.

## Known limitations

- **Pine has no concept of "current account"** — sim P&L is fractional R, not currency. Connect to a broker via webhook for real execution.
- **Symbol-agnostic but tuned for liquid markets**. Exotic symbols with weird tick sizes may need ATR/proximity tweaks.
- **HTF bias proxy via EMAs is not identical to the EA's BOS-based bias**. Generally directionally similar.
- **Repainting**: structure detection uses pivots which require `i_swing_len` bars of confirmation. Setups confirm at bar close.
- **Session boxes use bar timestamps**: if your data is gappy (e.g. crypto exchange downtime), boxes may have visual gaps.
