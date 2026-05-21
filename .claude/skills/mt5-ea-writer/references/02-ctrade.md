# CTrade Class — Methods, Signatures, Return Codes

From `<Trade/Trade.mqh>`, current builds. Verified against [CTrade docs](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade).

## Setup (call once in OnInit)

```mql5
void  SetExpertMagicNumber(ulong magic);
void  SetDeviationInPoints(ulong deviation);                  // slippage budget
bool  SetTypeFilling(ENUM_ORDER_TYPE_FILLING filling);
bool  SetTypeFillingBySymbol(const string symbol);            // auto-pick FOK/IOC/Return per broker
void  SetAsyncMode(bool mode);
void  SetMarginMode(void);
void  LogLevel(ENUM_LOG_LEVELS log_level);
```

Canonical OnInit block:
```mql5
g_trade.SetExpertMagicNumber(InpMagic);
g_trade.SetDeviationInPoints(20);   // 20 points typical; tune per symbol
g_trade.SetTypeFillingBySymbol(_Symbol);
```

## Quick market trades

```mql5
bool Buy (double volume, const string symbol=NULL, double price=0.0,
          double sl=0.0, double tp=0.0, const string comment="");
bool Sell(double volume, const string symbol=NULL, double price=0.0,
          double sl=0.0, double tp=0.0, const string comment="");
```

`price=0.0` means "use current market". On a real market order the `price` parameter is informational only — broker fills at current Ask (Buy) or Bid (Sell).

## Pending orders

```mql5
bool BuyLimit (double volume, double price, const string symbol=NULL,
               double sl=0.0, double tp=0.0,
               ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,
               datetime expiration=0, const string comment="");
bool SellLimit(double volume, double price, const string symbol=NULL, ...);
bool BuyStop  (double volume, double price, const string symbol=NULL, ...);
bool SellStop (double volume, double price, const string symbol=NULL, ...);
```

## Position operations

```mql5
bool PositionOpen    (const string symbol, ENUM_ORDER_TYPE order_type,
                      double volume, double price,
                      double sl, double tp, const string comment="");
bool PositionModify  (const string symbol, double sl, double tp);
bool PositionModify  (const ulong  ticket, double sl, double tp);
bool PositionClose   (const string symbol, ulong deviation=ULONG_MAX);
bool PositionClose   (const ulong  ticket, ulong deviation=ULONG_MAX);
bool PositionClosePartial(const string symbol, double volume, ulong deviation=ULONG_MAX);
bool PositionClosePartial(const ulong  ticket, double volume, ulong deviation=ULONG_MAX);
```

**Critical:** `PositionClosePartial` works on **hedging accounts only**. Check:
```mql5
ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
   Print("FATAL: partial close requires hedging account");
   return INIT_PARAMETERS_INCORRECT;
}
```

## Result access (after every trade call)

```mql5
uint   ResultRetcode(void)            const;   // returns uint
ulong  ResultOrder(void)              const;   // order ticket
ulong  ResultDeal(void)               const;   // deal ticket
double ResultVolume(void)             const;
double ResultPrice(void)              const;
double ResultBid(void)                const;
double ResultAsk(void)                const;
string ResultComment(void)            const;
string ResultRetcodeDescription(void) const;
```

## The mandatory pattern — bool return is NOT enough

```mql5
bool ok = g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "MyEA");
if(!ok) {
   PrintFormat("Trade request failed validation: retcode=%u (%s)",
               g_trade.ResultRetcode(),
               g_trade.ResultRetcodeDescription());
   return;
}
if(g_trade.ResultRetcode() != TRADE_RETCODE_DONE
&& g_trade.ResultRetcode() != TRADE_RETCODE_DONE_PARTIAL) {
   PrintFormat("Server rejected: retcode=%u (%s)",
               g_trade.ResultRetcode(),
               g_trade.ResultRetcodeDescription());
   return;
}
// Now safe to consider the trade open. Get the ticket:
ulong ticket = g_trade.ResultOrder();
// Or for instant-fill brokers where deal=order: g_trade.ResultDeal();
```

`bool` from `Buy()/Sell()/Close...()` only means **"request structure validated and was sent"**. The server can still reject the actual trade.

## TRADE_RETCODE_* constants you must handle

From [trade return codes enum](https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes):

| Code | Constant | Meaning | What to do |
|---|---|---|---|
| 10004 | `TRADE_RETCODE_REQUOTE` | Requote | Retry with refreshed price + larger deviation |
| 10006 | `TRADE_RETCODE_REJECT` | Rejected | Log and skip |
| 10008 | `TRADE_RETCODE_PLACED` | Pending order placed (async only) | Track via order ticket |
| **10009** | **`TRADE_RETCODE_DONE`** | **Success** | Proceed |
| 10010 | `TRADE_RETCODE_DONE_PARTIAL` | Only part filled | Check `ResultVolume()` for what filled |
| 10013 | `TRADE_RETCODE_INVALID` | Invalid request | Fix in code, never retry blindly |
| 10014 | `TRADE_RETCODE_INVALID_VOLUME` | Bad lot size | Read `SYMBOL_VOLUME_MIN/MAX/STEP` and re-normalize |
| 10015 | `TRADE_RETCODE_INVALID_PRICE` | Bad price | Refresh tick, retry |
| 10016 | `TRADE_RETCODE_INVALID_STOPS` | SL/TP too close to market | Check `SYMBOL_TRADE_STOPS_LEVEL` |
| 10018 | `TRADE_RETCODE_MARKET_CLOSED` | Off-hours | Skip, retry next session |
| 10019 | `TRADE_RETCODE_NO_MONEY` | Insufficient margin | Reduce size or skip |
| 10020 | `TRADE_RETCODE_PRICE_CHANGED` | Price changed mid-send | Retry once |
| 10027 | `TRADE_RETCODE_CLIENT_DISABLES_AT` | AutoTrading off in terminal | Cannot proceed; tell user to click "Algo Trading" |
| 10028 | `TRADE_RETCODE_LOCKED` | Account/symbol locked | Log; skip |
| 10029 | `TRADE_RETCODE_FROZEN` | Order frozen (within freeze level) | Check `SYMBOL_TRADE_FREEZE_LEVEL`, retry |
| 10030 | `TRADE_RETCODE_INVALID_FILL` | Filling mode unsupported | `SetTypeFillingBySymbol()` to auto-pick |
| 10036 | `TRADE_RETCODE_POSITION_CLOSED` | Already closed | Race condition; log and continue |

## Stops level + freeze level — pre-flight check before sending SL/TP

```mql5
double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
double min_dist     = MathMax(stops_level, freeze_level) * point;

// Reject if SL/TP closer than min_dist to current price
if(MathAbs(price - sl) < min_dist || MathAbs(tp - price) < min_dist) {
   Print("SL/TP too close; broker will reject (TRADE_RETCODE_INVALID_STOPS)");
   return;
}
```

**Source:** [Spreads and order distance](https://www.mql5.com/en/book/automation/symbols/symbols_spreads_levels)

## Reliable lot-size calculation (1% risk)

```mql5
double CalcLotSize(double risk_pct, double sl_distance_price)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * risk_pct / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0 || tick_value <= 0) return 0;

   double ticks_in_sl   = sl_distance_price / tick_size;
   double money_per_lot = ticks_in_sl * tick_value;
   if(money_per_lot <= 0) return 0;

   double lots = risk_money / money_per_lot;

   // Normalize to broker constraints
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   if(lots < vmin) lots = vmin;
   if(lots > vmax) lots = vmax;
   return lots;
}
```

## Sources

- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade
- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradebuy
- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclose
- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclosepartial
- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionmodify
- https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes
- https://www.mql5.com/en/book/automation/symbols/symbols_spreads_levels
- https://www.mql5.com/en/forum/23663 — "return value of OrderSend should be checked"
