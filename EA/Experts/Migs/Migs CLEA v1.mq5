//+------------------------------------------------------------------+
//|                                                       MigsEA.mq5  |
//|              Migs Hybrid Strategy — Universal Expert Advisor      |
//|                                                                   |
//|  Single-file MT5 EA. Paste into MetaEditor and compile (F7).      |
//|  Works on any symbol, any account (demo or live), any session.    |
//|                                                                   |
//|  Strategy:                                                        |
//|    1. Detect M5 BOS (decisive break of recent fractal swing)      |
//|    2. Identify the OB that produced the BOS impulse               |
//|    3. Confirm 1H bias aligns with the M5 BOS direction            |
//|    4. Compute entry (current price near OB), SL (OB edge+buffer)  |
//|    5. Open three positions sized 1/3 each:                        |
//|         - Position A: TP1 = entry +1R                             |
//|         - Position B: TP2 = entry +2R                             |
//|         - Position C: TP3 = entry +3R                             |
//|    6. On TP1 fill: move SL of B and C to entry (BE)               |
//|    7. On TP3 fill: trade complete                                 |
//|    8. On full SL hit: total loss = –1R                            |
//|                                                                   |
//|  Outcomes (assuming SL=BE after TP1):                             |
//|    All 3 TPs hit                    : +2.0R                       |
//|    TP1 + TP2 hit, TP3 BE            : +1.0R                       |
//|    TP1 hit, TP2/TP3 BE              : +0.33R                      |
//|    SL hit before TP1                : –1.0R                       |
//+------------------------------------------------------------------+
#property copyright "Migs"
#property version   "0.30"
#property description "Migs Hybrid Strategy EA — universal symbol/account. 3-TP thirds ladder."
#property strict

#include <Trade\Trade.mqh>

//==================================================================//
//  INPUTS                                                            //
//==================================================================//
input group "=== Risk & Sizing ==="
input double InpRiskPercent       = 1.0;       // % equity risk per trade (all 3 positions combined)
input double InpMaxLotsPerPos     = 100.0;     // safety cap; broker max overrides

input group "=== Structure Detection ==="
input int    InpSwingLookback     = 200;       // M5 bars scanned for swings
input int    InpSwingStrength     = 2;         // fractal strength (bars left/right)
input int    InpMaxBOSAgeBars     = 30;        // ignore BOS older than N M5 bars
input int    InpOBMaxAgeBars      = 60;        // ignore OB older than N M5 bars
input double InpEntryProximityATR = 0.7;       // enter when price within N*ATR of OB
input int    InpATRPeriod         = 14;

input group "=== HTF Bias ==="
input bool   InpRequire1HBias     = true;      // skip trade if 1H bias conflicts
input int    InpH1Lookback        = 200;       // H1 bars scanned for BOS
input int    InpH1MaxBOSAge       = 50;        // ignore H1 BOS older than N bars (ranging)

input group "=== Chop / Consolidation Filter ==="
input bool             InpEnableChopFilter   = true;   // master toggle
input bool             InpStrictH1Bias       = true;   // reject when 1H bias is RANGING
input double           InpADXMinimum         = 20.0;   // ADX must be >= this (0 = disable)
input int              InpADXPeriod          = 14;
input ENUM_TIMEFRAMES  InpADXTimeframe       = PERIOD_M15;
input int              InpBOSConflictBars    = 40;     // M5 bars scanned for opposite BOS (0 = disable)
input double           InpATRExpansionRatio  = 0.80;   // current ATR / ATR-MA must be >= this (0 = disable)
input int              InpATRMAPeriod        = 50;     // bars in ATR moving average

input group "=== Trade Management ==="
input int    InpMagic             = 20260522;
input int    InpMaxConcurrent     = 1;         // max simultaneous Migs trade groups
input int    InpSlippagePoints    = 30;
input bool   InpMoveSLtoBE        = true;      // SL→BE on remaining positions after TP1
input bool   InpEnableTrade       = true;      // master kill switch

input group "=== Safety ==="
input double InpDailyMaxLossR     = 3.0;       // kill switch after -N R / day (0 = off)
input int    InpMinBarsBetweenTrades = 6;      // cooldown after a close (M5 bars)

input group "=== Journal (optional) ==="
input bool   InpEnableJournal     = true;
input string InpJournalDir        = "Migs\\journal";

input group "=== Logging ==="
input bool   InpVerbose           = true;

input group "=== On-Chart Status Panel ==="
input bool             InpShowStatus       = true;
input ENUM_BASE_CORNER InpStatusCorner     = CORNER_LEFT_UPPER;
input int              InpStatusXOffset    = 10;
input int              InpStatusYOffset    = 20;
input int              InpStatusFontSize   = 9;
input string           InpStatusFontName   = "Consolas";
input color            InpStatusColor      = clrWhite;
input color            InpStatusHeaderClr  = clrGold;
input color            InpStatusGoodClr    = clrLimeGreen;
input color            InpStatusBadClr     = clrTomato;
input color            InpStatusMutedClr   = clrSilver;

//==================================================================//
//  CONSTANTS                                                         //
//==================================================================//
#define MIGS_VERSION    "0.3.0"
#define COMMENT_TP1     "MigsHybrid:TP1"
#define COMMENT_TP2     "MigsHybrid:TP2"
#define COMMENT_TP3     "MigsHybrid:TP3"

//==================================================================//
//  ENUMS                                                             //
//==================================================================//
enum ENUM_DIR    { DIR_NONE = 0, DIR_BUY = 1, DIR_SELL = 2 };
enum ENUM_BIAS   { BIAS_RANGE = 0, BIAS_BULL = 1, BIAS_BEAR = 2 };
enum ENUM_TP_TAG { TP_NONE = 0, TP_1 = 1, TP_2 = 2, TP_3 = 3 };

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

struct OB
{
   bool   valid;
   bool   is_demand;     // true for BUY setups, false for SELL
   double high;
   double low;
   int    shift;
   bool   fresh;
};

struct BOS
{
   bool   valid;
   bool   is_bullish;
   double broken_swing;
   double strength_price;  // body size in price units
   int    shift;
};

struct Setup
{
   bool        valid;
   ENUM_DIR    direction;
   ENUM_BIAS   bias_h1;
   OB          ob;
   BOS         bos;
   double      entry;
   double      sl;
   double      tp1;
   double      tp2;
   double      tp3;
   double      risk_price;     // |entry - sl| in price units
   double      atr_price;
   string      pattern;        // "01" for BUY, "02" for SELL
   string      reject_reason;
};

struct TradeGroup
{
   bool   active;
   double entry;
   double sl_initial;
   double tp1;
   double tp2;
   double tp3;
   double risk_price;
   double volume_each;
   string pattern;
   ENUM_DIR direction;
   datetime open_time;
   bool   tp1_filled;
   bool   moved_to_be;
   double mfe_r;
   double mae_r;
   int    journal_id;
};

//==================================================================//
//  GLOBALS                                                           //
//==================================================================//
CTrade       g_trade;
int          g_atr_handle  = INVALID_HANDLE;
int          g_adx_handle  = INVALID_HANDLE;
double       g_last_adx    = 0.0;
double       g_last_atr_ratio = 1.0;
string       g_chop_reason = "";
datetime     g_last_m5     = 0;
datetime     g_day_start   = 0;
double       g_day_r       = 0.0;
bool         g_day_kill    = false;
TradeGroup   g_group;
datetime     g_last_close_time = 0;
string       g_last_eval_msg   = "(none)";
datetime     g_status_redraw_t = 0;
ENUM_BIAS    g_cached_bias_h1  = BIAS_RANGE;
datetime     g_cached_bias_t   = 0;

#define STATUS_PREFIX "MigsStatus_"

//==================================================================//
//  LOGGING                                                           //
//==================================================================//
void MLog(const string tag, const string msg)
{
   if(!InpVerbose && tag != "ERR" && tag != "TRADE" && tag != "JOURNAL") return;
   PrintFormat("[MIGS][%s] %s", tag, msg);
}

string DirStr(const ENUM_DIR d)   { return d==DIR_BUY?"BUY":d==DIR_SELL?"SELL":"NONE"; }
string BiasStr(const ENUM_BIAS b) { return b==BIAS_BULL?"bullish":b==BIAS_BEAR?"bearish":"ranging"; }

//==================================================================//
//  PRICE / PIP / LOT HELPERS                                         //
//==================================================================//
double NormPrice(const double p)
{
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double PointSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

double TickSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
}

double TickValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
}

double LotStep()       { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); }
double LotMin()        { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double LotMaxBroker()  { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); }

double NormalizeLot(double lots)
{
   double step = LotStep();
   double minl = LotMin();
   double maxl = MathMin(LotMaxBroker(), InpMaxLotsPerPos);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   if(lots < minl) lots = minl;
   if(lots > maxl) lots = maxl;
   // Final rounding to step precision to avoid float drift
   int step_digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
   lots = NormalizeDouble(lots, step_digits);
   return lots;
}

// Lot size such that loss at sl_price_dist equals risk_money
double ComputeLot(const double sl_price_dist, const double risk_money)
{
   double tsize = TickSize();
   double tval  = TickValue();
   if(tsize <= 0 || tval <= 0 || sl_price_dist <= 0 || risk_money <= 0) return 0;
   double ticks_in_sl = sl_price_dist / tsize;
   if(ticks_in_sl <= 0) return 0;
   double money_per_lot = ticks_in_sl * tval;
   if(money_per_lot <= 0) return 0;
   double lots = risk_money / money_per_lot;
   return NormalizeLot(lots);
}

double ATRPrice()
{
   if(g_atr_handle == INVALID_HANDLE) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atr_handle, 0, 0, 1, buf) < 1) return 0;
   return buf[0];
}

//==================================================================//
//  STRUCTURE: SWINGS / BOS / OB                                      //
//==================================================================//
int FindSwings(const ENUM_TIMEFRAMES tf, const int lookback, const int strength,
               Swing &out[])
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

   int count = 0;
   for(int i = strength; i < lookback - strength; i++)
   {
      bool is_h = true, is_l = true;
      for(int k = 1; k <= strength; k++)
      {
         if(highs[i] <= highs[i-k] || highs[i] <= highs[i+k]) is_h = false;
         if(lows [i] >= lows [i-k] || lows [i] >= lows [i+k]) is_l = false;
         if(!is_h && !is_l) break;
      }
      if(is_h || is_l)
      {
         ArrayResize(out, count + 1);
         out[count].time      = times[i];
         out[count].price     = is_h ? highs[i] : lows[i];
         out[count].is_high   = is_h;
         out[count].bar_index = i;
         count++;
      }
   }
   return count;
}

bool DetectLastBOS(const ENUM_TIMEFRAMES tf, const int lookback, const int strength,
                   BOS &out)
{
   out.valid = false;
   Swing sw[];
   int n = FindSwings(tf, lookback, strength, sw);
   if(n < 2) return false;

   double closes[], opens[];
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(opens,  true);
   if(CopyClose(_Symbol, tf, 0, lookback, closes) != lookback) return false;
   if(CopyOpen (_Symbol, tf, 0, lookback, opens ) != lookback) return false;

   for(int i = 1; i < lookback - 1; i++)
   {
      double last_high = 0, last_low = 0;
      int    lhi = -1, lli = -1;
      for(int s = 0; s < n; s++)
      {
         if(sw[s].bar_index <= i) continue;
         if(sw[s].is_high  && lhi < 0) { last_high = sw[s].price; lhi = sw[s].bar_index; }
         if(!sw[s].is_high && lli < 0) { last_low  = sw[s].price; lli = sw[s].bar_index; }
         if(lhi >= 0 && lli >= 0) break;
      }
      if(lhi >= 0 && closes[i] > last_high)
      {
         out.valid = true;
         out.is_bullish = true;
         out.broken_swing = last_high;
         out.strength_price = MathAbs(closes[i] - opens[i]);
         out.shift = i;
         return true;
      }
      if(lli >= 0 && closes[i] < last_low)
      {
         out.valid = true;
         out.is_bullish = false;
         out.broken_swing = last_low;
         out.strength_price = MathAbs(opens[i] - closes[i]);
         out.shift = i;
         return true;
      }
   }
   return false;
}

bool DetectOB(const ENUM_TIMEFRAMES tf, const BOS &bos, OB &out)
{
   out.valid = false;
   if(!bos.valid) return false;

   int max_scan = MathMin(InpOBMaxAgeBars, 200);
   int copy = bos.shift + max_scan + 2;
   double opens[], closes[], highs[], lows[];
   ArraySetAsSeries(opens,  true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(highs,  true);
   ArraySetAsSeries(lows,   true);
   if(CopyOpen (_Symbol, tf, 0, copy, opens)  != copy) return false;
   if(CopyClose(_Symbol, tf, 0, copy, closes) != copy) return false;
   if(CopyHigh (_Symbol, tf, 0, copy, highs)  != copy) return false;
   if(CopyLow  (_Symbol, tf, 0, copy, lows)   != copy) return false;

   // Last opposite-color candle before the BOS impulse
   for(int i = bos.shift + 1; i < bos.shift + max_scan; i++)
   {
      bool down = (closes[i] < opens[i]);
      bool up   = (closes[i] > opens[i]);
      if(bos.is_bullish && down)
      {
         out.valid     = true;
         out.is_demand = true;
         out.high      = highs[i];
         out.low       = lows[i];
         out.shift     = i;
         break;
      }
      if(!bos.is_bullish && up)
      {
         out.valid     = true;
         out.is_demand = false;
         out.high      = highs[i];
         out.low       = lows[i];
         out.shift     = i;
         break;
      }
   }
   if(!out.valid) return false;

   // Freshness: has price re-entered the OB between then and now?
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

ENUM_BIAS DetectH1Bias()
{
   BOS b;
   if(!DetectLastBOS(PERIOD_H1, InpH1Lookback, InpSwingStrength, b)) return BIAS_RANGE;
   if(b.shift > InpH1MaxBOSAge) return BIAS_RANGE;
   return b.is_bullish ? BIAS_BULL : BIAS_BEAR;
}

//==================================================================//
//  CHOP / CONSOLIDATION FILTER                                       //
//==================================================================//
double ReadADX()
{
   if(g_adx_handle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_adx_handle, 0, 0, 1, buf) < 1) return 0.0;
   return buf[0];
}

double ATRExpansionRatio()
{
   if(g_atr_handle == INVALID_HANDLE) return 1.0;
   int n = InpATRMAPeriod + 5;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atr_handle, 0, 0, n, buf) < n) return 1.0;
   double sum = 0;
   for(int i = 1; i <= InpATRMAPeriod; i++) sum += buf[i];
   double ma = sum / InpATRMAPeriod;
   if(ma <= 0) return 1.0;
   return buf[0] / ma;
}

// Did an opposite-direction BOS print within the last `bars` M5 candles?
// If yes, market just whipsawed and is likely chopping.
bool HasOppositeBOSRecently(const bool current_is_bullish, const int bars)
{
   if(bars <= 0) return false;
   int copy = bars + 10;
   double closes[], opens[];
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(opens,  true);
   if(CopyClose(_Symbol, PERIOD_M5, 0, copy, closes) != copy) return false;
   if(CopyOpen (_Symbol, PERIOD_M5, 0, copy, opens ) != copy) return false;

   Swing sw[];
   int n = FindSwings(PERIOD_M5, copy, InpSwingStrength, sw);
   if(n < 2) return false;

   for(int i = 1; i <= bars; i++)
   {
      double last_high = 0, last_low = 0;
      int    lhi = -1, lli = -1;
      for(int s = 0; s < n; s++)
      {
         if(sw[s].bar_index <= i) continue;
         if(sw[s].is_high  && lhi < 0) { last_high = sw[s].price; lhi = sw[s].bar_index; }
         if(!sw[s].is_high && lli < 0) { last_low  = sw[s].price; lli = sw[s].bar_index; }
         if(lhi >= 0 && lli >= 0) break;
      }
      bool bull_break = (lhi >= 0 && closes[i] > last_high);
      bool bear_break = (lli >= 0 && closes[i] < last_low);
      if(current_is_bullish && bear_break) return true;
      if(!current_is_bullish && bull_break) return true;
   }
   return false;
}

bool IsChoppy(const Setup &s, string &reason)
{
   reason = "";
   if(!InpEnableChopFilter) return false;

   // 1. Strict H1 bias — reject when bias is unclear/ranging
   if(InpStrictH1Bias && s.bias_h1 == BIAS_RANGE)
   {
      reason = "1H bias ranging";
      return true;
   }

   // 2. ADX threshold (HTF directional strength)
   if(InpADXMinimum > 0)
   {
      double adx = ReadADX();
      g_last_adx = adx;
      if(adx > 0 && adx < InpADXMinimum)
      {
         reason = StringFormat("ADX %.1f < %.1f", adx, InpADXMinimum);
         return true;
      }
   }

   // 3. Opposite BOS in recent history = whipsaw
   if(InpBOSConflictBars > 0)
   {
      if(HasOppositeBOSRecently(s.direction == DIR_BUY, InpBOSConflictBars))
      {
         reason = StringFormat("whipsaw: opposite BOS within %d M5 bars", InpBOSConflictBars);
         return true;
      }
   }

   // 4. ATR squeeze (low-volatility consolidation)
   if(InpATRExpansionRatio > 0)
   {
      double ratio = ATRExpansionRatio();
      g_last_atr_ratio = ratio;
      if(ratio < InpATRExpansionRatio)
      {
         reason = StringFormat("ATR squeeze %.2f < %.2f", ratio, InpATRExpansionRatio);
         return true;
      }
   }

   return false;
}

//==================================================================//
//  SETUP BUILDER                                                     //
//==================================================================//
bool BuildSetup(Setup &s)
{
   s.valid = false;
   s.reject_reason = "";

   // 1. M5 BOS
   BOS bos;
   if(!DetectLastBOS(PERIOD_M5, InpSwingLookback, InpSwingStrength, bos))
   { s.reject_reason = "no M5 BOS"; return false; }
   if(bos.shift > InpMaxBOSAgeBars)
   { s.reject_reason = "M5 BOS too old"; return false; }
   s.bos = bos;

   ENUM_DIR dir = bos.is_bullish ? DIR_BUY : DIR_SELL;
   s.direction = dir;
   s.pattern = (dir == DIR_BUY) ? "buy" : "sell";

   // 2. OB
   OB ob;
   if(!DetectOB(PERIOD_M5, bos, ob))
   { s.reject_reason = "no OB"; return false; }
   s.ob = ob;

   // 3. 1H bias
   s.bias_h1 = DetectH1Bias();
   if(InpRequire1HBias)
   {
      bool aligned = (dir == DIR_BUY  && (s.bias_h1 == BIAS_BULL  || s.bias_h1 == BIAS_RANGE))
                  || (dir == DIR_SELL && (s.bias_h1 == BIAS_BEAR  || s.bias_h1 == BIAS_RANGE));
      if(!aligned) { s.reject_reason = "1H bias conflicts (" + BiasStr(s.bias_h1) + ")"; return false; }
   }

   // 3b. Chop / consolidation filter
   string chop_why;
   if(IsChoppy(s, chop_why))
   {
      g_chop_reason   = chop_why;
      s.reject_reason = "chop: " + chop_why;
      return false;
   }
   g_chop_reason = "";

   // 4. Entry proximity check — current price must be within N*ATR of the OB
   double atr = ATRPrice();
   s.atr_price = atr;
   if(atr <= 0) { s.reject_reason = "ATR unavailable"; return false; }
   double cur = (dir == DIR_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist_to_ob = 0;
   if(dir == DIR_BUY)
   {
      // Want current price to be near or inside the demand OB
      if(cur > ob.high) dist_to_ob = cur - ob.high;
      else              dist_to_ob = 0;  // already inside / below — touch
   }
   else
   {
      // Want current price to be near or inside the supply OB
      if(cur < ob.low) dist_to_ob = ob.low - cur;
      else              dist_to_ob = 0;
   }
   if(dist_to_ob > InpEntryProximityATR * atr)
   { s.reject_reason = StringFormat("price too far from OB (%.2fx ATR)", dist_to_ob / atr); return false; }

   // 5. SL — beyond OB edge with small buffer (10% of ATR)
   double buffer = atr * 0.10;
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

   // 6. Mechanical TPs — 1R, 2R, 3R
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
//  TRADE EXECUTION                                                   //
//==================================================================//
int CountMigsPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      n++;
   }
   return n;
}

ENUM_TP_TAG ParseTpTag(const string comment)
{
   if(StringFind(comment, COMMENT_TP1) >= 0) return TP_1;
   if(StringFind(comment, COMMENT_TP2) >= 0) return TP_2;
   if(StringFind(comment, COMMENT_TP3) >= 0) return TP_3;
   return TP_NONE;
}

bool DailyRiskAllow()
{
   if(InpDailyMaxLossR <= 0) return true;
   return !g_day_kill;
}

bool CooldownPassed()
{
   if(g_last_close_time == 0) return true;
   datetime now = TimeCurrent();
   long bars = (now - g_last_close_time) / (PeriodSeconds(PERIOD_M5));
   return bars >= InpMinBarsBetweenTrades;
}

bool ExecuteSetup(const Setup &s)
{
   if(!InpEnableTrade) { MLog("SKIP", "trade disabled by input"); return false; }
   if(!DailyRiskAllow()) { MLog("SKIP", "daily kill switch active"); return false; }
   if(!CooldownPassed()) { MLog("SKIP", "cooldown active"); return false; }
   if(CountMigsPositions() > 0) { MLog("SKIP", "existing Migs positions open"); return false; }
   if(g_group.active) { MLog("SKIP", "group already active"); return false; }

   // Total risk = InpRiskPercent of equity
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double total_risk = equity * InpRiskPercent / 100.0;

   // Each of 3 positions risks 1/3 of total
   double per_pos_risk = total_risk / 3.0;
   double lots_each    = ComputeLot(s.risk_price, per_pos_risk);
   if(lots_each <= 0)
   {
      MLog("ERR", StringFormat("Lot size 0; risk_price=%.5f equity=%.2f per_pos_risk=%.2f",
                                s.risk_price, equity, per_pos_risk));
      return false;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   string tps[]      = { COMMENT_TP1, COMMENT_TP2, COMMENT_TP3 };
   double tp_prices[] = { s.tp1, s.tp2, s.tp3 };
   int    opened = 0;

   for(int i = 0; i < 3; i++)
   {
      bool ok;
      if(s.direction == DIR_BUY)
         ok = g_trade.Buy(lots_each, _Symbol, s.entry, s.sl, tp_prices[i], tps[i]);
      else
         ok = g_trade.Sell(lots_each, _Symbol, s.entry, s.sl, tp_prices[i], tps[i]);

      if(!ok)
      {
         MLog("ERR", StringFormat("OrderSend %s failed retcode=%d %s",
                                   tps[i], g_trade.ResultRetcode(),
                                   g_trade.ResultRetcodeDescription()));
      }
      else
      {
         opened++;
         MLog("TRADE", StringFormat("Opened %s %s %.2flots @%s SL=%s TP=%s",
                                     DirStr(s.direction), tps[i], lots_each,
                                     DoubleToString(s.entry, _Digits),
                                     DoubleToString(s.sl,    _Digits),
                                     DoubleToString(tp_prices[i], _Digits)));
      }
   }

   if(opened == 0) return false;

   // Track group state
   g_group.active        = true;
   g_group.entry         = s.entry;
   g_group.sl_initial    = s.sl;
   g_group.tp1           = s.tp1;
   g_group.tp2           = s.tp2;
   g_group.tp3           = s.tp3;
   g_group.risk_price    = s.risk_price;
   g_group.volume_each   = lots_each;
   g_group.pattern       = s.pattern;
   g_group.direction     = s.direction;
   g_group.open_time     = TimeCurrent();
   g_group.tp1_filled    = false;
   g_group.moved_to_be   = false;
   g_group.mfe_r         = 0;
   g_group.mae_r         = 0;
   g_group.journal_id    = 0;

   if(InpEnableJournal) g_group.journal_id = WriteOpenJournal(s, lots_each);
   return true;
}

//==================================================================//
//  POSITION MANAGEMENT                                               //
//==================================================================//
void UpdateMfeMae()
{
   if(!g_group.active || g_group.risk_price <= 0) return;
   bool is_buy = (g_group.direction == DIR_BUY);
   double cur = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pl_price = (cur - g_group.entry) * (is_buy ? 1.0 : -1.0);
   double r_now = pl_price / g_group.risk_price;
   if(r_now > g_group.mfe_r) g_group.mfe_r = r_now;
   if(r_now < g_group.mae_r) g_group.mae_r = r_now;
}

bool TP1PositionStillOpen()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(ParseTpTag(PositionGetString(POSITION_COMMENT)) == TP_1) return true;
   }
   return false;
}

void MoveRemainingToBE()
{
   if(!InpMoveSLtoBE) return;
   if(g_group.moved_to_be) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      ENUM_TP_TAG tag = ParseTpTag(PositionGetString(POSITION_COMMENT));
      if(tag != TP_2 && tag != TP_3) continue;
      double cur_tp = PositionGetDouble(POSITION_TP);
      double be     = g_group.entry;
      if(!g_trade.PositionModify(t, be, cur_tp))
         MLog("ERR", StringFormat("BE modify failed ticket=%I64u rc=%d", t, g_trade.ResultRetcode()));
      else
         MLog("TRADE", StringFormat("SL→BE on ticket=%I64u", t));
   }
   g_group.moved_to_be = true;
}

void CheckTP1Fill()
{
   if(!g_group.active || g_group.tp1_filled) return;
   // If we never see a TP1-tagged position alive, treat as filled (it closed)
   if(!TP1PositionStillOpen())
   {
      g_group.tp1_filled = true;
      MLog("TRADE", "TP1 fill detected");
      MoveRemainingToBE();
   }
}

int CountActiveGroupPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(ParseTpTag(PositionGetString(POSITION_COMMENT)) != TP_NONE) n++;
   }
   return n;
}

void FinalizeGroupIfClosed()
{
   if(!g_group.active) return;
   if(CountActiveGroupPositions() > 0) return;

   // All 3 positions closed — compute realized R from history
   datetime from = g_group.open_time - 60;
   datetime to   = TimeCurrent() + 60;
   if(!HistorySelect(from, to))
   {
      MLog("ERR", "HistorySelect failed");
      g_group.active = false;
      return;
   }
   double total_profit = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_TIME) < g_group.open_time - 5) continue;
      total_profit += HistoryDealGetDouble(d, DEAL_PROFIT)
                    + HistoryDealGetDouble(d, DEAL_SWAP)
                    + HistoryDealGetDouble(d, DEAL_COMMISSION);
   }
   double equity_at_open = AccountInfoDouble(ACCOUNT_EQUITY) - total_profit;
   double risk_money_total = equity_at_open * InpRiskPercent / 100.0;
   double r_realized = (risk_money_total > 0) ? total_profit / risk_money_total : 0;

   g_day_r += r_realized;
   if(InpDailyMaxLossR > 0 && g_day_r <= -InpDailyMaxLossR && !g_day_kill)
   {
      g_day_kill = true;
      MLog("RISK", StringFormat("Daily kill switch ON: %.2fR <= -%.1fR", g_day_r, InpDailyMaxLossR));
   }

   if(InpEnableJournal) UpdateCloseJournal(g_group.journal_id, r_realized, total_profit);
   MLog("TRADE", StringFormat("Group closed. P/L=%.2f  R=%.2f  day=%.2fR  MFE=%.2fR  MAE=%.2fR",
                               total_profit, r_realized, g_day_r, g_group.mfe_r, g_group.mae_r));

   g_last_close_time = TimeCurrent();
   g_group.active = false;
}

//==================================================================//
//  JOURNAL                                                           //
//==================================================================//
string ZeroPad4(const int n) { return StringFormat("%04d", n); }
string Iso8601(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}
string DateOnly(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
}

int NextJournalId()
{
   string ctr = InpJournalDir + "\\counter.txt";
   int last = 0;
   int fh = FileOpen(ctr, FILE_READ | FILE_TXT | FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      string s = FileReadString(fh);
      last = (int)StringToInteger(s);
      FileClose(fh);
   }
   last++;
   fh = FileOpen(ctr, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh != INVALID_HANDLE) { FileWrite(fh, IntegerToString(last)); FileClose(fh); }
   return last;
}

int WriteOpenJournal(const Setup &s, const double lots_each)
{
   int id = NextJournalId();
   datetime now = TimeGMT();
   MqlDateTime dt; TimeToStruct(now, dt);
   string mdir = StringFormat("%s\\%04d\\%02d", InpJournalDir, dt.year, dt.mon);
   FolderCreate(mdir);

   string suffix = (s.direction == DIR_BUY) ? "buy" : "sell";
   string fname = StringFormat("%s\\%s-%s-%s.md", mdir, ZeroPad4(id), DateOnly(now), suffix);
   int fh = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
   {
      MLog("ERR", "Journal open failed: " + fname);
      return 0;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWrite(fh, "---");
   FileWrite(fh, "id: \"" + ZeroPad4(id) + "\"");
   FileWrite(fh, "timestamp_utc: " + Iso8601(now));
   FileWrite(fh, "symbol: " + _Symbol);
   FileWrite(fh, "direction: " + DirStr(s.direction));
   FileWrite(fh, "source: EA");
   FileWrite(fh, "strategy: Migs");
   FileWrite(fh, "pattern: \"" + s.pattern + "\"");
   FileWrite(fh, "htf_bias_1h: " + BiasStr(s.bias_h1));
   FileWrite(fh, "entry: "  + DoubleToString(s.entry, digits));
   FileWrite(fh, "sl: "     + DoubleToString(s.sl,    digits));
   FileWrite(fh, "tp1: "    + DoubleToString(s.tp1,   digits));
   FileWrite(fh, "tp2: "    + DoubleToString(s.tp2,   digits));
   FileWrite(fh, "tp3: "    + DoubleToString(s.tp3,   digits));
   FileWrite(fh, "risk_price_units: " + DoubleToString(s.risk_price, digits));
   FileWrite(fh, "tp1_rr: 1.0");
   FileWrite(fh, "tp2_rr: 2.0");
   FileWrite(fh, "tp3_rr: 3.0");
   FileWrite(fh, "volume_per_position: " + DoubleToString(lots_each, 2));
   FileWrite(fh, "position_count: 3");
   FileWrite(fh, "ob_high: " + DoubleToString(s.ob.high, digits));
   FileWrite(fh, "ob_low: "  + DoubleToString(s.ob.low,  digits));
   FileWrite(fh, "ob_fresh: " + (s.ob.fresh ? "true" : "false"));
   FileWrite(fh, "bos_broken_swing: " + DoubleToString(s.bos.broken_swing, digits));
   FileWrite(fh, "atr_price: " + DoubleToString(s.atr_price, digits));
   FileWrite(fh, "outcome: OPEN");
   FileWrite(fh, "r_realized: 0.0");
   FileWrite(fh, "profit_money: 0.0");
   FileWrite(fh, "mfe_r: 0.0");
   FileWrite(fh, "mae_r: 0.0");
   FileWrite(fh, "---");
   FileWrite(fh, "");
   FileWrite(fh, "## Notes");
   FileWrite(fh, "");
   FileWrite(fh, "EA-generated " + DirStr(s.direction) + ". BOS-anchored OB retest. "
                 "3-position thirds ladder. Open at " + DoubleToString(s.entry, digits) + ".");
   FileClose(fh);
   MLog("JOURNAL", "wrote " + fname + " (id=" + IntegerToString(id) + ")");
   return id;
}

bool UpdateCloseJournal(const int id, const double r_realized, const double profit_money)
{
   if(id <= 0) return false;
   // Find the file
   string filter = InpJournalDir + "\\*";
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);

   // Scan current and previous month
   for(int yo = 0; yo <= 1; yo++)
   {
      int year = dt.year - yo;
      for(int m = 12; m >= 1; m--)
      {
         string folder = StringFormat("%s\\%04d\\%02d", InpJournalDir, year, m);
         string find = folder + "\\" + ZeroPad4(id) + "-*.md";
         string fn;
         long h = FileFindFirst(find, fn);
         if(h == INVALID_HANDLE) continue;
         string full = folder + "\\" + fn;
         FileFindClose(h);

         int fh = FileOpen(full, FILE_READ | FILE_TXT | FILE_ANSI);
         if(fh == INVALID_HANDLE) continue;
         string lines[];
         int ln = 0;
         while(!FileIsEnding(fh))
         {
            ArrayResize(lines, ln + 1);
            lines[ln++] = FileReadString(fh);
         }
         FileClose(fh);

         string outcome = "BE";
         if(r_realized >= 1.5)  outcome = "TP3_HIT";
         else if(r_realized >= 0.5) outcome = "TP2_HIT";
         else if(r_realized >= 0.1) outcome = "TP1_HIT";
         else if(r_realized <= -0.7) outcome = "SL_HIT";

         for(int i = 0; i < ln; i++)
         {
            if(StringFind(lines[i], "outcome:") == 0)      lines[i] = "outcome: " + outcome;
            if(StringFind(lines[i], "r_realized:") == 0)   lines[i] = "r_realized: " + DoubleToString(r_realized, 3);
            if(StringFind(lines[i], "profit_money:") == 0) lines[i] = "profit_money: " + DoubleToString(profit_money, 2);
            if(StringFind(lines[i], "mfe_r:") == 0)        lines[i] = "mfe_r: " + DoubleToString(g_group.mfe_r, 3);
            if(StringFind(lines[i], "mae_r:") == 0)        lines[i] = "mae_r: " + DoubleToString(g_group.mae_r, 3);
         }
         fh = FileOpen(full, FILE_WRITE | FILE_TXT | FILE_ANSI);
         if(fh == INVALID_HANDLE) return false;
         for(int i = 0; i < ln; i++) FileWrite(fh, lines[i]);
         FileClose(fh);
         MLog("JOURNAL", "updated " + full + " -> " + outcome);
         return true;
      }
   }
   return false;
}

//==================================================================//
//  ON-CHART STATUS PANEL                                             //
//==================================================================//
void StatusEnsureLabel(const string key, const int x, const int y,
                       const string text, const color clr)
{
   string name = STATUS_PREFIX + key;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     InpStatusCorner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
      ObjectSetString (0, name, OBJPROP_FONT,       InpStatusFontName);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,     1000);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpStatusXOffset + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpStatusYOffset + y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  InpStatusFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
}

void StatusDeleteKey(const string key)
{
   string name = STATUS_PREFIX + key;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
}

void StatusCleanup()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, STATUS_PREFIX) == 0) ObjectDelete(0, nm);
   }
   ChartRedraw(0);
}

ENUM_BIAS GetCachedH1Bias()
{
   datetime now = TimeCurrent();
   if(now - g_cached_bias_t >= 60 || g_cached_bias_t == 0)
   {
      g_cached_bias_h1 = DetectH1Bias();
      g_cached_bias_t  = now;
   }
   return g_cached_bias_h1;
}

void DrawStatusPanel()
{
   if(!InpShowStatus) { StatusCleanup(); return; }

   int line_h  = InpStatusFontSize + 5;
   int y       = 0;
   int digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string ccy  = AccountInfoString(ACCOUNT_CURRENCY);

   // Header
   StatusEnsureLabel("hdr", 0, y,
      "===== MIGS HYBRID v" + MIGS_VERSION + " =====", InpStatusHeaderClr);
   y += line_h;

   // Status line
   color stat_clr  = InpStatusGoodClr;
   string stat_str = "ACTIVE";
   if(!InpEnableTrade)        { stat_clr = InpStatusMutedClr; stat_str = "DISABLED (input)"; }
   else if(g_day_kill)        { stat_clr = InpStatusBadClr;   stat_str = "KILL-SWITCH"; }
   else if(g_group.active)    { stat_clr = InpStatusHeaderClr;stat_str = "IN-TRADE"; }
   else if(!CooldownPassed()) { stat_clr = InpStatusMutedClr; stat_str = "COOLDOWN"; }
   StatusEnsureLabel("st_l", 0,  y, "Status   :", InpStatusColor);
   StatusEnsureLabel("st_v", 90, y, stat_str,     stat_clr);
   y += line_h;

   // Symbol / TF
   StatusEnsureLabel("sym", 0, y,
      StringFormat("Symbol   : %s (%s)", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)),
      InpStatusColor);
   y += line_h;

   // Account / mode
   bool is_real = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL);
   StatusEnsureLabel("acct", 0, y,
      "Account  : " + (is_real ? "LIVE" : "DEMO") +
      "  #" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
      is_real ? clrOrange : InpStatusColor);
   y += line_h;

   // Equity
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   StatusEnsureLabel("eq", 0, y,
      StringFormat("Equity   : %.2f %s", equity, ccy), InpStatusColor);
   y += line_h;

   // Risk per trade in money
   double risk_money = equity * InpRiskPercent / 100.0;
   StatusEnsureLabel("risk", 0, y,
      StringFormat("Risk     : %.2f%% = %.2f %s", InpRiskPercent, risk_money, ccy),
      InpStatusColor);
   y += line_h;

   // Day R
   color day_clr = (g_day_r > 0) ? InpStatusGoodClr
                   : (g_day_r < 0) ? InpStatusBadClr
                   : InpStatusMutedClr;
   string kill_suffix = (InpDailyMaxLossR > 0)
      ? StringFormat("  (kill @ -%.1fR)", InpDailyMaxLossR) : "";
   StatusEnsureLabel("dR_l", 0,  y, "Day R    :", InpStatusColor);
   StatusEnsureLabel("dR_v", 90, y, StringFormat("%+.2fR%s", g_day_r, kill_suffix), day_clr);
   y += line_h;

   // Separator
   StatusEnsureLabel("sep1", 0, y, "-----------------------------", InpStatusMutedClr);
   y += line_h;

   // 1H bias
   ENUM_BIAS bias = GetCachedH1Bias();
   color bias_clr = (bias == BIAS_BULL) ? InpStatusGoodClr
                    : (bias == BIAS_BEAR) ? InpStatusBadClr
                    : InpStatusMutedClr;
   StatusEnsureLabel("bi_l", 0,  y, "1H Bias  :", InpStatusColor);
   StatusEnsureLabel("bi_v", 90, y, BiasStr(bias), bias_clr);
   y += line_h;

   // Last eval message
   string em = g_last_eval_msg;
   if(StringLen(em) > 36) em = StringSubstr(em, 0, 33) + "...";
   StatusEnsureLabel("ev", 0, y, "Last eval: " + em, InpStatusMutedClr);
   y += line_h;

   // Separator
   StatusEnsureLabel("sep2", 0, y, "-----------------------------", InpStatusMutedClr);
   y += line_h;

   // Trade info
   if(g_group.active)
   {
      StatusEnsureLabel("th", 0, y,
         "TRADE OPEN  pattern=#" + g_group.pattern,
         InpStatusHeaderClr);
      y += line_h;

      color dir_clr = (g_group.direction == DIR_BUY) ? InpStatusGoodClr : InpStatusBadClr;
      StatusEnsureLabel("td", 0, y, "  Dir   : " + DirStr(g_group.direction), dir_clr);
      y += line_h;

      StatusEnsureLabel("te", 0, y,
         StringFormat("  Entry : %s", DoubleToString(g_group.entry, digits)),
         InpStatusColor);
      y += line_h;

      double sl_now = g_group.moved_to_be ? g_group.entry : g_group.sl_initial;
      color sl_clr  = g_group.moved_to_be ? InpStatusGoodClr : InpStatusColor;
      string sl_tag = g_group.moved_to_be ? "  (BE)" : "";
      StatusEnsureLabel("ts", 0, y,
         StringFormat("  SL    : %s%s", DoubleToString(sl_now, digits), sl_tag),
         sl_clr);
      y += line_h;

      string tp1_tag = g_group.tp1_filled ? "  [FILLED]" : "";
      color  tp1_clr = g_group.tp1_filled ? InpStatusGoodClr : InpStatusColor;
      StatusEnsureLabel("t1", 0, y,
         StringFormat("  TP1   : %s%s", DoubleToString(g_group.tp1, digits), tp1_tag),
         tp1_clr);
      y += line_h;

      StatusEnsureLabel("t2", 0, y,
         StringFormat("  TP2   : %s", DoubleToString(g_group.tp2, digits)),
         InpStatusColor);
      y += line_h;

      StatusEnsureLabel("t3", 0, y,
         StringFormat("  TP3   : %s", DoubleToString(g_group.tp3, digits)),
         InpStatusColor);
      y += line_h;

      color mfe_clr = (g_group.mfe_r > 0) ? InpStatusGoodClr : InpStatusMutedClr;
      color mae_clr = (g_group.mae_r < 0) ? InpStatusBadClr  : InpStatusMutedClr;
      StatusEnsureLabel("tmf", 0,   y, StringFormat("  MFE   : %+.2fR", g_group.mfe_r), mfe_clr);
      StatusEnsureLabel("tma", 130, y, StringFormat("MAE: %+.2fR",      g_group.mae_r), mae_clr);
      y += line_h;

      // Volume per position
      StatusEnsureLabel("tv", 0, y,
         StringFormat("  Vol/pos: %.2f lots (x3)", g_group.volume_each),
         InpStatusMutedClr);
      y += line_h;
   }
   else
   {
      // Clear any stale trade lines
      string trade_keys[] = {"th","td","te","ts","t1","t2","t3","tmf","tma","tv"};
      for(int i = 0; i < ArraySize(trade_keys); i++) StatusDeleteKey(trade_keys[i]);

      StatusEnsureLabel("th", 0, y, "NO TRADE OPEN", InpStatusMutedClr);
      y += line_h;
   }

   // Chop filter status line
   if(InpEnableChopFilter)
   {
      string chop_str;
      color  chop_clr;
      if(g_chop_reason != "")
      {
         chop_str = "CHOP: " + g_chop_reason;
         chop_clr = InpStatusBadClr;
      }
      else
      {
         chop_str = StringFormat("OK  ADX=%.1f  ATR-r=%.2f", g_last_adx, g_last_atr_ratio);
         chop_clr = InpStatusGoodClr;
      }
      StatusEnsureLabel("chop", 0, y, "Chop     : " + chop_str, chop_clr);
      y += line_h;
   }
   else
   {
      StatusDeleteKey("chop");
   }

   // Footer
   StatusEnsureLabel("sep3", 0, y, "-----------------------------", InpStatusMutedClr);
   y += line_h;
   StatusEnsureLabel("ft", 0, y,
      StringFormat("magic=%d  ATR=%s",
                   InpMagic,
                   (g_atr_handle != INVALID_HANDLE
                    ? DoubleToString(ATRPrice(), digits) : "n/a")),
      InpStatusMutedClr);

   ChartRedraw(0);
}

//==================================================================//
//  DAILY RESET                                                       //
//==================================================================//
void RollDayIfNeeded()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   datetime today_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(today_start != g_day_start)
   {
      g_day_start = today_start;
      g_day_r     = 0.0;
      g_day_kill  = false;
      MLog("RISK", "New day; counters reset");
   }
}

bool IsNewM5Bar()
{
   datetime t[1];
   if(CopyTime(_Symbol, PERIOD_M5, 0, 1, t) != 1) return false;
   if(t[0] != g_last_m5) { g_last_m5 = t[0]; return true; }
   return false;
}

//==================================================================//
//  EVENT HANDLERS                                                    //
//==================================================================//
int OnInit(void)
{
   MLog("INIT", StringFormat("Migs EA v%s  symbol=%s  TF=%s  magic=%d  risk=%.2f%%",
                              MIGS_VERSION, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                              InpMagic, InpRiskPercent));

   if(_Period != PERIOD_M5)
      MLog("WARN", "EA expects M5; current TF is " + EnumToString((ENUM_TIMEFRAMES)_Period));

   g_atr_handle = iATR(_Symbol, PERIOD_M5, InpATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
   {
      MLog("ERR", "iATR handle creation failed");
      return INIT_FAILED;
   }

   if(InpEnableChopFilter && InpADXMinimum > 0)
   {
      g_adx_handle = iADX(_Symbol, InpADXTimeframe, InpADXPeriod);
      if(g_adx_handle == INVALID_HANDLE)
      {
         MLog("ERR", "iADX handle creation failed");
         return INIT_FAILED;
      }
      MLog("INIT", StringFormat("Chop filter ON  ADX(%s,%d)>=%.1f  BOSConflict=%d  ATRr>=%.2f  strictH1=%s",
                                 EnumToString(InpADXTimeframe), InpADXPeriod, InpADXMinimum,
                                 InpBOSConflictBars, InpATRExpansionRatio,
                                 InpStrictH1Bias ? "true" : "false"));
   }

   if(InpEnableJournal) FolderCreate(InpJournalDir);
   RollDayIfNeeded();
   DrawStatusPanel();

   // Reattach to an existing group if positions are open (after restart)
   if(CountMigsPositions() > 0)
   {
      MLog("INIT", "Detected existing Migs positions; reattaching state in degraded mode");
      g_group.active = true;
      g_group.direction = DIR_NONE;
      g_group.entry = 0;
      g_group.tp1_filled = !TP1PositionStillOpen();
   }

   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_atr_handle != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   if(g_adx_handle != INVALID_HANDLE) IndicatorRelease(g_adx_handle);
   StatusCleanup();
   MLog("DEINIT", "reason=" + IntegerToString(reason));
}

void OnTimer(void)
{
   RollDayIfNeeded();
   DrawStatusPanel();
}

void OnTick(void)
{
   // Maintenance every tick
   if(g_group.active)
   {
      UpdateMfeMae();
      CheckTP1Fill();
      FinalizeGroupIfClosed();
   }

   // Throttled status panel redraw (1Hz)
   datetime now = TimeCurrent();
   if(InpShowStatus && now != g_status_redraw_t)
   {
      g_status_redraw_t = now;
      DrawStatusPanel();
   }

   // New-signal logic gated by M5 bar
   if(!IsNewM5Bar()) return;
   if(g_group.active) return;
   if(!DailyRiskAllow()) return;
   if(!CooldownPassed()) return;
   if(CountMigsPositions() > 0) return;
   if(!InpEnableTrade) return;

   Setup s;
   if(!BuildSetup(s))
   {
      if(s.reject_reason != "") MLog("EVAL", "no setup: " + s.reject_reason);
      g_last_eval_msg = (s.reject_reason != "") ? s.reject_reason : "no setup";
      DrawStatusPanel();
      return;
   }

   MLog("SIGNAL", StringFormat("%s pattern#%s  entry=%s  SL=%s  TP3=%s  R=%s  htf=%s",
                                DirStr(s.direction), s.pattern,
                                DoubleToString(s.entry, _Digits),
                                DoubleToString(s.sl, _Digits),
                                DoubleToString(s.tp3, _Digits),
                                DoubleToString(s.risk_price, _Digits),
                                BiasStr(s.bias_h1)));
   g_last_eval_msg = StringFormat("SIGNAL %s @%s",
                                  DirStr(s.direction),
                                  DoubleToString(s.entry, _Digits));
   ExecuteSetup(s);
   DrawStatusPanel();
}

void OnTrade(void)
{
   if(!g_group.active) return;
   // Trigger a finalize check — positions may have closed
   FinalizeGroupIfClosed();
}
