# BG Golden 15m SMC — MT5 Expert Advisor

Single-file MT5 EA that is a **Pine-parity port of `TradingView/BG-Golden-Signal-15m-SMC.pine`** (v6).
It executes the BG Golden engine on **M15**: **BOS → order-block retest** with an **HTF (H1) bias
gate**, a mechanical **TP1/TP2/TP3 = +1R/+2R/+3R** ladder, and an optional SL-trail chain.

> **This is the only strategy in the project** (decision 2026-06-10). The 5m EA, the plain 15m EA,
> Dawn Raider, and the BTC pine were all retired — recover them from git history if ever needed.

> **Goal:** ≥95% backtest agreement with the TradingView indicator. Every behavioural rule
> here is copied from the pine — none are invented. See the `// Pine i_*` comment on each input.

## Status

**Version 0.9.1 — SMC pine literal defaults.** Magic **20261505**, journal dir **`BG\journal-15m-smc`**.
The trade engine is the BG Golden 15m engine; defaults follow the SMC pine's **literal input
declarations**, plus the pine's `g_risk` experiment inputs (all default off).

- **HTF bias gate ON @ H1** (`InpRequireHTF=true`, EMA 12/80) — validated best on 15m. Lenient:
  trend-match and ranging both allowed, **counter-trend always blocked**.
- **Structure (15m):** BOS age 20, OB age 40, entry proximity 0.4×ATR(14), SL buffer 0.45×ATR,
  Min-SL clamp $9 / filter $4, cooldown **2 bars**.
- **Sessions (GMT+8):** Asia 08:00–12:00 **Mon/Tue/Thu/Fri** · London 14:00–17:00 **Tue–Fri** ·
  NY AM 21:30–23:00 **Mon** · NY Lunch 00:00–01:00 (weekend-only DoW = dead on XAUUSD) ·
  NY PM 01:30–04:00 **Wed**.

## Install

1. **Copy the file into MT5.** In MT5: `File → Open Data Folder`, then:

   ```
   <Data Folder>/MQL5/Experts/…/BG-Golden-Signal-15m-SMC.mq5   ← from EA/Experts/BG/
   ```

2. **Compile.** Open MetaEditor (F4), open the file, press **F7**. Compiles clean with 0 errors
   (standard `<Trade\*.mqh>` library only — no external includes).

3. **Attach to chart.** **XAUUSD, M15 timeframe** → drag the EA from Navigator → Common tab:
   enable *Allow live trading* → OK. Confirm *Algo Trading* is lit in the MT5 toolbar.

4. **(Optional) Journal.** First run creates `MQL5/Files/BG/journal-15m-smc/` automatically; each
   opened trade gets a markdown entry that is back-filled with the outcome when it closes.

## How it trades

On every **new M15 bar** (signal logic is gated to bar close, mirroring Pine `barstate.isconfirmed`):

1. **Swings** — `ta.pivothigh/pivotlow(1,1)` fractals track the last swing high/low.
2. **BOS** — a *transition* break: `close > last_high AND prev_close ≤ last_high` (or the bear mirror).
   The active BOS persists and **ages out by bar count** after `InpBOSAge` bars.
3. **OB** — re-anchored **only when a fresh BOS fires**: the last opposite-colour candle within
   `InpOBAge` bars before the break.
4. **HTF bias** — EMA(12)/EMA(80) + close gate on the **previous closed H1 bar** (non-repaint).
   Composable: `match` and/or `range` allowed; counter-trend always blocked. **ON by default.**
5. **Proximity** — price must be within `InpEntryATR × ATR` of the OB edge.
6. **SL** — beyond the OB edge ± `InpSLBufATR × ATR`. This distance **defines 1R**.
   - **Min-SL filter** (`InpMinSLFilter`, default $4): *reject* the setup if the natural OB SL is tighter.
   - **Min-SL clamp** (`InpMinSLClamp`, default $9): *widen* the SL to this floor if it's still tighter (trade still fires).
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

## Input parameters (defaults = SMC pine literal inputs)

### Structure Detection (`g_struct`)
| Input | Default | Pine | Notes |
|---|---|---|---|
| `InpSwingLen` | 1 | `i_swing_len` | Pivot strength (bars L/R) |
| `InpBOSAge` | 20 | `i_bos_age` | Max BOS age in bars |
| `InpOBAge` | 40 | `i_ob_age` | Max OB lookback in bars |
| `InpEntryATR` | 0.4 | `i_entry_atr` | Entry proximity × ATR |
| `InpATRPer` | 14 | `i_atr_per` | ATR period |
| `InpSLBufATR` | 0.45 | `i_sl_buf` | SL buffer × ATR beyond OB |
| `InpMinSLClamp` | 9.0 | `i_min_sl` | Widen SL to this $ floor |
| `InpMinSLFilter` | 4.0 | `i_min_sl_flt` | Reject setup if natural SL < this $ |

### HTF Bias (`g_htf`)
| Input | Default | Pine | Notes |
|---|---|---|---|
| `InpRequireHTF` | **true** | `i_req_h1` | Master gate — ON is validated-best on 15m |
| `InpHTFAllowMatch` | true | `i_h1_allow_match` | LONG in bull / SHORT in bear |
| `InpHTFAllowRange` | true | `i_h1_allow_range` | Trade during HTF ranging |
| `InpHTFTimeframe` | **H1** | `"60"` | Bias timeframe |
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
| `InpCooldownBars` | 2 | `i_cooldown` | Bars to wait after the bench empties |

### Risk Sizing
| Input | Default | Notes |
|---|---|---|
| `InpRiskPercent` | 1.0 | % equity risked per trade (when `InpUseFixedLots=false`) |
| `InpUseFixedLots` | false | ON = trade a fixed lot size; OFF = size by % risk |
| `InpFixedLots` | 0.10 | Fixed lot size when `InpUseFixedLots=true` |
| `InpMaxLots` | 100.0 | Safety cap; broker max still overrides |

### Session Filter (`g_sess`, GMT+8)
| Input | Default | Notes |
|---|---|---|
| `InpUseSessions` | true | Master session toggle |
| `InpServerGMTOffset` | 0 | **Your broker's server-clock UTC offset** (GMT+3 → 3, GMT+2 → 2, UTC → 0). Calibrate via the panel's Manila clock |
| `InpSessionGMTOffset` | 8 | Timezone the session strings are written in (GMT+8 Manila) — leave at 8 |
| `InpUseAsia` / `InpAsiaSession` | true / `08:00-12:00` | Asia DoW: **Mon/Tue/Thu/Fri** (`InpAsiaDow*`) |
| `InpUseLondon` / `InpLondonSession` | true / `14:00-17:00` | London DoW: **Tue–Fri** (`InpLondonDow*`) |
| `InpUseNYAM` / `InpNYAMSession` | true / `21:30-23:00` | NY AM DoW: **Mon** (+Sat/Sun, dead on XAUUSD) |
| `InpUseNYLunch` / `InpNYLunchSession` | true / `00:00-01:00` | NY Lunch DoW: **Sat/Sun only** → never trades |
| `InpUseNYPM` / `InpNYPMSession` | true / `01:30-04:00` | NY PM DoW: **Wed** (+Sat/Sun, dead) |

> **⚠️ Broker server time.** MT5's server clock usually isn't UTC. Set **`InpServerGMTOffset`** to
> your broker's offset; the EA converts server → UTC → GMT+8 so the session windows and every
> per-session DoW gate land correctly. **Calibrate on the on-chart panel:** it shows live **MT5
> time** and **Manila time** — nudge `InpServerGMTOffset` until the Manila clock matches real Manila.

### Risk Controls & Strategy Experiments (`g_risk`, all default off)
| Input | Default | Pine | Notes |
|---|---|---|---|
| `InpMaxDayTrades` | 0 | `i_max_day_trades` | Cap NEW opens per **Manila** day (0 = off) |
| `InpMaxDayLossR` | 0.0 | `i_max_day_loss_r` | Stop opening once day R ≤ −this (0 = off) |
| `InpExitOnFlip` | false | `i_exit_on_flip` | React when HTF bias flips against an open trade |
| `InpFlipCloseAtMarket` | false | `i_flip_action` | false = move to BE, true = close at market |
| `InpBOSMinATR` | 0.0 | `i_bos_min_atr` | Require BOS close to clear swing by N×ATR (0 = off) |

### Date Range (`g_dates`)
| Input | Default | Notes |
|---|---|---|
| `InpUseLast30Days` | true | Pine `i_use_last30`. Effectively a **no-op in the EA** (it compares each bar to `TimeCurrent()−30d`, i.e. itself, so it always passes) — the **Strategy Tester's own date range bounds the run**, not this input. Harmless to leave on. |
| `InpUseLast7/14/60Days`, `InpUseCustomDates` | false | Priority: 7 > 14 > 30 > 60 > custom |

### Trade Management / Journal / Logging / Panel
| Input | Default | Notes |
|---|---|---|
| `InpMagic` | **20261505** | Distinct from the retired 5m (20260522) / 15m (20261504) magics |
| `InpSlippagePoints` | 30 | Allowed deviation on market orders |
| `InpEnableJournal` | true | Write markdown journal entries |
| `InpJournalDir` | `BG\journal-15m-smc` | Relative to `MQL5\Files` |
| `InpVerbose` | true | INFO logs to the Experts tab |
| `InpShowPanel` | true | On-chart status panel (+ colour/position inputs) |

## Known MT5 ↔ Pine divergences (≤5% expected backtest delta)

1. **Fill model** — Pine simulates fills against bar HIGH/LOW; MT5 fills on tick. Same-bar TP+SL
   races can resolve differently.
2. **Entry price** — Pine enters at bar close; MT5 enters at market on the next tick. Small slippage per entry.
3. **Costs** — Pine ignores spread/commission/swap; MT5 books them.
4. **SL and the final TP are both broker-attached** — so both exits fill server-side even if the
   EA/PC disconnects. (Ride-past-TP3 mode is the exception: no fixed TP, the EA trails the SL up.)
5. **TP detection** uses the last *closed* bar's H/L (entry is bar-gated too), so an intrabar TP
   touch is recognized one bar later than a live pine chart would show it. The broker SL still fires intrabar.

## Backtesting & optimization

- Strategy Tester: XAUUSD, M15, *Every tick based on real ticks* for the most faithful TP/SL races.
- The internal `InpUseLast30Days` is a no-op (above) — the **tester's own date range** bounds the run.
- **Set `InpServerGMTOffset` to your broker's offset** or the session windows shift and the backtest
  won't match the pine.
- Ongoing parameter sweeps live in
  [`Experts/BG/optimization-15m-smc-2026-06-06.md`](Experts/BG/optimization-15m-smc-2026-06-06.md)
  — batch 1 (150 passes) complete, batch 2 (extended ranges, Recovery-Factor criterion) specced.

## Journal compatibility

EA entries land in `MQL5/Files/BG/journal-15m-smc/YYYY/MM/NNNN-YYYY-MM-DD-[buy|sell].md` with the
same YAML frontmatter as the discretionary `journal/`, tagged `strategy: BG` / `source: EA`. To pull
EA trades into the project:

```
robocopy "<MT5 Data>\MQL5\Files\BG\journal-15m-smc" "<project>\journal" /E /XO
python scripts/update_stats.py
```

## File map

```
EA/
├── README.md                                  ← this file
├── Experts/BG/
│   ├── BG-Golden-Signal-15m-SMC.mq5           ← the EA (single file, Pine-parity)
│   ├── BG-Golden-Signal-15m-SMC.ex5           ← compiled binary
│   └── optimization-15m-smc-2026-06-06.md     ← parameter-sweep log (batch 1 done, batch 2 specced)
└── Scripts/
    ├── sync_journal_from_ea.py        ← EA → project journal pull (reads MQL5\Files\BG\…)
    ├── sync_stats_to_ea.py            ← (stale) relic of the removed WR-gate; EA no longer reads stats
    └── fetch_ff_calendar.py           ← (stale) relic of the removed news gate
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `OrderSend failed: 10018` | Trading disabled — click *Algo Trading* in the MT5 toolbar. |
| `lots = 0` in the log | Risk % × equity too small for the symbol's tick value. Raise risk % or balance. |
| Zero signals | Expected when the gate/session/date filters exclude the moment. Confirm `InpServerGMTOffset` matches your broker, that you're inside an enabled killzone+DoW window, or widen `InpEntryATR` / raise `InpBOSAge`. |
| Signals but no journal | `InpEnableJournal=true` and `MQL5\Files\BG\journal-15m-smc\` writable. |

## Known limitations

- **Single TF**: executes on the chart's TF (intended M15) with H1 bias. Both are input-driven.
- **No DOL targets**: TPs are mechanical 1R/2R/3R, not liquidity-anchored. Matches doctrine.
- **No HTF S/R headroom gate yet**: the EA can fire a trend-aligned signal straight into an opposing
  1H/4H level inside the TP2 distance. Planned: `InpMinRoomR` runway check (doctrine §9 "TP3 has runway").
- **In-memory trade state**: restarting the EA with a position open may not re-fire the SL-trail
  correctly. Avoid restarting mid-trade.
- **Cooldown** is approximated by elapsed-seconds ÷ bar-seconds (the pine counts `bar_index`); a
  weekend gap can shift it by a bar or two.
