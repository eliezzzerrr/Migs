# Position Management — Iteration, Netting vs Hedging, OnTradeTransaction

## The backward iteration pattern

**Always backward. Always filter by magic + symbol.**

```mql5
for(int i = PositionsTotal() - 1; i >= 0; i--)
{
   ulong ticket = PositionGetTicket(i);          // implicitly selects
   if(ticket == 0) continue;
   if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
   if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;

   // Safe to read POSITION_TYPE, POSITION_VOLUME, POSITION_SL, POSITION_TP,
   // POSITION_PRICE_OPEN, POSITION_PROFIT, etc.
   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double vol = PositionGetDouble(POSITION_VOLUME);
   // ...
}
```

**Why backward:** closing a position shifts every index after it. A forward loop will skip positions or read garbage on rebound.

**Why magic+symbol filter:** without it, your EA can close/modify positions belonging to other EAs or to the user. This is the most common cause of "my EA closed my manual trade" support tickets.

**Why `PositionGetTicket(i)` doesn't need a separate Select:** the function **internally selects** the position. Subsequent `PositionGet*` calls in the same iteration read from that selection. Source: [PositionGetTicket](https://www.mql5.com/en/docs/trading/positiongetticket).

## Reading position properties

```mql5
// Integer-valued
long pos_magic     = PositionGetInteger(POSITION_MAGIC);
long pos_id        = PositionGetInteger(POSITION_IDENTIFIER);  // STABLE across partial closes
ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
datetime pos_time  = (datetime)PositionGetInteger(POSITION_TIME);

// Double-valued
double pos_open    = PositionGetDouble(POSITION_PRICE_OPEN);
double pos_sl      = PositionGetDouble(POSITION_SL);
double pos_tp      = PositionGetDouble(POSITION_TP);
double pos_volume  = PositionGetDouble(POSITION_VOLUME);
double pos_profit  = PositionGetDouble(POSITION_PROFIT);

// String-valued
string pos_symbol  = PositionGetString(POSITION_SYMBOL);
string pos_comment = PositionGetString(POSITION_COMMENT);
```

**Use `POSITION_IDENTIFIER`, not `POSITION_TICKET`, for cross-restart tracking.** The ticket can change on partial close in hedging mode; the identifier is the original position ID and is stable.

## Netting vs Hedging — the account-model split

Check once in `OnInit`:

```mql5
ENUM_ACCOUNT_MARGIN_MODE mm =
   (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);

bool is_hedging = (mm == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
bool is_netting = (mm == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
               || (mm == ACCOUNT_MARGIN_MODE_EXCHANGE);
```

### Differences

| Behavior | Netting | Hedging |
|---|---|---|
| Positions per symbol | One. New trade in opposite direction reduces / flips it. | Many. Each trade is its own position with its own ticket. |
| `PositionClosePartial()` | **Not allowed** — broker rejects | Allowed |
| Multi-TP strategies (open N positions with different TPs) | Must simulate via partial reduce | Native: open N positions, each with its own SL/TP |
| `PositionClose(symbol)` | Closes the (single) symbol position | Closes only the **first** matching position — use ticket-based close instead |

### Enforcing requirements at init

```mql5
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("FATAL: this EA requires a hedging account "
            "(uses PositionClosePartial / multi-position TPs).");
      return INIT_PARAMETERS_INCORRECT;   // user-fixable
   }
   // ... rest of init
   return INIT_SUCCEEDED;
}
```

**Source:** [Account type: netting or hedging](https://www.mql5.com/en/book/automation/account/account_netting_hedge)

## OnTradeTransaction — detecting closures cleanly

Use `OnTradeTransaction` to react to position closures (the most reliable signal that a trade has fully exited):

```mql5
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest      &request,
                        const MqlTradeResult       &result)
{
   // We only care about deal additions (other transaction types are noise here)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   // Select the deal in history
   if(!HistoryDealSelect(trans.deal)) return;

   // Filter by our symbol + magic
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)        return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;

   // Only act on exit deals
   ENUM_DEAL_ENTRY entry =
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
   {
      double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                     + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      ulong  pos_id  = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      double price   = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      datetime when  = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

      // Update your journal / state here
      OnPositionClosed(pos_id, profit, price, when);
   }
}
```

**`DEAL_ENTRY_*` values:**
- `DEAL_ENTRY_IN` — entry deal that opened a position
- `DEAL_ENTRY_OUT` — exit deal that fully closed a position
- `DEAL_ENTRY_INOUT` — netting reversal (one deal both closes old position and opens opposite)
- `DEAL_ENTRY_OUT_BY` — close by opposite (hedging accounts only, when CloseBy was used)

**Sources:** [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction), [MqlTradeTransaction](https://www.mql5.com/en/docs/constants/structures/mqltradetransaction)

## Tracking trade groups across restarts

If you have multi-position trade groups (e.g. 3 positions with TP1/TP2/TP3), persist the state:

```mql5
// MQL5\Files\MyEA\open_groups.csv schema:
//   group_id,position_id_tp1,position_id_tp2,position_id_tp3,entry_time,sl,tp1,tp2,tp3
```

On `OnInit`, read the CSV and cross-check each `position_id` against `PositionsTotal()`:
- If position is still open → restore group state
- If position is missing → group has closed; remove from CSV

Keying on `POSITION_IDENTIFIER` (not ticket) is mandatory for this to survive partial closes.

## `CountMigsPositions()` — counting open positions belonging to this EA

```mql5
int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      n++;
   }
   return n;
}
```

## Sources

- https://www.mql5.com/en/docs/trading/positiongetticket
- https://www.mql5.com/en/docs/constants/structures/mqltradetransaction
- https://www.mql5.com/en/docs/event_handlers/ontradetransaction
- https://www.mql5.com/en/book/automation/account/account_netting_hedge
- https://www.mql5.com/en/forum/482901 — Position iteration patterns
