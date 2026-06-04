# BG Dawn Raider 5m — Optimization Run (saved 2026-06-04)

Saved mid-session as crash insurance. These are **in-sample optimization** results;
forward (out-of-sample) validation still pending.

## Run config
- **Expert:** BG-Dawn-Raider-5m.ex5 (v0.2.0, Pine-synced defaults)
- **Symbol/TF:** XAUUSD, M5
- **Period:** 2025.01.01 → 2026.06.04  (Forward 1/4 → forward starts 2026.01.25)
- **Modelling:** Every tick based on real ticks
- **Delays:** Zero latency, ideal execution  (⚠️ optimistic — no slippage/spread cost)
- **Deposit:** 100,000 USD @ 1:500
- **Optimization:** Fast genetic, **Custom max** (OnTester = expected_payoff × √trades, rejects <30 trades)

## Top results (sorted by Result = custom criterion)

| Pass | Result | Profit | Trades | Exp.payoff | DD% | ReqBoth | ADXfilter | ADXmin | Entry | BrkATR | RetestTol | RetestBars | MoveBE_R | TrailATR |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0,234 | **4720.85** | 60,271.74 | 163 | 369.77 | 13.53 | **true** | **true** | 20 | RETEST | 0.5 | 0.6 | 12 | 2.0 | 4.0 |
| 0,179 | 3718.68 | 58,206.54 | 245 | 237.58 | 19.24 | false | false | 30 | RETEST | 0.8 | 0.4 | 18 | 0.0 | 3.0 |
| 0,2.. | (3rd row cut off in screenshot — re-capture if needed) |

## Key read (in-sample)
- **The TIGHTER config won.** Best custom score has **RequireBoth = true AND ADX filter = ON** —
  the regime filters earned their keep. Higher expected payoff (369.77 vs 237.58) and lower
  drawdown (13.53% vs 19.24%) than the loosened variant.
- The loosened variant (filters OFF) gave MORE trades (245 vs 163) but worse per-trade expectancy
  and higher DD → this contradicts the manual "loosen it up" chase. The optimizer prefers selectivity.
- Winner: RETEST mode, break 0.5×ATR, retest tol 0.6, retest 12 bars, BE at 2R, trail 4.0×ATR.

## ⚠️ Validity caveats — verify before trusting
1. **GMT offset** must have been calibrated (InpServerGMTOffset ≠ 0) for THIS run, or session
   windows were wrong and these numbers are meaningless.
2. **News filter** should have been OFF for Pine-parity.
3. **In-sample only** — check the **Forward** tab: do the forward-period winners match these
   in-sample winners? If not, it's overfit.
4. Zero-latency fills — re-run the chosen config with realistic delay before believing the R.
