# Compile Errors — Catalog & Diagnosis

## The cascading-error rule

**If MetaEditor reports 50+ errors after a small edit, fix only the FIRST one and recompile.** The remaining errors almost always cascade from a single upstream parse failure.

When the parser hits an unexpected token, it doesn't gracefully recover — it continues with confused state, mis-tokenizes everything after, and produces a wall of meaningless "undeclared identifier" / "unbalanced parenthesis" / "illegal operation use" errors.

**Sources:** [forum 451399](https://www.mql5.com/en/forum/451399), [forum 64542](https://www.mql5.com/en/forum/64542)

## Error → root cause mapping

Mapping from the [official compile-error list](https://www.mql5.com/en/docs/constants/errorswarnings/errorscompile) to causes I've observed in production:

| Error text | Most likely actual cause |
|---|---|
| **132: `'(' - opening parenthesis expected`** | A *previous* statement is missing `;` — parser thinks current line is a function declaration. Look UPWARD for the missing semicolon. |
| **145: `'(' - unbalanced left parenthesis`** | Mismatched bracket *earlier* in the file. Could be in an include. Editor "Match Brace" (Ctrl+M) locates it. |
| **150: `'+' - illegal operation use`** *(or `'('`, `'['`, etc.)* | Operator applied to incompatible types. Common: concatenating string with struct, or arithmetic on an array name (`arr + 1` instead of `arr[0] + 1`). |
| **177: `'X' - lvalue expected`** | Assigning to a function call, a constant, or a temporary. Example: `Symbol() = "EURUSD"`. Or assigning to a const-by-reference parameter. |
| **239: `'X' - syntax error`** | Generic parser fail — usually missing `;`, `}`, or a non-ASCII char snuck into a string. |
| **241: `'X' - array required`** | Indexing a non-array. Typically: forgot `[]` in declaration. `double atr;` then `atr[0]` → error. |
| **256: `'X' - undeclared identifier`** | Identifier not in scope. In ~80% of real cases: an `.mqh` defining it wasn't included, OR an earlier parse error prevented the declaration from registering. |

## Common patterns that produce specific errors

### Pattern A — `#property strict` in .mqh

```mql5
// File: MyLib.mqh
#property strict       ← MQL4-only; MQL5 parser may treat as garbage
#ifndef __MYLIB_MQH__
...
```

**Result:** dozens of "undeclared identifier" errors throughout downstream code, because the parser fails to register the `.mqh` contents.

**Fix:** Strip `#property strict` from every `.mqh`. It belongs nowhere in MQL5.

### Pattern B — `input` inside .mqh

```mql5
// File: MyConfig.mqh
#ifndef __MYCONFIG_MQH__
#define __MYCONFIG_MQH__
input double InpRiskPct = 1.0;   ← parser may accept but terminal ignores
#endif
```

**Result:** the input doesn't show in Properties UI. Worse — if the header is included multiple times (transitively), you can get "redefinition" warnings or silent symbol shadowing.

**Fix:** Move all `input` and `input group` declarations to the main `.mq5`, at top level, before `OnInit`.

### Pattern C — `dt.month` or `dt.minute`

```mql5
MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
int m = dt.month;    ← ERROR: undeclared identifier
int s = dt.minute;   ← ERROR: undeclared identifier
```

**Fix:** Use `dt.mon` and `dt.min`. Short form is canonical.

### Pattern D — Missing `;` on the line above

```mql5
double atr = ATRPrice()    ← missing semicolon
double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);  ← reported error line
```

**Result:** error reported on the second line, but the fix is on the first.

**Fix:** When MetaEditor highlights line N, check line N-1. Especially `132`, `239`, `145`.

### Pattern E — Unbalanced brace inside an include

```mql5
// MyLib.mqh
int MyFunc() {
   if(x > 0) {
      return 1;
   // missing closing }
   return 0;
}
```

**Result:** errors cascade through every file included after this point.

**Fix:** Run editor's "Match Brace" on every `{` in the included file. Or compile each `.mqh` individually if MetaEditor supports it.

### Pattern F — Forward declaration order

```mql5
// Function A calls function B, but B is defined below A in source order.
int A() { return B() + 1; }
int B() { return 42; }
```

MQL5 **does** support forward declarations for free functions (single-pass compilation with hoisting), so this usually works. BUT struct field references DON'T forward-declare:

```mql5
void Process(Setup &s) {   ← Setup not yet defined
   s.entry = 0;
}
struct Setup { double entry; };
```

**Fix:** Define structs and enums above functions that use them.

### Pattern G — Misused operator on array vs scalar

```mql5
double arr[];
ArrayResize(arr, 10);
double x = arr + 1;   ← ERROR: illegal operation use
double y = arr[0] + 1;   ← correct
```

### Pattern H — Implicit cast that doesn't exist

```mql5
string s = "3.14";
double d = s;        ← may compile but produces 0 silently in some builds
double d = (double)s;  ← C-style cast; works in current builds
double d = StringToDouble(s);  ← canonical, always works
```

**Recommendation:** always use `StringToDouble`, `StringToInteger`, `StringToTime` explicitly.

## What to do when overwhelmed by errors

1. **Scroll to the very first error** in MetaEditor's output panel.
2. **Read only that one.** Note the file and line.
3. **Check the line above it first** — most syntax errors are reported one line down from where they actually are.
4. **Identify which class** of cause from the table above.
5. **Fix it. Recompile. See what's left.**
6. Repeat.

Don't try to "fix all errors at once" — you'll chase phantom errors that disappear with the first fix.

## "Function not defined" vs "Function not declared"

- **Not declared** → no header brought the prototype in. Add the `#include`.
- **Not defined** → declared (prototype seen) but implementation missing. Either implement it or remove the call.

MetaEditor often reports both as "undeclared identifier".

## MQL5 vs MQL4 syntax differences that bite migrating code

| MQL4 code | MQL5 equivalent | Notes |
|---|---|---|
| `Bid` / `Ask` (predefined vars) | `SymbolInfoDouble(_Symbol, SYMBOL_BID)` | predefined vars removed |
| `Digits` | `_Digits` or `(int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)` | underscore prefix |
| `Point` | `_Point` | underscore prefix |
| `Period()` | `_Period` | |
| `Symbol()` | `_Symbol` | |
| `iATR(NULL, 0, 14, 0)` | `iATR(_Symbol, _Period, 14)` + `CopyBuffer(h, 0, 0, 1, buf); double atr = buf[0];` | shift param removed, returns handle |
| `OrderSend(...)` direct | `CTrade.Buy()` / `Sell()` / `PositionOpen()` | use CTrade class |
| `OrderSelect(i, SELECT_BY_POS)` + `OrderType()` | `PositionGetTicket(i)` + `PositionGetInteger(POSITION_TYPE)` | ticket-based |
| `init()` / `start()` / `deinit()` | `OnInit()` / `OnTick()` / `OnDeinit()` | new event names |
| `MODE_BID`, `MODE_ASK` (MarketInfo modes) | `SYMBOL_BID`, `SYMBOL_ASK` | enum-based |

## Sources

- https://www.mql5.com/en/docs/constants/errorswarnings/errorscompile
- https://www.mql5.com/en/forum/447117 — property strict directive
- https://www.mql5.com/en/forum/411530 — input parameters in mqh files
- https://www.mql5.com/en/forum/451399 — cascading errors
- https://www.mql5.com/en/forum/64542 — first error rule
