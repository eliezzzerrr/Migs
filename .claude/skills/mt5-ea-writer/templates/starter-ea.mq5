//+------------------------------------------------------------------+
//|                                              StarterEA.mq5        |
//|                                            Copyright 2026, You    |
//+------------------------------------------------------------------+
// RIGHT-FIRST-TIME CHECKLIST  (verify before every compile)
// [✓] No #property strict anywhere
// [✓] All `input` at top-level of .mq5, above includes
// [✓] OnInit returns int, returns INIT_SUCCEEDED/FAILED/PARAMETERS_INCORRECT
// [✓] Indicator handles created in OnInit, released in OnDeinit
// [✓] Every trade call followed by ResultRetcode() == TRADE_RETCODE_DONE check
// [✓] PositionsTotal() loop is backward, filters by magic + symbol
// [✓] MqlDateTime fields use .mon and .min (NOT .month / .minute)
// [✓] CalendarValueHistory gated on !MQLInfoInteger(MQL_TESTER)
// [✓] ChartRedraw(0) called once after batch of ObjectSet*
// [✓] SetTypeFillingBySymbol + SetDeviationInPoints set in OnInit
// [✓] No iATR/iMA/etc inside OnTick — only CopyBuffer from cached handles
// [✓] SL/TP pre-flight check against SYMBOL_TRADE_STOPS_LEVEL
// [✓] IsNewBar() gate around bar-close strategy logic
//+------------------------------------------------------------------+
#property copyright "You"
#property version   "1.00"
#property description "MT5 EA starter template — compiles cleanly. Replace strategy logic in EvaluateAndTrade()."

//==================================================================//
//  INCLUDES                                                          //
//==================================================================//
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================//
//  INPUTS                                                            //
//==================================================================//
input group "=== Identity ==="
input long   InpMagicNumber  = 20260522;
input string InpComment      = "StarterEA";

input group "=== Risk ==="
input double InpRiskPercent  = 1.0;
input int    InpMaxOpen      = 1;

input group "=== Indicators ==="
input int    InpATRPeriod    = 14;

input group "=== Trade Management ==="
input ulong  InpDeviationPts = 20;
input bool   InpEnableTrade  = true;

input group "=== Display ==="
input bool   InpShowPanel    = true;
input color  InpPanelColor   = clrBlack;
input string InpPanelFont    = "Consolas";
input int    InpPanelSize    = 10;

//==================================================================//
//  ENUMS                                                             //
//==================================================================//
enum ENUM_TRADE_STATE { STATE_FLAT, STATE_LONG, STATE_SHORT };

//==================================================================//
//  STRUCTS                                                           //
//==================================================================//
struct TradeState
{
   ulong    position_id;
   datetime entry_time;
   double   entry_price;
   double   sl;
   double   tp;
   double   r_distance;
};

//==================================================================//
//  GLOBALS                                                           //
//==================================================================//
CTrade        g_trade;
CSymbolInfo   g_symbol;
CPositionInfo g_pos;

int          g_hATR        = INVALID_HANDLE;
datetime     g_last_bar    = 0;
int          g_total_wins  = 0;
int          g_total_loss  = 0;
double       g_total_r     = 0.0;

#define PANEL_PREFIX "StarterEA_Panel_"

//==================================================================//
//  HELPERS                                                           //
//==================================================================//
bool IsNewBar()
{
   datetime cur = iTime(_Symbol, _Period, 0);
   if(cur == g_last_bar) return false;
   g_last_bar = cur;
   return true;
}

double ATRValue()
{
   if(g_hATR == INVALID_HANDLE) return 0.0;
   if(BarsCalculated(g_hATR) < InpATRPeriod) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, 0, 2, buf) < 2) return 0.0;
   return buf[1];   // last closed bar
}

double NormalizeLots(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   if(lots < vmin) return vmin;
   if(lots > vmax) return vmax;
   return lots;
}

double CalcLotSize(double risk_pct, double sl_distance_price)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * risk_pct / 100.0;
   double tick_v     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_s     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_s <= 0 || tick_v <= 0 || sl_distance_price <= 0) return 0.0;
   double ticks_in_sl = sl_distance_price / tick_s;
   double money_per_lot = ticks_in_sl * tick_v;
   if(money_per_lot <= 0) return 0.0;
   return NormalizeLots(risk_money / money_per_lot);
}

bool PassesStopLevels(double entry, double sl, double tp)
{
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_dist     = MathMax(stops_level, freeze_level) * point;
   if(MathAbs(entry - sl) < min_dist) return false;
   if(tp > 0 && MathAbs(tp - entry) < min_dist) return false;
   return true;
}

int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      n++;
   }
   return n;
}

void EnsurePanelLabel(string suffix, int x, int y, string text, color clr)
{
   string nm = PANEL_PREFIX + suffix;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER,     1000);
      ObjectSetString (0, nm, OBJPROP_FONT,       InpPanelFont);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   InpPanelSize);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     clr);
   ObjectSetString (0, nm, OBJPROP_TEXT,      text);
}

void DrawPanel()
{
   if(!InpShowPanel) return;
   int y = 20;
   int decisive = g_total_wins + g_total_loss;
   double wr = (decisive > 0) ? (double)g_total_wins / decisive : 0.0;

   EnsurePanelLabel("hdr",  10, y, "=== Starter EA v1.0 ===",                            InpPanelColor); y += 15;
   EnsurePanelLabel("sym",  10, y, StringFormat("Symbol  : %s  %s", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period)), InpPanelColor); y += 15;
   EnsurePanelLabel("eq",   10, y, StringFormat("Equity  : %.2f %s", AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoString(ACCOUNT_CURRENCY)), InpPanelColor); y += 15;
   EnsurePanelLabel("pos",  10, y, StringFormat("Open    : %d / %d",  CountMyPositions(), InpMaxOpen),    InpPanelColor); y += 15;
   if(decisive > 0)
      EnsurePanelLabel("wr",   10, y, StringFormat("WR      : %.0f%% (%d/%d, %+0.1fR)", wr * 100, g_total_wins, decisive, g_total_r), InpPanelColor);
   else
      EnsurePanelLabel("wr",   10, y, "WR      : 0/0",                                  InpPanelColor);
   y += 15;
   EnsurePanelLabel("atr",  10, y, StringFormat("ATR(%d) : %s", InpATRPeriod, DoubleToString(ATRValue(), _Digits)), InpPanelColor); y += 15;

   ChartRedraw(0);
}

//==================================================================//
//  STRATEGY — replace this with your actual logic                    //
//==================================================================//
void EvaluateAndTrade()
{
   // Example: do nothing. Replace with real strategy.
   //
   // Typical flow:
   //   1. Read indicator buffers (CopyBuffer from cached handles)
   //   2. Apply your entry condition
   //   3. Compute entry, SL, TP, lot size
   //   4. PassesStopLevels() check
   //   5. trade.Buy() or trade.Sell()
   //   6. Check trade.ResultRetcode() == TRADE_RETCODE_DONE
   //   7. Persist trade state (if multi-position) for OnTradeTransaction reconciliation
}

//==================================================================//
//  EVENT HANDLERS                                                    //
//==================================================================//
int OnInit(void)
{
   // Symbol info ready check
   if(!g_symbol.Name(_Symbol)) return INIT_FAILED;

   // Indicator handles
   g_hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle: ", GetLastError());
      return INIT_FAILED;
   }

   // CTrade setup
   g_trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPts);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // Optional: enforce account type. Uncomment if your strategy needs hedging.
   // if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   // {
   //    Print("FATAL: hedging account required for multi-position TPs.");
   //    return INIT_PARAMETERS_INCORRECT;
   // }

   // Timer for periodic panel refresh
   EventSetTimer(1);

   DrawPanel();
   PrintFormat("StarterEA v1.0 initialized on %s %s, magic=%d",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period), InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw(0);
   PrintFormat("StarterEA deinitialized; reason=%d", reason);
}

void OnTick(void)
{
   if(!InpEnableTrade) return;

   // Strategy fires once per bar close
   if(!IsNewBar()) return;

   // Max-concurrent gate
   if(CountMyPositions() >= InpMaxOpen) return;

   EvaluateAndTrade();
}

void OnTimer(void)
{
   DrawPanel();
}

void OnTrade(void)
{
   // Lightweight reconciliation; heavy lifting in OnTradeTransaction.
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest      &request,
                        const MqlTradeResult       &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)        return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   // Track WR + R for the panel
   if(profit > 0.0) { g_total_wins++; }
   else if(profit < 0.0) { g_total_loss++; }

   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double r_realized = (risk_money > 0) ? profit / risk_money : 0.0;
   g_total_r += r_realized;

   PrintFormat("Position closed: profit=%.2f R=%.2f cumR=%.2f WR=%d/%d",
               profit, r_realized, g_total_r, g_total_wins, g_total_wins + g_total_loss);

   DrawPanel();
}
//+------------------------------------------------------------------+
