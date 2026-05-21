# EA Skeleton — Canonical File Structure

## `#property` directives — what belongs in `.mq5`

| Directive | Purpose |
|---|---|
| `#property copyright "..."` | Author string in Properties dialog |
| `#property link "..."` | URL in Properties dialog |
| `#property version "1.00"` | Version string |
| `#property description "..."` | Description (can repeat for multi-line) |

## `#property` directives — what to NEVER include

| Directive | Why not |
|---|---|
| `#property strict` | **MQL4-only.** In MQL5 it's at best ignored, at worst cascades parse errors when seen by the preprocessor in `.mqh` files. |
| `#property indicator_*` | Indicator-only (`indicator_chart_window`, `indicator_buffers`, `indicator_plots`, etc.). Not for EAs. |
| `#property show_inputs` | Script-only. |

**Source:** [MQL5 forum 447117 — property strict directive](https://www.mql5.com/en/forum/447117)

## Where `input` declarations MUST live

**Top-level in the main `.mq5` file only.** Never inside `.mqh` includes.

```mql5
// MyEA.mq5 — TOP of file, ABOVE OnInit
input group "=== Identity ==="
input long   InpMagicNumber = 20260522;
input string InpComment     = "MigsHybrid";

input group "=== Risk ==="
input double InpRiskPct  = 1.0;
input int    InpMaxOpen  = 3;
```

`input group "..."` is valid syntax that visually groups parameters in the Properties UI. It does nothing functional.

**Source:** [Input Variables docs](https://www.mql5.com/en/docs/basis/variables/inputvariables), [MQL5 forum 411530 — Input parameters in mqh files](https://www.mql5.com/en/forum/411530)

**Why this matters:** putting `input` inside an `.mqh` is the #1 cause of cascading "undeclared identifier" errors. The compiler accepts the syntax but the terminal doesn't expose the parameters; downstream code that references them breaks, and if the `.mqh` is header-guarded the parser can hit redefinition issues.

## Header guard pattern for `.mqh`

Use classical `#ifndef`. `#pragma once` works in current MetaEditor but isn't officially documented:

```mql5
// MyEA_Risk.mqh
#ifndef __MYEA_RISK_MQH__
#define __MYEA_RISK_MQH__

// ... contents ...

#endif // __MYEA_RISK_MQH__
```

Use ALL_CAPS guard macros prefixed and suffixed with `__` to avoid collision with project identifiers.

## `#include` order

```mql5
// 1. Standard Library first, angle brackets
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\OrderInfo.mqh>

// 2. Project headers after, quotes
#include "MyEA_Risk.mqh"
#include "MyEA_Journal.mqh"
```

- Angle brackets `< >` → searched in `MQL5\Include\` and standard library
- Double quotes `" "` → searched relative to the source file's directory

**Source:** [Including source files](https://www.mql5.com/en/book/basis/preprocessor/preprocessor_include)

## Event handler signatures — verified against current MT5 docs

```mql5
int  OnInit(void);
void OnDeinit(const int reason);
void OnTick(void);
void OnTrade(void);
void OnTimer(void);
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest      &request,
                        const MqlTradeResult       &result);
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
void OnBookEvent(const string &symbol);
```

**`OnInit` return codes** (`ENUM_INIT_RETCODE`):
- `INIT_SUCCEEDED` (0) — EA runs normally
- `INIT_FAILED` — generic init failure, terminal will not restart automatically
- `INIT_PARAMETERS_INCORRECT` — user-fixable; terminal highlights inputs as invalid
- `INIT_AGENT_NOT_SUITABLE` — used by Strategy Tester optimizer agents only

**Sources:** [OnInit](https://www.mql5.com/en/docs/event_handlers/oninit), [OnTick](https://www.mql5.com/en/docs/event_handlers/ontick), [OnTimer](https://www.mql5.com/en/docs/event_handlers/ontimer), [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction)

## Recommended single-file section order

```mql5
//+------------------------------------------------------------------+
//|                                                  MyEA.mq5         |
//|                                            Copyright 2026, You    |
//+------------------------------------------------------------------+
#property copyright "You"
#property version   "1.00"
#property description "One-line summary of what the EA does."

// 1. INCLUDES (standard library, then project)
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

// 2. ENUMS (named, never anonymous)
enum ENUM_TRADE_STATE { STATE_FLAT, STATE_LONG, STATE_SHORT };

// 3. INPUTS (with input group dividers)
input group "=== Identity ==="
input long InpMagicNumber = 20260522;

input group "=== Risk ==="
input double InpRiskPct = 1.0;

// 4. STRUCTS (named)
struct MyTrade {
   ulong    position_id;
   datetime entry_time;
   double   entry_price;
   double   sl, tp;
};

// 5. GLOBALS (g_ prefix)
CTrade        g_trade;
CSymbolInfo   g_symbol;
CPositionInfo g_pos;
int           g_hATR = INVALID_HANDLE;
MyTrade       g_open[];
datetime      g_last_bar = 0;

// 6. HELPERS (one function per logical concern)
bool   IsNewBar();
double CalcLotSize(double risk_pct, double sl_distance);
bool   PassesStopLevels(double price, double sl, double tp);
void   UpdatePanel();

// 7. EVENT HANDLERS
int OnInit() {
   if(!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_hATR = iATR(_Symbol, _Period, 14);
   if(g_hATR == INVALID_HANDLE) return INIT_FAILED;
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   ObjectsDeleteAll(0, "MyEA_");
}

void OnTick() {
   if(!IsNewBar()) return;
   // ... strategy logic ...
}

void OnTimer() {
   UpdatePanel();
}

void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest      &q,
                        const MqlTradeResult       &r) {
   if(t.type != TRADE_TRANSACTION_DEAL_ADD) return;
   // ... handle close ...
}
```

## Naming conventions

- **Inputs:** `Inp` prefix → `InpRiskPct`, `InpMagicNumber`
- **Globals:** `g_` prefix → `g_trade`, `g_hATR`
- **Handles:** `h` or `g_h` prefix → `hATR`, `g_hADX`
- **Functions:** PascalCase, verb-noun → `OpenLongPosition`, `IsNewBar`, `CalcLotSize`
- **Constants/macros:** `UPPER_SNAKE_CASE` → `MAX_RETRIES`, `MIGS_VERSION`
- **Files:** `PascalCase.mq5` matching the strategy name

## Source URLs (cited inline above, deduplicated)

- https://www.mql5.com/en/forum/447117
- https://www.mql5.com/en/docs/basis/variables/inputvariables
- https://www.mql5.com/en/forum/411530
- https://www.mql5.com/en/book/basis/preprocessor/preprocessor_include
- https://www.mql5.com/en/docs/event_handlers/oninit
- https://www.mql5.com/en/docs/event_handlers/ontick
- https://www.mql5.com/en/docs/event_handlers/ontimer
- https://www.mql5.com/en/docs/event_handlers/ontradetransaction
