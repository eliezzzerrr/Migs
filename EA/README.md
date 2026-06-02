# BG Golden 5m — MT5 Expert Advisor

Single-file MT5 EA that is a **Pine-parity port of `TradingView/BG-Golden-Signal-5m.pine`** (v6).
It executes the BG Golden Signal 5m engine: **M5 BOS → order-block retest** with an optional HTF
bias gate, a mechanical **TP1/TP2/TP3 = +1R/+2R/+3R** ladder, and an optional SL-trail chain.

> **Goal:** ≥95% backtest agreement with the TradingView indicator. Every behavioural rule
> here is copied from the pine — none are invented. See the `// Pine i_*` comment on each input.

## Status

**Version 0.8.0 — Pine-parity + BG rebrand.** Internals renamed Migs→BG (copyright, panel, struct,
logs, journal dir, `strategy:` tag). Defaults are aligned to the **live `BG-Golden-Signal-5m` "v3"
chart**:

- **HTF bias gate OFF** (`InpRequireHTF=false`) — validated best on XAUUSD 5m (no-gate `+40R / 55.9% WR`
  vs match-only `+12R / 50% WR`, 2026-05-26). HTF timeframe **H2**, EMA 12/80. Two sub-toggle inputs
  reproduce the pine's composable gate exactly when you turn it on.
- **Min-SL clamp $10**, filter $4, cooldown **12 bars**.
- **Sessions (GMT+8):** Asia **Mon–Fri** + London **Mon & Wed**. NY AM/Lunch/PM are enabled-but-idle
  in the pine (all weekdays off) so they never trade — left **off** in the EA (same net behaviour).

## Install

1. **Copy the file into MT5.** In MT5: `File → Open Data Folder`, then:

   ```
   <Data Folder>/MQL5/Experts/…/BG-Golden-Signal-5m.mq5   ← from EA/Experts/BG/
   ```

2. **Compile.** Open MetaEditor (F4), open `BG-Golden-Signal-5m.mq5`, press **F7**. Compiles clean
   with 0 errors (standard `<Trade\*.mqh>` library only — no external includes).

3. **Attach to chart.** **XAUUSD, M5 timeframe** → drag the EA from Navigator → Common tab:
   enable *Allow live trading* → OK. Confirm *Algo Trading* is lit in the MT5 toolbar.

4. **(Optional) Journal.** First run creates `MQL5/Files/BG/journal/` automatically; each opened
   trade gets a markdown entry that is back-filled with the outcome when it closes.

## How it trades

On every **new M5 bar** (signal logic is gated to bar close, mirroring Pine `barstate.isconfirmed`):

1. **Swings** — `ta.pivothigh/pivotlow(1,1)` fractals track the last swing high/low.
2. **BOS** — a *transition* break: `close > last_high AND prev_close ≤ last_high` (or the bear mirror).
   The active BOS persists and **ages out by bar count** after `InpBOSAge` bars.
3. **OB** — re-anchored **only when a fresh BOS fires**: the last opposite-colour candle within
   `InpOBAge` bars before the break.
4. **HTF bias** (optional) — EMA(`12`)/EMA(`80`) + close gate on the **previous closed H2 bar**
   (non-repaint). Composable: `match` and/or `range` allowed; counter-trend always blocked when
   the gate is on. **OFF by default.**
5. **Proximity** — price must be within `InpEntryATR × ATR` of the OB edge.
6. **SL** — beyond the OB edge ± `InpSLBufATR × ATR`. This distance **defines 1R**.
   - **Min-SL filter** (`InpMinSLFilter`, default $4): *reject* the setup if the natural OB SL is tighter.
   - **Min-SL clamp** (`InpMinSLClamp`, default $10): *widen* the SL to this floor if it's still tighter (trade still fires).
7. **TP1/TP2/TP3** = entry ± 1R/2R/3R.
8. **One position, full size, rides to the highest enabled TP.** No thirds, no partials.
   With the defaults (TP2 on, TP3 off) the trade exits at **+2R**.
9. **Optional SL-trail chain** — BE after TP1, TP1 after TP2, BE after TP2, or TP2 after TP3 (ride
   past TP3). An SL hit **while trailed** (eff R ≥ 0) is booked as a **win**; only an untrailed stop is a loss.
10. **Logs** the outcome to the journal when the position closes.

### Realized R (default config: TP2 final, no trailing)

| Scenario | Realized |
|---|---|
| Price reaches TP2 | **+2.0R** |
| SL hit first | **−1.0R** |

Enable `InpUseTP3` / the move-SL toggles to reshape this exactly as the pine's TP and trail inputs do.

## Input parameters (defaults = live v3 chart)

### Structure Detection (`g_struct`)
| Input | Default | Pine | Notes |
|---|---|---|---|
| `InpSwingLen` | 1 | `i_swing_len` | Pivot strength (bars L/R) |
| `InpBOSAge` | 30 | `i_bos_age` | Max BOS age in bars |
| `InpOBAge` | 60 | `i_ob_age` | Max OB lookback in bars |
| `InpEntryATR` | 0.9 | `i_entry_atr` | Entry proximity × ATR |
| `InpATRPer` | 15 | `i_atr_per` | ATR period |
| `InpSLBufATR` | 0.10 | `i_sl_buf` | SL buffer × ATR beyond OB |
| `InpMinSLClamp` | **10.0** | `i_min_sl` | Widen SL to this $ floor |
| `InpMinSLFilter` | 4.0 | `i_min_sl_flt` | Reject setup if natural SL < this $ |

### HTF Bias (`g_htf`)
| Input | Default | Pine | Notes |
|---|---|---|---|
| `InpRequireHTF` | **false** | `i_req_h1` | Master gate — OFF is validated-best on 5m |
| `InpHTFAllowMatch` | true | `i_h1_allow_match` | When ON: LONG in bull / SHORT in bear |
| `InpHTFAllowRange` | true | `i_h1_allow_range` | When ON: trade during HTF ranging |
| `InpHTFTimeframe` | **H2** | `"120"` | Bias timeframe (live v3 chart) |
| `InpHTFFastEMA` | 12 | `i_h1_fast` | |
| `InpHTFSlowEMA` | 80 | `i_h1_slow` | |

> Counter-trend is **always** blocked when `InpRequireHTF` is on, regardless of the sub-toggles.
> Untick `InpHTFAllowRange` for the pine's strict match-only mode.

### Trade Setup (`g_sim`)
| Input | Default | Pine | Notes |
|---|---|---|---|
| `InpEnableTrade` | true | `i_sim_on` | Master kill switch |
| `InpMaxPositions` | 1 | `i_max_pos` | Concurrent trades (>1 needs a hedging account) |
| `InpUseTP2` | true | `i_use_tp2` | +2R target (final TP by default) |
| `InpUseTP3` | false | `i_use_tp3` | +3R target |
| `InpMoveBE` | false | `i_move_be` | SL → BE after TP1 |
| `InpMoveTP1AfterTP2` | false | `i_move_tp1` | SL → TP1 (+1R lock) after TP2 |
| `InpMoveBEAfterTP2` | false | `i_move_be2` | SL → BE after TP2 |
| `InpMoveTP2AfterTP3` | false | `i_move_tp2` | SL → TP2 after TP3 (ride past TP3) |
| `InpCooldownBars` | 12 | `i_cooldown` | Bars to wait after the bench empties |

### Risk Sizing
| Input | Default | Notes |
|---|---|---|
| `InpRiskPercent` | 1.0 | % equity risked per trade (when `InpUseFixedLots=false`) |
| `InpUseFixedLots` | false | ON = trade a fixed lot size; OFF = size by % risk |
| `InpFixedLots` | 0.10 | Fixed lot size when `InpUseFixedLots=true` |
| `InpMaxLots` | 100.0 | Safety cap; broker max still overrides |

### Session Filter (`g_sess`, GMT+8 — live v3 chart)
| Input | Default | Notes |
|---|---|---|
| `InpUseSessions` | true | Master session toggle |
| `InpServerGMTOffset` | 0 | **Your broker's server-clock UTC offset** (GMT+3 → 3, GMT+2 → 2, UTC → 0). Calibrate via the panel's Manila clock |
| `InpSessionGMTOffset` | 8 | Timezone the session strings are written in (GMT+8 Manila) — leave at 8 |
| `InpUseAsia` / `InpAsiaSession` | true / `08:00-12:00` | Asia killzone (Mon–Fri; no weekend gold bars) |
| `InpUseLondon` / `InpLondonSession` | true / `14:00-17:00` | London **ENABLED** |
| `InpLondonDowMon … Sun` | **Mon+Wed on** (Sat/Sun ticked, inert) | Per-day London gate (Pine `i_london_dow_*`); weekday read in GMT+8 |
| `InpUseNYAM` / `InpNYAMSession` | false / `21:30-23:00` | Pine enables it but with all days off (idle); left off here |
| `InpUseNYLunch` / `InpNYLunchSession` | false / `00:00-01:00` | idem |
| `InpUseNYPM` / `InpNYPMSession` | false / `01:30-04:00` | idem |

> **⚠️ Broker server time (handled in v0.8.0).** MT5's server clock usually isn't UTC. Set
> **`InpServerGMTOffset`** to your broker's offset (GMT+3 → `3`, GMT+2 → `2`, UTC → `0`); the EA
> converts server → UTC → GMT+8 so the session windows and the London DoW gate land correctly.
> **Calibrate on the on-chart panel:** it shows live **MT5 time** and **Manila time** — nudge
> `InpServerGMTOffset` until the Manila clock matches real Manila. (The Experts log also prints a
> detected offset on init, live only.)
>
> **DoW filter** is wired for **London** only. Asia runs Mon–Fri (no weekend gold bars, so its
> chart-side Sat/Sun-off makes no difference). NY DoW isn't wired — those sessions are off; ask if
> you want them.

### Date Range (`g_dates`)
| Input | Default | Notes |
|---|---|---|
| `InpUseLast30Days` | true | Pine `i_use_last30`. Effectively a **no-op in the EA** (it compares each bar to `TimeCurrent()−30d`, i.e. itself, so it always passes) — the **Strategy Tester's own date range bounds the run**, not this input. Harmless to leave on. |
| `InpUseLast7/14/60Days`, `InpUseCustomDates` | false | Priority: 7 > 14 > 30 > 60 > custom |

### Trade Management / Safety / Journal / Logging / Panel
| Input | Default | Notes |
|---|---|---|
| `InpMagic` | 20260522 | EA magic number |
| `InpSlippagePoints` | 30 | Allowed deviation on market orders |
| `InpDailyMaxLossR` | 5.0 | Soft daily kill switch in R (0 = off; UTC day) |
| `InpEnableJournal` | true | Write markdown journal entries |
| `InpJournalDir` | `BG\journal` | Relative to `MQL5\Files` |
| `InpVerbose` | true | INFO logs to the Experts tab |
| `InpShowPanel` | true | On-chart status panel (+ colour/position inputs) |

## Known MT5 ↔ Pine divergences (≤5% expected backtest delta)

1. **Fill model** — Pine simulates fills against bar HIGH/LOW; MT5 fills on tick. Same-bar TP+SL
   races can resolve differently.
2. **Entry price** — Pine enters at bar close; MT5 enters at market on the next tick. Small slippage per entry.
3. **Costs** — Pine ignores spread/commission/swap; MT5 books them.
4. **SL broker-attached, TP managed internally** — so the position can ride past TP3 when
   `InpMoveTP2AfterTP3` is on. If the EA disconnects, the position rides on its broker SL only.
5. **TP detection** uses the last *closed* bar's H/L (entry is bar-gated too), so an intrabar TP
   touch is recognized one bar later than a live pine chart would show it. The broker SL still fires intrabar.
6. **NY sessions** — the pine enables NY AM/Lunch/PM with all weekdays off (idle); the EA keeps
   them disabled. Net trades are identical (Asia + London Mon/Wed). If you ever tick an NY weekday
   on the chart, the EA needs NY DoW inputs added to match.

## Backtesting

- Strategy Tester: XAUUSD, M5, *Every tick based on real ticks* for the most faithful TP/SL races.
- The internal `InpUseLast30Days` is a no-op (above) — the **tester's own date range** bounds the run.
- **Set `InpServerGMTOffset` to your broker's offset** (see the broker-time note; calibrate via the
  panel's Manila clock) or the session windows shift and the backtest won't match the pine.
- To compare against the pine, match the indicator's inputs on the same window and expect the
  divergences above.

## Journal compatibility

EA entries land in `MQL5/Files/BG/journal/YYYY/MM/NNNN-YYYY-MM-DD-[buy|sell].md` with the same YAML
frontmatter as the discretionary `journal/`, tagged `strategy: BG` / `source: EA`. To pull EA trades
into the project:

```
robocopy "<MT5 Data>\MQL5\Files\BG\journal" "<project>\journal" /E /XO
python scripts/update_stats.py
```

## File map

```
EA/
├── README.md                          ← this file
├── Experts/BG/BG-Golden-Signal-5m.mq5     ← the EA (single file, Pine-parity)
└── Scripts/
    ├── sync_journal_from_ea.py        ← EA → project journal pull (reads MQL5\Files\BG\journal)
    ├── sync_stats_to_ea.py            ← (stale) relic of the removed WR-gate; EA no longer reads stats
    └── fetch_ff_calendar.py           ← (stale) relic of the removed news gate
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `OrderSend failed: 10018` | Trading disabled — click *Algo Trading* in the MT5 toolbar. |
| `lots = 0` in the log | Risk % × equity too small for the symbol's tick value. Raise risk % or balance. |
| Zero signals | Expected when the gate/session/date filters exclude the moment. Confirm `InpSessionGMTOffset` matches your broker, that you're in the Asia or London(Mon/Wed) killzone, or widen `InpEntryATR` / raise `InpBOSAge`. |
| Signals but no journal | `InpEnableJournal=true` and `MQL5\Files\BG\journal\` writable. |
| Daily kill never resets | `OnTimer` checks the UTC day every second; keep the EA attached across the UTC rollover. |

## Known limitations

- **Single TF**: executes on the chart's TF (intended M5) with H2 bias. Both are input-driven.
- **No DOL targets**: TPs are mechanical 1R/2R/3R, not liquidity-anchored. Matches doctrine.
- **In-memory trade state**: restarting the EA with a position open may not re-fire the SL-trail
  correctly. Avoid restarting mid-trade.
- **Cooldown** is approximated by elapsed-seconds ÷ bar-seconds (the pine counts `bar_index`); a
  weekend gap can shift it by a bar or two.
- **NY DoW** not wired (those sessions are off by default).
