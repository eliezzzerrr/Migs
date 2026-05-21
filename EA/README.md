# Migs EA — MT5 Expert Advisor

Single-file MT5 EA that executes the **Migs Hybrid Strategy**: BOS → OB retest with 1H bias alignment, 3-TP mechanical ladder (TP1=+1R, TP2=+2R, TP3=+3R), sized as thirds.

## Status

**Version 0.3.0 — Universal.** Works on any symbol, any account (demo or live), any session. No XAUUSD restriction, no demo guard, no news gate. Risk and management are configurable inputs.

## Install

1. **Copy the file into MT5.** In MT5: `File → Open Data Folder`. Then:

   ```
   <Data Folder>/
     MQL5/
       Experts/Migs/MigsEA.mq5      ← from EA/Experts/Migs/
   ```

2. **Compile.** Open MetaEditor (F4 in MT5), open `MigsEA.mq5`, press F7. Should compile clean with 0 errors.

3. **Attach to chart.** Any symbol, **M5 timeframe** → drag the EA from Navigator → Common tab: enable "Allow live trading" → OK. Confirm "Algo Trading" is enabled in the MT5 toolbar.

4. **(Optional) Journal.** First run will create `MQL5/Files/Migs/journal/` automatically. Each opened trade gets a markdown journal entry; outcome is back-filled when the group closes.

## How it trades

On every new M5 bar (and only on new bars), the EA:

1. **Scans for a recent M5 BOS** — a close beyond a recent fractal swing high/low.
2. **Identifies the OB** that fueled the BOS impulse (last opposite-color candle before the breakout).
3. **Confirms 1H bias** by reading the latest H1 BOS direction. Requires bias to agree (configurable).
4. **Checks proximity** — current price must be within `InpEntryProximityATR × ATR` of the OB.
5. **Computes SL** beyond the OB edge plus a small buffer (10% of ATR).
6. **Computes TP1 / TP2 / TP3** mechanically: entry ± 1R / 2R / 3R.
7. **Opens 3 positions** sized 1/3 each, same SL, different TPs. Total risk = `InpRiskPercent` of equity.
8. **Manages**:
   - On TP1 fill → moves SL of TP2 and TP3 positions to entry (BE).
   - On TP2 fill → nothing further (already BE).
   - On TP3 fill → group complete.
9. **Logs outcome** to journal when all 3 positions close (TP3_HIT / TP2_HIT / TP1_HIT / SL_HIT / BE).

Blended R outcomes (with BE move after TP1):

| Scenario | Realized |
|---|---|
| All 3 TPs hit | **+2.0R** |
| TP1 + TP2, TP3 → BE | +1.0R |
| TP1 only, TP2/TP3 → BE | +0.33R |
| SL hit before TP1 | –1.0R |

## Input parameters

### Risk & Sizing
| Input | Default | Notes |
|---|---|---|
| `InpRiskPercent` | 1.0 | % equity risked across all 3 positions combined |
| `InpMaxLotsPerPos` | 100.0 | Safety cap; broker max overrides |

### Structure Detection
| Input | Default | Notes |
|---|---|---|
| `InpSwingLookback` | 200 | M5 bars scanned |
| `InpSwingStrength` | 2 | Fractal strength (bars left/right) |
| `InpMaxBOSAgeBars` | 30 | Ignore BOS older than N M5 bars |
| `InpOBMaxAgeBars` | 60 | Ignore OB older than N M5 bars |
| `InpEntryProximityATR` | 0.7 | Enter only when price is within N×ATR of the OB |
| `InpATRPeriod` | 14 | ATR period |

### HTF Bias
| Input | Default | Notes |
|---|---|---|
| `InpRequire1HBias` | true | Skip if 1H bias conflicts with trade direction |
| `InpH1Lookback` | 200 | H1 bars scanned for BOS |
| `InpH1MaxBOSAge` | 50 | Ignore H1 BOS older than N bars (treat as ranging) |

### Trade Management
| Input | Default | Notes |
|---|---|---|
| `InpMagic` | 20260522 | EA magic number |
| `InpMaxConcurrent` | 1 | Max simultaneous Migs groups on this symbol |
| `InpSlippagePoints` | 30 | Allowed deviation on market orders |
| `InpMoveSLtoBE` | true | Move TP2/TP3 SL to entry after TP1 fills |
| `InpEnableTrade` | true | Master kill switch |

### Safety
| Input | Default | Notes |
|---|---|---|
| `InpDailyMaxLossR` | 3.0 | Kill switch after N R loss per day (0 = off) |
| `InpMinBarsBetweenTrades` | 6 | Cooldown in M5 bars after close |

### Journal
| Input | Default | Notes |
|---|---|---|
| `InpEnableJournal` | true | Write markdown journal entries to `Files/Migs/journal/` |
| `InpJournalDir` | `Migs\journal` | Relative to `MQL5\Files` |

### Logging
| Input | Default | Notes |
|---|---|---|
| `InpVerbose` | true | Print INFO-level logs to Experts tab |

## What it does NOT enforce

By design, the v0.3 EA does not gate on:
- **Account type** (demo vs live)
- **Symbol** (any instrument)
- **Session** (24/7)
- **News** (trader-managed)
- **WR gate** (no auto-skip on direction-level WR)
- **Pattern matching beyond direction** (always tags `buy` / `sell`)

If you want any of these as gates, add them as inputs and wire into `OnTick()` before `ExecuteSetup()`.

## Multi-symbol

Attach the EA to multiple charts. Each chart instance runs independently with its own `InpMagic` — set distinct magics per chart if you want clean position separation, or share one magic to enforce `InpMaxConcurrent` across charts.

## Journal compatibility

EA journal entries land in `MQL5/Files/Migs/journal/YYYY/MM/NNNN-YYYY-MM-DD-[buy|sell].md` with the same YAML frontmatter as the discretionary `journal/` in this project. Sync periodically if you want EA and discretionary trades in one stats file:

```
robocopy "<MT5 Data>\MQL5\Files\Migs\journal" "<project>\journal" /E /XO
python scripts/update_stats.py
```

## File map

```
EA/
├── README.md                       ← this file
├── Experts/Migs/MigsEA.mq5         ← the EA (single file)
└── Scripts/
    ├── sync_stats_to_ea.py         ← optional: project → EA stats push
    ├── sync_journal_from_ea.py     ← optional: EA → project journal pull
    └── fetch_ff_calendar.py        ← optional: news calendar (gate disabled by default)
```

## Troubleshooting

| Symptom | Check |
|---|---|
| "OrderSend failed: 10018" | Trading disabled. Click "Algo Trading" in MT5 toolbar. |
| "Lot size 0" log | Risk % × equity is too small for the symbol's tick value. Raise risk % or use a larger balance. |
| Zero signals | Try lowering `InpRequire1HBias` to false, raising `InpEntryProximityATR`, or extending `InpMaxBOSAgeBars`. |
| Positions opened but no TP fills | Slippage on TP modify; check broker freeze/stops level. EA uses market TPs which most brokers respect. |
| Journal not written | `InpEnableJournal=true` and check `MQL5\Files\Migs\journal\` exists / is writable. |
| Daily kill switch never resets | `OnTimer` runs every 60s and checks UTC day; ensure the EA was attached overnight UTC. |

## Known limitations

- **Single TF**: hardcoded to M5 execution + H1 bias. Both could be made input-driven.
- **No DOL targets**: TPs are mechanical (1R/2R/3R), not anchored to liquidity pools. Matches doctrine.
- **No sweep-wick filter**: doesn't distinguish "OB retest after liquidity sweep" from "OB retest after random pullback." Matches doctrine.
- **Position-group state in memory**: if the EA is restarted mid-trade, state is reconstructed best-effort but BE move may not re-fire correctly. Avoid restarting the EA with positions open.
- **Backtester**: should work for in-sample testing. For news/calendar-dependent variants, the EA doesn't use news so no special handling needed.
