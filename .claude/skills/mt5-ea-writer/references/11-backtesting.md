# Backtesting Nuances

## Tick modeling modes

From [Testing Trading Strategies](https://www.mql5.com/en/docs/runtime/testing):

| Mode | OnTick frequency | Use case | Speed |
|---|---|---|---|
| **Every tick based on real ticks** | Every recorded historical tick | Highest fidelity; broker must provide tick history | Slowest |
| **Every tick** | Synthesized intra-bar ticks | Good fidelity; works without tick history | Slow |
| **1 Minute OHLC** | One tick per OHLC of each 1m bar | Mid fidelity; intra-1m moves modelled coarsely | Fast |
| **Open prices only** | One tick per bar of testing TF, at open | Bar-close strategies only; no intra-bar SL/TP testing | Fastest |

**Pick the mode based on the strategy:**

- **Open-prices-only**: valid only if your EA fires at bar close AND doesn't depend on intra-bar SL/TP hits. The Migs Hybrid (1R/2R/3R ladder) does use intra-bar SL/TP, so this mode is wrong.
- **1 Minute OHLC**: a reasonable compromise. Intra-bar order of hits is simulated by the 1m OHLC pattern, which is fine for 5m+ strategies.
- **Every tick / Every tick based on real ticks**: the only ways to faithfully simulate scalp strategies that depend on intra-second order of fills.

## What the tester CAN'T do

| Feature | Status in tester |
|---|---|
| `CalendarValueHistory` | Returns 0; no calendar in tester |
| Real spread | Recorded M1 spread or fixed value; no book depth |
| `WebRequest` | Disabled |
| DLL calls | Disabled |
| Live news / feeds | None |
| Multi-symbol live data | Only the chart symbol has tick-level fidelity |
| Real slippage / requotes | Simulated coarsely (or not at all) |
| Multiple terminal instances | One tester, one symbol focus |
| Weekend handling | Tester skips weekends; `TimeCurrent` jumps from Friday close to Sunday open |

## `MQLInfoInteger(MQL_TESTER)` gate

Use this to fork code paths cleanly:

```mql5
if(MQLInfoInteger(MQL_TESTER))
{
   // Tester-specific: use CSV news, fake bid-ask, etc.
}
else
{
   // Live: real API calls
}
```

Other useful `MQLInfoInteger` flags:
- `MQL_VISUAL_MODE` — true when running tester in visual mode
- `MQL_OPTIMIZATION` — true when running in optimizer
- `MQL_FORWARD` — true when running forward test
- `MQL_DEBUG` — true when compiled in debug mode

**Source:** [forum 227207](https://www.mql5.com/en/forum/227207)

## Visual mode

- ~10× slower than non-visual
- Use for spot-checking a few days
- Never use for optimization passes

Enable in Strategy Tester: Visualization checkbox.

## Forward testing

Strategy Tester → enable "Forward" mode → pick split ratio (1/2, 1/3, 1/4).

The optimizer runs on the **first part** of history, then automatically tests the best parameter set on the **held-out second part**. Required for credibility before live trading.

**For DEMO-phase EAs:** at minimum 6 months in-sample + 3 months forward. Longer is better.

## Optimization modes

- **Slow complete algorithm**: tests every combination. OK for ≤10,000 combos.
- **Fast genetic algorithm**: heuristic search. Use for >10,000 combos.
- **All symbols selected in Market Watch**: each symbol tested in turn; cumulative results.

## Optimization sanity checks

- **Don't over-optimize.** A strategy with 6 inputs each at 10 values has 1,000,000 combinations — guaranteed overfit.
- **Lock most inputs, optimize 1-3.** Pick the inputs with the most theoretical significance.
- **Out-of-sample test mandatory.** In-sample winner often loses out-of-sample.
- **Beware the highest profit factor combo.** Often a fluke. Look at consistency: low max drawdown, low max consecutive loss, similar in/out-of-sample.

## Realistic execution settings

In Strategy Tester options:

| Setting | Recommended |
|---|---|
| **Spread** | Current (uses recorded), or fix to your broker's typical |
| **Initial deposit** | Match your live account |
| **Leverage** | Match your live broker |
| **Use date** | Yes; pick at least 6 months for daily strategies, 1+ year for scalpers |
| **Optimization mode** | Disabled for single runs |

## Weekend handling

```mql5
MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
if(dt.day_of_week == 0 || dt.day_of_week == 6) return;   // Sun/Sat
```

In the tester, `TimeCurrent()` skips weekends entirely — there are no Saturday/Sunday ticks. But the gap matters for "minutes since last bar" math: on Sunday open (Asia session), the previous bar can be Friday close, ~48 hours ago.

## Reading the tester report

Key metrics:

| Metric | What's good |
|---|---|
| Profit Factor (PF) | > 1.5 = solid, > 2.0 = great, < 1.0 = unprofitable |
| Expected Payoff | Positive; aim for at least 0.2R per trade |
| Sharpe Ratio | > 1.0 acceptable, > 2.0 excellent |
| Recovery Factor | Net profit / max drawdown; > 3.0 is good |
| Max consecutive losses | Important psychologically; if streak > 10, you'll quit before recovery |
| Max consecutive profit (R) | Indicates upside variance |
| Total trades | Need ≥100 for statistical significance |

## Performance tip

Strategy Tester is single-threaded per chart by default. For optimization, MetaTrader uses agents — multiple parallel processes. Check Tools → Options → Agents. More agents = more parallelism = faster optimization sweeps.

## Common backtest-to-live discrepancies

1. **Spread**: tester used 10-pip spread; live broker shows 25-pip at news → live PF much worse
2. **Slippage**: tester slippage = 0; live slippage on retail = 1-5 points/order × hundreds of trades
3. **Commission**: tester ignores commission unless explicitly configured; live commission halves PF on scalpers
4. **Latency**: tester instant fills; live with 100ms broker latency misses fast moves
5. **Re-quotes**: tester never requotes; live broker requotes during news

Always run a **forward demo for 1+ week** before going live, even after a clean backtest. The forward demo uses live spread, latency, and commission — closest to real conditions.

## Sources

- https://www.mql5.com/en/docs/runtime/testing
- https://www.mql5.com/en/book/automation/tester/tester_time
- https://www.mql5.com/en/forum/227207 — MQL_TESTER detection
