//+------------------------------------------------------------------+
//|                                                MigsHybrid.mq5      |
//|                                            Copyright 2026, Migs    |
//|                                                                    |
//|  Migs Hybrid Strategy — universal MT5 EA                           |
//|  Mirrors the Pine indicator "Migs Hybrid v6" detection logic.      |
//|                                                                    |
//|  CHANGELOG                                                          |
//|   v0.5.0 (2026-05-22)                                              |
//|     • Input defaults updated to live Pine settings:                |
//|         HTFFastEMA 15→12, HTFSlowEMA 35→52                         |
//|         ADXTimeframe M5→H4                                          |
//|         ATRExpansionRatio 0.80→0.75                                |
//|         ATRMAPeriod 50→200                                          |
//|     • DetectLastBOS refactored from STATE-based to TRANSITION-based:│
//|         old: any bar where close>swing → BOS (re-fires in trend)   |
//|         new: only the SINGLE bar where close>swing AND             |
//|              close[prev]<=swing (Pine semantics)                   |
//|     • ActiveBOS persistence layer added: once detected, BOS stays  |
//|       active for InpMaxBOSAgeBars without re-detection. Opposite   |
//|       transition clears the previous active BOS.                   |
//|     • DetectHTFBias adds close-vs-fast-EMA check:                  |
//|         old: f>s → BULL                                             |
//|         new: f>s AND htf_close>f → BULL (Pine semantics)           |
//|     • HasOppositeBOSWithin now scans for transition-based opposite │
//|       BOS in the lookback window (was state-based, would always    |
//|       return true in any sustained trend).                         |
//|   v0.4.0 — TF-agnostic execution, EMA-based HTF bias               |
//|   v0.3.0 — universal symbol/account; single-file build              |
//|                                                                    |
//|  Strategy:                                                          |
//|    1. Detect transition-based BOS on chart TF                      |
//|    2. Anchor OB = last opposite-color candle before the breakout   |
//|    3. HTF (default 1H) EMA(12) vs EMA(52) + close-vs-fast bias     |
//|    4. Chop filters: ADX(14) on H4 + whipsaw + ATR expansion        |
//|    5. Entry within InpEntryProximityATR × ATR of OB                |
//|    6. SL = OB edge ± (InpSLBufferATR × ATR)                        |
//|    7. TPs = entry ± 1R / 2R / 3R (mechanical)                      |
//|    8. Sized as thirds across 3 positions                           |
//|    9. On TP1 fill → move SL of TP2/TP3 positions to BE             |
//+------------------------------------------------------------------+
#property copyright "Migs"
#property version   "0.50"
#property description "Migs Hybrid v0.5 — transition-based BOS, EMA+close HTF bias, Pine-matched defaults."

//==================================================================//
//  INCLUDES                                                          //
//==================================================================//
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================//
//  INPUTS                                                            //
//==================================================================//
input group "=== Risk & Sizing ==="
input double InpRiskPercent       = 1.0;       // % equity risk per trade (all 3 positions combined)
input double InpMaxLotsPerPos     = 100.0;     // safety cap

input group "=== Structure Detection ==="
input int    InpSwingLookback     = 200;       // chart-TF bars scanned for swings
input int    InpSwingStrength     = 2;         // fractal strength (bars L/R) — Pine: 2
input int    InpMaxBOSAgeBars     = 30;        // ignore BOS older than N chart bars — Pine: 30
input int    InpOBMaxAgeBars      = 60;        // ignore OB older than N chart bars — Pine: 60
input double InpEntryProximityATR = 0.7;       // enter when price within N×ATR of OB — Pine: 0.7
input int    InpATRPeriod         = 14;        // Pine: 14
input double InpSLBufferATR       = 0.10;      // SL beyond OB edge as fraction of ATR — Pine: 0.1

input group "=== HTF Bias (EMA + close gate) ==="
input bool            InpRequireHTFBias = true;          // skip when HTF bias conflicts — Pine: ✓
input ENUM_TIMEFRAMES InpHTFTimeframe   = PERIOD_H1;     // higher timeframe for bias — Pine: 1H
input int             InpHTFFastEMA     = 12;            // fast EMA period on HTF — Pine: 12
input int             InpHTFSlowEMA     = 52;            // slow EMA period on HTF — Pine: 52

input group "=== Chop / Consolidation Filter ==="
input bool             InpEnableChopFilter   = true;       // master toggle — Pine: ✓
input bool             InpStrictHTFBias      = true;       // reject when HTF bias is RANGING — Pine: ✓
input double           InpADXMinimum         = 20.0;       // ADX must be ≥ this — Pine: 20
input int              InpADXPeriod          = 14;         // Pine: 14
input ENUM_TIMEFRAMES  InpADXTimeframe       = PERIOD_H4;  // Pine: 4 hours
input int              InpWhipsawLookback    = 40;         // bars scanned for opposite transition — Pine: 40
input double           InpATRExpansionRatio  = 0.75;       // current ATR / ATR-MA must be ≥ this — Pine: 0.75
input int              InpATRMAPeriod        = 200;        // bars in ATR moving average — Pine: 200

input group "=== Trade Management ==="
input long   InpMagic             = 20260522;  // unique magic number for this EA
input int    InpMaxConcurrent     = 1;         // max simultaneous Migs groups
input ulong  InpSlippagePoints    = 30;        // allowed deviation on market orders
input bool   InpMoveSLtoBE        = true;      // SL→BE on remaining positions after TP1 — Pine: ✓
input bool   InpEnableTrade       = true;      // master kill switch (false = simulation only)

input group "=== Safety ==="
input double InpDailyMaxLossR     = 3.0;       // kill switch after −N R / day (0 = off)
input int    InpMinBarsBetweenTrades = 6;      // cooldown in chart-TF bars after close — Pine: 6

input group "=== Journal ==="
input bool   InpEnableJournal     = true;      // write markdown journal entries
input string InpJournalDir        = "Migs\\journal";   // relative to MQL5\Files

input group "=== Logging ==="
input bool   InpVerbose           = true;

input group "=== On-Chart Status Panel ==="
input bool             InpShowStatus       = true;
input ENUM_BASE_CORNER InpStatusCorner     = CORNER_RIGHT_UPPER;
input int              InpStatusXOffset    = 10;
input int              InpStatusYOffset    = 20;
input int              InpStatusFontSize   = 9;
input string           InpStatusFontName   = "Consolas";
input color            InpStatusColor      = clrBlack;       // body text
input color            InpStatusHeaderClr  = clrBlack;       // headers
input color            InpStatusGoodClr    = clrDarkGreen;   // positive state
input color            InpStatusBadClr     = clrFireBrick;   // negative state
input color            InpStatusMutedClr   = clrDimGray;     // muted
input color            InpStatusWarnClr    = clrDarkOrange;  // live-account warning

input group "=== Display Targets (informational) ==="
input double InpTargetWinRate     = 0.66;      // aspirational WR shown on panel (Pine 66.3%)

//==================================================================//
//  CONSTANTS                                                         //
//==================================================================//
#define MIGS_VERSION   "0.5.0"
#define COMMENT_TP1    "Migs:TP1"
#define COMMENT_TP2    "Migs:TP2"
#define COMMENT_TP3    "Migs:TP3"
#define PANEL_PREFIX   "MigsStatus_"

//==================================================================//
//  ENUMS                                                             //
//==================================================================//
enum ENUM_DIR    { DIR_NONE = 0, DIR_BUY = 1, DIR_SELL = 2 };
enum ENUM_BIAS   { BIAS_RANGE = 0, BIAS_BULL = 1, BIAS_BEAR = 2 };
enum ENUM_TP_TAG { TP_NONE   = 0, TP_1 = 1, TP_2 = 2, TP_3 = 3 };

//==================================================================//
//  STRUCTS                                                           //
//==================================================================//
struct Swing
{
   datetime time;
   double   price;
   bool     is_high;
   int      bar_index;
};

struct BOS
{
   bool   valid;
   bool   is_bullish;
   double broken_swing;
   double strength_price;
   int    shift;              // recomputed from ActiveBOS.detected_at via iBarShift
};

// Persisted BOS state — survives across OnTick calls. detected_at is the bar
// time of the original transition; converting back to shift via iBarShift keeps
// the OB-anchor stable as new bars print.
struct ActiveBOS
{
   bool     active;
   bool     is_bullish;
   double   broken_swing;
   double   strength_price;
   datetime detected_at;      // OPEN time of the transition bar — stable
};

struct OB
{
   bool   valid;
   bool   is_demand;
   double high;
   double low;
   int    shift;
   bool   fresh;
};

struct Setup
{
   bool       valid;
   ENUM_DIR   direction;
   ENUM_BIAS  bias_htf;
   OB         ob;
   BOS        bos;
   double     entry;
   double     sl;
   double     tp1, tp2, tp3;
   double     risk_price;
   double     atr_price;
   string     pattern;
   string     reject_reason;
};

struct TradeGroup
{
   bool     active;
   ulong    ticket_tp1, ticket_tp2, ticket_tp3;
   double   entry;
   double   sl_initial;
   double   tp1, tp2, tp3;
   double   risk_price;
   double   volume_each;
   string   pattern;
   ENUM_DIR direction;
   datetime open_time;
   bool     tp1_filled;
   bool     moved_to_be;
   double   mfe_r, mae_r;
   int      journal_id;
};

//==================================================================//
//  GLOBALS                                                           //
//==================================================================//
CTrade       g_trade;
CSymbolInfo  g_symbol;

int          g_hATR        = INVALID_HANDLE;
int          g_hADX        = INVALID_HANDLE;
int          g_hEMA_HTF_fast = INVALID_HANDLE;
int          g_hEMA_HTF_slow = INVALID_HANDLE;

datetime     g_last_bar    = 0;
datetime     g_day_start   = 0;
double       g_day_r       = 0.0;
bool         g_day_kill    = false;

TradeGroup   g_group;
datetime     g_last_close_time = 0;
string       g_last_eval_msg   = "(none)";
datetime     g_status_redraw_t = 0;

ENUM_BIAS    g_cached_bias_htf = BIAS_RANGE;
datetime     g_cached_bias_t   = 0;

string       g_chop_reason     = "";
double       g_last_adx        = 0.0;
double       g_last_atr_ratio  = 1.0;

// Read-only running stats (panel only)
int          g_total_wins     = 0;
int          g_total_loss     = 0;
double       g_total_r        = 0.0;
int          g_consec_losses  = 0;

// BOS persistence layer (v0.5.0)
ActiveBOS    g_active_bos = {false, false, 0.0, 0.0, 0};

//==================================================================//
//  HELPERS                                                           //
//==================================================================//
void MLog(string tag, string msg)
{
   if(!InpVerbose && tag != "ERR" && tag != "TRADE" && tag != "JOURNAL" && tag != "RISK" && tag != "BOS")
      return;
   PrintFormat("[MIGS][%s] %s", tag, msg);
}

string DirStr(const ENUM_DIR d) { return d == DIR_BUY ? "BUY" : d == DIR_SELL ? "SELL" : "NONE"; }
string BiasStr(const ENUM_BIAS b) { return b == BIAS_BULL ? "bullish" : b == BIAS_BEAR ? "bearish" : "ranging"; }

double NormPrice(const double p)
{
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizeLots(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   if(lots < vmin) return vmin;
   if(lots > vmax) return vmax;
   if(lots > InpMaxLotsPerPos) return InpMaxLotsPerPos;
   return lots;
}

double ATRPrice()
{
   if(g_hATR == INVALID_HANDLE) return 0.0;
   if(BarsCalculated(g_hATR) < InpATRPeriod + 5) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, 0, 2, buf) < 2) return 0.0;
   return buf[1];
}

//==================================================================//
//  STRUCTURE DETECTION — Swings + Transition-based BOS               //
//==================================================================//
int FindSwings(ENUM_TIMEFRAMES tf, const int lookback, const int strength, Swing &out[])
{
   ArrayResize(out, 0);
   if(lookback < strength * 3 + 1) return 0;

   double highs[], lows[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   ArraySetAsSeries(times, true);
   if(CopyHigh(_Symbol, tf, 0, lookback, highs) != lookback) return 0;
   if(CopyLow (_Symbol, tf, 0, lookback, lows ) != lookback) return 0;
   if(CopyTime(_Symbol, tf, 0, lookback, times) != lookback) return 0;

   int n = 0;
   for(int i = strength; i < lookback - strength; i++)
   {
      bool is_h = true, is_l = true;
      for(int k = 1; k <= strength; k++)
      {
         if(highs[i] <= highs[i - k] || highs[i] <= highs[i + k]) is_h = false;
         if(lows [i] >= lows [i - k] || lows [i] >= lows [i + k]) is_l = false;
         if(!is_h && !is_l) break;
      }
      if(is_h || is_l)
      {
         ArrayResize(out, n + 1);
         out[n].time      = times[i];
         out[n].price     = is_h ? highs[i] : lows[i];
         out[n].is_high   = is_h;
         out[n].bar_index = i;
         n++;
      }
   }
   return n;
}

// Test if a transition happened at bar `i`, given pre-loaded arrays.
// Returns true and fills out_* if yes. Pine semantics:
//   bull = close[i] > prior_swing_high AND close[i+1] <= prior_swing_high
//   bear = close[i] < prior_swing_low  AND close[i+1] >= prior_swing_low
bool IsTransitionAt(const int i,
                    const double &opens[], const double &closes[],
                    const Swing &sw[], const int n_sw,
                    bool &out_bullish, double &out_swing, double &out_strength)
{
   double last_high_price = 0, last_low_price = 0;
   int last_high_bar = -1, last_low_bar = -1;
   for(int s = 0; s < n_sw; s++)
   {
      if(sw[s].bar_index <= i) continue;
      if(sw[s].is_high  && last_high_bar < 0) { last_high_price = sw[s].price; last_high_bar = sw[s].bar_index; }
      if(!sw[s].is_high && last_low_bar  < 0) { last_low_price  = sw[s].price; last_low_bar  = sw[s].bar_index; }
      if(last_high_bar >= 0 && last_low_bar >= 0) break;
   }
   bool t_bull = (last_high_bar >= 0 && closes[i] > last_high_price && closes[i + 1] <= last_high_price);
   bool t_bear = (last_low_bar  >= 0 && closes[i] < last_low_price  && closes[i + 1] >= last_low_price);
   if(t_bull)
   {
      out_bullish  = true;
      out_swing    = last_high_price;
      out_strength = MathAbs(closes[i] - opens[i]);
      return true;
   }
   if(t_bear)
   {
      out_bullish  = false;
      out_swing    = last_low_price;
      out_strength = MathAbs(opens[i] - closes[i]);
      return true;
   }
   return false;
}

// Scan recent bars for the MOST RECENT transition. Update g_active_bos if found.
// Age-out the active BOS if it's older than InpMaxBOSAgeBars.
// Called once per new chart bar (and once at OnInit).
void ScanAndUpdateBOSState()
{
   // 1. Age-out existing active BOS
   if(g_active_bos.active)
   {
      int shift_now = iBarShift(_Symbol, _Period, g_active_bos.detected_at, true);
      if(shift_now < 0 || shift_now > InpMaxBOSAgeBars)
      {
         MLog("BOS", StringFormat("active %s BOS aged out (shift=%d > max=%d)",
                                   g_active_bos.is_bullish ? "BULL" : "BEAR",
                                   shift_now, InpMaxBOSAgeBars));
         g_active_bos.active = false;
      }
   }

   // 2. Look for a NEW transition in the recent window
   Swing sw[];
   int n_sw = FindSwings(_Period, InpSwingLookback, InpSwingStrength, sw);
   if(n_sw < 2) return;

   int copy = MathMin(InpSwingLookback, InpMaxBOSAgeBars + 10);
   double opens[], closes[];
   datetime times[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(times, true);
   if(CopyOpen (_Symbol, _Period, 0, copy, opens ) != copy) return;
   if(CopyClose(_Symbol, _Period, 0, copy, closes) != copy) return;
   if(CopyTime (_Symbol, _Period, 0, copy, times ) != copy) return;

   int limit = MathMin(InpMaxBOSAgeBars, copy - 2);
   for(int i = 1; i <= limit; i++)
   {
      bool t_bull;
      double t_swing, t_strength;
      if(!IsTransitionAt(i, opens, closes, sw, n_sw, t_bull, t_swing, t_strength)) continue;

      // Found the most recent transition. Adopt if newer than current active.
      if(!g_active_bos.active || times[i] > g_active_bos.detected_at)
      {
         bool flipped = (g_active_bos.active && g_active_bos.is_bullish != t_bull);
         g_active_bos.active         = true;
         g_active_bos.is_bullish     = t_bull;
         g_active_bos.broken_swing   = t_swing;
         g_active_bos.strength_price = t_strength;
         g_active_bos.detected_at    = times[i];
         MLog("BOS", StringFormat("%s transition detected at shift %d%s — swing=%s",
                                   t_bull ? "BULL" : "BEAR", i,
                                   flipped ? " (FLIPPED previous)" : "",
                                   DoubleToString(t_swing, _Digits)));
      }
      return;   // Most recent transition wins; stop scanning.
   }
}

// Public accessor: returns the currently active BOS (if any) as a fresh BOS
// struct with `shift` recomputed via iBarShift so the OB anchor stays correct
// as new bars print.
bool GetActiveBOS(BOS &out)
{
   out.valid = false;
   if(!g_active_bos.active) return false;
   int shift = iBarShift(_Symbol, _Period, g_active_bos.detected_at, true);
   if(shift < 0 || shift > InpMaxBOSAgeBars) return false;
   out.valid          = true;
   out.is_bullish     = g_active_bos.is_bullish;
   out.broken_swing   = g_active_bos.broken_swing;
   out.strength_price = g_active_bos.strength_price;
   out.shift          = shift;
   return true;
}

// Scan last N bars for a transition of the OPPOSITE direction relative to
// current_bullish. Used by the whipsaw chop filter. Transition-based per v0.5.
bool HasOppositeTransitionWithin(const int N, const bool current_bullish)
{
   if(N <= 0) return false;
   int scan_lb = MathMin(InpSwingLookback, N + 10);

   Swing sw[];
   int n_sw = FindSwings(_Period, scan_lb, InpSwingStrength, sw);
   if(n_sw < 2) return false;

   double opens[], closes[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   if(CopyOpen (_Symbol, _Period, 0, scan_lb, opens ) != scan_lb) return false;
   if(CopyClose(_Symbol, _Period, 0, scan_lb, closes) != scan_lb) return false;

   int limit = MathMin(N, scan_lb - 2);
   for(int i = 1; i <= limit; i++)
   {
      bool t_bull;
      double t_swing, t_strength;
      if(!IsTransitionAt(i, opens, closes, sw, n_sw, t_bull, t_swing, t_strength)) continue;
      // Hit on an opposite-direction transition is what we're filtering against.
      if(current_bullish && !t_bull) return true;
      if(!current_bullish && t_bull) return true;
      // Same direction → keep looking; whipsaw is "I just got a contrary signal"
   }
   return false;
}

// OB detection — unchanged from v0.4 except it now reads from a transition-based BOS.
bool DetectOB(ENUM_TIMEFRAMES tf, const BOS &bos, OB &out)
{
   out.valid = false;
   if(!bos.valid) return false;

   int max_scan = MathMin(InpOBMaxAgeBars, 100);
   int copy = bos.shift + max_scan + 2;
   double opens[], closes[], highs[], lows[];
   ArraySetAsSeries(opens,  true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(highs,  true);
   ArraySetAsSeries(lows,   true);
   if(CopyOpen (_Symbol, tf, 0, copy, opens ) != copy) return false;
   if(CopyClose(_Symbol, tf, 0, copy, closes) != copy) return false;
   if(CopyHigh (_Symbol, tf, 0, copy, highs ) != copy) return false;
   if(CopyLow  (_Symbol, tf, 0, copy, lows  ) != copy) return false;

   for(int i = bos.shift + 1; i < bos.shift + max_scan; i++)
   {
      bool down = (closes[i] < opens[i]);
      bool up   = (closes[i] > opens[i]);
      if(bos.is_bullish && down)
      {
         out.valid = true;
         out.is_demand = true;
         out.high = highs[i]; out.low = lows[i];
         out.shift = i;
         break;
      }
      if(!bos.is_bullish && up)
      {
         out.valid = true;
         out.is_demand = false;
         out.high = highs[i]; out.low = lows[i];
         out.shift = i;
         break;
      }
   }
   if(!out.valid) return false;

   // Freshness: has price re-entered the OB body since formation?
   out.fresh = true;
   for(int j = out.shift - 1; j >= 1; j--)
   {
      if(out.is_demand)
      {
         if(lows[j] <= out.high && highs[j] >= out.low) { out.fresh = false; break; }
      }
      else
      {
         if(highs[j] >= out.low && lows[j] <= out.high) { out.fresh = false; break; }
      }
   }
   return true;
}

//==================================================================//
//  HTF BIAS — EMA + close-vs-fast-EMA gate (v0.5)                    //
//==================================================================//
ENUM_BIAS DetectHTFBias()
{
   if(g_hEMA_HTF_fast == INVALID_HANDLE || g_hEMA_HTF_slow == INVALID_HANDLE) return BIAS_RANGE;
   if(BarsCalculated(g_hEMA_HTF_fast) < InpHTFSlowEMA + 5) return BIAS_RANGE;
   if(BarsCalculated(g_hEMA_HTF_slow) < InpHTFSlowEMA + 5) return BIAS_RANGE;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(g_hEMA_HTF_fast, 0, 0, 2, fast) < 2) return BIAS_RANGE;
   if(CopyBuffer(g_hEMA_HTF_slow, 0, 0, 2, slow) < 2) return BIAS_RANGE;

   // Pull last CLOSED HTF bar's close (shift=1)
   double htf_close[];
   ArraySetAsSeries(htf_close, true);
   if(CopyClose(_Symbol, InpHTFTimeframe, 1, 1, htf_close) < 1) return BIAS_RANGE;

   double f = fast[1];        // EMA(fast) at last-closed HTF bar
   double s = slow[1];        // EMA(slow) at last-closed HTF bar
   double c = htf_close[0];   // last-closed HTF bar close

   // Pine semantics:
   //   h1_bull = h1_fast > h1_slow AND h1_close > h1_fast
   //   h1_bear = h1_fast < h1_slow AND h1_close < h1_fast
   //   otherwise → ranging
   if(f > s && c > f) return BIAS_BULL;
   if(f < s && c < f) return BIAS_BEAR;
   return BIAS_RANGE;
}

ENUM_BIAS GetCachedHTFBias()
{
   datetime now = TimeCurrent();
   if(now - g_cached_bias_t > 60)
   {
      g_cached_bias_htf = DetectHTFBias();
      g_cached_bias_t   = now;
   }
   return g_cached_bias_htf;
}

//==================================================================//
//  CHOP FILTER                                                       //
//==================================================================//
bool ADXAbove(double minimum, double &out_adx)
{
   out_adx = 0.0;
   if(InpADXMinimum <= 0) return true;
   if(g_hADX == INVALID_HANDLE) return true;
   if(BarsCalculated(g_hADX) < InpADXPeriod + 5) return true;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hADX, 0, 0, 2, buf) < 2) return true;
   out_adx = buf[1];
   return (out_adx >= minimum);
}

bool ATRExpanding(double min_ratio, double &out_ratio)
{
   out_ratio = 1.0;
   if(min_ratio <= 0) return true;
   if(g_hATR == INVALID_HANDLE) return true;
   if(BarsCalculated(g_hATR) < InpATRMAPeriod + 5) return true;

   double atrs[];
   ArraySetAsSeries(atrs, true);
   if(CopyBuffer(g_hATR, 0, 0, InpATRMAPeriod + 1, atrs) < InpATRMAPeriod + 1) return true;
   double sum = 0;
   for(int i = 1; i <= InpATRMAPeriod; i++) sum += atrs[i];
   double ma = sum / InpATRMAPeriod;
   if(ma <= 0) return true;
   out_ratio = atrs[1] / ma;
   return (out_ratio >= min_ratio);
}

bool IsChoppy(const Setup &s, string &reason)
{
   reason = "";
   if(!InpEnableChopFilter) return false;

   if(InpStrictHTFBias && s.bias_htf == BIAS_RANGE)
   {
      reason = "strict HTF: ranging bias";
      return true;
   }
   double adx;
   if(!ADXAbove(InpADXMinimum, adx))
   {
      reason = StringFormat("ADX %.1f < min %.1f", adx, InpADXMinimum);
      g_last_adx = adx;
      return true;
   }
   g_last_adx = adx;

   if(InpWhipsawLookback > 0 && HasOppositeTransitionWithin(InpWhipsawLookback, s.direction == DIR_BUY))
   {
      reason = StringFormat("whipsaw: opposite transition in %d bars", InpWhipsawLookback);
      return true;
   }
   double atr_ratio;
   if(!ATRExpanding(InpATRExpansionRatio, atr_ratio))
   {
      reason = StringFormat("ATR ratio %.2f < min %.2f", atr_ratio, InpATRExpansionRatio);
      g_last_atr_ratio = atr_ratio;
      return true;
   }
   g_last_atr_ratio = atr_ratio;
   return false;
}

//==================================================================//
//  SETUP BUILDER                                                     //
//==================================================================//
bool BuildSetup(Setup &s)
{
   s.valid = false;
   s.reject_reason = "";

   // 1. Active BOS from the persistence layer (transition-based)
   BOS bos;
   if(!GetActiveBOS(bos))
   { s.reject_reason = "no active BOS"; return false; }
   s.bos = bos;
   ENUM_DIR dir = bos.is_bullish ? DIR_BUY : DIR_SELL;
   s.direction = dir;
   s.pattern = (dir == DIR_BUY) ? "buy" : "sell";

   // 2. OB anchored to BOS
   OB ob;
   if(!DetectOB(_Period, bos, ob))
   { s.reject_reason = "no OB"; return false; }
   s.ob = ob;

   // 3. HTF EMA + close-vs-fast bias
   s.bias_htf = GetCachedHTFBias();
   if(InpRequireHTFBias)
   {
      bool aligned = (dir == DIR_BUY  && s.bias_htf == BIAS_BULL)
                  || (dir == DIR_SELL && s.bias_htf == BIAS_BEAR)
                  || (s.bias_htf == BIAS_RANGE && !InpStrictHTFBias);
      if(!aligned) { s.reject_reason = "HTF bias conflicts (" + BiasStr(s.bias_htf) + ")"; return false; }
   }

   // 4. Chop filters
   string chop_why;
   if(IsChoppy(s, chop_why))
   {
      g_chop_reason = chop_why;
      s.reject_reason = "chop: " + chop_why;
      return false;
   }
   g_chop_reason = "";

   // 5. Entry proximity
   double atr = ATRPrice();
   s.atr_price = atr;
   if(atr <= 0) { s.reject_reason = "ATR unavailable"; return false; }

   double cur = (dir == DIR_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist_to_ob = 0;
   if(dir == DIR_BUY)  dist_to_ob = (cur > ob.high) ? cur - ob.high : 0;
   else                dist_to_ob = (cur < ob.low ) ? ob.low - cur : 0;
   if(dist_to_ob > InpEntryProximityATR * atr)
   { s.reject_reason = StringFormat("price too far from OB (%.2fxATR)", dist_to_ob / atr); return false; }

   // 6. SL beyond OB edge + buffer
   double buffer = atr * InpSLBufferATR;
   if(dir == DIR_BUY)
   {
      s.entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      s.sl    = NormPrice(ob.low - buffer);
   }
   else
   {
      s.entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      s.sl    = NormPrice(ob.high + buffer);
   }
   s.risk_price = MathAbs(s.entry - s.sl);
   if(s.risk_price <= 0) { s.reject_reason = "zero risk"; return false; }

   // 7. Stops-level pre-flight
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_dist     = MathMax(stops_level, freeze_level) * point;
   if(s.risk_price < min_dist)
   { s.reject_reason = StringFormat("SL %.5f < broker min %.5f", s.risk_price, min_dist); return false; }

   // 8. Mechanical 1R/2R/3R
   double R = s.risk_price;
   if(dir == DIR_BUY)
   {
      s.tp1 = NormPrice(s.entry + 1.0 * R);
      s.tp2 = NormPrice(s.entry + 2.0 * R);
      s.tp3 = NormPrice(s.entry + 3.0 * R);
   }
   else
   {
      s.tp1 = NormPrice(s.entry - 1.0 * R);
      s.tp2 = NormPrice(s.entry - 2.0 * R);
      s.tp3 = NormPrice(s.entry - 3.0 * R);
   }
   s.valid = true;
   return true;
}

//==================================================================//
//  RISK + EXECUTION  (UNCHANGED from v0.4)                           //
//==================================================================//
double CalcTotalLots(double sl_distance_price)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * InpRiskPercent / 100.0;
   double tick_v     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_s     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_s <= 0 || tick_v <= 0 || sl_distance_price <= 0) return 0.0;
   double ticks_in_sl   = sl_distance_price / tick_s;
   double money_per_lot = ticks_in_sl * tick_v;
   if(money_per_lot <= 0) return 0.0;
   return NormalizeLots(risk_money / money_per_lot);
}

int CountMigsPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)  continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagic) continue;
      n++;
   }
   return n;
}

bool CooldownPassed()
{
   if(g_last_close_time == 0) return true;
   datetime now = TimeCurrent();
   long secs_per_bar = PeriodSeconds(_Period);
   if(secs_per_bar <= 0) return true;
   long bars = (now - g_last_close_time) / secs_per_bar;
   return (bars >= InpMinBarsBetweenTrades);
}

bool DailyRiskAllow()
{
   if(g_day_kill) return false;
   if(InpDailyMaxLossR <= 0) return true;
   if(g_day_r <= -InpDailyMaxLossR) { g_day_kill = true; return false; }
   return true;
}

bool ExecuteSetup(const Setup &s)
{
   if(!InpEnableTrade) { MLog("SKIP", "trade execution disabled (InpEnableTrade=false)"); return false; }

   double total_lots = CalcTotalLots(s.risk_price);
   if(total_lots <= 0) { MLog("ERR", "lot size 0"); return false; }

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double third_raw = total_lots / 3.0;
   double third = MathFloor(third_raw / step) * step;
   if(third < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      MLog("WARN", "volume too small for thirds; opening single position");
      g_trade.SetExpertMagicNumber((ulong)InpMagic);
      g_trade.SetDeviationInPoints(InpSlippagePoints);
      g_trade.SetTypeFillingBySymbol(_Symbol);
      string cmt = StringFormat("Migs:%s:single", s.pattern);
      bool ok = false;
      if(s.direction == DIR_BUY) ok = g_trade.Buy (total_lots, _Symbol, s.entry, s.sl, s.tp2, cmt);
      else                       ok = g_trade.Sell(total_lots, _Symbol, s.entry, s.sl, s.tp2, cmt);
      if(!ok || (g_trade.ResultRetcode() != TRADE_RETCODE_DONE && g_trade.ResultRetcode() != TRADE_RETCODE_DONE_PARTIAL))
      {
         MLog("ERR", "single trade send failed retcode " + IntegerToString(g_trade.ResultRetcode()));
         return false;
      }
      g_group.ticket_tp1 = g_trade.ResultOrder();
      g_group.ticket_tp2 = 0;
      g_group.ticket_tp3 = 0;
   }
   else
   {
      g_trade.SetExpertMagicNumber((ulong)InpMagic);
      g_trade.SetDeviationInPoints(InpSlippagePoints);
      g_trade.SetTypeFillingBySymbol(_Symbol);

      ulong tickets[3] = {0, 0, 0};
      double tps[3];
      tps[0] = s.tp1; tps[1] = s.tp2; tps[2] = s.tp3;
      string tags[3];
      tags[0] = COMMENT_TP1; tags[1] = COMMENT_TP2; tags[2] = COMMENT_TP3;

      for(int i = 0; i < 3; i++)
      {
         string cmt = StringFormat("%s:%s", tags[i], s.pattern);
         bool ok = false;
         if(s.direction == DIR_BUY) ok = g_trade.Buy (third, _Symbol, s.entry, s.sl, tps[i], cmt);
         else                       ok = g_trade.Sell(third, _Symbol, s.entry, s.sl, tps[i], cmt);
         if(!ok || (g_trade.ResultRetcode() != TRADE_RETCODE_DONE && g_trade.ResultRetcode() != TRADE_RETCODE_DONE_PARTIAL))
         {
            MLog("ERR", StringFormat("position %d send failed retcode %d", i + 1, g_trade.ResultRetcode()));
            for(int j = 0; j < i; j++)
               if(tickets[j] != 0) g_trade.PositionClose(tickets[j]);
            return false;
         }
         tickets[i] = g_trade.ResultOrder();
         if(tickets[i] == 0) tickets[i] = g_trade.ResultDeal();
      }
      g_group.ticket_tp1 = tickets[0];
      g_group.ticket_tp2 = tickets[1];
      g_group.ticket_tp3 = tickets[2];
   }

   g_group.active       = true;
   g_group.entry        = s.entry;
   g_group.sl_initial   = s.sl;
   g_group.tp1          = s.tp1;
   g_group.tp2          = s.tp2;
   g_group.tp3          = s.tp3;
   g_group.risk_price   = s.risk_price;
   g_group.volume_each  = third;
   g_group.pattern      = s.pattern;
   g_group.direction    = s.direction;
   g_group.open_time    = TimeCurrent();
   g_group.tp1_filled   = false;
   g_group.moved_to_be  = false;
   g_group.mfe_r        = 0.0;
   g_group.mae_r        = 0.0;
   g_group.journal_id   = InpEnableJournal ? WriteOpenJournal(s) : 0;

   MLog("TRADE", StringFormat("Opened %s grp: lots=%.2f x3 entry=%s SL=%s TP1=%s TP2=%s TP3=%s tickets=%I64u/%I64u/%I64u",
                              DirStr(s.direction), third,
                              DoubleToString(s.entry, _Digits),
                              DoubleToString(s.sl, _Digits),
                              DoubleToString(s.tp1, _Digits),
                              DoubleToString(s.tp2, _Digits),
                              DoubleToString(s.tp3, _Digits),
                              g_group.ticket_tp1, g_group.ticket_tp2, g_group.ticket_tp3));
   return true;
}

//==================================================================//
//  MANAGEMENT — partial fills, BE move, MFE/MAE  (UNCHANGED)         //
//==================================================================//
void UpdateMFE_MAE()
{
   if(!g_group.active || g_group.risk_price <= 0) return;
   double cur = (g_group.direction == DIR_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double dist = (cur - g_group.entry) * (g_group.direction == DIR_BUY ? 1 : -1);
   double r = dist / g_group.risk_price;
   if(r > g_group.mfe_r) g_group.mfe_r = r;
   if(r < g_group.mae_r) g_group.mae_r = r;
}

void CheckTP1AndMoveBE()
{
   if(!g_group.active || !InpMoveSLtoBE) return;
   if(g_group.tp1_filled && g_group.moved_to_be) return;

   bool tp1_open = (g_group.ticket_tp1 != 0 && PositionSelectByTicket(g_group.ticket_tp1));
   if(!tp1_open && !g_group.tp1_filled)
   {
      g_group.tp1_filled = true;
      MLog("TRADE", "TP1 filled — moving SL of remaining positions to BE");
   }

   if(g_group.tp1_filled && !g_group.moved_to_be)
   {
      bool moved_any = false;
      ulong remaining[2] = {g_group.ticket_tp2, g_group.ticket_tp3};
      for(int i = 0; i < 2; i++)
      {
         if(remaining[i] == 0) continue;
         if(!PositionSelectByTicket(remaining[i])) continue;
         double cur_sl = PositionGetDouble(POSITION_SL);
         double cur_tp = PositionGetDouble(POSITION_TP);
         double be = g_group.entry;
         if(MathAbs(cur_sl - be) < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5) continue;
         if(g_trade.PositionModify(remaining[i], be, cur_tp))
         {
            moved_any = true;
            MLog("TRADE", StringFormat("SL→BE on ticket %I64u", remaining[i]));
         }
      }
      if(moved_any) g_group.moved_to_be = true;
   }
}

void FinalizeGroupIfClosed()
{
   if(!g_group.active) return;
   bool any_open = false;
   ulong tickets[3] = {g_group.ticket_tp1, g_group.ticket_tp2, g_group.ticket_tp3};
   for(int i = 0; i < 3; i++)
      if(tickets[i] != 0 && PositionSelectByTicket(tickets[i])) { any_open = true; break; }
   if(any_open) return;

   HistorySelect(g_group.open_time - 60, TimeCurrent() + 60);
   double total_profit = 0;
   int deals_n = HistoryDealsTotal();
   for(int i = 0; i < deals_n; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_TIME) < g_group.open_time - 5) continue;
      total_profit += HistoryDealGetDouble(d, DEAL_PROFIT)
                    + HistoryDealGetDouble(d, DEAL_SWAP)
                    + HistoryDealGetDouble(d, DEAL_COMMISSION);
   }
   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double r_realized = (risk_money > 0) ? total_profit / risk_money : 0;

   g_day_r += r_realized;
   if(InpDailyMaxLossR > 0 && g_day_r <= -InpDailyMaxLossR && !g_day_kill)
   {
      g_day_kill = true;
      MLog("RISK", StringFormat("Daily kill switch ON: %.2fR <= -%.1fR", g_day_r, InpDailyMaxLossR));
   }

   g_total_r += r_realized;
   if(r_realized > 0.05)        { g_total_wins++; g_consec_losses = 0; }
   else if(r_realized < -0.5)   { g_total_loss++; g_consec_losses++; }

   if(InpEnableJournal) UpdateCloseJournal(g_group.journal_id, r_realized, total_profit);
   MLog("TRADE", StringFormat("Group closed: P/L=%.2f R=%.2f day=%.2fR MFE=%.2fR MAE=%.2fR",
                              total_profit, r_realized, g_day_r, g_group.mfe_r, g_group.mae_r));

   g_last_close_time = TimeCurrent();
   g_group.active = false;
}

//==================================================================//
//  JOURNAL  (UNCHANGED from v0.4 — user instruction)                 //
//==================================================================//
int g_next_journal_id_cache = -1;

int NextJournalId()
{
   if(g_next_journal_id_cache < 0)
   {
      int max_id = 0;
      string fname;
      string filter = InpJournalDir + "\\*.md";
      long h = FileFindFirst(filter, fname);
      if(h != INVALID_HANDLE)
      {
         do {
            int id = (int)StringToInteger(StringSubstr(fname, 0, 4));
            if(id > max_id) max_id = id;
         } while(FileFindNext(h, fname));
         FileFindClose(h);
      }
      MqlDateTime nowdt; TimeToStruct(TimeCurrent(), nowdt);
      for(int m = 1; m <= 12; m++)
      {
         string sub = StringFormat("%s\\%04d\\%02d\\*.md", InpJournalDir, nowdt.year, m);
         h = FileFindFirst(sub, fname);
         if(h == INVALID_HANDLE) continue;
         do {
            int id = (int)StringToInteger(StringSubstr(fname, 0, 4));
            if(id > max_id) max_id = id;
         } while(FileFindNext(h, fname));
         FileFindClose(h);
      }
      g_next_journal_id_cache = max_id;
   }
   g_next_journal_id_cache++;
   return g_next_journal_id_cache;
}

string Pad4(int n) { return StringFormat("%04d", n); }

int WriteOpenJournal(const Setup &s)
{
   int id = NextJournalId();
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   string ydir = StringFormat("%s\\%04d", InpJournalDir, dt.year);
   string mdir = StringFormat("%s\\%02d", ydir, dt.mon);
   FolderCreate(InpJournalDir);
   FolderCreate(ydir);
   FolderCreate(mdir);

   string suffix = (s.direction == DIR_BUY) ? "buy" : "sell";
   string fname = StringFormat("%s\\%s-%04d-%02d-%02d-%s.md",
                               mdir, Pad4(id), dt.year, dt.mon, dt.day, suffix);

   int fh = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE) { MLog("ERR", "journal open failed: " + fname); return -1; }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWrite(fh, "---");
   FileWrite(fh, "id: \"" + Pad4(id) + "\"");
   FileWrite(fh, StringFormat("timestamp_utc: %04d-%02d-%02dT%02d:%02d:%02dZ",
                              dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec));
   FileWrite(fh, "direction: " + DirStr(s.direction));
   FileWrite(fh, "phase: DEMO");
   FileWrite(fh, "strategy: Migs");
   FileWrite(fh, "source: EA");
   FileWrite(fh, "ea_version: \"" + MIGS_VERSION + "\"");
   FileWrite(fh, "pattern: \"" + s.pattern + "\"");
   FileWrite(fh, "execution_tf: " + EnumToString((ENUM_TIMEFRAMES)_Period));
   FileWrite(fh, "htf_tf: " + EnumToString(InpHTFTimeframe));
   FileWrite(fh, "htf_bias: " + BiasStr(s.bias_htf));
   FileWrite(fh, "news_window: disabled");
   FileWrite(fh, "atr_price: " + DoubleToString(s.atr_price, digits));
   FileWrite(fh, "ob_type: " + (s.ob.is_demand ? "demand" : "supply"));
   FileWrite(fh, "ob_high: " + DoubleToString(s.ob.high, digits));
   FileWrite(fh, "ob_low: "  + DoubleToString(s.ob.low,  digits));
   FileWrite(fh, "ob_fresh: " + (s.ob.fresh ? "true" : "false"));
   FileWrite(fh, "bos_price: " + DoubleToString(s.bos.broken_swing, digits));
   FileWrite(fh, "bos_strength_price: " + DoubleToString(s.bos.strength_price, digits));
   FileWrite(fh, "entry: " + DoubleToString(s.entry, digits));
   FileWrite(fh, "sl: "    + DoubleToString(s.sl, digits));
   FileWrite(fh, "tp1: "   + DoubleToString(s.tp1, digits));
   FileWrite(fh, "tp2: "   + DoubleToString(s.tp2, digits));
   FileWrite(fh, "tp3: "   + DoubleToString(s.tp3, digits));
   FileWrite(fh, "risk_price: " + DoubleToString(s.risk_price, digits));
   FileWrite(fh, "outcome: OPEN");
   FileWrite(fh, "r_realized: 0.0");
   FileWrite(fh, "mfe_r: 0.0");
   FileWrite(fh, "mae_r: 0.0");
   FileWrite(fh, "exit_reason: \"\"");
   FileWrite(fh, "---");
   FileWrite(fh, "");
   FileWrite(fh, "## Notes");
   FileWrite(fh, "");
   FileWrite(fh, StringFormat("EA-generated %s entry on %s %s. HTF bias %s.",
                              s.pattern, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period), BiasStr(s.bias_htf)));
   FileClose(fh);
   MLog("JOURNAL", "wrote " + fname);
   return id;
}

bool UpdateCloseJournal(const int id, const double r_realized, const double profit_money)
{
   if(id <= 0) return false;
   MqlDateTime nowdt; TimeToStruct(TimeCurrent(), nowdt);
   string filter = StringFormat("%s\\%04d\\%02d\\%s-*.md", InpJournalDir, nowdt.year, nowdt.mon, Pad4(id));
   string fname;
   long h = FileFindFirst(filter, fname);
   if(h == INVALID_HANDLE) { MLog("ERR", "journal not found id=" + IntegerToString(id)); return false; }
   string path = StringFormat("%s\\%04d\\%02d\\%s", InpJournalDir, nowdt.year, nowdt.mon, fname);
   FileFindClose(h);

   int fh = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE) { MLog("ERR", "journal read failed: " + path); return false; }
   string lines[];
   int n = 0;
   while(!FileIsEnding(fh))
   {
      ArrayResize(lines, n + 1);
      lines[n++] = FileReadString(fh);
   }
   FileClose(fh);

   string outcome = "BE";
   if(r_realized >= 1.5)        outcome = "TP3_HIT";
   else if(r_realized >= 0.5)   outcome = "TP2_HIT";
   else if(r_realized >= 0.1)   outcome = "TP1_HIT";
   else if(r_realized <= -0.7)  outcome = "SL_HIT";

   for(int i = 0; i < n; i++)
   {
      if(StringFind(lines[i], "outcome:") == 0)     lines[i] = "outcome: " + outcome;
      if(StringFind(lines[i], "r_realized:") == 0)  lines[i] = "r_realized: " + DoubleToString(r_realized, 3);
      if(StringFind(lines[i], "mfe_r:") == 0)       lines[i] = "mfe_r: " + DoubleToString(g_group.mfe_r, 3);
      if(StringFind(lines[i], "mae_r:") == 0)       lines[i] = "mae_r: " + DoubleToString(g_group.mae_r, 3);
      if(StringFind(lines[i], "exit_reason:") == 0) lines[i] = "exit_reason: \"" + outcome + "\"";
   }

   fh = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE) return false;
   for(int i = 0; i < n; i++) FileWrite(fh, lines[i]);
   FileClose(fh);
   MLog("JOURNAL", "updated " + path + " -> " + outcome);
   return true;
}

//==================================================================//
//  STATUS PANEL  (UNCHANGED from v0.4 — user instruction)            //
//==================================================================//
void StatusEnsureLabel(string suffix, int x, int y, string text, color clr)
{
   string nm = PANEL_PREFIX + suffix;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     InpStatusCorner);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,
         InpStatusCorner == CORNER_RIGHT_UPPER || InpStatusCorner == CORNER_RIGHT_LOWER
            ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER,     1000);
      ObjectSetString (0, nm, OBJPROP_FONT,       InpStatusFontName);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, InpStatusXOffset + x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, InpStatusYOffset + y);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  InpStatusFontSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     clr);
   ObjectSetString (0, nm, OBJPROP_TEXT,      text);
}

void StatusDeleteKey(string suffix)
{
   string nm = PANEL_PREFIX + suffix;
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
}

void StatusCleanup()
{
   ObjectsDeleteAll(0, PANEL_PREFIX);
}

void DrawStatusPanel()
{
   if(!InpShowStatus) { StatusCleanup(); return; }

   int line_h = InpStatusFontSize + 5;
   int y      = 0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string ccy = AccountInfoString(ACCOUNT_CURRENCY);

   StatusEnsureLabel("hdr", 0, y,
      "===== MIGS HYBRID v" + MIGS_VERSION + " =====", InpStatusHeaderClr);
   y += line_h;

   color stat_clr = InpStatusGoodClr;
   string stat_str = "READY";
   if(!InpEnableTrade)        { stat_clr = InpStatusMutedClr; stat_str = "DISABLED (input)"; }
   else if(g_day_kill)        { stat_clr = InpStatusBadClr;   stat_str = "KILL-SWITCH"; }
   else if(g_group.active)    { stat_clr = InpStatusHeaderClr;stat_str = "IN-TRADE"; }
   else if(!CooldownPassed()) { stat_clr = InpStatusMutedClr; stat_str = "COOLDOWN"; }
   StatusEnsureLabel("state", 0, y, "State    : " + stat_str, stat_clr);
   y += line_h;

   StatusEnsureLabel("sym", 0, y,
      StringFormat("Symbol   : %s %s", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)),
      InpStatusColor);
   y += line_h;

   ENUM_BIAS bias = GetCachedHTFBias();
   color bias_clr = (bias == BIAS_BULL) ? InpStatusGoodClr
                  : (bias == BIAS_BEAR) ? InpStatusBadClr
                                        : InpStatusMutedClr;
   StatusEnsureLabel("htf", 0, y,
      StringFormat("HTF      : %s (EMA %d/%d) %s",
                   EnumToString(InpHTFTimeframe), InpHTFFastEMA, InpHTFSlowEMA,
                   BiasStr(bias)),
      bias_clr);
   y += line_h;

   // Active BOS row (v0.5 — diagnostic)
   if(g_active_bos.active)
   {
      int sh = iBarShift(_Symbol, _Period, g_active_bos.detected_at, true);
      color bos_clr = g_active_bos.is_bullish ? InpStatusGoodClr : InpStatusBadClr;
      StatusEnsureLabel("bos", 0, y,
         StringFormat("BOS      : %s @shift %d (%s)",
                      g_active_bos.is_bullish ? "BULL" : "BEAR",
                      sh,
                      DoubleToString(g_active_bos.broken_swing, digits)),
         bos_clr);
      y += line_h;
   }
   else
   {
      StatusEnsureLabel("bos", 0, y, "BOS      : none active", InpStatusMutedClr);
      y += line_h;
   }

   if(InpEnableChopFilter)
   {
      color  chop_clr;
      string chop_str;
      if(g_chop_reason != "") { chop_clr = InpStatusBadClr;  chop_str = g_chop_reason; }
      else                    { chop_clr = InpStatusGoodClr; chop_str = StringFormat("OK ADX=%.1f ATR-r=%.2f", g_last_adx, g_last_atr_ratio); }
      StatusEnsureLabel("chop", 0, y, "Chop     : " + chop_str, chop_clr);
      y += line_h;
   }

   bool is_real = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL);
   StatusEnsureLabel("acct", 0, y,
      "Account  : " + (is_real ? "LIVE" : "DEMO"),
      is_real ? InpStatusWarnClr : InpStatusColor);
   y += line_h;

   StatusEnsureLabel("eq", 0, y,
      StringFormat("Equity   : %.2f %s", AccountInfoDouble(ACCOUNT_EQUITY), ccy),
      InpStatusColor);
   y += line_h;

   color day_clr = (g_day_r > 0) ? InpStatusGoodClr
                 : (g_day_r < 0) ? InpStatusBadClr
                                 : InpStatusMutedClr;
   StatusEnsureLabel("dR", 0, y,
      StringFormat("Day R    : %+.2fR (kill @ -%.1fR)", g_day_r, InpDailyMaxLossR),
      day_clr);
   y += line_h;

   int decisive = g_total_wins + g_total_loss;
   double live_wr = (decisive > 0) ? (double)g_total_wins / decisive : 0.0;
   color wr_clr = (decisive == 0) ? InpStatusMutedClr
                : (live_wr >= InpTargetWinRate ? InpStatusGoodClr : InpStatusBadClr);
   string wr_str = (decisive == 0)
      ? StringFormat("WR       : 0/0   (target %.0f%%)", InpTargetWinRate * 100)
      : StringFormat("WR       : %.0f%% (%d/%d, target %.0f%%, %+.1fR)",
                     live_wr * 100, g_total_wins, decisive, InpTargetWinRate * 100, g_total_r);
   StatusEnsureLabel("wr", 0, y, wr_str, wr_clr);
   y += line_h;

   StatusEnsureLabel("strk", 0, y,
      StringFormat("Consec L : %d", g_consec_losses), InpStatusMutedClr);
   y += line_h;

   StatusEnsureLabel("ev", 0, y, "Last eval: " + g_last_eval_msg, InpStatusMutedClr);
   y += line_h;

   if(g_group.active)
   {
      StatusEnsureLabel("sep1", 0, y, "------------------", InpStatusMutedClr);
      y += line_h;
      color dir_clr = (g_group.direction == DIR_BUY) ? InpStatusGoodClr : InpStatusBadClr;
      StatusEnsureLabel("th", 0, y, "TRADE: " + DirStr(g_group.direction), dir_clr);
      y += line_h;
      StatusEnsureLabel("te", 0, y, "Entry: " + DoubleToString(g_group.entry, digits), InpStatusColor);
      y += line_h;
      double sl_disp = g_group.moved_to_be ? g_group.entry : g_group.sl_initial;
      color sl_clr   = g_group.moved_to_be ? InpStatusGoodClr : InpStatusColor;
      string sl_tag  = g_group.moved_to_be ? " (BE)" : "";
      StatusEnsureLabel("ts", 0, y, "SL   : " + DoubleToString(sl_disp, digits) + sl_tag, sl_clr);
      y += line_h;
      string tp1_tag = g_group.tp1_filled ? " [FILLED]" : "";
      color  tp1_clr = g_group.tp1_filled ? InpStatusGoodClr : InpStatusColor;
      StatusEnsureLabel("t1", 0, y, "TP1  : " + DoubleToString(g_group.tp1, digits) + tp1_tag, tp1_clr);
      y += line_h;
      StatusEnsureLabel("t2", 0, y, "TP2  : " + DoubleToString(g_group.tp2, digits), InpStatusColor);
      y += line_h;
      StatusEnsureLabel("t3", 0, y, "TP3  : " + DoubleToString(g_group.tp3, digits), InpStatusColor);
      y += line_h;
      StatusEnsureLabel("tmf", 0, y,
         StringFormat("MFE/MAE: %+.2fR / %+.2fR", g_group.mfe_r, g_group.mae_r),
         InpStatusMutedClr);
      y += line_h;
   }
   else
   {
      string trade_keys[] = {"sep1", "th", "te", "ts", "t1", "t2", "t3", "tmf"};
      for(int i = 0; i < ArraySize(trade_keys); i++) StatusDeleteKey(trade_keys[i]);
   }

   ChartRedraw(0);
}

//==================================================================//
//  DAILY RESET + NEW-BAR                                             //
//==================================================================//
void RollDayIfNeeded()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(today != g_day_start)
   {
      g_day_start = today;
      g_day_r     = 0.0;
      g_day_kill  = false;
      MLog("RISK", "new UTC day; counters reset");
   }
}

bool IsNewBar()
{
   datetime t[1];
   if(CopyTime(_Symbol, _Period, 0, 1, t) != 1) return false;
   if(t[0] != g_last_bar) { g_last_bar = t[0]; return true; }
   return false;
}

//==================================================================//
//  EVENT HANDLERS                                                    //
//==================================================================//
int OnInit(void)
{
   MLog("INIT", StringFormat("MigsHybrid v%s on %s %s magic=%d risk=%.2f%%",
                             MIGS_VERSION, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                             InpMagic, InpRiskPercent));

   if(!g_symbol.Name(_Symbol)) { MLog("ERR", "symbol info failed"); return INIT_FAILED; }

   g_hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE) { MLog("ERR", "iATR failed"); return INIT_FAILED; }

   g_hADX = iADX(_Symbol, InpADXTimeframe, InpADXPeriod);
   if(g_hADX == INVALID_HANDLE) { MLog("ERR", "iADX failed"); return INIT_FAILED; }

   g_hEMA_HTF_fast = iMA(_Symbol, InpHTFTimeframe, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMA_HTF_fast == INVALID_HANDLE) { MLog("ERR", "iMA fast failed"); return INIT_FAILED; }

   g_hEMA_HTF_slow = iMA(_Symbol, InpHTFTimeframe, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMA_HTF_slow == INVALID_HANDLE) { MLog("ERR", "iMA slow failed"); return INIT_FAILED; }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   FolderCreate(InpJournalDir);
   EventSetTimer(1);
   RollDayIfNeeded();

   // Reset BOS persistence on init; rebuild on first new bar.
   g_active_bos.active = false;
   ScanAndUpdateBOSState();

   DrawStatusPanel();

   PrintFormat("MigsHybrid v%s initialized. HTF=%s EMA %d/%d. ADX TF=%s. Chart TF=%s. Strict=%s.",
               MIGS_VERSION,
               EnumToString(InpHTFTimeframe), InpHTFFastEMA, InpHTFSlowEMA,
               EnumToString(InpADXTimeframe), EnumToString((ENUM_TIMEFRAMES)_Period),
               InpStrictHTFBias ? "true" : "false");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hATR          != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hADX          != INVALID_HANDLE) IndicatorRelease(g_hADX);
   if(g_hEMA_HTF_fast != INVALID_HANDLE) IndicatorRelease(g_hEMA_HTF_fast);
   if(g_hEMA_HTF_slow != INVALID_HANDLE) IndicatorRelease(g_hEMA_HTF_slow);
   StatusCleanup();
   ChartRedraw(0);
   MLog("DEINIT", "reason=" + IntegerToString(reason));
}

void OnTimer(void)
{
   RollDayIfNeeded();
   DrawStatusPanel();
}

void OnTick(void)
{
   if(g_group.active)
   {
      UpdateMFE_MAE();
      CheckTP1AndMoveBE();
      FinalizeGroupIfClosed();
   }

   datetime now = TimeCurrent();
   if(InpShowStatus && now != g_status_redraw_t)
   {
      g_status_redraw_t = now;
      DrawStatusPanel();
   }

   if(!IsNewBar()) return;

   // Refresh BOS state once per new chart bar.
   ScanAndUpdateBOSState();

   if(g_group.active) return;
   if(!DailyRiskAllow()) return;
   if(!CooldownPassed()) return;
   if(CountMigsPositions() >= InpMaxConcurrent) return;
   if(!InpEnableTrade) return;

   Setup s;
   if(!BuildSetup(s))
   {
      g_last_eval_msg = (s.reject_reason != "") ? s.reject_reason : "no setup";
      if(InpVerbose) MLog("EVAL", g_last_eval_msg);
      DrawStatusPanel();
      return;
   }

   g_last_eval_msg = StringFormat("SIGNAL %s @%s",
                                  DirStr(s.direction), DoubleToString(s.entry, _Digits));
   MLog("SIGNAL", StringFormat("%s pattern=%s entry=%s SL=%s TP1=%s TP2=%s TP3=%s htf=%s",
                                DirStr(s.direction), s.pattern,
                                DoubleToString(s.entry, _Digits),
                                DoubleToString(s.sl, _Digits),
                                DoubleToString(s.tp1, _Digits),
                                DoubleToString(s.tp2, _Digits),
                                DoubleToString(s.tp3, _Digits),
                                BiasStr(s.bias_htf)));

   ExecuteSetup(s);
   DrawStatusPanel();
}

void OnTrade(void)
{
   if(g_group.active)
   {
      CheckTP1AndMoveBE();
      FinalizeGroupIfClosed();
   }
}
