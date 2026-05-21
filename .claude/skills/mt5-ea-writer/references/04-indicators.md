# Indicator Handles + CopyBuffer

## The cardinal rule

**Create handles ONCE in `OnInit`. Release in `OnDeinit`. NEVER call `iATR()`/`iMA()`/`iADX()`/`iCustom()` inside `OnTick`.**

Each `i*()` call creates a new handle. MT5 caches identical-parameter calls, but a parameter-driven call (e.g. `iATR(_Symbol, _Period, InpPeriod)` where `InpPeriod` varies) creates a new handle each tick. The leak is invisible in the Strategy Tester and only manifests in live trading as creeping memory + eventual crash.

**Source:** [MQL5 forum 358611 — massive memory leak from indicator handles in OnTick](https://www.mql5.com/en/forum/358611)

## Canonical pattern

```mql5
// Globals
int g_hATR_M5 = INVALID_HANDLE;
int g_hADX_M5 = INVALID_HANDLE;

int OnInit()
{
   g_hATR_M5 = iATR(_Symbol, PERIOD_M5, 14);
   g_hADX_M5 = iADX(_Symbol, PERIOD_M5, 14);
   if(g_hATR_M5 == INVALID_HANDLE || g_hADX_M5 == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed: ", GetLastError());
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_hATR_M5 != INVALID_HANDLE) IndicatorRelease(g_hATR_M5);
   if(g_hADX_M5 != INVALID_HANDLE) IndicatorRelease(g_hADX_M5);
}

void OnTick()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_hATR_M5, 0, 0, 3, atr) <= 0) return;   // not ready yet
   double atr_current = atr[1];   // index 1 = last closed bar
   // ... use atr_current
}
```

**Note:** `IndicatorRelease()` is a no-op in the Strategy Tester ([forum 234090](https://www.mql5.com/en/forum/234090)) but must still be called for live hygiene.

## Built-in indicator signatures

```mql5
int iATR (const string symbol, ENUM_TIMEFRAMES period, int ma_period);
int iADX (const string symbol, ENUM_TIMEFRAMES period, int adx_period);
   // Buffers: 0 = MAIN_LINE, 1 = PLUSDI_LINE, 2 = MINUSDI_LINE
int iMA  (const string symbol, ENUM_TIMEFRAMES period, int ma_period, int ma_shift,
          ENUM_MA_METHOD ma_method, ENUM_APPLIED_PRICE applied_price);
int iRSI (const string symbol, ENUM_TIMEFRAMES period, int ma_period,
          ENUM_APPLIED_PRICE applied_price);
int iMACD(const string symbol, ENUM_TIMEFRAMES period, int fast_ema_period,
          int slow_ema_period, int signal_period, ENUM_APPLIED_PRICE applied_price);
   // Buffers: 0 = MAIN_LINE, 1 = SIGNAL_LINE
int iBands(const string symbol, ENUM_TIMEFRAMES period, int bands_period,
           int bands_shift, double deviation, ENUM_APPLIED_PRICE applied_price);
   // Buffers: 0 = BASE_LINE, 1 = UPPER_BAND, 2 = LOWER_BAND
int iStochastic(const string symbol, ENUM_TIMEFRAMES period, int Kperiod, int Dperiod,
                int slowing, ENUM_MA_METHOD ma_method, ENUM_STO_PRICE price_field);
   // Buffers: 0 = MAIN_LINE, 1 = SIGNAL_LINE
```

**Sources:** [iATR](https://www.mql5.com/en/docs/indicators/iatr), [iADX](https://www.mql5.com/en/docs/indicators/iadx), [iMA](https://www.mql5.com/en/docs/indicators/ima), [iRSI](https://www.mql5.com/en/docs/indicators/irsi), [iMACD](https://www.mql5.com/en/docs/indicators/imacd), [iBands](https://www.mql5.com/en/docs/indicators/ibands)

## Notable MQL4→MQL5 difference

In MQL4, indicator functions took a `shift` parameter and returned the value directly:
```mql4
double atr = iATR(NULL, 0, 14, 0);   // MQL4: returns value at shift 0
```

In MQL5 they return a **handle**, and you `CopyBuffer` from it. The `shift` is gone:
```mql5
int h = iATR(_Symbol, _Period, 14);   // MQL5: returns handle
double buf[];
CopyBuffer(h, 0, 0, 1, buf);
double atr = buf[0];
```

## CopyBuffer

Three overloads, all return `int`. Returns `-1` on error, otherwise number of elements actually copied.

```mql5
int CopyBuffer(int handle, int buffer_num, int      start_pos,  int      count,    double &buf[]);
int CopyBuffer(int handle, int buffer_num, datetime start_time, int      count,    double &buf[]);
int CopyBuffer(int handle, int buffer_num, datetime start_time, datetime stop_time, double &buf[]);
```

**Source:** [CopyBuffer](https://www.mql5.com/en/docs/series/copybuffer)

## ArraySetAsSeries

Controls the indexing direction of an array. Doesn't change physical layout, only access semantics.

```mql5
double buf[];
ArraySetAsSeries(buf, true);
CopyBuffer(handle, 0, 0, 100, buf);
// buf[0] = most recent bar
// buf[99] = oldest of the 100 copied

// vs. without:
double buf2[];
CopyBuffer(handle, 0, 0, 100, buf2);
// buf2[0] = oldest
// buf2[99] = most recent
```

**Convention in this skill: always `ArraySetAsSeries(buf, true)` for price/buffer reads.** It matches how traders think (index 0 = "now", index 1 = "last closed bar"). Apply once **before** `CopyBuffer`.

**Source:** [Indexing direction in arrays](https://www.mql5.com/en/docs/series/bufferdirection)

## BarsCalculated — readiness check

`int BarsCalculated(int handle)` returns the number of bars the indicator has finished calculating, or `-1` if not ready. Always check before the first `CopyBuffer` after handle creation, especially on EA startup:

```mql5
if(BarsCalculated(g_hATR_M5) < 100) return;   // not enough data yet
double atr[];
ArraySetAsSeries(atr, true);
if(CopyBuffer(g_hATR_M5, 0, 0, 3, atr) <= 0) return;
```

**Source:** [BarsCalculated](https://www.mql5.com/en/docs/series/barscalculated)

## Custom indicator via `iCustom`

```mql5
int iCustom(const string symbol, ENUM_TIMEFRAMES period,
            const string indicator_path, ...);   // variadic: pass indicator inputs in order
```

Example:
```mql5
g_hMyInd = iCustom(_Symbol, _Period, "MyFolder\\MyIndicator", 14, 2.0, true);
```

**Important:** `iCustom` paths use `\\` (escaped backslash) on Windows. Path is relative to `MQL5\Indicators\`.

## CopyHigh/Low/Close/Open/Time

Same pattern as `CopyBuffer`. Always call `ArraySetAsSeries` first:

```mql5
double highs[]; datetime times[];
ArraySetAsSeries(highs, true);
ArraySetAsSeries(times, true);
if(CopyHigh(_Symbol, PERIOD_M5, 0, 200, highs) != 200) return;
if(CopyTime(_Symbol, PERIOD_M5, 0, 200, times) != 200) return;
```

Return value is the number of bars copied (or `-1`). Check against your request size.

## Sources

- https://www.mql5.com/en/docs/indicators/iatr
- https://www.mql5.com/en/docs/indicators/iadx
- https://www.mql5.com/en/docs/indicators/ima
- https://www.mql5.com/en/docs/indicators/irsi
- https://www.mql5.com/en/docs/series/copybuffer
- https://www.mql5.com/en/docs/series/bufferdirection
- https://www.mql5.com/en/docs/series/barscalculated
- https://www.mql5.com/en/forum/358611 — Memory leak from handle creation in OnTick
- https://www.mql5.com/en/forum/234090 — IndicatorRelease in tester
- https://www.mql5.com/en/articles/22363 — Leak-free multi-timeframe engine
