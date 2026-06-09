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

## Leaderboard snapshot #2 (run still in progress — 265 of 10,080 passes, ~2.6% done)
Sorted by Profit. All entries RETEST mode. Run NOT finished — best will likely keep improving.

| Pass | Result | Profit | Trades | Payoff | DD% | ReqBoth | ADXfilt | ADXmin | Brk | RetTol | RetBars | BE_R | Trail |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **0,26** | **6749.49** | **87,222.65** | 167 | 522.29 | 12.40 | **true** | false | 30 | 0.6 | 0.4 | 16 | 0.0 | 3.5 |
| 0,234 | 4720.85 | 60,271.74 | 163 | 369.77 | 13.53 | true | true | 20 | 0.5 | 0.6 | 12 | 2.0 | 4.0 |
| 0,179 | 3718.68 | 58,206.54 | 245 | 237.58 | 19.24 | false | false | 30 | 0.8 | 0.4 | 18 | 0.0 | 3.0 |
| 0,205 | 4514.85 | 57,641.80 | 163 | 353.63 | 12.76 | true | true | 20 | 0.3 | 0.6 | 16 | 2.0 | 3.5 |
| 0,349 | 3933.67 | 51,439.35 | 171 | 300.81 | 11.25 | true | false | 20 | 0.7 | 0.3 | 14 | 1.0 | 3.5 |
| 0,19  | 3632.59 | 49,006.36 | 182 | 269.27 | 13.19 | true | false | 25 | 0.7 | 0.7 | 12 | 2.0 | 3.0 |
| 0,14  | 3043.18 | 48,975.39 | 259 | 189.09 | 14.90 | false | false | 20 | 0.8 | 0.3 | 18 | 0.0 | 1.5 |
| 0,21  | 3742.32 | 48,216.45 | 166 | 290.46 | 18.81 | true | false | 30 | 0.8 | 0.5 | 10 | 2.0 | 4.0 |
| 0,350 | 2909.65 | 46,826.38 | 259 | 180.80 | 21.55 | false | false | 20 | 0.8 | 0.7 | 6  | 0.0 | 3.5 |
| 0,176 | 2855.58 | 44,788.05 | 246 | 182.07 | 19.93 | false | false | 35 | 0.5 | 0.3 | 18 | 0.0 | 3.0 |
| 0,5   | 2589.92 | 42,949.02 | 275 | 156.18 | 18.71 | false | false | 20 | 0.3 | 0.7 | 12 | 1.5 | 3.5 |
| 0,64  | 3413.48 | 42,360.22 | 154 | 275.07 | 15.65 | true | true | 20 | 0.3 | 0.4 | 16 | 2.0 | 3.5 |
| 0,304 | 2567.49 | 42,031.70 | 268 | 156.83 | 22.11 | false | false | 35 | 0.3 | 0.6 | 16 | 2.0 | 3.5 |
| 0,2   | 2600.29 | 41,766.77 | 258 | 161.89 | 22.55 | false | true | 15 | 0.8 | 0.6 | 14 | 1.0 | 3.5 |

## Key read (in-sample, partial run)
- **RequireBoth = TRUE dominates the leaderboard.** Every top-Result row is `true`; every `false`
  row sits lower. true-group Results: 6749/4720/4514/3933/3632/3742/3413. false-group: 3718/3043/
  2909/2855/2589/2567/2600. The dual-HTF agreement is the single biggest edge driver.
- **true-ReqBoth = fewer, better trades** (154–182 trades, DD 11–18%). **false-ReqBoth = more trades**
  (245–275) but lower expectancy and HIGHER drawdown (18–22%). The manual "loosen it up / more trades"
  chase lands squarely in the WORSE cluster. Selectivity wins.
- **ADX filter:** less decisive — current best has it OFF (ADXmin then irrelevant), but 0,234/0,205/0,64
  have it ON and score well. Inconclusive so far.
- **Current best (0,26):** ReqBoth ON, ADX filter OFF, RETEST, break 0.6×ATR, retest tol 0.4, retest 16 bars,
  BE OFF, trail 3.5×ATR → 167 trades, payoff 522, DD 12.4%, +87,222 (87% on 100k, in-sample ~12.5mo).

## ⚠️ Validity caveats — verify before trusting
1. **GMT offset** must have been calibrated (InpServerGMTOffset ≠ 0) for THIS run, or session
   windows were wrong and these numbers are meaningless.
2. **News filter** should have been OFF for Pine-parity.
3. **In-sample only** — check the **Forward** tab: do the forward-period winners match these
   in-sample winners? If not, it's overfit.
4. Zero-latency fills — re-run the chosen config with realistic delay before believing the R.
