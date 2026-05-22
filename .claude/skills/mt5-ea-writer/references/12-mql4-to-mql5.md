# MQL4 → MQL5 Migration Cheat Sheet

When migrating a legacy MQL4 EA to MQL5, these are the changes that matter most. Many MQL4 patterns will compile-fail or silently misbehave in MQL5.

## Event handler renames

| MQL4 | MQL5 |
|---|---|
| `int init()` | `int OnInit()` |
| `int start()` | `void OnTick()` |
| `int deinit()` | `void OnDeinit(const int reason)` |
| `int onChartEvent()` (MQL4 didn't have native equivalent) | `void OnChartEvent(...)` |

## Predefined variables

| MQL4 | MQL5 |
|---|---|
| `Bid` | `SymbolInfoDouble(_Symbol, SYMBOL_BID)` |
| `Ask` | `SymbolInfoDouble(_Symbol, SYMBOL_ASK)` |
| `Digits` | `_Digits` or `(int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)` |
| `Point` | `_Point` |
| `Period()` | `_Period` |
| `Symbol()` | `_Symbol` (or `Symbol()` still works as function) |

The underscored predefined vars (`_Symbol`, `_Period`, `_Digits`, `_Point`, `_LastError`, `_StopFlag`, `_UninitReason`) are MQL5-canonical.

## Indicator API — the big one

**MQL4:** indicator functions return the value directly, take a `shift` parameter.
```mql4
double atr_current   = iATR(NULL, 0, 14, 0);   // value at shift 0
double atr_yesterday = iATR(NULL, 0, 14, 1);   // value at shift 1
```

**MQL5:** indicator functions return a **handle**. You `CopyBuffer` from it.
```mql5
// In OnInit:
int g_hATR = iATR(_Symbol, _Period, 14);
// In OnTick:
double buf[]; ArraySetAsSeries(buf, true);
CopyBuffer(g_hATR, 0, 0, 2, buf);
double atr_current   = buf[0];
double atr_yesterday = buf[1];
```

The `shift` parameter is gone from all `i*()` functions. Apply via the `start_pos` argument of `CopyBuffer`.

**Common indicators that lost shift:**
- `iATR`, `iADX`, `iMA`, `iRSI`, `iMACD`, `iBands`, `iStochastic`
- `iCCI`, `iSAR`, `iIchimoku`, `iATR`

## Trade API

**MQL4:** direct `OrderSend()` returns ticket.
```mql4
int ticket = OrderSend(Symbol(), OP_BUY, 0.1, Ask, 3, Ask-100*Point, Ask+200*Point, "buy", 12345, 0, clrGreen);
```

**MQL5:** use the `CTrade` class.
```mql5
#include <Trade\Trade.mqh>
CTrade trade;
trade.SetExpertMagicNumber(12345);
trade.SetDeviationInPoints(3);
trade.SetTypeFillingBySymbol(_Symbol);

trade.Buy(0.1, _Symbol, 0.0, sl, tp, "buy");
if(trade.ResultRetcode() != TRADE_RETCODE_DONE) { /* failed */ }
ulong ticket = trade.ResultOrder();
```

The raw `OrderSend()` still exists in MQL5 but with a completely different signature using `MqlTradeRequest` + `MqlTradeResult` structs — only worth using if you need the lower-level control.

## Order vs Position model

**MQL4:** orders and positions are the same thing. `OrderSelect()` selects an active order which has a ticket and a position.

**MQL5:** orders are pending; positions are open. They have separate ticket pools and APIs:
- Pending orders: `OrdersTotal()`, `OrderGetTicket(i)`, `OrderGetDouble(ORDER_PRICE_OPEN)`, etc.
- Open positions: `PositionsTotal()`, `PositionGetTicket(i)`, `PositionGetDouble(POSITION_PRICE_OPEN)`, etc.
- History: `HistorySelect(from, to)`, `HistoryDealsTotal()`, `HistoryOrdersTotal()`, etc.

**MQL4 idiom:**
```mql4
for(int i = OrdersTotal() - 1; i >= 0; i--) {
   if(OrderSelect(i, SELECT_BY_POS)) {
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == magic) {
         double sl = OrderStopLoss();
         OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrRed);
      }
   }
}
```

**MQL5 equivalent:**
```mql5
for(int i = PositionsTotal() - 1; i >= 0; i--) {
   ulong ticket = PositionGetTicket(i);
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
   if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
   double sl = PositionGetDouble(POSITION_SL);
   trade.PositionClose(ticket);
}
```

## Symbol info

**MQL4:** `MarketInfo(symbol, mode)` with magic-constant modes.
```mql4
double spread = MarketInfo(Symbol(), MODE_SPREAD);
double bid    = MarketInfo(Symbol(), MODE_BID);
```

**MQL5:** type-safe `SymbolInfoDouble/Integer/String` with enum keys.
```mql5
double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);   // returns long (cast as needed)
double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
double tick_v = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
```

| MQL4 MODE_* | MQL5 SYMBOL_* |
|---|---|
| `MODE_BID` | `SYMBOL_BID` |
| `MODE_ASK` | `SYMBOL_ASK` |
| `MODE_SPREAD` | `SYMBOL_SPREAD` |
| `MODE_DIGITS` | `SYMBOL_DIGITS` |
| `MODE_POINT` | `SYMBOL_POINT` |
| `MODE_LOTSIZE` | `SYMBOL_TRADE_CONTRACT_SIZE` |
| `MODE_TICKVALUE` | `SYMBOL_TRADE_TICK_VALUE` |
| `MODE_MINLOT` | `SYMBOL_VOLUME_MIN` |
| `MODE_MAXLOT` | `SYMBOL_VOLUME_MAX` |
| `MODE_LOTSTEP` | `SYMBOL_VOLUME_STEP` |
| `MODE_STOPLEVEL` | `SYMBOL_TRADE_STOPS_LEVEL` |
| `MODE_FREEZELEVEL` | `SYMBOL_TRADE_FREEZE_LEVEL` |

## Time

`MqlDateTime` is the MQL5 struct. The fields are short-form (`mon`, `min`) — MQL4's `TimeMonth()`, `TimeMinute()` accessor functions still work but the struct field access does not.

```mql4
int m = TimeMonth(t);       // MQL4 way; still works in MQL5
```
```mql5
MqlDateTime dt; TimeToStruct(t, dt);
int m = dt.mon;             // MQL5 canonical
```

## String handling

| MQL4 | MQL5 |
|---|---|
| `StringConcatenate(a, b, c)` | `a + b + c` (operator overload) or `StringConcatenate()` (still works) |
| `StringSubstr(s, start, count)` | same — unchanged |
| Implicit cast `string s = 3.14` | same — works |

## Drawing on chart

**MQL4:** `ObjectCreate(name, type, sub, time, price)` — 5 args, no chart_id.
**MQL5:** `ObjectCreate(chart_id, name, type, sub, time, price, ...)` — chart_id first arg (`0` = current chart).

```mql5
ObjectCreate(0, "MyLabel", OBJ_LABEL, 0, 0, 0);
```

Property setters changed too — see [08-chart-objects.md](08-chart-objects.md).

## File I/O

| MQL4 | MQL5 |
|---|---|
| `FileOpen(name, mode)` | `FileOpen(name, flags, delim, codepage)` |
| `FILE_BIN \| FILE_READ` | same flags work; defaults different |
| Default encoding ANSI | Default encoding **UNICODE** |
| `FilePathName` | `FILE_COMMON` flag for shared folder |

If your MQL4 EA wrote text files that worked with Notepad, you must add `FILE_ANSI` explicitly in MQL5 or they'll be UTF-16.

## `start()` vs `OnTick()` — tick gating

MQL4's `start()` was called per tick. MQL5's `OnTick()` is also per tick.

**MQL4 had no first-class "OnTimer".** MQL5 has `OnTimer()` after `EventSetTimer(N)`. Use it for periodic tasks (panel update, position management heartbeat) instead of inflating `OnTick` overhead.

## Magic number setter

**MQL4:** every `OrderSend(...)` takes a `magic` parameter directly.
**MQL5:** `trade.SetExpertMagicNumber(magic)` is set once on the CTrade object, applies to all subsequent calls.

## `start()` returning int

In MQL4 you could `return(0)` from `start()`. In MQL5 `OnTick()` returns `void` — no return value.

## Backward compatibility

**MQL5 supports MQL4 in compatibility mode for many functions.** `TimeMonth()`, `TimeMinute()`, `OrderSend()` (the MQL4 form), `MarketInfo()`, etc. still compile.

**But:**
- Mixing MQL4 and MQL5 styles is brittle. Prefer canonical MQL5 forms.
- Some MQL4 features (predefined `Bid` / `Ask` / `Digits` global vars; the order-based loop) are deprecated and behave subtly differently.
- The order/position split is fundamental — you cannot avoid migrating that.

## Recommended migration order

1. Convert event handlers (`init` → `OnInit`, etc.)
2. Convert indicator calls to handle pattern (single biggest risk)
3. Convert trade API to `CTrade`
4. Convert order loops to position loops
5. Convert `MarketInfo` → `SymbolInfo*`
6. Convert chart object code (add `chart_id`)
7. Compile, fix one error at a time, never look at the wall of cascading errors

## Sources

- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade
- https://www.mql5.com/en/docs/trading
- https://www.mql5.com/en/docs/series
- https://www.mql5.com/en/articles/100 — Beginners EA guide (MQL5)
- https://www.mql5.com/en/articles/11216 — Concepts and structures
