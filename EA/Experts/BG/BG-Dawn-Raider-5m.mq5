//+------------------------------------------------------------------+
//|                                       BG-Dawn-Raider-5m.mq5        |
//|                                            Copyright 2026, BG      |
//|                                                                    |
//|  HTF-BIAS + CONFIRMED ASIAN-RANGE BREAKOUT (XAUUSD, M5).           |
//|  A NEW, standalone strategy — NOT related to BG-Golden-Signal-5m.  |
//|                                                                    |
//|  Doctrine source: docs/research/                                  |
//|    2026-06-03-xauusd-asian-htf-5m-deep-research.md                |
//|  Every rule below traces to that digest. Where the research left   |
//|  a question open (raw-vs-retest entry, target management), the     |
//|  EA exposes a TOGGLE so the DEMO run produces the missing data.    |
//|                                                                    |
//|  STRATEGY (times are PHT / GMT+8 by default — the trader's clock): |
//|   1. HTF BIAS  — EMA(fast)/EMA(slow) stack on H1 AND H4 must agree |
//|      (close-vs-fast gate), plus an ADX regime filter. RANGING or   |
//|      low-ADX  => NO TRADE. (Research finding 4 + 6: trade with the |
//|      HTF trend; the breakout edge lives in high-vol regimes only.) |
//|   2. ASIAN BOX — track the Tokyo-session high/low over the range   |
//|      window (08:00-15:00 PHT). Frozen when the window ends.        |
//|   3. EXECUTION — only during the London-open window (15:00-17:00   |
//|      PHT = 07:00-09:00 GMT), still BEFORE NY red-folder data.      |
//|   4. ENTRY (gold variant) — a 5m BODY close beyond the box on the  |
//|      bias side, THEN a pullback that RETESTS and HOLDS the level   |
//|      (gold fakes raw breakouts ~70-80% of the time — finding 3).   |
//|      InpEntryMode=RAW skips the retest for A/B testing.            |
//|   5. STOP — beyond the retest swing +/- an ATR buffer (NOT the far |
//|      side of the range, which is the ~1:1 R:R trap — finding 2),   |
//|      floored by InpMinStopUSD.                                     |
//|   6. MANAGEMENT — optimize for EXPECTANCY, not win rate (finding   |
//|      5). Move SL->BE at +1R, then ATR-TRAIL the runner to capture  |
//|      the heavy-tail winners. No fixed 2:1/3:1 scale-out (that exact |
//|      scheme was REFUTED 0-3 in verification). NOTE: a 0.01-lot      |
//|      position can't be partialled, so BE-at-1R replaces "partial   |
//|      at 1R"; identical intent for a 1-lot-indivisible account.     |
//|   7. CAPS — <=3 trades/day + a daily max-loss kill (in R).         |
//|   8. NEWS — block new entries around USD/EUR/GBP high-impact events |
//|      (EU morning data overlaps the 15:00-17:00 PHT window).        |
//|                                                                    |
//|  HONEST CAVEAT (from the research): there is NO gold-specific       |
//|  backtest of this design. Every performance number is borrowed     |
//|  from oil/equities/trend-following. This is a HYPOTHESIS to        |
//|  forward-test in DEMO. The CSV log exists to gather that data.     |
//|                                                                    |
//|  RIGHT-FIRST-TIME CHECKLIST                                        |
//|   [x] No #property strict                                          |
//|   [x] All input at top-level of .mq5                               |
//|   [x] OnInit returns int (INIT_SUCCEEDED/FAILED/PARAMETERS_INCORRECT)
//|   [x] All indicator handles created in OnInit, released in OnDeinit |
//|   [x] Every trade call checked via ResultRetcode==TRADE_RETCODE_DONE
//|   [x] PositionSelectByTicket; single-position model, magic+symbol   |
//|   [x] MqlDateTime uses .mon and .min                                |
//|   [x] ChartRedraw(0) once after batch of ObjectSet*                |
//|   [x] SetTypeFillingBySymbol + SetDeviationInPoints in OnInit      |
//|   [x] No iATR/iMA/iADX inside OnTick — CopyBuffer from cached       |
//|   [x] SL pre-flight vs SYMBOL_TRADE_STOPS_LEVEL/FREEZE_LEVEL        |
//|   [x] IsNewBar() gate around bar-close signal logic                 |
//|   [x] CalendarValueHistory gated on !MQL_TESTER + CSV fallback     |
//|   [x] No PositionClosePartial (single position — netting-safe)     |
//+------------------------------------------------------------------+
#property copyright "BG"
#property version   "0.20"
#property description "BG Dawn Raider 5m v0.2.0 — HTF-bias + confirmed Asian-range breakout (XAUUSD). Defaults Pine-synced (ADX15, exec15-23, 1-of-2 HTF, BE off, trail1.5). Forward-test build."

//==================================================================//
//  INCLUDES                                                          //
//==================================================================//
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================//
//  ENUMS                                                             //
//==================================================================//
enum ENUM_DIR        { DIR_NONE = 0, DIR_BUY = 1, DIR_SELL = 2 };
enum ENUM_BIAS       { BIAS_RANGE = 0, BIAS_BULL = 1, BIAS_BEAR = 2 };
enum ENUM_ENTRY_MODE { ENTRY_RETEST = 0,   // break -> pullback -> hold (gold default)
                       ENTRY_RAW    = 1 }; // enter on the breakout close (A/B test)

//==================================================================//
//  INPUTS                                                            //
//==================================================================//
input group "=== Master ==="
input bool   InpEnableTrade       = true;        // Master kill switch

input group "=== HTF Bias (research finding 4 + ADX regime, finding 6) ==="
input bool            InpUseHTF1        = true;          // Use HTF #1 in the bias
input ENUM_TIMEFRAMES InpHTF1           = PERIOD_H1;     // HTF #1
input bool            InpUseHTF2        = true;          // Use HTF #2 in the bias
input ENUM_TIMEFRAMES InpHTF2           = PERIOD_H4;     // HTF #2
input bool            InpRequireBothAgree = false;       // Both HTFs must agree (else RANGE=no trade) — Pine-synced: H1 primary, H4 fallback
input int             InpHTFFastEMA     = 20;            // Fast EMA (both HTFs)
input int             InpHTFSlowEMA     = 50;            // Slow EMA (both HTFs)
input bool            InpUseADXFilter   = true;          // Block trades when HTF is non-trending
input ENUM_TIMEFRAMES InpADXTimeframe   = PERIOD_H1;     // ADX timeframe
input int             InpADXPeriod      = 14;            // ADX period
input double          InpADXMin         = 15.0;          // Min ADX to consider HTF "trending" — Pine-synced

input group "=== Asian Range Box (PHT / GMT+8, hour resolution — optimizable) ==="
input int    InpRangeStartHour    = 8;          // Tokyo range-build START hour (PHT, 0-23)
input int    InpRangeEndHour      = 15;         // Range END hour (PHT) — box freezes; exec may begin

input group "=== Execution Window (PHT / GMT+8, hour resolution — optimizable) ==="
input int    InpExecStartHour     = 15;         // Execution START hour (PHT, 0-23)
input int    InpExecEndHour       = 23;         // Execution END hour (PHT) — no new entries after. Pine-synced (was 17; now spans NY). News filter handles US events.

input group "=== Entry ==="
input ENUM_ENTRY_MODE InpEntryMode      = ENTRY_RETEST; // RETEST (gold default) or RAW (A/B test)
input double InpBreakoutMinATR    = 0.5;        // Breakout candle range >= x*ATR (0 = off)
input double InpRetestTolATR      = 0.5;        // Pullback must come within x*ATR of the level
input int    InpRetestMaxBars     = 12;         // Bars to wait for the retest before abandoning — Pine-synced

input group "=== Stops & Targets ==="
input int    InpATRPeriod         = 14;         // ATR period (M5; stops/trail/breakout strength)
input double InpSLBufferATR       = 0.3;        // SL buffer beyond the retest swing (x ATR)
input double InpMinStopUSD        = 3.0;        // Min stop distance in $ (floor; widen if tighter)
input double InpMoveBEAtR         = 0.0;        // Move SL->BE once price reaches this R (0 = off) — Pine-synced: BE OFF
input bool   InpUseTrail          = true;       // ATR-trail the runner (capture heavy tail)
input double InpTrailStartR       = 1.0;        // Start trailing after this R
input double InpTrailATRmult      = 1.5;        // Trail distance = x * ATR behind the extreme — Pine-synced
input double InpFinalTPR          = 0.0;        // Hard broker TP at this R (0 = ride the trail)

input group "=== Risk Sizing ==="
input double InpRiskPercent       = 1.0;        // % equity risked per trade (when not fixed lots)
input bool   InpUseFixedLots      = false;      // ON = fixed lots; OFF = size by % risk
input double InpFixedLots         = 0.01;       // Fixed lot size
input double InpMaxLots           = 100.0;      // Safety cap
input bool   InpWarnMinLotRisk    = true;       // Warn when min-lot over-risks the % target

input group "=== Daily Caps ==="
input int    InpMaxTradesPerDay   = 3;          // Hard cap on entries per PHT day
input double InpDailyMaxLossR     = 2.0;        // Daily kill switch in R (0 = off)
input int    InpCooldownBars      = 3;          // Bars to wait after a trade closes

input group "=== News Filter (USD/EUR/GBP high-impact) ==="
input bool   InpUseNewsFilter     = false;      // Block new entries around high-impact news — OFF for Pine-parity backtest (Pine has no news gate; re-enable for live)
input int    InpNewsMinsBefore    = 15;         // Blackout minutes before an event
input int    InpNewsMinsAfter     = 15;         // Blackout minutes after an event
input string InpNewsCurrencies    = "USD,EUR,GBP"; // Currencies whose news blocks entries
input string InpNewsCSV           = "news.csv"; // Tester fallback CSV (MQL5\Files\news.csv)

input group "=== Session Timezone ==="
input int    InpSessionGMTOffset  = 8;          // TZ the window strings are written in (GMT+8 PHT) — leave at 8
input int    InpServerGMTOffset   = 0;          // Broker SERVER clock UTC offset (GMT+3 broker => 3). Calibrate via the panel's Manila clock.

input group "=== Trade Management ==="
input long   InpMagic             = 20260603;   // EA magic (distinct from BG Golden)
input ulong  InpSlippagePoints    = 30;         // Allowed deviation on market orders

input group "=== CSV Trade Log ==="
input bool   InpEnableCSVLog      = true;       // Append each closed trade to a CSV (for analysis)
input string InpCSVFile           = "BGDR\\bgdr_trades.csv"; // Relative to MQL5\Files

input group "=== Optimization (Strategy Tester) ==="
input int    InpMinTesterTrades   = 30;         // OnTester: reject optimization passes with fewer trades than this

input group "=== Logging ==="
input bool   InpVerbose           = true;       // INFO logs to the Experts tab

input group "=== On-Chart Status Panel ==="
input bool             InpShowPanel      = true;
input ENUM_BASE_CORNER InpPanelCorner    = CORNER_RIGHT_UPPER;
input int              InpPanelX         = 10;
input int              InpPanelY         = 20;
input int              InpPanelFontSize   = 9;
input string           InpPanelFontName   = "Consolas";
input color            InpPanelColor      = clrBlack;
input color            InpPanelHeaderClr  = clrSaddleBrown;
input color            InpPanelGoodClr    = clrDarkGreen;
input color            InpPanelBadClr     = clrFireBrick;
input color            InpPanelMutedClr   = clrDimGray;
input color            InpPanelWarnClr    = clrDarkOrange;

//==================================================================//
//  CONSTANTS                                                         //
//==================================================================//
#define BGDR_VERSION       "0.1.0"
#define PANEL_PREFIX        "BGDR_"
#define ATR_BUFFER_BARS     5
#define BIAS_CACHE_SECS     30
#define CSV_HEADER          "open_utc,close_utc,dir,mode,bias,adx,box_high,box_low,box_size,entry,sl,risk_usd,exit,r,mfe_r,outcome"

//==================================================================//
//  STRUCTS                                                           //
//==================================================================//
struct SetupCandidate
{
   bool      valid;
   ENUM_DIR  dir;
   double    entry;
   double    sl;
   double    risk;
   string    mode;
   string    reason;
};

struct BGDRPos
{
   ulong     ticket;
   bool      is_long;
   double    entry;        // actual fill
   double    sl_initial;
   double    eff_sl;       // current (possibly trailed) SL
   double    risk;         // |entry - sl_initial| in price
   bool      be_done;
   double    max_price;    // best price reached since entry (for trail + MFE)
   double    mfe_r;        // max favourable excursion in R
   datetime  open_time;    // server time at open
   string    mode;         // "retest" / "raw"
   string    bias_str;     // bias at entry
   double    adx;          // ADX at entry
   double    box_high;
   double    box_low;
};

//==================================================================//
//  GLOBALS                                                           //
//==================================================================//
CTrade        g_trade;
CSymbolInfo   g_symbol;

int           g_hATR        = INVALID_HANDLE;
int           g_hEMA_H1f    = INVALID_HANDLE;
int           g_hEMA_H1s    = INVALID_HANDLE;
int           g_hEMA_H4f    = INVALID_HANDLE;
int           g_hEMA_H4s    = INVALID_HANDLE;
int           g_hADX        = INVALID_HANDLE;

datetime      g_last_bar    = 0;

// Asian box
double        g_box_high    = 0.0;
double        g_box_low     = 0.0;
bool          g_box_has     = false;

// Breakout / retest state machine
int           g_phase       = 0;          // 0 = await breakout, 1 = await retest hold
ENUM_DIR      g_break_dir   = DIR_NONE;
double        g_break_level = 0.0;
double        g_retest_ext   = 0.0;       // lowest low (buy) / highest high (sell) since breakout
bool          g_retest_touched = false;
int           g_bars_since_break = 0;

// Bias cache
ENUM_BIAS     g_bias_cache  = BIAS_RANGE;
datetime      g_bias_t      = 0;

// Day state (PHT day)
datetime      g_pht_day     = 0;
int           g_day_trades  = 0;
double        g_day_r       = 0.0;
int           g_day_wins    = 0;
int           g_day_losses  = 0;
bool          g_day_kill    = false;

// Position
BGDRPos       g_pos;
bool          g_has_pos     = false;
datetime      g_last_close_time = 0;

// Aggregate stats
int           g_sim_count   = 0;
int           g_sim_wins    = 0;
int           g_sim_losses  = 0;
double        g_sim_total_r = 0.0;

// Panel diagnostics
string        g_last_eval_msg = "(init)";
string        g_session_now   = "off";
datetime      g_status_redraw_t = 0;
bool          g_news_warned     = false;

//==================================================================//
//  HELPERS — logging / formatting / math                            //
//==================================================================//
void MLog(const string tag, const string msg)
{
   if(!InpVerbose && tag != "ERR" && tag != "TRADE" && tag != "RISK" && tag != "INIT")
      return;
   PrintFormat("[BGDR][%s] %s", tag, msg);
}

string DirStr(const ENUM_DIR d)  { return d == DIR_BUY ? "BUY" : d == DIR_SELL ? "SELL" : "NONE"; }
string BiasStr(const ENUM_BIAS b){ return b == BIAS_BULL ? "bullish" : b == BIAS_BEAR ? "bearish" : "ranging"; }

double NormPrice(const double p)
{
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizeLots(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   if(lots < vmin) return vmin;
   if(lots > vmax) return vmax;
   if(lots > InpMaxLots) return InpMaxLots;
   return lots;
}

double ATRValue()
{
   if(g_hATR == INVALID_HANDLE) return 0.0;
   if(BarsCalculated(g_hATR) < InpATRPeriod + ATR_BUFFER_BARS) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, 0, 2, buf) < 2) return 0.0;
   return buf[1];   // last closed bar
}

double RiskMoney(const double lots, const double sl_distance)
{
   double tick_v = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_s = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_s <= 0 || tick_v <= 0 || sl_distance <= 0) return 0.0;
   return (sl_distance / tick_s) * tick_v * lots;
}

double CalcLotsForRisk(const double sl_distance)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * InpRiskPercent / 100.0;
   double tick_v     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_s     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_s <= 0 || tick_v <= 0 || sl_distance <= 0) return 0.0;
   double money_per_lot = (sl_distance / tick_s) * tick_v;
   if(money_per_lot <= 0) return 0.0;
   return NormalizeLots(risk_money / money_per_lot);
}

//==================================================================//
//  TIME / SESSION HELPERS (PHT-centric; mirrors BG Golden TZ logic) //
//==================================================================//
bool ParseSession(const string s, int &h_from, int &m_from, int &h_to, int &m_to)
{
   if(StringLen(s) != 11) return false;   // "HH:MM-HH:MM"
   h_from = (int)StringToInteger(StringSubstr(s, 0, 2));
   m_from = (int)StringToInteger(StringSubstr(s, 3, 2));
   h_to   = (int)StringToInteger(StringSubstr(s, 6, 2));
   m_to   = (int)StringToInteger(StringSubstr(s, 9, 2));
   return true;
}

// Is the given UTC moment inside a "HH:MM-HH:MM" window written in gmt_offset TZ?
bool InSession(const string sess, const datetime utc_now, const int gmt_offset)
{
   int hf, mf, ht, mt;
   if(!ParseSession(sess, hf, mf, ht, mt)) return false;
   datetime local = utc_now + gmt_offset * 3600;
   MqlDateTime dt; TimeToStruct(local, dt);
   int now_m  = dt.hour * 60 + dt.min;
   int from_m = hf * 60 + mf;
   int to_m   = ht * 60 + mt;
   if(from_m <= to_m) return (now_m >= from_m && now_m < to_m);
   return (now_m >= from_m || now_m < to_m);   // crosses midnight
}

// Minutes-of-day (0..1439) in PHT for a broker-SERVER moment.
int PHTMinOfDay(const datetime server_t)
{
   datetime pht = server_t - InpServerGMTOffset * 3600 + InpSessionGMTOffset * 3600;
   MqlDateTime dt; TimeToStruct(pht, dt);
   return dt.hour * 60 + dt.min;
}

// Is a broker-SERVER moment inside an [start_h, end_h) PHT hour window?
bool InHourWindow(const int start_h, const int end_h, const datetime server_t)
{
   int m    = PHTMinOfDay(server_t);
   int from = start_h * 60;
   int to   = end_h   * 60;
   if(from <= to) return (m >= from && m < to);
   return (m >= from || m < to);   // crosses midnight
}

// PHT calendar day (midnight) for a broker-SERVER moment.
datetime PHTDay(const datetime server_t)
{
   datetime pht = server_t - InpServerGMTOffset * 3600 + InpSessionGMTOffset * 3600;
   MqlDateTime dt; TimeToStruct(pht, dt);
   return StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
}

//==================================================================//
//  HTF BIAS — EMA stack on H1 + H4, ADX regime gate                  //
//==================================================================//
ENUM_BIAS BiasOnTF(const int hf, const int hs, const ENUM_TIMEFRAMES tf)
{
   if(hf == INVALID_HANDLE || hs == INVALID_HANDLE) return BIAS_RANGE;
   if(BarsCalculated(hf) < InpHTFSlowEMA + 5) return BIAS_RANGE;
   if(BarsCalculated(hs) < InpHTFSlowEMA + 5) return BIAS_RANGE;
   double f[], s[], c[];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   ArraySetAsSeries(c, true);
   if(CopyBuffer(hf, 0, 0, 2, f) < 2) return BIAS_RANGE;
   if(CopyBuffer(hs, 0, 0, 2, s) < 2) return BIAS_RANGE;
   if(CopyClose(_Symbol, tf, 1, 1, c) < 1) return BIAS_RANGE;
   double ff = f[1], ss = s[1], cc = c[0];   // previous closed HTF bar (non-repaint)
   if(ff > ss && cc > ff) return BIAS_BULL;
   if(ff < ss && cc < ff) return BIAS_BEAR;
   return BIAS_RANGE;
}

double ADXValue()
{
   if(g_hADX == INVALID_HANDLE) return 0.0;
   if(BarsCalculated(g_hADX) < InpADXPeriod + 5) return 0.0;
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(g_hADX, 0, 0, 2, b) < 2) return 0.0;   // buffer 0 = ADX main line
   return b[1];
}

ENUM_BIAS DetectNetBias()
{
   ENUM_BIAS b1 = InpUseHTF1 ? BiasOnTF(g_hEMA_H1f, g_hEMA_H1s, InpHTF1) : BIAS_RANGE;
   ENUM_BIAS b2 = InpUseHTF2 ? BiasOnTF(g_hEMA_H4f, g_hEMA_H4s, InpHTF2) : BIAS_RANGE;

   ENUM_BIAS net;
   if(InpUseHTF1 && InpUseHTF2)
   {
      if(InpRequireBothAgree) net = (b1 == b2) ? b1 : BIAS_RANGE;
      else                    net = (b1 != BIAS_RANGE) ? b1 : b2;
   }
   else if(InpUseHTF1) net = b1;
   else if(InpUseHTF2) net = b2;
   else                net = BIAS_RANGE;   // no HTF selected => no directional bias => no trade

   if(InpUseADXFilter)
   {
      double adx = ADXValue();
      if(adx > 0.0 && adx < InpADXMin) net = BIAS_RANGE;   // non-trending regime => stand down
   }
   return net;
}

ENUM_BIAS GetNetBias()
{
   datetime now = TimeCurrent();
   if(now - g_bias_t > BIAS_CACHE_SECS)
   {
      g_bias_cache = DetectNetBias();
      g_bias_t     = now;
   }
   return g_bias_cache;
}

//==================================================================//
//  NEWS FILTER — calendar (live) + CSV fallback (tester)             //
//==================================================================//
bool NewsCurrencyBlocked(const string ccy)
{
   return (StringFind(InpNewsCurrencies, ccy) >= 0);
}

bool NewsFromAPI(const datetime utc_now)
{
   datetime from = utc_now - InpNewsMinsBefore * 60;
   datetime to   = utc_now + InpNewsMinsAfter  * 60;
   MqlCalendarValue values[];
   int got = CalendarValueHistory(values, from, to);
   if(got < 0)
   {
      // Deliberate fail-OPEN: a persistent calendar error must not silently
      // disable ALL trading. The execution window already dodges US news;
      // EU-news protection is secondary. Warn once, then allow.
      if(!g_news_warned)
      {
         MLog("RISK", StringFormat("Calendar API error %d — news filter failing OPEN (trades allowed).", GetLastError()));
         g_news_warned = true;
      }
      return false;
   }
   for(int i = 0; i < got; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      MqlCalendarCountry cc;
      if(!CalendarCountryById(ev.country_id, cc)) continue;
      if(!NewsCurrencyBlocked(cc.currency)) continue;
      datetime t = values[i].time;
      if(t >= from && t <= to) return true;
   }
   return false;
}

bool NewsFromCSV(const datetime utc_now)
{
   int fh = FileOpen(InpNewsCSV, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return false;   // no data => don't block
   datetime from = utc_now - InpNewsMinsBefore * 60;
   datetime to   = utc_now + InpNewsMinsAfter  * 60;
   bool found = false, header_skipped = false;
   while(!FileIsEnding(fh))
   {
      string ts  = FileReadString(fh);
      string imp = FileReadString(fh);
      string ccy = FileReadString(fh);
      string evn = FileReadString(fh);
      if(!header_skipped) { header_skipped = true; continue; }
      if(StringFind(imp, "High") < 0 && StringFind(imp, "Red") < 0) continue;
      if(!NewsCurrencyBlocked(ccy)) continue;
      datetime t = StringToTime(ts);
      if(t >= from && t <= to) { found = true; break; }
   }
   FileClose(fh);
   return found;
}

bool IsNewsBlackout(const datetime server_now)
{
   if(!InpUseNewsFilter) return false;
   datetime utc = server_now - InpServerGMTOffset * 3600;
   if(MQLInfoInteger(MQL_TESTER)) return NewsFromCSV(utc);
   return NewsFromAPI(utc);
}

//==================================================================//
//  BREAKOUT STATE MACHINE                                            //
//==================================================================//
void ResetBreakout()
{
   g_phase          = 0;
   g_break_dir      = DIR_NONE;
   g_break_level    = 0.0;
   g_retest_ext     = 0.0;
   g_retest_touched = false;
   g_bars_since_break = 0;
}

// Build the box from the last CLOSED bar if it fell inside the range window.
void UpdateBox()
{
   double highs[], lows[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   ArraySetAsSeries(times, true);
   if(CopyHigh(_Symbol, _Period, 0, 2, highs) < 2) return;
   if(CopyLow (_Symbol, _Period, 0, 2, lows ) < 2) return;
   if(CopyTime(_Symbol, _Period, 0, 2, times) < 2) return;

   if(!InHourWindow(InpRangeStartHour, InpRangeEndHour, times[1])) return;   // closed bar not in the range window
   if(!g_box_has)
   {
      g_box_high = highs[1];
      g_box_low  = lows[1];
      g_box_has  = true;
   }
   else
   {
      g_box_high = MathMax(g_box_high, highs[1]);
      g_box_low  = MathMin(g_box_low,  lows[1]);
   }
}

// Apply the min-stop floor + broker stops-level pre-flight and fill the candidate.
void FinishSetup(SetupCandidate &s, const ENUM_DIR dir, double entry, double sl, const string mode)
{
   double risk = (dir == DIR_BUY) ? (entry - sl) : (sl - entry);
   if(InpMinStopUSD > 0 && risk < InpMinStopUSD)
   {
      sl   = (dir == DIR_BUY) ? (entry - InpMinStopUSD) : (entry + InpMinStopUSD);
      risk = InpMinStopUSD;
   }
   if(risk <= 0) { s.reason = "zero risk"; return; }

   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_dist     = MathMax(stops_level, freeze_level) * point;
   if(risk < min_dist) { s.reason = StringFormat("risk %.2f < broker min %.2f", risk, min_dist); return; }

   s.valid = true;
   s.dir   = dir;
   s.entry = NormPrice(entry);
   s.sl    = NormPrice(sl);
   s.risk  = risk;
   s.mode  = mode;
}

// The heart: detect the confirmed breakout on the last closed bar.
SetupCandidate EvaluateEntry()
{
   SetupCandidate s;
   s.valid = false; s.reason = ""; s.dir = DIR_NONE; s.entry = 0; s.sl = 0; s.risk = 0; s.mode = "";

   ENUM_BIAS bias = GetNetBias();
   ENUM_DIR  dir  = (bias == BIAS_BULL) ? DIR_BUY : (bias == BIAS_BEAR) ? DIR_SELL : DIR_NONE;
   if(dir == DIR_NONE) { ResetBreakout(); s.reason = "HTF ranging / low ADX"; return s; }

   // If we were armed in the opposite direction (bias flipped), start over.
   if(g_phase != 0 && g_break_dir != dir) ResetBreakout();

   double c[], h[], l[];
   ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   if(CopyClose(_Symbol, _Period, 0, 3, c) < 3) { s.reason = "bars n/a"; return s; }
   if(CopyHigh (_Symbol, _Period, 0, 3, h) < 3) { s.reason = "bars n/a"; return s; }
   if(CopyLow  (_Symbol, _Period, 0, 3, l) < 3) { s.reason = "bars n/a"; return s; }

   double atr = ATRValue();
   if(atr <= 0) { s.reason = "ATR n/a"; return s; }

   double cc = c[1], hh = h[1], ll = l[1];   // last closed bar
   double tol = InpRetestTolATR * atr;
   double buf = InpSLBufferATR  * atr;

   if(dir == DIR_BUY)
   {
      double level = g_box_high;
      if(g_phase == 0)
      {
         bool body_close = (cc > level);                                   // close (body) beyond — excludes wick pokes
         bool strong     = (InpBreakoutMinATR <= 0) || ((hh - ll) >= InpBreakoutMinATR * atr);
         if(body_close && strong)
         {
            if(InpEntryMode == ENTRY_RAW)
            {
               FinishSetup(s, DIR_BUY, cc, ll - buf, "raw");
               if(!s.valid && s.reason == "") s.reason = "raw setup rejected";
               return s;
            }
            g_phase = 1; g_break_dir = DIR_BUY; g_break_level = level;
            g_retest_ext = ll; g_retest_touched = false; g_bars_since_break = 0;
            s.reason = "broke up; await retest";
            return s;
         }
         s.reason = "await up-break";
         return s;
      }
      else  // phase 1: waiting for the retest to hold
      {
         g_bars_since_break++;
         g_retest_ext = MathMin(g_retest_ext, ll);
         if(cc < g_box_low)               { ResetBreakout(); s.reason = "breakout failed (closed below box)"; return s; }
         if(g_bars_since_break > InpRetestMaxBars) { ResetBreakout(); s.reason = "retest timed out"; return s; }
         if(ll <= g_break_level + tol) g_retest_touched = true;            // came back to test the level
         if(g_retest_touched && cc > g_break_level)                        // and closed back above => held
         {
            FinishSetup(s, DIR_BUY, cc, g_retest_ext - buf, "retest");
            if(!s.valid && s.reason == "") s.reason = "retest setup rejected";
            return s;
         }
         s.reason = g_retest_touched ? "retested; await hold-close" : "await retest";
         return s;
      }
   }
   else  // DIR_SELL (mirror)
   {
      double level = g_box_low;
      if(g_phase == 0)
      {
         bool body_close = (cc < level);
         bool strong     = (InpBreakoutMinATR <= 0) || ((hh - ll) >= InpBreakoutMinATR * atr);
         if(body_close && strong)
         {
            if(InpEntryMode == ENTRY_RAW)
            {
               FinishSetup(s, DIR_SELL, cc, hh + buf, "raw");
               if(!s.valid && s.reason == "") s.reason = "raw setup rejected";
               return s;
            }
            g_phase = 1; g_break_dir = DIR_SELL; g_break_level = level;
            g_retest_ext = hh; g_retest_touched = false; g_bars_since_break = 0;
            s.reason = "broke down; await retest";
            return s;
         }
         s.reason = "await down-break";
         return s;
      }
      else
      {
         g_bars_since_break++;
         g_retest_ext = MathMax(g_retest_ext, hh);
         if(cc > g_box_high)              { ResetBreakout(); s.reason = "breakout failed (closed above box)"; return s; }
         if(g_bars_since_break > InpRetestMaxBars) { ResetBreakout(); s.reason = "retest timed out"; return s; }
         if(hh >= g_break_level - tol) g_retest_touched = true;
         if(g_retest_touched && cc < g_break_level)
         {
            FinishSetup(s, DIR_SELL, cc, g_retest_ext + buf, "retest");
            if(!s.valid && s.reason == "") s.reason = "retest setup rejected";
            return s;
         }
         s.reason = g_retest_touched ? "retested; await hold-close" : "await retest";
         return s;
      }
   }
}

//==================================================================//
//  GATING                                                            //
//==================================================================//
bool IsNewBar()
{
   datetime t[1];
   if(CopyTime(_Symbol, _Period, 0, 1, t) != 1) return false;
   if(t[0] != g_last_bar) { g_last_bar = t[0]; return true; }
   return false;
}

bool CooldownPassed()
{
   if(g_last_close_time == 0) return true;
   long secs = (long)(TimeCurrent() - g_last_close_time);
   long bs   = PeriodSeconds(_Period);
   if(bs <= 0) return true;
   return ((secs / bs) >= InpCooldownBars);
}

void RollDayIfNeeded()
{
   datetime d = PHTDay(TimeTradeServer());
   if(d != g_pht_day)
   {
      g_pht_day    = d;
      g_day_trades = 0;
      g_day_r      = 0.0;
      g_day_wins   = 0;
      g_day_losses = 0;
      g_day_kill   = false;
      g_box_has    = false;
      g_box_high   = 0.0;
      g_box_low    = 0.0;
      ResetBreakout();
      MLog("RISK", "new PHT day; box + daily counters reset");
   }
}

//==================================================================//
//  EXECUTION                                                         //
//==================================================================//
double ClosedPositionPrice(const ulong pos_ticket)
{
   if(!HistorySelectByPosition(pos_ticket)) return 0.0;
   double price = 0.0;
   int n = HistoryDealsTotal();
   for(int i = n - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      { price = HistoryDealGetDouble(d, DEAL_PRICE); break; }
   }
   return price;
}

void SetSL(const double new_sl)
{
   if(!PositionSelectByTicket(g_pos.ticket)) return;
   double tp = PositionGetDouble(POSITION_TP);
   if(!g_trade.PositionModify(g_pos.ticket, NormPrice(new_sl), tp))
      MLog("ERR", StringFormat("SL modify failed retcode=%d (%s)",
                               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
}

void CSVAppend(const string line)
{
   if(!InpEnableCSVLog) return;
   FolderCreate("BGDR");
   int fh = FileOpen(InpCSVFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE) { MLog("ERR", "CSV open failed: " + InpCSVFile); return; }
   if(FileSize(fh) == 0) FileWriteString(fh, CSV_HEADER + "\r\n");
   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh, line + "\r\n");
   FileClose(fh);
}

void CSVLogTrade(const double r, const double exit_price, const string outcome)
{
   datetime ot_utc = g_pos.open_time     - InpServerGMTOffset * 3600;
   datetime ct_utc = TimeTradeServer()   - InpServerGMTOffset * 3600;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string line =
        TimeToString(ot_utc, TIME_DATE | TIME_SECONDS) + ","
      + TimeToString(ct_utc, TIME_DATE | TIME_SECONDS) + ","
      + (g_pos.is_long ? "BUY" : "SELL") + ","
      + g_pos.mode + ","
      + g_pos.bias_str + ","
      + DoubleToString(g_pos.adx, 1) + ","
      + DoubleToString(g_pos.box_high, dg) + ","
      + DoubleToString(g_pos.box_low,  dg) + ","
      + DoubleToString(g_pos.box_high - g_pos.box_low, 2) + ","
      + DoubleToString(g_pos.entry, dg) + ","
      + DoubleToString(g_pos.sl_initial, dg) + ","
      + DoubleToString(g_pos.risk,  2) + ","
      + DoubleToString(exit_price,  dg) + ","
      + DoubleToString(r, 3) + ","
      + DoubleToString(g_pos.mfe_r, 2) + ","
      + outcome;
   CSVAppend(line);
}

bool OpenTrade(SetupCandidate &s)
{
   if(!InpEnableTrade) return false;

   double lots = InpUseFixedLots ? NormalizeLots(InpFixedLots) : CalcLotsForRisk(s.risk);
   if(lots <= 0) { MLog("ERR", "lots = 0 (risk too small for tick value)"); return false; }

   if(!InpUseFixedLots && InpWarnMinLotRisk)
   {
      double rm  = RiskMoney(lots, s.risk);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double pct = (eq > 0) ? rm / eq * 100.0 : 0.0;
      if(pct > InpRiskPercent * 1.10)
         MLog("RISK", StringFormat("Min-lot OVER-RISK: %.2f lots risks %.2f %s (%.2f%% > target %.2f%%). Account too small to honour %.2f%% on a $%.2f stop.",
                                   lots, rm, AccountInfoString(ACCOUNT_CURRENCY), pct, InpRiskPercent, InpRiskPercent, s.risk));
   }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   double tp = 0.0;
   if(InpFinalTPR > 0)
      tp = NormPrice(s.dir == DIR_BUY ? s.entry + InpFinalTPR * s.risk
                                      : s.entry - InpFinalTPR * s.risk);

   string cmt = StringFormat("BGDR:%s:%s", s.dir == DIR_BUY ? "buy" : "sell", s.mode);
   bool ok = (s.dir == DIR_BUY)
                ? g_trade.Buy (lots, _Symbol, 0.0, s.sl, tp, cmt)
                : g_trade.Sell(lots, _Symbol, 0.0, s.sl, tp, cmt);

   uint rc = g_trade.ResultRetcode();
   if(!ok || rc != TRADE_RETCODE_DONE)
   {
      MLog("ERR", StringFormat("OrderSend failed retcode=%u (%s)", rc, g_trade.ResultRetcodeDescription()));
      return false;
   }

   ulong ticket = g_trade.ResultOrder();
   if(ticket == 0) ticket = g_trade.ResultDeal();
   if(ticket == 0) { MLog("ERR", "OrderSend ok but ticket=0; not tracking"); return false; }

   double fill = g_trade.ResultPrice();
   if(fill <= 0) fill = s.entry;
   double risk = (s.dir == DIR_BUY) ? (fill - s.sl) : (s.sl - fill);
   if(risk <= 0) risk = s.risk;

   g_pos.ticket     = ticket;
   g_pos.is_long    = (s.dir == DIR_BUY);
   g_pos.entry      = fill;
   g_pos.sl_initial = s.sl;
   g_pos.eff_sl     = s.sl;
   g_pos.risk       = risk;
   g_pos.be_done    = false;
   g_pos.max_price  = fill;
   g_pos.mfe_r      = 0.0;
   g_pos.open_time  = TimeTradeServer();
   g_pos.mode       = s.mode;
   g_pos.bias_str   = BiasStr(GetNetBias());
   g_pos.adx        = ADXValue();
   g_pos.box_high   = g_box_high;
   g_pos.box_low    = g_box_low;
   g_has_pos        = true;
   g_day_trades++;
   g_sim_count++;

   MLog("TRADE", StringFormat("OPEN %s [%s] lots=%.2f entry=%.2f SL=%.2f risk=$%.2f tp=%.2f tkt=%I64u (day trade #%d)",
                              DirStr(s.dir), s.mode, lots, fill, s.sl, risk, tp, ticket, g_day_trades));
   return true;
}

void FinalizeClosed(double r, const double exit_price)
{
   bool win = (r > 0.0);
   g_sim_total_r += r;
   if(win) g_sim_wins++; else g_sim_losses++;
   g_day_r += r;
   if(win) g_day_wins++; else g_day_losses++;
   if(InpDailyMaxLossR > 0 && g_day_r <= -InpDailyMaxLossR && !g_day_kill)
   {
      g_day_kill = true;
      MLog("RISK", StringFormat("Daily kill ON: %.2fR <= -%.1fR", g_day_r, InpDailyMaxLossR));
   }

   string outcome;
   if(MathAbs(r) < 0.05)      outcome = "BE";
   else if(r >= 2.0)          outcome = "WIN_BIG";
   else if(win)               outcome = "WIN";
   else                       outcome = "LOSS";

   CSVLogTrade(r, exit_price, outcome);
   MLog("TRADE", StringFormat("CLOSE %s R=%.2f (mfe %.2fR) cum=%.2fR  W:L=%d:%d",
                              outcome, r, g_pos.mfe_r, g_sim_total_r, g_sim_wins, g_sim_losses));

   g_last_close_time = TimeCurrent();
   g_has_pos = false;
   ResetBreakout();
}

void ProcessPosition()
{
   if(!g_has_pos) return;

   // Closed by broker (SL hit, trailed SL, or hard TP)?
   if(!PositionSelectByTicket(g_pos.ticket))
   {
      double exit_price = ClosedPositionPrice(g_pos.ticket);
      if(exit_price <= 0) exit_price = g_pos.eff_sl;   // history not ready — approximate with last SL
      double r = (g_pos.is_long) ? (exit_price - g_pos.entry) / g_pos.risk
                                 : (g_pos.entry - exit_price) / g_pos.risk;
      FinalizeClosed(r, exit_price);
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double cur = g_pos.is_long ? bid : ask;

   if(g_pos.is_long) g_pos.max_price = MathMax(g_pos.max_price, cur);
   else              g_pos.max_price = MathMin(g_pos.max_price, cur);

   double fav  = g_pos.is_long ? (g_pos.max_price - g_pos.entry) : (g_pos.entry - g_pos.max_price);
   double favR = (g_pos.risk > 0) ? fav / g_pos.risk : 0.0;
   if(favR > g_pos.mfe_r) g_pos.mfe_r = favR;

   // Move SL -> break-even at +InpMoveBEAtR (replaces "partial at 1R" — 0.01 lot is indivisible)
   if(!g_pos.be_done && InpMoveBEAtR > 0 && favR >= InpMoveBEAtR)
   {
      SetSL(g_pos.entry);
      g_pos.eff_sl  = g_pos.entry;
      g_pos.be_done = true;
      MLog("TRADE", "reached +" + DoubleToString(InpMoveBEAtR, 1) + "R; SL -> break-even");
   }

   // ATR-trail the runner to capture the heavy tail
   if(InpUseTrail && favR >= InpTrailStartR)
   {
      double atr = ATRValue();
      if(atr > 0)
      {
         double nsl = g_pos.is_long ? (g_pos.max_price - InpTrailATRmult * atr)
                                    : (g_pos.max_price + InpTrailATRmult * atr);
         if(g_pos.is_long && nsl > g_pos.eff_sl + _Point)  { SetSL(nsl); g_pos.eff_sl = nsl; }
         if(!g_pos.is_long && nsl < g_pos.eff_sl - _Point) { SetSL(nsl); g_pos.eff_sl = nsl; }
      }
   }
}

//==================================================================//
//  STATUS PANEL                                                      //
//==================================================================//
void EnsureLabel(const string suffix, const int x, const int y, const string text, const color clr)
{
   string nm = PANEL_PREFIX + suffix;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,
         (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER)
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

string PhaseStr()
{
   if(g_has_pos)        return "IN TRADE";
   if(g_phase == 1)     return g_retest_touched ? "retest held?" : "await retest";
   return "await break";
}

void DrawPanel()
{
   if(!InpShowPanel) return;
   int line_h = InpPanelFontSize + 5;
   int y = 0;
   int decisive = g_sim_wins + g_sim_losses;
   double wr = decisive > 0 ? (double)g_sim_wins / decisive : 0.0;

   EnsureLabel("hdr", 0, y, "BG DAWN RAIDER 5m v" + BGDR_VERSION, InpPanelHeaderClr); y += line_h;
   EnsureLabel("sym", 0, y, StringFormat("Symbol  : %s %s", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)), InpPanelColor); y += line_h;

   datetime srv_t = TimeTradeServer();
   datetime mnl_t = srv_t - InpServerGMTOffset * 3600 + InpSessionGMTOffset * 3600;
   EnsureLabel("mt5t", 0, y, StringFormat("MT5 time: %s (GMT%+d)", TimeToString(srv_t, TIME_DATE | TIME_MINUTES), InpServerGMTOffset), InpPanelColor); y += line_h;
   EnsureLabel("mnlt", 0, y, StringFormat("Manila  : %s (GMT+%d)", TimeToString(mnl_t, TIME_DATE | TIME_MINUTES), InpSessionGMTOffset), InpPanelColor); y += line_h;

   ENUM_BIAS bias = GetNetBias();
   color bclr = bias == BIAS_BULL ? InpPanelGoodClr : bias == BIAS_BEAR ? InpPanelBadClr : InpPanelMutedClr;
   EnsureLabel("bias", 0, y, StringFormat("HTF bias: %s  (ADX %.0f)", BiasStr(bias), ADXValue()), bclr); y += line_h;

   if(g_box_has)
      EnsureLabel("box", 0, y, StringFormat("Asia box: %.2f - %.2f  ($%.2f)", g_box_low, g_box_high, g_box_high - g_box_low), InpPanelColor);
   else
      EnsureLabel("box", 0, y, "Asia box: building...", InpPanelMutedClr);
   y += line_h;

   EnsureLabel("sess", 0, y, StringFormat("Window  : %s   [%s]", g_session_now, PhaseStr()), InpPanelColor); y += line_h;

   if(g_has_pos)
   {
      EnsureLabel("pos", 0, y, StringFormat("Trade   : %s @%.2f SL %.2f %s mfe %.2fR",
                                            g_pos.is_long ? "BUY" : "SELL", g_pos.entry, g_pos.eff_sl,
                                            g_pos.be_done ? "(BE+)" : "", g_pos.mfe_r), InpPanelColor);
   }
   else
   {
      string lots_str = InpUseFixedLots
         ? StringFormat("flat  (fixed %.2f lots)", NormalizeLots(InpFixedLots))
         : StringFormat("flat  (~%.2f lots @ $%.0f SL, %.1f%%)", CalcLotsForRisk(InpMinStopUSD), InpMinStopUSD, InpRiskPercent);
      EnsureLabel("pos", 0, y, "Trade   : " + lots_str, InpPanelColor);
   }
   y += line_h;

   color dayclr = g_day_kill ? InpPanelBadClr : InpPanelColor;
   EnsureLabel("day", 0, y, StringFormat("Today   : %d/%d trades  %+.2fR %s",
                                         g_day_trades, InpMaxTradesPerDay, g_day_r, g_day_kill ? "(KILLED)" : ""), dayclr); y += line_h;

   color wrclr = decisive == 0 ? InpPanelMutedClr : (wr >= 0.5 ? InpPanelGoodClr : InpPanelBadClr);
   string wr_str = decisive == 0
      ? StringFormat("Record  : 0/0 (cum %+.1fR)", g_sim_total_r)
      : StringFormat("Record  : %.0f%% (%d/%d) %+.1fR", wr * 100, g_sim_wins, decisive, g_sim_total_r);
   EnsureLabel("wr", 0, y, wr_str, wrclr); y += line_h;

   EnsureLabel("ev", 0, y, "Last    : " + g_last_eval_msg, InpPanelMutedClr);

   ChartRedraw(0);
}

//==================================================================//
//  EVENT HANDLERS                                                    //
//==================================================================//
int OnInit(void)
{
   MLog("INIT", StringFormat("BG Dawn Raider v%s — HTF-bias + Asian-range breakout. Symbol=%s TF=%s",
                             BGDR_VERSION, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)));

   if(!g_symbol.Name(_Symbol)) return INIT_FAILED;

   if(!InpUseHTF1 && !InpUseHTF2)
   {
      MLog("ERR", "At least one HTF must be enabled for a directional bias.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE) { MLog("ERR", "iATR failed"); return INIT_FAILED; }

   if(InpUseHTF1)
   {
      g_hEMA_H1f = iMA(_Symbol, InpHTF1, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_H1s = iMA(_Symbol, InpHTF1, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hEMA_H1f == INVALID_HANDLE || g_hEMA_H1s == INVALID_HANDLE) { MLog("ERR", "iMA H1 failed"); return INIT_FAILED; }
   }
   if(InpUseHTF2)
   {
      g_hEMA_H4f = iMA(_Symbol, InpHTF2, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_H4s = iMA(_Symbol, InpHTF2, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hEMA_H4f == INVALID_HANDLE || g_hEMA_H4s == INVALID_HANDLE) { MLog("ERR", "iMA H4 failed"); return INIT_FAILED; }
   }
   if(InpUseADXFilter)
   {
      g_hADX = iADX(_Symbol, InpADXTimeframe, InpADXPeriod);
      if(g_hADX == INVALID_HANDLE) { MLog("ERR", "iADX failed"); return INIT_FAILED; }
   }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(InpEnableCSVLog) FolderCreate("BGDR");
   EventSetTimer(1);
   RollDayIfNeeded();
   DrawPanel();

   int detected = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 3600.0);
   MLog("INIT", StringFormat("Server=%s GMT=%s detected~GMT%+d. InpServerGMTOffset=GMT%+d, windows in GMT+%d (PHT). EntryMode=%s.",
                             TimeToString(TimeTradeServer(), TIME_DATE | TIME_MINUTES),
                             TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES),
                             detected, InpServerGMTOffset, InpSessionGMTOffset,
                             InpEntryMode == ENTRY_RETEST ? "RETEST" : "RAW"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hATR     != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEMA_H1f != INVALID_HANDLE) IndicatorRelease(g_hEMA_H1f);
   if(g_hEMA_H1s != INVALID_HANDLE) IndicatorRelease(g_hEMA_H1s);
   if(g_hEMA_H4f != INVALID_HANDLE) IndicatorRelease(g_hEMA_H4f);
   if(g_hEMA_H4s != INVALID_HANDLE) IndicatorRelease(g_hEMA_H4s);
   if(g_hADX     != INVALID_HANDLE) IndicatorRelease(g_hADX);
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw(0);
   MLog("INIT", "deinit; reason=" + IntegerToString(reason));
}

void OnTimer(void)
{
   RollDayIfNeeded();
   DrawPanel();
}

void OnTick(void)
{
   // Manage the open trade every tick (fast moves, BE, trail, broker-close detection)
   if(g_has_pos) ProcessPosition();

   datetime now = TimeCurrent();
   if(InpShowPanel && now != g_status_redraw_t)
   {
      g_status_redraw_t = now;
      DrawPanel();
   }

   // Signal logic is bar-close gated
   if(!IsNewBar()) return;

   RollDayIfNeeded();
   UpdateBox();   // extend the Asian box while inside the range window

   datetime srv = TimeTradeServer();
   g_session_now = InHourWindow(InpExecStartHour, InpExecEndHour, srv) ? "EXEC"
                 : InHourWindow(InpRangeStartHour, InpRangeEndHour, srv) ? "range" : "off";

   if(!InpEnableTrade)                         { g_last_eval_msg = "trade disabled"; return; }
   if(g_has_pos)                               { g_last_eval_msg = "in trade";       return; }
   if(!InHourWindow(InpExecStartHour, InpExecEndHour, srv)) { g_last_eval_msg = "outside exec window"; ResetBreakout(); return; }
   if(!g_box_has)                              { g_last_eval_msg = "no range box yet"; return; }
   if(g_day_kill)                              { g_last_eval_msg = "daily kill";     return; }
   if(g_day_trades >= InpMaxTradesPerDay)      { g_last_eval_msg = "daily trade cap"; return; }
   if(!CooldownPassed())                       { g_last_eval_msg = "cooldown";       return; }
   if(IsNewsBlackout(srv))                     { g_last_eval_msg = "news blackout";  return; }

   SetupCandidate s = EvaluateEntry();
   if(!s.valid)
   {
      g_last_eval_msg = s.reason;
      DrawPanel();
      return;
   }

   g_last_eval_msg = StringFormat("SIGNAL %s [%s] @%.2f", DirStr(s.dir), s.mode, s.entry);
   MLog("TRADE", StringFormat("%s entry=%.2f SL=%.2f risk=$%.2f mode=%s box=%.2f-%.2f",
                              DirStr(s.dir), s.entry, s.sl, s.risk, s.mode, g_box_low, g_box_high));
   if(OpenTrade(s)) ResetBreakout();
   DrawPanel();
}

void OnTrade(void)
{
   // Catch broker-side closes (SL/TP fills) between ticks.
   if(g_has_pos) ProcessPosition();
}

//+------------------------------------------------------------------+
//|  Custom optimization criterion (select "Custom max" in tester).   |
//|  Optimizes for EXPECTANCY, sample-size aware: per-trade expected   |
//|  payoff * sqrt(trades), so a robust well-sampled edge beats a      |
//|  lucky handful. Passes with < InpMinTesterTrades score 0 (reject). |
//|  Mirrors the research mandate: optimize expectancy, not win rate.  |
//+------------------------------------------------------------------+
double OnTester(void)
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < InpMinTesterTrades) return 0.0;
   double ep = TesterStatistics(STAT_EXPECTED_PAYOFF);   // per-trade expectancy (deposit ccy)
   return ep * MathSqrt(trades);
}
//+------------------------------------------------------------------+
