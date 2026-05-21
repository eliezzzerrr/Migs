---
name: mt5-ea-writer
description: Expert MQL5 Expert Advisor writer for MetaTrader 5. ALWAYS use whenever the user mentions MT5, MetaTrader 5, MQL5, Expert Advisor, EA, .mq5 files, .mqh files, MetaEditor, CTrade, OnTick/OnInit/OnTrade, CalendarValueHistory, iATR/iADX/iMA/iRSI handles, position management via PositionsTotal/PositionGetTicket, OR asks to write/debug/compile/refactor any MetaTrader 5 EA. Also use for MQL4→MQL5 migration and decoding MetaEditor compile errors (cascading "undeclared identifier", "unbalanced left parenthesis", "illegal operation use", "lvalue expected"). If the user's existing code is .mq5 or .mqh, this skill MUST trigger.
argument-hint: "[task — write, debug, or refactor]"
metadata:
  version: "1.0.0"
  build_target: MetaTrader 5 (builds 4000+, 2024-2025)
---

# MT5 EA Writer — Expert MQL5 Reference

You write production MetaTrader 5 Expert Advisors that **compile cleanly on first try**. The single most expensive failure mode in MQL5 is the cascading parse error: one tiny mistake (a `#property strict` in an `.mqh`, an `input` declared inside a header guard, a missing `;`) produces 50–80 errors, and the wall of red noise hides the one line you need to fix. This skill encodes the patterns that prevent that.

## When this skill activates

- User asks to write an EA, indicator (`.mq5` / `.ex5`), or include file (`.mqh`)
- User pastes an MQL5 compile-error dump and asks for help
- User mentions: CTrade, OnInit/OnTick/OnTrade/OnTimer/OnTradeTransaction, OrderSend, PositionsTotal, PositionGetTicket, CalendarValueHistory, iATR/iADX/iMA/iRSI, CopyBuffer, ChartRedraw, FolderCreate, FileOpen, OBJ_LABEL, MqlDateTime, TradeResult
- User is migrating from MQL4 → MQL5
- User is touching `.claude/skills/mt5-ea-writer/templates/starter-ea.mq5` or any `.mq5`/`.mqh` in this repo

Do NOT activate for: TradingView Pine Script (use `pine-script-expert`), cTrader cAlgo, NinjaTrader, ThinkOrSwim ThinkScript, generic Python/JS trading.

## Hard rules — violate any of these and the EA WILL fail to compile

1. **NEVER put `#property strict` in a `.mq5` or `.mqh` file.** It's MQL4-only. In MQL5 it's at best a warning, at worst it cascades 50+ parser errors. Strip it from every file before submitting to compile.
2. **NEVER put `input` or `input group` declarations inside an `.mqh` include file.** They must live at top-level in the main `.mq5`. Putting them in includes is the single most common cause of "undeclared identifier" cascades.
3. **NEVER call `iATR()` / `iMA()` / `iADX()` / `iCustom()` inside `OnTick()`.** Create handles ONCE in `OnInit`, store as globals, release in `OnDeinit`. Calling inside OnTick is a handle leak invisible to the Strategy Tester.
4. **NEVER treat `trade.Buy()` returning `true` as "trade succeeded".** The `bool` only means request validated. Always check `trade.ResultRetcode() == TRADE_RETCODE_DONE` afterward.
5. **NEVER loop `for(int i = 0; i < PositionsTotal(); i++)` forward.** Closes/modifies shift indices. Loop backward: `for(int i = PositionsTotal() - 1; i >= 0; i--)`. Always filter by magic AND symbol.
6. **NEVER use `dt.month` or `dt.minute` on `MqlDateTime`.** The fields are `.mon` and `.min` (short form). Writing the long form is a guaranteed "undeclared identifier".
7. **NEVER use `PositionClosePartial()` on netting accounts.** It's hedging-only. Check `AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` first or refuse to init.
8. **NEVER ship a strategy using `CalendarValueHistory()` without an `MQLInfoInteger(MQL_TESTER)` gate + CSV fallback.** The calendar API returns 0 in the Strategy Tester.

## The Right-First-Time Checklist

Before submitting any `.mq5` to MetaEditor (F7), verify every one of these:

1. ☐ No `#property strict` anywhere.
2. ☐ All `input` declarations are in the main `.mq5`, **above** `OnInit` and `#include` of project headers.
3. ☐ `#include <Trade\Trade.mqh>` (standard library, angle brackets) comes **before** any project `.mqh` (quotes).
4. ☐ `OnInit` returns `int` and returns one of `INIT_SUCCEEDED`/`INIT_FAILED`/`INIT_PARAMETERS_INCORRECT`.
5. ☐ Every indicator handle is created in `OnInit` and released in `OnDeinit` via `IndicatorRelease(handle)`.
6. ☐ Every `trade.Buy()`/`Sell()`/`PositionClose()` is followed by a `trade.ResultRetcode() == TRADE_RETCODE_DONE` check.
7. ☐ `PositionsTotal()` loops are **backward** and filter `POSITION_SYMBOL == _Symbol` AND `POSITION_MAGIC == InpMagic`.
8. ☐ All `MqlDateTime` field accesses use `.mon` (not `.month`) and `.min` (not `.minute`).
9. ☐ `CalendarValueHistory()` is gated on `!MQLInfoInteger(MQL_TESTER)` with a CSV fallback for the tester.
10. ☐ `ChartRedraw(0)` is called **once after a batch** of `ObjectSet*` calls, not before each one.
11. ☐ `trade.SetTypeFillingBySymbol(_Symbol)` and `trade.SetDeviationInPoints(...)` are set in `OnInit`.
12. ☐ Hedging-only operations (`PositionClosePartial`) are guarded by `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` check.
13. ☐ No `iATR()`/`iMA()`/`iADX()` calls inside `OnTick` — only `CopyBuffer` from cached handles.
14. ☐ SL/TP distance ≥ `SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)` AND `SYMBOL_TRADE_FREEZE_LEVEL` before sending.
15. ☐ `IsNewBar()` gate fires the strategy once per closed bar (not every tick), unless tick-by-tick is intentional.

## Workflow

### Writing a new EA from scratch

1. **Confirm scope with the user:** symbol(s), timeframe, account type (hedging/netting), strategy logic in plain English, risk model, target line count.
2. **Start from `templates/starter-ea.mq5`** — copy it and modify. The starter is known to compile cleanly on current MT5 builds and demonstrates every pattern in this skill correctly.
3. **Single-file architecture** for EAs up to ~2000 lines. Multi-file with `.mqh` is only worth it when you have a reusable library; for a single strategy, single file removes a whole class of include-chain bugs.
4. **Walk the Right-First-Time Checklist** before declaring "done".
5. **Run F7 in MetaEditor** — if errors appear, fix the **first one** and recompile (the rest usually cascade from the first).

### Debugging a compile error dump

1. Read **only the first 3 errors with line numbers**. The rest are almost always cascade noise.
2. Check `references/09-compile-errors.md` for the error-code → real-cause mapping.
3. Most likely root causes (in order):
   - `#property strict` somewhere
   - `input` inside an `.mqh`
   - `dt.month` / `dt.minute` typo
   - Missing `;` on the line **above** the reported error
   - Unbalanced `(` or `{` earlier in the file
4. Fix one thing at a time and recompile.

### Migrating MQL4 → MQL5

See `references/12-mql4-to-mql5.md`. Key headlines: no `start()`/`init()`/`deinit()` (use OnTick/OnInit/OnDeinit), no `OrderSend` direct (use `CTrade`), magic number setter changed, `iATR(symbol, tf, period, shift)` lost its `shift` param, position model is now ticket-based not order-based.

## Reference files (read on demand)

When you need detail beyond the hard rules above, load the specific reference:

| Topic | File |
|---|---|
| EA file structure, `#property`, includes, event handlers | `references/01-skeleton.md` |
| CTrade class — every method + signature + retcodes | `references/02-ctrade.md` |
| Position iteration, netting vs hedging, OnTradeTransaction | `references/03-positions.md` |
| Indicator handles, CopyBuffer, ArraySetAsSeries | `references/04-indicators.md` |
| Economic calendar API + CSV fallback for tester | `references/05-calendar.md` |
| File I/O — FileOpen flags, FolderCreate, FileFind | `references/06-files.md` |
| Time functions — TimeGMT vs TimeCurrent vs TimeTradeServer | `references/07-time.md` |
| On-chart objects — OBJ_LABEL panels, ChartRedraw | `references/08-chart-objects.md` |
| Compile-error catalog (132/145/150/177/241/256) | `references/09-compile-errors.md` |
| Anti-patterns + production failure modes | `references/10-anti-patterns.md` |
| Backtesting nuances — tick modes, what the tester can't do | `references/11-backtesting.md` |
| MQL4 → MQL5 migration cheat sheet | `references/12-mql4-to-mql5.md` |

## Naming conventions to follow

- **Inputs:** `Inp` prefix (`InpRiskPct`, `InpMagicNumber`)
- **Globals:** `g_` prefix (`g_trade`, `g_hATR_M5`)
- **Indicator handles:** `h` or `g_h` prefix (`hATR`, `g_hADX`)
- **Functions:** PascalCase, verb-noun (`OpenLongPosition`, `IsNewBar`, `CalcLotSize`)
- **Constants/macros:** `UPPER_SNAKE_CASE`
- **Files:** `PascalCase.mq5` matching the main strategy name

## Output style when writing code

- **Always include the right-first-time checklist as comments at the top** of any new EA — even just as a checklist of `// ✓ no #property strict` markers, so the next reader can confirm at a glance.
- **Cite the doctrine source** when you reference the user's strategy — never invent rules.
- **Single file by default.** Only split into `.mqh` if the same code is used across multiple EAs.
- **One section comment block per logical chunk** (INCLUDES, INPUTS, ENUMS, STRUCTS, GLOBALS, HELPERS, EVENT HANDLERS).
- **Defensive defaults**: `InpMagic` non-zero, `InpEnableTrade = true` (master kill switch), `SetDeviationInPoints(20)`, `SetTypeFillingBySymbol(_Symbol)`.

## Build target

Targets current MetaTrader 5 (builds ~4000+, 2024–2025). For older builds, some calendar/CTrade signatures differ — flag this to the user if they're on a pre-2020 terminal.
