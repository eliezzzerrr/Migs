# Anti-Patterns — Production Failure Modes

The catalog of things that actually broke real EAs. Each row is a thing-to-NEVER-do followed by the fix.

| Anti-pattern | Why it bites | Fix |
|---|---|---|
| **`iATR()` / `iMA()` / `iCustom()` inside `OnTick`** | New handle each call. MT5 caches identical-param calls but parameter-driven ones leak. Invisible in tester ([forum 358611](https://www.mql5.com/en/forum/358611)). | Create handles once in `OnInit`. Store as globals. Release in `OnDeinit`. |
| **Forward `for(int i=0; i<PositionsTotal(); i++)`** | Closing/modifying positions shifts indices; you skip or double-process. | Iterate backward: `for(int i = PositionsTotal()-1; i >= 0; i--)`. |
| **No magic+symbol filter in position loops** | EA closes/modifies positions belonging to other EAs or the user. | Always filter `POSITION_SYMBOL == _Symbol && POSITION_MAGIC == InpMagic`. |
| **Treating `trade.Buy() == true` as success** | `bool` only confirms request validated. Server can still reject. | Check `trade.ResultRetcode() == TRADE_RETCODE_DONE` after every trade call. |
| **Acting on every tick instead of bar close** | Same signal fires hundreds of times per bar; orders pile up; whipsaw. | Use `IsNewBar()` gate guarding `iTime(_Symbol, _Period, 0)`. |
| **No slippage budget** | First requote in volatile move rejects the trade. | `trade.SetDeviationInPoints(20)` (or more for fast symbols). |
| **SL/TP too close to market** | `TRADE_RETCODE_INVALID_STOPS` (10016) or `FROZEN` (10029). | Pre-flight check against `SYMBOL_TRADE_STOPS_LEVEL` and `SYMBOL_TRADE_FREEZE_LEVEL`. |
| **`if(a == b)` on doubles** | Floating-point arithmetic never produces exact equality. | `if(MathAbs(a - b) < _Point * 0.5)` or epsilon `~1e-8`. NormalizeDouble alone doesn't fix subsequent arithmetic. |
| **Forgetting `IndicatorRelease` in OnDeinit** | Handle leak persists across recompiles and EA reloads. | `if(g_handle != INVALID_HANDLE) IndicatorRelease(g_handle);` |
| **Deep recursion** | Stack overflow with no clean error. MQL5 stack size is not published. | Convert to iterative. |
| **Wrong fill type** | `TRADE_RETCODE_INVALID_FILL` (10030). | `trade.SetTypeFillingBySymbol(_Symbol)` in `OnInit` — auto-picks FOK/IOC/Return per broker. |
| **Calling Calendar API in tester** | Returns 0 — your news gate silently disables in backtest. | Gate with `MQLInfoInteger(MQL_TESTER)` + CSV fallback. |
| **`#property strict` in `.mqh`** | MQL4-only. Cascades parse errors in MQL5. | Remove from every file. It's not needed for MQL5 strict-mode equivalent. |
| **`input` inside header-guarded `.mqh`** | Parser may accept but terminal ignores; downstream uses fail. | Move to main `.mq5`, top level, above `#include` of project headers. |
| **`dt.month` / `dt.minute`** | `MqlDateTime` fields are `.mon` and `.min` — long form is undeclared. | Always use short form. |
| **`PositionClosePartial` on netting accounts** | Broker rejects; partial close not supported in netting mode. | Check `ACCOUNT_MARGIN_MODE` in OnInit; refuse to init on netting if your strategy needs partials. |
| **Single-position EA on hedging account** | `PositionClose(symbol)` closes only the first matching — others remain open. | Use ticket-based close on hedging: `PositionClose(ticket)`. |
| **Hardcoded XAUUSD pip = 0.1** | Other brokers use 0.01 or 1.0 for gold; your sizing is wrong. | `_Point` is the broker's quoted minimum; convert pips→price via an input. |
| **`StringToTime("2026-05-22 14:30")`** | Returns 0 — requires dots `2026.05.22 14:30`. | Always use dot-separator dates with `StringToTime`. |
| **`OnInit()` returning `void`** | Legacy signature; modern handler is `int OnInit()`. | Return `INIT_SUCCEEDED` / `INIT_FAILED` / `INIT_PARAMETERS_INCORRECT`. |
| **`FileOpen` without `FILE_ANSI`** | Defaults to UTF-16 — Notepad/Excel/Python see binary. | Always pass `FILE_TXT | FILE_ANSI` or `FILE_CSV | FILE_ANSI`. |
| **`FileOpen` with `FILE_CSV` but no delimiter** | Defaults to TAB, not comma. | Pass delimiter as 5th argument: `FileOpen(path, FILE_CSV|FILE_ANSI|FILE_WRITE, ',')`. |
| **`ChartRedraw` after every `ObjectSet*`** | Flickering, CPU pegged. | Call `ChartRedraw(0)` ONCE after a batch of property changes. |
| **No `INVALID_HANDLE` check** | `FileWrite` / `CopyBuffer` silently no-op; data lost. | Always check handle != `INVALID_HANDLE` before use. |
| **In-memory state lost on restart** | EA recompile / terminal restart wipes globals; open positions become unmanaged. | Persist critical state (open trade groups) to `MQL5\Files\`; restore in `OnInit` from `PositionsTotal()` + file cross-check. |
| **Magic number = 0** | Zero is special — collides with manual trades and other zero-magic EAs. | Always pick a unique non-zero magic. Convention: YYYYMMDD of EA creation. |
| **Hardcoded `_Symbol` in MagicNumber lookups** | Multi-instance EA on different charts share state. | Magic alone is enough; symbol filter is the second pass. |

## Specific traps in trade lifecycle

### Trap: opening an order then immediately reading `g_group.ticket`

```mql5
g_trade.Buy(lots, _Symbol, 0.0, sl, tp);
g_group.ticket = g_trade.ResultOrder();   // ← may be 0 on instant-fill brokers
```

On instant-fill brokers, the order may already be a deal (no pending order). Fix:

```mql5
g_trade.Buy(lots, _Symbol, 0.0, sl, tp);
if(g_trade.ResultRetcode() != TRADE_RETCODE_DONE) return;
ulong ticket = g_trade.ResultOrder();
if(ticket == 0) ticket = g_trade.ResultDeal();   // fallback
```

### Trap: `PositionModify` when SL or TP equals current value

Some brokers reject the modify as "no change". Always read current SL/TP before modifying:

```mql5
if(!PositionSelectByTicket(ticket)) return;
double cur_sl = PositionGetDouble(POSITION_SL);
double cur_tp = PositionGetDouble(POSITION_TP);
if(MathAbs(cur_sl - new_sl) < _Point * 0.5 &&
   MathAbs(cur_tp - new_tp) < _Point * 0.5) return;   // no-op
g_trade.PositionModify(ticket, new_sl, new_tp);
```

### Trap: setting SL on the wrong side of price

`SymbolInfoDouble(_Symbol, SYMBOL_BID)` returns current bid. For a BUY, SL must be BELOW bid. If `new_sl > bid`, broker rejects with `TRADE_RETCODE_INVALID_STOPS`.

```mql5
double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
if(is_buy && new_sl >= bid) return;   // SL must be below bid
if(!is_buy && new_sl <= ask) return;  // SL must be above ask
```

### Trap: TP1 reached but `PositionClose(ticket)` returns invalid ticket

If you opened a position and immediately need to partial-close, the position may not be selectable yet (it's in the trade queue). Defensive pattern:

```mql5
if(!PositionSelectByTicket(ticket))
{
   Sleep(50);    // 50ms — brokers usually settle within a tick
   if(!PositionSelectByTicket(ticket)) return;
}
g_trade.PositionClosePartial(ticket, lots / 2);
```

(`Sleep` in MQL5 is allowed in EAs; it yields ticks but doesn't block other timer events for too long.)

## Backtesting traps

- **Spread**: tester uses recorded M1 spread or fixed value; cannot replicate book depth or real-time slippage. EAs that profit only from tight spreads will lose in live.
- **Calendar**: returns 0. See [05-calendar.md](05-calendar.md).
- **Time functions** all collapse to `TimeCurrent()`. Don't mix `TimeLocal` and `TimeGMT`.
- **WebRequest** disabled. DLL calls disabled. `MQLInfoInteger(MQL_TESTER)` gate any external calls.
- **OnTimer rate**: timer fires accurately in tester, but the simulated time advances per the tick model, not real wall clock.

## When in doubt

- Code defensively. Every external call (broker, file, indicator) can fail.
- Log enough that you can reconstruct what happened from the Experts log.
- Never silently swallow errors.
- Test on a demo account for at least 1 week before going live, even after a clean backtest.

## Sources

- https://www.mql5.com/en/forum/358611 — Memory leak from handle creation in OnTick
- https://www.mql5.com/en/forum/23663 — return value of OrderSend should be checked
- https://www.mql5.com/en/book/automation/symbols/symbols_spreads_levels — Stops and freeze levels
- https://www.mql5.com/en/book/automation/symbols/symbols_execution_filling — Filling modes
- https://www.mql5.com/en/book/basis/builtin_types/float_numbers — Floating-point comparison
