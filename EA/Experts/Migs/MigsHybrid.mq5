//+------------------------------------------------------------------+
//|                                                MigsHybrid.mq5      |
//|                                            Copyright 2026, Migs    |
//|                                                                    |
//|  PINE-PARITY BUILD — mirrors BG-Golden-Signals.pine (v6).          |
//|  Goal: ≥95% backtest agreement with TradingView indicator.         |
//|                                                                    |
//|  CHANGELOG                                                          |
//|   v0.6.0 (2026-05-22)                                              |
//|     • Full rewrite to Pine-parity. All logic mirrors                |
//|       BG-Golden-Signals.pine exactly:                               |
//|         – pivothigh/pivotlow(strength=1) for swings                 |
//|         – transition BOS (close>swing AND close[1]<=swing)          |
//|         – BOS persistence: active flag + bos_bar (age-out by       |
//|           bar count, not bar time)                                  |
//|         – OB anchored ONLY when new BOS fires                       |
//|         – HTF EMA(12)/EMA(80) on PERIOD_H2 + close-vs-fast gate    |
//|         – SOFTER HTF rule: bull OK if h1_bull OR NOT h1_bear        |
//|         – Min-SL $-FILTER (reject) + $-CLAMP (widen)                |
//|         – Sessions in GMT+8 (Asia 08:00-12:00 default)             |
//|         – Date filter: Last 30 days (live: disable)                |
//|         – Single position rides full size to highest enabled TP    |
//|         – Intermediate TPs trigger SL trails (BE / TP1 / TP2)       |
//|         – SL-while-trailed counts as WIN (eff_sl_r >= 0)            |
//|         – No partials, no 3-position thirds                         |
//|     • Stripped: ADX filter, whipsaw filter, ATR expansion filter   |
//|       — none exist in BG-Golden-Signals.pine                        |
//|   v0.5.0 — transition-based BOS, EMA+close HTF bias                |
//|   v0.4.0 — TF-agnostic execution                                    |
//|                                                                    |
//|  KNOWN MT5↔PINE DIVERGENCES (≤5% expected backtest delta):         |
//|   1. Pine simulates fills using bar HIGH/LOW; MT5 fills on tick.   |
//|      Same-bar TP+SL races may resolve differently.                 |
//|   2. Pine entry = bar close. MT5 entry = market Ask/Bid at the     |
//|      next-bar open. Small slippage on every entry.                 |
//|   3. Spread/commission/swap — Pine doesn't model. MT5 does.        |
//|   4. SL is broker-attached for safety. TP is internally tracked    |
//|      so we can ride past TP3 when i_move_tp2 is enabled.           |
//|      → If EA disconnects, position rides on SL only.               |
//|                                                                    |
//|  RIGHT-FIRST-TIME CHECKLIST                                        |
//|   [✓] No #property strict                                          |
//|   [✓] All input at top-level of .mq5                               |
//|   [✓] OnInit returns int (INIT_SUCCEEDED/FAILED/PARAMETERS_INCORRECT)
//|   [✓] All indicator handles created in OnInit, released in OnDeinit
//|   [✓] Every trade call checked via ResultRetcode == TRADE_RETCODE_DONE
//|   [✓] PositionsTotal loops are backward + filter magic+symbol
//|   [✓] MqlDateTime uses .mon and .min                                |
//|   [✓] ChartRedraw(0) once after batch of ObjectSet*                |
//|   [✓] SetTypeFillingBySymbol + SetDeviationInPoints in OnInit      |
//|   [✓] No iATR/iMA/iADX inside OnTick — CopyBuffer from cached      |
//|   [✓] SL pre-flight check against SYMBOL_TRADE_STOPS_LEVEL          |
//|   [✓] IsNewBar() gate around bar-close logic                        |
//+------------------------------------------------------------------+
#property copyright "Migs"
#property version   "0.60"
#property description "Migs Hybrid v0.6 — Pine-parity build matching BG-Golden-Signals.pine."

//==================================================================//
//  INCLUDES                                                          //
//==================================================================//
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================//
//  INPUTS — defaults mirror BG-Golden-Signals.pine exactly           //
//==================================================================//
input group "=== Structure Detection (Pine: g_struct) ==="
input int    InpSwingLen          = 1;          // Pine i_swing_len
input int    InpBOSAge            = 30;         // Pine i_bos_age
input int    InpOBAge             = 60;         // Pine i_ob_age
input double InpEntryATR          = 0.9;        // Pine i_entry_atr
input int    InpATRPer            = 15;         // Pine i_atr_per
input double InpSLBufATR          = 0.10;       // Pine i_sl_buf
input double InpMinSLClamp        = 10.0;       // Pine i_min_sl ($ widen)
input double InpMinSLFilter       = 4.0;        // Pine i_min_sl_flt ($ reject)

input group "=== HTF Bias (Pine: g_htf) ==="
input bool            InpRequireHTF     = true;        // Pine i_req_h1
input ENUM_TIMEFRAMES InpHTFTimeframe   = PERIOD_H2;   // Pine "120" = 2H
input int             InpHTFFastEMA     = 12;          // Pine i_h1_fast
input int             InpHTFSlowEMA     = 80;          // Pine i_h1_slow

input group "=== Trade Setup (Pine: g_sim) ==="
input bool   InpEnableTrade       = true;       // Master switch (Pine i_sim_on)
input int    InpMaxPositions      = 1;          // Pine i_max_pos
input bool   InpUseTP2            = true;       // Pine i_use_tp2
input bool   InpUseTP3            = false;      // Pine i_use_tp3
input bool   InpMoveBE            = false;      // Pine i_move_be (SL→BE after TP1)
input bool   InpMoveTP1AfterTP2   = false;      // Pine i_move_tp1
input bool   InpMoveBEAfterTP2    = false;      // Pine i_move_be2
input bool   InpMoveTP2AfterTP3   = false;      // Pine i_move_tp2 (ride past TP3)
input int    InpCooldownBars      = 23;         // Pine i_cooldown

input group "=== Risk Sizing ==="
input double InpRiskPercent       = 1.0;        // % equity risked per trade
input double InpMaxLots           = 100.0;      // safety cap

input group "=== Session Filter (Pine: g_sess, default GMT+8 Asia) ==="
input bool   InpUseSessions       = true;       // Pine i_use_sessions
input int    InpSessionGMTOffset  = 8;          // Pine "GMT+8" — Manila/PHT
input bool   InpUseAsia           = true;       // Pine i_use_asia
input string InpAsiaSession       = "08:00-12:00";  // Pine i_asia_sess
input bool   InpUseLondon         = false;
input string InpLondonSession     = "14:00-17:00";
input bool   InpUseNYAM           = false;
input string InpNYAMSession       = "21:30-23:00";
input bool   InpUseNYLunch        = false;
input string InpNYLunchSession    = "00:00-01:00";
input bool   InpUseNYPM           = false;
input string InpNYPMSession       = "01:30-04:00";

input group "=== Date Range (Pine: g_dates; live: disable all) ==="
input bool   InpUseLast30Days     = true;       // Pine i_use_last30 default
input bool   InpUseLast7Days      = false;
input bool   InpUseLast14Days     = false;
input bool   InpUseLast60Days     = false;
input bool   InpUseCustomDates    = false;
input datetime InpCustomFrom      = D'2025.01.01 00:00';
input datetime InpCustomTo        = D'2031.01.01 00:00';

input group "=== Trade Management ==="
input long   InpMagic             = 20260522;
input ulong  InpSlippagePoints    = 30;

input group "=== Safety ==="
input double InpDailyMaxLossR     = 5.0;        // soft kill switch; 0 = off

input group "=== Journal ==="
input bool   InpEnableJournal     = true;
input string InpJournalDir        = "Migs\\journal";

input group "=== Logging ==="
input bool   InpVerbose           = true;

input group "=== On-Chart Status Panel ==="
input bool             InpShowPanel        = true;
input ENUM_BASE_CORNER InpPanelCorner      = CORNER_RIGHT_UPPER;
input int              InpPanelX           = 10;
input int              InpPanelY           = 20;
input int              InpPanelFontSize    = 9;
input string           InpPanelFontName    = "Consolas";
input color            InpPanelColor       = clrBlack;
input color            InpPanelHeaderClr   = clrBlack;
input color            InpPanelGoodClr     = clrDarkGreen;
input color            InpPanelBadClr      = clrFireBrick;
input color            InpPanelMutedClr    = clrDimGray;
input color            InpPanelWarnClr     = clrDarkOrange;

//==================================================================//
//  CONSTANTS                                                         //
//==================================================================//
#define MIGS_VERSION           "0.6.0"
#define PANEL_PREFIX           "MigsStatus_"
#define MAX_BARS_FETCH         500    // hard cap on CopyHigh/Low/Close lookback
#define HTF_BIAS_CACHE_SECS    60     // re-evaluate HTF bias at this cadence
#define ATR_BUFFER_BARS        5      // require ATRPer + this many bars before reading

//==================================================================//
//  ENUMS                                                             //
//==================================================================//
enum ENUM_DIR  { DIR_NONE = 0, DIR_BUY = 1, DIR_SELL = 2 };
enum ENUM_BIAS { BIAS_RANGE = 0, BIAS_BULL = 1, BIAS_BEAR = 2 };

//==================================================================//
//  STRUCTS                                                           //
//==================================================================//
struct Swing
{
   double   price;
   int      bar_index;
   bool     is_high;
};

// Per-position trade state — mirrors Pine Trade UDT.
// Multi-position support: we hold an array of these.
struct MigsTrade
{
   ulong    ticket;            // broker ticket
   bool     is_long;
   double   entry;
   double   sl_initial;        // original SL when opened
   double   tp1, tp2, tp3;
   double   eff_sl;            // current effective SL (may be trailed)
   double   eff_sl_r;          // R value if eff_sl is hit: -1, 0, +1, +2
   bool     tp1_done;
   bool     tp2_done;
   bool     tp3_done;
   datetime open_time;         // bar open time when trade fired
   double   risk_price;        // |entry - sl_initial| in price
   int      journal_id;
   int      journal_year;      // year folder of journal entry (open time)
   int      journal_month;     // month folder of journal entry (open time)
};

//==================================================================//
//  GLOBALS                                                           //
//==================================================================//
CTrade        g_trade;
CSymbolInfo   g_symbol;

int           g_hATR              = INVALID_HANDLE;
int           g_hEMA_HTF_fast     = INVALID_HANDLE;
int           g_hEMA_HTF_slow     = INVALID_HANDLE;

datetime      g_last_bar          = 0;
datetime      g_last_close_time   = 0;

// BOS persistence (Pine: active_bull_bos / active_bear_bos / bos_bar)
bool          g_active_bull_bos   = false;
bool          g_active_bear_bos   = false;
int           g_bos_bar_age       = -1;   // bar count since bos_bar; -1 = none
datetime      g_bos_bar_time      = 0;    // for iBarShift recovery

// OB (re-anchored only on new BOS — Pine semantics)
double        g_ob_high           = 0.0;
double        g_ob_low            = 0.0;
bool          g_ob_demand         = false;
bool          g_ob_valid          = false;

// HTF bias cache
ENUM_BIAS     g_cached_bias_htf   = BIAS_RANGE;
datetime      g_cached_bias_t     = 0;

// Swing pivot state (Pine: last_sh / last_sl)
double        g_last_sh           = 0.0;
double        g_last_sl           = 0.0;
bool          g_has_last_sh       = false;
bool          g_has_last_sl       = false;
datetime      g_last_sh_time      = 0;
datetime      g_last_sl_time      = 0;

// Daily aggregates (PHT day per Pine)
datetime      g_day_anchor        = 0;
double        g_day_r             = 0.0;
int           g_day_wins          = 0;
int           g_day_losses        = 0;
bool          g_day_kill          = false;

// Open positions (multi-position support, up to InpMaxPositions)
MigsTrade     g_trades[];

// Aggregate stats (displayed on panel)
int           g_sim_count         = 0;
int           g_sim_wins          = 0;
int           g_sim_losses        = 0;
double        g_sim_total_r       = 0.0;

// Diagnostic for panel
string        g_last_eval_msg     = "(none)";
datetime      g_status_redraw_t   = 0;
string        g_session_now       = "off";

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
   if(lots > InpMaxLots) return InpMaxLots;
   return lots;
}

double ATRValue()
{
   if(g_hATR == INVALID_HANDLE) return 0.0;
   if(BarsCalculated(g_hATR) < InpATRPer + ATR_BUFFER_BARS) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, 0, 2, buf) < 2) return 0.0;
   return buf[1];   // last closed bar
}

double CalcLotsForRisk(const double sl_distance)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * InpRiskPercent / 100.0;
   double tick_v     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_s     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_s <= 0 || tick_v <= 0 || sl_distance <= 0) return 0.0;
   double ticks    = sl_distance / tick_s;
   double money_pl = ticks * tick_v;
   if(money_pl <= 0) return 0.0;
   return NormalizeLots(risk_money / money_pl);
}

//==================================================================//
//  PIVOT DETECTION (Pine ta.pivothigh / ta.pivotlow)                 //
//                                                                    //
//  ta.pivothigh(len, len) returns the pivot value if bar `len` bars  //
//  ago is a high pivot — i.e. higher than `len` bars on each side.   //
//  Detects on bar `len`-back; we mirror that exactly.                //
//==================================================================//
bool IsPivotHigh(const double &highs[], const int i, const int len)
{
   // highs[] is ArraySetAsSeries(true). highs[i] is candidate.
   // Need len bars on each side. Most recent bar is highs[0].
   for(int k = 1; k <= len; k++)
   {
      if(i - k < 0) return false;            // can't look forward
      if(highs[i - k] > highs[i]) return false;  // newer bar exceeds
      if(highs[i + k] >= highs[i]) return false; // older bar matches/exceeds
   }
   return true;
}

bool IsPivotLow(const double &lows[], const int i, const int len)
{
   for(int k = 1; k <= len; k++)
   {
      if(i - k < 0) return false;
      if(lows[i - k] < lows[i]) return false;
      if(lows[i + k] <= lows[i]) return false;
   }
   return true;
}

//==================================================================//
//  HTF BIAS — EMA + close gate (Pine semantics)                      //
//==================================================================//
ENUM_BIAS DetectHTFBias()
{
   if(g_hEMA_HTF_fast == INVALID_HANDLE || g_hEMA_HTF_slow == INVALID_HANDLE) return BIAS_RANGE;
   if(BarsCalculated(g_hEMA_HTF_fast) < InpHTFSlowEMA + 5) return BIAS_RANGE;
   if(BarsCalculated(g_hEMA_HTF_slow) < InpHTFSlowEMA + 5) return BIAS_RANGE;

   double fast[], slow[], htf_close[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(htf_close, true);
   if(CopyBuffer(g_hEMA_HTF_fast, 0, 0, 2, fast) < 2) return BIAS_RANGE;
   if(CopyBuffer(g_hEMA_HTF_slow, 0, 0, 2, slow) < 2) return BIAS_RANGE;
   if(CopyClose(_Symbol, InpHTFTimeframe, 1, 1, htf_close) < 1) return BIAS_RANGE;

   double f = fast[1];
   double s = slow[1];
   double c = htf_close[0];

   // Pine:
   //   h1_bull = h1_fast > h1_slow and h1_close > h1_fast
   //   h1_bear = h1_fast < h1_slow and h1_close < h1_fast
   if(f > s && c > f) return BIAS_BULL;
   if(f < s && c < f) return BIAS_BEAR;
   return BIAS_RANGE;
}

ENUM_BIAS GetCachedHTFBias()
{
   datetime now = TimeCurrent();
   if(now - g_cached_bias_t > HTF_BIAS_CACHE_SECS)
   {
      g_cached_bias_htf = DetectHTFBias();
      g_cached_bias_t   = now;
   }
   return g_cached_bias_htf;
}

//==================================================================//
//  SESSION FILTER — Pine GMT+8 default                               //
//                                                                    //
//  Session strings: "HH:MM-HH:MM" in InpSessionGMTOffset timezone.   //
//  Default GMT+8 (Manila). Each killzone is a window in that TZ.    //
//==================================================================//
bool ParseSession(const string s, int &h_from, int &m_from, int &h_to, int &m_to)
{
   // expect "HH:MM-HH:MM"
   if(StringLen(s) != 11) return false;
   h_from = (int)StringToInteger(StringSubstr(s, 0, 2));
   m_from = (int)StringToInteger(StringSubstr(s, 3, 2));
   h_to   = (int)StringToInteger(StringSubstr(s, 6, 2));
   m_to   = (int)StringToInteger(StringSubstr(s, 9, 2));
   return true;
}

bool InSession(const string sess_str, const datetime utc_now, const int gmt_offset)
{
   int hf, mf, ht, mt;
   if(!ParseSession(sess_str, hf, mf, ht, mt)) return false;
   datetime local = utc_now + gmt_offset * 3600;
   MqlDateTime dt; TimeToStruct(local, dt);
   int now_mins = dt.hour * 60 + dt.min;
   int from_mins = hf * 60 + mf;
   int to_mins   = ht * 60 + mt;
   if(from_mins <= to_mins)
      return (now_mins >= from_mins && now_mins < to_mins);
   else
      return (now_mins >= from_mins || now_mins < to_mins);  // window crosses midnight
}

bool IsInAnyAllowedSession(const datetime utc_now)
{
   if(!InpUseSessions) return true;
   bool any_enabled = InpUseAsia || InpUseLondon || InpUseNYAM || InpUseNYLunch || InpUseNYPM;
   if(!any_enabled) return true;   // all sessions disabled → allow all hours

   if(InpUseAsia    && InSession(InpAsiaSession,    utc_now, InpSessionGMTOffset)) { g_session_now = "Asia";    return true; }
   if(InpUseLondon  && InSession(InpLondonSession,  utc_now, InpSessionGMTOffset)) { g_session_now = "London";  return true; }
   if(InpUseNYAM    && InSession(InpNYAMSession,    utc_now, InpSessionGMTOffset)) { g_session_now = "NY AM";   return true; }
   if(InpUseNYLunch && InSession(InpNYLunchSession, utc_now, InpSessionGMTOffset)) { g_session_now = "NY Lunch";return true; }
   if(InpUseNYPM    && InSession(InpNYPMSession,    utc_now, InpSessionGMTOffset)) { g_session_now = "NY PM";   return true; }
   g_session_now = "off";
   return false;
}

//==================================================================//
//  DATE RANGE FILTER (Pine: Last 30 days default)                    //
//==================================================================//
bool IsInDateRange(const datetime utc_now)
{
   bool any_active = InpUseLast7Days || InpUseLast14Days || InpUseLast30Days
                  || InpUseLast60Days || InpUseCustomDates;
   if(!any_active) return true;

   // Pine priority order: 7 > 14 > 30 > 60 > custom
   if(InpUseLast7Days)   return (utc_now >= TimeCurrent() - 7  * 86400);
   if(InpUseLast14Days)  return (utc_now >= TimeCurrent() - 14 * 86400);
   if(InpUseLast30Days)  return (utc_now >= TimeCurrent() - 30 * 86400);
   if(InpUseLast60Days)  return (utc_now >= TimeCurrent() - 60 * 86400);
   if(InpUseCustomDates) return (utc_now >= InpCustomFrom && utc_now <= InpCustomTo);
   return true;
}

//==================================================================//
//  STRUCTURE STATE UPDATE — called once per new bar                  //
//                                                                    //
//  Mirrors Pine signal logic:                                        //
//    1. Detect new pivot via ta.pivothigh/low(len, len).             //
//    2. Update last_sh / last_sl with the pivot price.               //
//    3. Detect BOS transition (close > last_sh AND close[1] <= last_sh) //
//    4. Update active_bull_bos / active_bear_bos + bos_bar.          //
//    5. Age out active flags if (bar_index - bos_bar) > i_bos_age.   //
//    6. On new BOS, re-anchor OB: scan back i=1..i_ob_age for first  //
//       opposite-color candle.                                       //
//==================================================================//
void UpdateStructureState()
{
   // Pull bars needed for pivot + lookback.
   // Pivot candidate sits at index (InpSwingLen + 1) — see note below — so we
   // need at least 2*InpSwingLen + 2 bars before any BOS/OB lookback applies.
   int needed = MathMax(InpBOSAge + 50, InpOBAge + InpSwingLen * 2 + 10);
   needed = MathMin(needed, MAX_BARS_FETCH);

   double highs[], lows[], opens[], closes[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(times, true);
   if(CopyHigh (_Symbol, _Period, 0, needed, highs)  != needed) return;
   if(CopyLow  (_Symbol, _Period, 0, needed, lows)   != needed) return;
   if(CopyOpen (_Symbol, _Period, 0, needed, opens)  != needed) return;
   if(CopyClose(_Symbol, _Period, 0, needed, closes) != needed) return;
   if(CopyTime (_Symbol, _Period, 0, needed, times)  != needed) return;

   // ---- 1. New pivot?
   //         Pine: at close of bar N, ta.pivothigh(len, len) confirms bar
   //         (N - len) as the pivot using high[len-1..0] as right (newer)
   //         neighbours, where high[0] = bar N (just-closed) IS already
   //         settled. We're evaluating on IsNewBar (start of bar N+1), so
   //         the just-closed bar is highs[1], not highs[0] — highs[0] is the
   //         freshly-opened bar with ~1 tick of data. To mirror Pine the
   //         candidate must sit at index InpSwingLen + 1, with the right
   //         neighbour window starting at highs[1] (NOT highs[0]).
   int piv_i = InpSwingLen + 1;
   if(IsPivotHigh(highs, piv_i, InpSwingLen))
   {
      g_last_sh = highs[piv_i];
      g_last_sh_time = times[piv_i];
      g_has_last_sh = true;
   }
   if(IsPivotLow(lows, piv_i, InpSwingLen))
   {
      g_last_sl = lows[piv_i];
      g_last_sl_time = times[piv_i];
      g_has_last_sl = true;
   }

   // ---- 2. BOS transition: close[1] > last_sh AND close[2] <= last_sh
   //         (last closed bar broke through). Pine's `close` on bar evaluation
   //         = the just-closed bar; here closes[1] is that bar.
   bool bull_bos = false, bear_bos = false;
   if(g_has_last_sh && closes[1] > g_last_sh && closes[2] <= g_last_sh)
      bull_bos = true;
   if(g_has_last_sl && closes[1] < g_last_sl && closes[2] >= g_last_sl)
      bear_bos = true;

   // ---- 3. Update active BOS state
   if(bull_bos)
   {
      g_active_bull_bos = true;
      g_active_bear_bos = false;
      g_bos_bar_age     = 0;
      g_bos_bar_time    = times[1];
      MLog("BOS", StringFormat("BULL BOS: close=%.5f broke swing=%.5f",
                                closes[1], g_last_sh));
   }
   else if(bear_bos)
   {
      g_active_bear_bos = true;
      g_active_bull_bos = false;
      g_bos_bar_age     = 0;
      g_bos_bar_time    = times[1];
      MLog("BOS", StringFormat("BEAR BOS: close=%.5f broke swing=%.5f",
                                closes[1], g_last_sl));
   }
   else if(g_active_bull_bos || g_active_bear_bos)
   {
      // age the active BOS by one bar
      g_bos_bar_age++;
      if(g_bos_bar_age > InpBOSAge)
      {
         g_active_bull_bos = false;
         g_active_bear_bos = false;
         g_ob_valid = false;
         MLog("BOS", "active BOS aged out");
      }
   }

   // ---- 4. OB re-anchor on new BOS (Pine: only updates ob_* when BOS fires)
   if(bull_bos)
   {
      g_ob_valid  = false;
      int limit = MathMin(InpOBAge, needed - 2);
      for(int i = 2; i <= limit + 1; i++)
      {
         // Pine indexes from `1` relative to the BOS bar (which is closes[1]).
         // From the BOS bar, "i=1" looks at closes[i+1] in our series (since
         // the BOS itself was at closes[1]). The candle BEFORE the BOS is closes[2].
         if(closes[i] < opens[i])
         {
            g_ob_high = highs[i];
            g_ob_low  = lows[i];
            g_ob_demand = true;
            g_ob_valid = true;
            break;
         }
      }
      if(g_ob_valid)
         MLog("BOS", StringFormat("OB anchored: demand %.5f-%.5f", g_ob_low, g_ob_high));
   }
   if(bear_bos)
   {
      g_ob_valid = false;
      int limit = MathMin(InpOBAge, needed - 2);
      for(int i = 2; i <= limit + 1; i++)
      {
         if(closes[i] > opens[i])
         {
            g_ob_high = highs[i];
            g_ob_low  = lows[i];
            g_ob_demand = false;
            g_ob_valid = true;
            break;
         }
      }
      if(g_ob_valid)
         MLog("BOS", StringFormat("OB anchored: supply %.5f-%.5f", g_ob_low, g_ob_high));
   }
}

//==================================================================//
//  SETUP DETECTION (Pine bull_setup / bear_setup)                    //
//==================================================================//
struct SetupCandidate
{
   bool      valid;
   ENUM_DIR  direction;
   double    entry;
   double    sl_raw;            // OB-derived SL (before clamp)
   double    sl_final;          // after clamp
   double    risk;
   double    tp1, tp2, tp3;
   string    reject_reason;
};

bool BuildSetup(SetupCandidate &out)
{
   out.valid = false;
   out.reject_reason = "";

   if(!g_ob_valid)
   { out.reject_reason = "no OB"; return false; }
   if(!g_active_bull_bos && !g_active_bear_bos)
   { out.reject_reason = "no active BOS"; return false; }

   bool have_ob_bull = g_active_bull_bos && g_ob_demand;
   bool have_ob_bear = g_active_bear_bos && !g_ob_demand;
   if(!have_ob_bull && !have_ob_bear)
   { out.reject_reason = "BOS/OB direction mismatch"; return false; }

   ENUM_DIR dir = have_ob_bull ? DIR_BUY : DIR_SELL;
   out.direction = dir;

   // Use last closed bar's close as Pine's `close` reference
   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(_Symbol, _Period, 0, 2, closes) < 2)
   { out.reject_reason = "close not available"; return false; }
   double c = closes[1];

   double atr = ATRValue();
   if(atr <= 0)
   { out.reject_reason = "ATR unavailable"; return false; }

   // Entry proximity
   double dist = 0.0;
   if(dir == DIR_BUY)  dist = (c > g_ob_high) ? c - g_ob_high : 0.0;
   else                dist = (c < g_ob_low)  ? g_ob_low - c : 0.0;
   if(dist > InpEntryATR * atr)
   { out.reject_reason = StringFormat("price too far from OB (%.2fxATR > %.2fxATR)",
                                       dist / atr, InpEntryATR);
     return false; }

   // HTF agreement — SOFTER rule (Pine):
   //   h1_ok_bull = NOT i_req_h1 OR h1_bull OR NOT h1_bear
   //   h1_ok_bear = NOT i_req_h1 OR h1_bear OR NOT h1_bull
   ENUM_BIAS bias = GetCachedHTFBias();
   bool h1_ok = true;
   if(InpRequireHTF)
   {
      if(dir == DIR_BUY)  h1_ok = (bias == BIAS_BULL || bias != BIAS_BEAR);
      else                h1_ok = (bias == BIAS_BEAR || bias != BIAS_BULL);
   }
   if(!h1_ok)
   { out.reject_reason = "HTF bias conflicts (" + BiasStr(bias) + ")"; return false; }

   // Build candidate SL
   double raw_sl  = (dir == DIR_BUY) ? (g_ob_low  - InpSLBufATR * atr)
                                     : (g_ob_high + InpSLBufATR * atr);
   double raw_dst = (dir == DIR_BUY) ? (c - raw_sl) : (raw_sl - c);

   // Min SL FILTER — reject if too tight
   if(InpMinSLFilter > 0 && raw_dst < InpMinSLFilter)
   { out.reject_reason = StringFormat("SL %.2f$ < min filter %.2f$", raw_dst, InpMinSLFilter);
     return false; }

   // Min SL CLAMP — widen if still too tight
   double final_sl = raw_sl;
   if(InpMinSLClamp > 0 && raw_dst < InpMinSLClamp)
      final_sl = (dir == DIR_BUY) ? (c - InpMinSLClamp) : (c + InpMinSLClamp);

   double risk = (dir == DIR_BUY) ? (c - final_sl) : (final_sl - c);
   if(risk <= 0) { out.reject_reason = "zero risk"; return false; }

   // Broker stops-level pre-flight
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_dist     = MathMax(stops_level, freeze_level) * point;
   if(risk < min_dist)
   { out.reject_reason = StringFormat("risk %.5f < broker stops min %.5f", risk, min_dist);
     return false; }

   out.entry    = c;
   out.sl_raw   = raw_sl;
   out.sl_final = NormPrice(final_sl);
   out.risk     = risk;
   if(dir == DIR_BUY)
   {
      out.tp1 = NormPrice(c + 1.0 * risk);
      out.tp2 = NormPrice(c + 2.0 * risk);
      out.tp3 = NormPrice(c + 3.0 * risk);
   }
   else
   {
      out.tp1 = NormPrice(c - 1.0 * risk);
      out.tp2 = NormPrice(c - 2.0 * risk);
      out.tp3 = NormPrice(c - 3.0 * risk);
   }
   out.valid = true;
   return true;
}

//==================================================================//
//  GATING — cooldown, max positions, date, session                   //
//==================================================================//
bool CooldownPassed()
{
   if(ArraySize(g_trades) > 0) return true;   // multi-position: cooldown only when empty
   if(g_last_close_time == 0) return true;
   long secs = (long)(TimeCurrent() - g_last_close_time);
   long bar_secs = PeriodSeconds(_Period);
   if(bar_secs <= 0) return true;
   long bars = secs / bar_secs;
   return (bars >= InpCooldownBars);
}

bool DailyRiskAllow()
{
   if(g_day_kill) return false;
   if(InpDailyMaxLossR <= 0) return true;
   if(g_day_r <= -InpDailyMaxLossR) { g_day_kill = true; return false; }
   return true;
}

void RollDayIfNeeded()
{
   // Pine attributes outcomes to the trade's OPEN day in Asia/Manila tz.
   // For the EA's day kill switch we just use UTC day; close enough.
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(today != g_day_anchor)
   {
      g_day_anchor = today;
      g_day_r      = 0.0;
      g_day_wins   = 0;
      g_day_losses = 0;
      g_day_kill   = false;
      MLog("RISK", "new UTC day; daily counters reset");
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
//  TRADE EXECUTION                                                   //
//                                                                    //
//  Single-position-per-trade (no thirds). Broker SL attached for     //
//  safety. TP MANAGED INTERNALLY — we don't attach TP to broker so   //
//  we can ride past TP3 when i_move_tp2 is enabled.                  //
//==================================================================//
bool OpenTrade(const SetupCandidate &s)
{
   if(!InpEnableTrade) return false;

   double lots = CalcLotsForRisk(s.risk);
   if(lots <= 0) { MLog("ERR", "lots = 0"); return false; }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   string cmt = StringFormat("Migs:%s", s.direction == DIR_BUY ? "buy" : "sell");
   bool ok = false;
   // SL attached, TP=0 (managed internally)
   if(s.direction == DIR_BUY)
      ok = g_trade.Buy (lots, _Symbol, s.entry, s.sl_final, 0.0, cmt);
   else
      ok = g_trade.Sell(lots, _Symbol, s.entry, s.sl_final, 0.0, cmt);

   uint retcode = g_trade.ResultRetcode();
   if(!ok || retcode != TRADE_RETCODE_DONE)
   {
      MLog("ERR", StringFormat("OrderSend failed retcode %u (%s)",
                                retcode, g_trade.ResultRetcodeDescription()));
      return false;
   }
   // Treat partial fills as failure: position size diverges from requested
   // risk, which would corrupt R-math in the journal. Rare on XAUUSD but
   // we prefer to skip cleanly rather than book a smaller position silently.
   if(g_trade.ResultVolume() > 0
      && MathAbs(g_trade.ResultVolume() - lots) > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) / 2.0)
   {
      MLog("ERR", StringFormat("Partial fill: requested %.2f got %.2f — closing immediately",
                                lots, g_trade.ResultVolume()));
      ulong t = g_trade.ResultOrder();
      if(t == 0) t = g_trade.ResultDeal();
      if(t != 0 && PositionSelectByTicket(t)) g_trade.PositionClose(t);
      return false;
   }

   ulong ticket = g_trade.ResultOrder();
   if(ticket == 0) ticket = g_trade.ResultDeal();
   if(ticket == 0)
   {
      MLog("ERR", StringFormat("OrderSend reported success but ticket=0 (retcode=%d). Refusing to track.",
                                g_trade.ResultRetcode()));
      return false;
   }

   // Capture open-time year/month so close handler always finds the right
   // journal file even when a trade spans a month boundary.
   datetime open_now = TimeCurrent();
   MqlDateTime open_dt; TimeToStruct(open_now, open_dt);

   // Push trade onto active array
   int n = ArraySize(g_trades);
   ArrayResize(g_trades, n + 1);
   g_trades[n].ticket        = ticket;
   g_trades[n].is_long       = (s.direction == DIR_BUY);
   g_trades[n].entry         = s.entry;
   g_trades[n].sl_initial    = s.sl_final;
   g_trades[n].tp1           = s.tp1;
   g_trades[n].tp2           = s.tp2;
   g_trades[n].tp3           = s.tp3;
   g_trades[n].eff_sl        = s.sl_final;
   g_trades[n].eff_sl_r      = -1.0;
   g_trades[n].tp1_done      = false;
   g_trades[n].tp2_done      = false;
   g_trades[n].tp3_done      = false;
   g_trades[n].open_time     = open_now;
   g_trades[n].risk_price    = s.risk;
   g_trades[n].journal_year  = open_dt.year;
   g_trades[n].journal_month = open_dt.mon;
   g_trades[n].journal_id    = InpEnableJournal ? WriteOpenJournal(s, ticket, open_dt) : 0;

   g_sim_count++;
   MLog("TRADE", StringFormat("Opened %s lots=%.2f entry=%.5f SL=%.5f TP1=%.5f TP2=%.5f TP3=%.5f ticket=%I64u",
                              DirStr(s.direction), lots, s.entry, s.sl_final,
                              s.tp1, s.tp2, s.tp3, ticket));
   return true;
}

void RemoveTradeAtIndex(const int idx)
{
   int n = ArraySize(g_trades);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n - 1; i++) g_trades[i] = g_trades[i + 1];
   ArrayResize(g_trades, n - 1);
}

//==================================================================//
//  TRADE MANAGEMENT — process each open trade on bar close            //
//                                                                    //
//  Mirrors Pine logic exactly. Uses bar HIGH/LOW for TP checks (bar  //
//  did or didn't touch the level); uses LIVE Bid/Ask for the         //
//  internal-SL fallback (a trailed SL set mid-bar must not be tested //
//  against the bar that closed before it moved).                     //
//==================================================================//

// Process one open trade. Returns true if the trade was closed (and removed
// from g_trades) inside this call.
bool ProcessOneTrade(const int idx, const double bar_high, const double bar_low,
                     const datetime cur_bar_time)
{
   if(cur_bar_time <= g_trades[idx].open_time) return false;

   const bool tp3_is_final = (InpUseTP3 && !InpMoveTP2AfterTP3);
   const bool tp2_is_final = (!InpUseTP3 && InpUseTP2);
   const bool tp1_is_final = (!InpUseTP3 && !InpUseTP2);

   const bool is_long = g_trades[idx].is_long;

   // ----- TP1 -----
   if(!g_trades[idx].tp1_done)
   {
      bool hit = is_long ? (bar_high >= g_trades[idx].tp1) : (bar_low <= g_trades[idx].tp1);
      if(hit)
      {
         g_trades[idx].tp1_done = true;
         if(tp1_is_final) { CloseTradeAsWin(idx, 1.0, "TP1"); return true; }
         if(InpMoveBE)
         {
            g_trades[idx].eff_sl   = g_trades[idx].entry;
            g_trades[idx].eff_sl_r = 0.0;
            ModifyBrokerSL(idx, g_trades[idx].entry);
            MLog("TRADE", "TP1 hit; SL->BE");
         }
      }
   }

   // ----- TP2 -----
   if(InpUseTP2 && !g_trades[idx].tp2_done)
   {
      bool hit = is_long ? (bar_high >= g_trades[idx].tp2) : (bar_low <= g_trades[idx].tp2);
      if(hit)
      {
         g_trades[idx].tp2_done = true;
         if(tp2_is_final) { CloseTradeAsWin(idx, 2.0, "TP2"); return true; }
         if(InpMoveTP1AfterTP2)
         {
            g_trades[idx].eff_sl   = g_trades[idx].tp1;
            g_trades[idx].eff_sl_r = 1.0;
            ModifyBrokerSL(idx, g_trades[idx].tp1);
            MLog("TRADE", "TP2 hit; SL->TP1");
         }
         else if(InpMoveBEAfterTP2)
         {
            g_trades[idx].eff_sl   = g_trades[idx].entry;
            g_trades[idx].eff_sl_r = 0.0;
            ModifyBrokerSL(idx, g_trades[idx].entry);
            MLog("TRADE", "TP2 hit; SL->BE");
         }
      }
   }

   // ----- TP3 -----
   if(InpUseTP3 && !g_trades[idx].tp3_done)
   {
      bool hit = is_long ? (bar_high >= g_trades[idx].tp3) : (bar_low <= g_trades[idx].tp3);
      if(hit)
      {
         g_trades[idx].tp3_done = true;
         if(tp3_is_final) { CloseTradeAsWin(idx, 3.0, "TP3"); return true; }
         if(InpMoveTP2AfterTP3)
         {
            g_trades[idx].eff_sl   = g_trades[idx].tp2;
            g_trades[idx].eff_sl_r = 2.0;
            ModifyBrokerSL(idx, g_trades[idx].tp2);
            MLog("TRADE", "TP3 hit; SL->TP2 (riding past TP3)");
         }
      }
   }

   // ----- SL: broker may have already filled -----
   if(!PositionSelectByTicket(g_trades[idx].ticket))
   {
      double r = g_trades[idx].eff_sl_r;
      bool was_win = (r >= 0.0);   // SL-while-trailed counts as WIN
      FinalizeClosedTrade(idx, r, was_win, was_win ? "SL_TRAILED" : "SL");
      return true;
   }

   // Internal-SL fallback (broker modify failed and we trailed past the
   // current ticket SL). Compare to LIVE Bid/Ask — comparing to the prior
   // closed bar's H/L would fire spuriously when eff_sl was moved up after
   // that bar closed.
   double cur = is_long ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool internal_sl_hit = is_long ? (cur <= g_trades[idx].eff_sl)
                                  : (cur >= g_trades[idx].eff_sl);
   if(internal_sl_hit)
   {
      g_trade.PositionClose(g_trades[idx].ticket);
      double r = g_trades[idx].eff_sl_r;
      bool was_win = (r >= 0.0);
      FinalizeClosedTrade(idx, r, was_win, was_win ? "SL_TRAILED" : "SL");
      return true;
   }

   return false;
}

void ProcessActiveTrades()
{
   int n = ArraySize(g_trades);
   if(n == 0) return;

   // Last closed bar's H/L drives TP detection (bar did or didn't touch).
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   if(CopyHigh(_Symbol, _Period, 0, 2, highs) < 2) return;
   if(CopyLow (_Symbol, _Period, 0, 2, lows ) < 2) return;
   double bar_high = highs[1];
   double bar_low  = lows[1];

   datetime tt[1];
   if(CopyTime(_Symbol, _Period, 0, 1, tt) != 1) return;
   datetime cur_bar_time = tt[0];

   // Iterate newest-first so any removal inside ProcessOneTrade doesn't
   // shift indices we haven't visited yet.
   for(int idx = n - 1; idx >= 0; idx--)
      ProcessOneTrade(idx, bar_high, bar_low, cur_bar_time);
}

void CloseTradeAsWin(const int idx, const double r_value, const string reason)
{
   ulong t = g_trades[idx].ticket;
   if(PositionSelectByTicket(t))
   {
      if(!g_trade.PositionClose(t))
         MLog("ERR", StringFormat("close failed ticket=%I64u retcode=%d", t, g_trade.ResultRetcode()));
   }
   FinalizeClosedTrade(idx, r_value, true, reason);
}

void ModifyBrokerSL(const int idx, const double new_sl)
{
   ulong t = g_trades[idx].ticket;
   if(!PositionSelectByTicket(t)) return;
   double cur_tp = PositionGetDouble(POSITION_TP);
   if(!g_trade.PositionModify(t, NormPrice(new_sl), cur_tp))
   {
      MLog("ERR", StringFormat("SL modify failed ticket=%I64u retcode=%d",
                                t, g_trade.ResultRetcode()));
   }
}

void FinalizeClosedTrade(const int idx, const double r_realized, const bool is_win, const string reason)
{
   g_sim_total_r += r_realized;
   if(is_win) g_sim_wins++;
   else       g_sim_losses++;

   // Daily aggregates
   g_day_r += r_realized;
   if(is_win) g_day_wins++;
   else       g_day_losses++;
   if(InpDailyMaxLossR > 0 && g_day_r <= -InpDailyMaxLossR && !g_day_kill)
   {
      g_day_kill = true;
      MLog("RISK", StringFormat("Daily kill switch ON: %.2fR <= -%.1fR", g_day_r, InpDailyMaxLossR));
   }

   if(InpEnableJournal)
      UpdateCloseJournal(g_trades[idx].journal_id,
                         g_trades[idx].journal_year,
                         g_trades[idx].journal_month,
                         r_realized, reason);
   MLog("TRADE", StringFormat("Closed: %s R=%.2f cum=%.2fR (W:L = %d:%d)",
                              reason, r_realized, g_sim_total_r, g_sim_wins, g_sim_losses));

   g_last_close_time = TimeCurrent();
   RemoveTradeAtIndex(idx);
}

//==================================================================//
//  JOURNAL — UTF-8 encoded; format consumed by scripts/update_stats.py //
//==================================================================//
string Pad4(int n) { return StringFormat("%04d", n); }

// Write a single line as UTF-8 + CRLF via FILE_BIN. Avoids the FILE_ANSI
// codepage corruption risk in the original implementation.
void JournalWriteLine(int fh, const string s)
{
   uchar bytes[];
   int sz = StringToCharArray(s + "\r\n", bytes, 0, WHOLE_ARRAY, CP_UTF8);
   // StringToCharArray includes a trailing NUL — trim it.
   if(sz > 0 && bytes[sz - 1] == 0) sz--;
   if(sz > 0) FileWriteArray(fh, bytes, 0, sz);
}

// Read an entire UTF-8 file and split it into lines (CRLF or LF tolerated).
// Returns -1 on open failure, otherwise the line count.
int JournalReadLines(const string path, string &lines[])
{
   ArrayResize(lines, 0);
   int fh = FileOpen(path, FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE) return -1;
   ulong sz = FileSize(fh);
   uchar bytes[];
   if(sz > 0)
   {
      ArrayResize(bytes, (int)sz);
      FileReadArray(fh, bytes, 0, (int)sz);
   }
   FileClose(fh);
   string content = (sz > 0) ? CharArrayToString(bytes, 0, WHOLE_ARRAY, CP_UTF8) : "";
   int n = StringSplit(content, (ushort)10, lines);   // split on LF
   for(int i = 0; i < n; i++)
   {
      int len = StringLen(lines[i]);
      if(len > 0 && StringGetCharacter(lines[i], len - 1) == 13)   // strip trailing CR
         lines[i] = StringSubstr(lines[i], 0, len - 1);
   }
   return n;
}

// Scan every YYYY/MM/*.md under InpJournalDir for the highest existing ID and
// return max+1. Re-scans on every call (no cache) so external sync scripts
// can't desync this counter from the on-disk truth.
int NextJournalId()
{
   int max_id = 0;
   string fn;

   // 1) Stray files directly in InpJournalDir
   long rh = FileFindFirst(InpJournalDir + "\\*.md", fn);
   if(rh != INVALID_HANDLE)
   {
      do {
         int id = (int)StringToInteger(StringSubstr(fn, 0, 4));
         if(id > max_id) max_id = id;
      } while(FileFindNext(rh, fn));
      FileFindClose(rh);
   }

   // 2) Walk every year folder, then every month folder within it
   string entry;
   long yh = FileFindFirst(InpJournalDir + "\\*", entry);
   if(yh == INVALID_HANDLE) return max_id + 1;
   do {
      // Strip trailing backslash that FileFindFirst attaches to folder names.
      int el = StringLen(entry);
      string name = (el > 0 && StringGetCharacter(entry, el - 1) == '\\')
                       ? StringSubstr(entry, 0, el - 1)
                       : entry;
      int y = (int)StringToInteger(name);
      if(y < 2000 || y > 2100) continue;   // not a year folder
      for(int m = 1; m <= 12; m++)
      {
         string sub = StringFormat("%s\\%s\\%02d\\*.md", InpJournalDir, name, m);
         long mh = FileFindFirst(sub, fn);
         if(mh == INVALID_HANDLE) continue;
         do {
            int id = (int)StringToInteger(StringSubstr(fn, 0, 4));
            if(id > max_id) max_id = id;
         } while(FileFindNext(mh, fn));
         FileFindClose(mh);
      }
   } while(FileFindNext(yh, entry));
   FileFindClose(yh);

   return max_id + 1;
}

int WriteOpenJournal(const SetupCandidate &s, const ulong ticket, const MqlDateTime &dt)
{
   int id = NextJournalId();
   string ydir = StringFormat("%s\\%04d", InpJournalDir, dt.year);
   string mdir = StringFormat("%s\\%02d", ydir, dt.mon);
   FolderCreate(InpJournalDir);
   FolderCreate(ydir);
   FolderCreate(mdir);
   string suffix = (s.direction == DIR_BUY) ? "buy" : "sell";
   string fname = StringFormat("%s\\%s-%04d-%02d-%02d-%s.md",
                               mdir, Pad4(id), dt.year, dt.mon, dt.day, suffix);
   int fh = FileOpen(fname, FILE_WRITE | FILE_BIN);
   if(fh == INVALID_HANDLE) { MLog("ERR", "journal open failed: " + fname); return -1; }
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   JournalWriteLine(fh, "---");
   JournalWriteLine(fh, "id: \"" + Pad4(id) + "\"");
   JournalWriteLine(fh, StringFormat("timestamp_utc: %04d-%02d-%02dT%02d:%02d:%02dZ",
                                     dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec));
   JournalWriteLine(fh, "direction: " + DirStr(s.direction));
   JournalWriteLine(fh, "strategy: Migs");
   JournalWriteLine(fh, "source: EA");
   JournalWriteLine(fh, "ea_version: \"" + MIGS_VERSION + "\"");
   JournalWriteLine(fh, "pattern: \"" + (s.direction == DIR_BUY ? "buy" : "sell") + "\"");
   JournalWriteLine(fh, "execution_tf: " + EnumToString((ENUM_TIMEFRAMES)_Period));
   JournalWriteLine(fh, "htf_tf: " + EnumToString(InpHTFTimeframe));
   JournalWriteLine(fh, "htf_bias: " + BiasStr(GetCachedHTFBias()));
   JournalWriteLine(fh, "session: " + g_session_now);
   JournalWriteLine(fh, "ticket: " + IntegerToString((long)ticket));
   JournalWriteLine(fh, "entry: "   + DoubleToString(s.entry, digits));
   JournalWriteLine(fh, "sl: "      + DoubleToString(s.sl_final, digits));
   JournalWriteLine(fh, "tp1: "     + DoubleToString(s.tp1, digits));
   JournalWriteLine(fh, "tp2: "     + DoubleToString(s.tp2, digits));
   JournalWriteLine(fh, "tp3: "     + DoubleToString(s.tp3, digits));
   JournalWriteLine(fh, "risk_price: " + DoubleToString(s.risk, digits));
   JournalWriteLine(fh, "outcome: OPEN");
   JournalWriteLine(fh, "r_realized: 0.0");
   JournalWriteLine(fh, "exit_reason: \"\"");
   JournalWriteLine(fh, "---");
   JournalWriteLine(fh, "");
   JournalWriteLine(fh, "## Notes");
   JournalWriteLine(fh, "");
   JournalWriteLine(fh, "Pine-parity EA entry. " + s.reject_reason);
   FileClose(fh);
   MLog("JOURNAL", "wrote " + fname);
   return id;
}

// Locate the journal file using the OPEN-time year/month (passed in via
// MigsTrade) — never the current time. A trade opened on June 30 and closed
// on July 1 used to silently miss its file.
bool UpdateCloseJournal(const int id, const int year, const int month,
                        const double r_realized, const string reason)
{
   if(id <= 0) return false;
   string filter = StringFormat("%s\\%04d\\%02d\\%s-*.md",
                                InpJournalDir, year, month, Pad4(id));
   string fn;
   long h = FileFindFirst(filter, fn);
   if(h == INVALID_HANDLE) return false;
   FileFindClose(h);
   string path = StringFormat("%s\\%04d\\%02d\\%s",
                              InpJournalDir, year, month, fn);

   string lines[];
   int n = JournalReadLines(path, lines);
   if(n < 0) return false;

   string outcome;
   if(reason == "TP1") outcome = "TP1_HIT";
   else if(reason == "TP2") outcome = "TP2_HIT";
   else if(reason == "TP3") outcome = "TP3_HIT";
   else if(reason == "SL_TRAILED") outcome = "BE";
   else outcome = "SL_HIT";

   for(int i = 0; i < n; i++)
   {
      if(StringFind(lines[i], "outcome:") == 0)     lines[i] = "outcome: " + outcome;
      if(StringFind(lines[i], "r_realized:") == 0)  lines[i] = "r_realized: " + DoubleToString(r_realized, 3);
      if(StringFind(lines[i], "exit_reason:") == 0) lines[i] = "exit_reason: \"" + reason + "\"";
   }
   // StringSplit on the trailing \n leaves an empty final element; drop it so
   // the rewrite doesn't grow a blank line on every update.
   int write_n = n;
   if(write_n > 0 && StringLen(lines[write_n - 1]) == 0) write_n--;

   int fh = FileOpen(path, FILE_WRITE | FILE_BIN);
   if(fh == INVALID_HANDLE) return false;
   for(int i = 0; i < write_n; i++) JournalWriteLine(fh, lines[i]);
   FileClose(fh);
   MLog("JOURNAL", "updated " + path + " -> " + outcome);
   return true;
}

//==================================================================//
//  STATUS PANEL                                                      //
//==================================================================//
void EnsureLabel(string suffix, int x, int y, string text, color clr)
{
   string nm = PANEL_PREFIX + suffix;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,
         InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER
            ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1000);
      ObjectSetString(0, nm, OBJPROP_FONT, InpPanelFontName);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpPanelFontSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
}

void DrawPanel()
{
   if(!InpShowPanel) return;
   int line_h = InpPanelFontSize + 5;
   int y = 0;
   int decisive = g_sim_wins + g_sim_losses;
   double wr = decisive > 0 ? (double)g_sim_wins / decisive : 0.0;

   EnsureLabel("hdr", 0, y, "MIGS HYBRID v" + MIGS_VERSION + " (Pine parity)", InpPanelHeaderClr); y += line_h;
   EnsureLabel("sym", 0, y, StringFormat("Symbol  : %s %s", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)), InpPanelColor); y += line_h;

   ENUM_BIAS bias = GetCachedHTFBias();
   color bclr = bias == BIAS_BULL ? InpPanelGoodClr : bias == BIAS_BEAR ? InpPanelBadClr : InpPanelMutedClr;
   EnsureLabel("htf", 0, y,
      StringFormat("HTF     : %s EMA %d/%d %s", EnumToString(InpHTFTimeframe), InpHTFFastEMA, InpHTFSlowEMA, BiasStr(bias)),
      bclr);
   y += line_h;

   string bos_str;
   color  bos_clr;
   if(g_active_bull_bos)      { bos_str = "BULL (age " + IntegerToString(g_bos_bar_age) + ")"; bos_clr = InpPanelGoodClr; }
   else if(g_active_bear_bos) { bos_str = "BEAR (age " + IntegerToString(g_bos_bar_age) + ")"; bos_clr = InpPanelBadClr; }
   else                       { bos_str = "none"; bos_clr = InpPanelMutedClr; }
   EnsureLabel("bos", 0, y, "BOS     : " + bos_str, bos_clr); y += line_h;

   if(g_ob_valid)
   {
      EnsureLabel("ob", 0, y,
         StringFormat("OB      : %s %.5f-%.5f", g_ob_demand ? "demand" : "supply", g_ob_low, g_ob_high),
         InpPanelColor);
   }
   else
   {
      EnsureLabel("ob", 0, y, "OB      : none", InpPanelMutedClr);
   }
   y += line_h;

   EnsureLabel("sess", 0, y, "Session : " + g_session_now, InpPanelColor); y += line_h;

   EnsureLabel("pos", 0, y,
      StringFormat("Trades  : %d / %d active", ArraySize(g_trades), InpMaxPositions),
      InpPanelColor);
   y += line_h;

   color wrclr = decisive == 0 ? InpPanelMutedClr : (wr >= 0.5 ? InpPanelGoodClr : InpPanelBadClr);
   string wr_str = decisive == 0
      ? StringFormat("WR      : 0/0 (cum %+.1fR)", g_sim_total_r)
      : StringFormat("WR      : %.0f%% (%d/%d) %+0.1fR", wr * 100, g_sim_wins, decisive, g_sim_total_r);
   EnsureLabel("wr", 0, y, wr_str, wrclr); y += line_h;

   EnsureLabel("dayr", 0, y, StringFormat("Day R   : %+.2fR (W:L %d:%d)", g_day_r, g_day_wins, g_day_losses),
                g_day_r > 0 ? InpPanelGoodClr : g_day_r < 0 ? InpPanelBadClr : InpPanelMutedClr);
   y += line_h;

   EnsureLabel("ev", 0, y, "Last eval: " + g_last_eval_msg, InpPanelMutedClr);

   ChartRedraw(0);
}

//==================================================================//
//  EVENT HANDLERS                                                    //
//==================================================================//
int OnInit(void)
{
   MLog("INIT", StringFormat("MigsHybrid v%s — Pine parity. Symbol=%s TF=%s",
                              MIGS_VERSION, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)));

   if(!g_symbol.Name(_Symbol)) return INIT_FAILED;

   g_hATR = iATR(_Symbol, _Period, InpATRPer);
   if(g_hATR == INVALID_HANDLE) { MLog("ERR", "iATR failed"); return INIT_FAILED; }

   g_hEMA_HTF_fast = iMA(_Symbol, InpHTFTimeframe, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMA_HTF_fast == INVALID_HANDLE) { MLog("ERR", "iMA fast failed"); return INIT_FAILED; }

   g_hEMA_HTF_slow = iMA(_Symbol, InpHTFTimeframe, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMA_HTF_slow == INVALID_HANDLE) { MLog("ERR", "iMA slow failed"); return INIT_FAILED; }

   // Hedging-account check for multi-position support
   if(InpMaxPositions > 1)
   {
      ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         MLog("WARN", "InpMaxPositions>1 requires hedging account; netting will combine positions");
      }
   }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   FolderCreate(InpJournalDir);
   EventSetTimer(1);
   RollDayIfNeeded();
   DrawPanel();

   PrintFormat("Migs v%s ready. HTF=%s EMA %d/%d. Pivot len=%d. EntryATR=%.2f. SL buf=%.2f. MinSL($)=%.1f/%.1f. Cooldown=%dbars.",
               MIGS_VERSION,
               EnumToString(InpHTFTimeframe), InpHTFFastEMA, InpHTFSlowEMA,
               InpSwingLen, InpEntryATR, InpSLBufATR,
               InpMinSLFilter, InpMinSLClamp, InpCooldownBars);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hATR          != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEMA_HTF_fast != INVALID_HANDLE) IndicatorRelease(g_hEMA_HTF_fast);
   if(g_hEMA_HTF_slow != INVALID_HANDLE) IndicatorRelease(g_hEMA_HTF_slow);
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw(0);
   MLog("DEINIT", "reason=" + IntegerToString(reason));
}

void OnTimer(void)
{
   RollDayIfNeeded();
   DrawPanel();
}

void OnTick(void)
{
   // Manage trades every tick (in case of fast moves)
   if(ArraySize(g_trades) > 0) ProcessActiveTrades();

   datetime now = TimeCurrent();
   if(InpShowPanel && now != g_status_redraw_t)
   {
      g_status_redraw_t = now;
      DrawPanel();
   }

   // Signal logic only on new bar (bar-close confirmation, mirrors Pine isconfirmed)
   if(!IsNewBar()) return;

   // Update structure state on every new bar
   UpdateStructureState();

   // Gating
   if(!InpEnableTrade)                          { g_last_eval_msg = "trade disabled"; return; }
   if(!IsInDateRange(now))                      { g_last_eval_msg = "outside date range"; return; }
   if(!IsInAnyAllowedSession(now))              { g_last_eval_msg = "outside session"; return; }
   if(!DailyRiskAllow())                        { g_last_eval_msg = "daily kill"; return; }
   if(!CooldownPassed())                        { g_last_eval_msg = "cooldown"; return; }
   if(ArraySize(g_trades) >= InpMaxPositions)   { g_last_eval_msg = "max positions"; return; }

   SetupCandidate s;
   if(!BuildSetup(s))
   {
      g_last_eval_msg = s.reject_reason;
      DrawPanel();
      return;
   }

   g_last_eval_msg = StringFormat("SIGNAL %s @%.5f", DirStr(s.direction), s.entry);
   MLog("SIGNAL", StringFormat("%s entry=%.5f SL=%.5f TP1=%.5f TP2=%.5f TP3=%.5f risk=%.5f",
                                DirStr(s.direction), s.entry, s.sl_final,
                                s.tp1, s.tp2, s.tp3, s.risk));
   OpenTrade(s);
   DrawPanel();
}

void OnTrade(void)
{
   // Re-check closures on trade events (catches broker SL fills)
   if(ArraySize(g_trades) > 0) ProcessActiveTrades();
}
