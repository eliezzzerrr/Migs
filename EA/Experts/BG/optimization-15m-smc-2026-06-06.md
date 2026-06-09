# BG Golden 15m SMC — Optimization run (partial)

**Captured:** 2026-06-06, paused at **pass 56 of 150** (elapsed 04:41:55 / est. remaining 12:35:08).
**EA:** BG-Golden-Signal-15m-SMC.ex5 · **Symbol/TF:** XAUUSD M15
**Period:** 2026.01.01 → 2026.06.04 · **Forward:** 1/4 (fwd start 2026.04.26)
**Modelling:** Every tick based on real ticks · **Deposit:** 100000 USD 1:500
**Algorithm:** Slow complete · **Criterion / sort:** Profit Factor max
**Swept:** InpEntryATR, InpSLBufATR, InpMinSLClamp (bos_age=20, ob_age=40, swing=1, atr_per=14, min_sl_flt=4 fixed)

> NOTE: in-sample, **spread-blind** numbers (no cost modeled yet). Forward-quarter column not shown in this view. Treat as raw, not validated.

## Results so far (sorted by Profit Factor)

| Pass | Result | Profit | Trades | PF | Exp.payoff | DD % | EntryATR | SLBufATR | MinSLClamp |
|---|---|---|---|---|---|---|---|---|---|
| 109 | 1.29 | 48071.06 | 231 | 1.29 | 208.10 | 16.45 | 0.3 | 0.40 | 11 |
| 111 | 1.27 | 47617.68 | 262 | 1.27 | 181.75 | 14.41 | 0.5 | 0.40 | 11 |
| 112 | 1.24 | 44053.26 | 271 | 1.24 | 162.56 | 18.94 | 0.6 | 0.40 | 11 |
| 110 | 1.22 | 36584.91 | 248 | 1.22 | 147.52 | 16.09 | 0.4 | 0.40 | 11 |
| 113 | 1.22 | 41003.69 | 283 | 1.22 | 144.89 | 21.34 | 0.7 | 0.40 | 11 |
| 131 | 1.20 | 35257.02 | 272 | 1.20 | 129.62 | 25.25 | 0.7 | 0.20 | 13 |
| 114 | 1.19 | 30063.82 | 226 | 1.19 | 133.03 | 17.96 | 0.2 | 0.50 | 11 |
| 95  | 1.19 | 37371.72 | 285 | 1.19 | 131.13 | 17.53 | 0.2 | 0.10 | 11 |
| 108 | 1.18 | 27229.79 | 216 | 1.18 | 126.06 | 18.97 | 0.2 | 0.40 | 11 |
| 127 | 1.18 | 26492.17 | 206 | 1.18 | 128.60 | 21.07 | 0.3 | 0.20 | 13 |
| 129 | 1.18 | 29880.35 | 245 | 1.18 | 121.96 | 18.85 | 0.5 | 0.20 | 13 |
| 130 | 1.17 | 27814.53 | 261 | 1.17 | 106.57 | 23.00 | 0.6 | 0.20 | 13 |
| 128 | 1.16 | 25393.54 | 230 | 1.16 | 110.41 | 19.85 | 0.4 | 0.20 | 13 |
| 22  | 1.16 | 35670.89 | 313 | 1.16 | 113.96 | **10.80** | 0.6 | 0.40 | 5 |

## Quick read (not a recommendation — half the grid is still unrun)
- **A plateau is forming around SLBuf 0.40 + MinSL 11**, with EntryATR 0.3–0.6 all landing PF 1.22–1.29. That cluster (109/111/112/110) is more trustworthy than any single peak — exactly the "neighbors also work" robustness signal.
- **Pass 22 is the standout for *survivability*:** lowest drawdown (10.80%) with the most trades (313) and still PF 1.16 / 35.7k profit. Low DD + high trade count = the kind of row that tends to hold forward, even if it's not top profit.
- Highest DD rows (131 @ 25%, 130 @ 23%) are the ones to be wary of regardless of profit.

## When you're back
- **You won't lose the 56 done passes.** MT5 caches optimization results — re-run the *identical* config and it resumes from cache (only the remaining ~94 passes run).
- Let it finish → then model real spread → then check the forward-quarter column before trusting any row.

---

# Batch 1 — COMPLETE (150/150)

**Re-captured:** 2026-06-08 from `Desktop\BG 15m SMC optimization results.xml`.
**Server:** Exness-MT5Trial8 · **Modelling:** Every tick / real ticks → **spread IS modeled** (these are net-of-cost, not spread-blind).
**Export title period:** 2025.01.01 → 2026.06.04 (~17 months — CONFIRM vs the 5-month panel setting).
**Swept:** EntryATR {0.2..0.7}, SLBufATR {0.10..0.50}, MinSLClamp {5..13}.

## Top configs by profit (net of spread)

| Pass | Profit | PF | Recov | DD% | Trades | EntryATR | SLBuf | MinSL |
|---|---|---|---|---|---|---|---|---|
| 118 | 54,589 | 1.28 | 3.83 | **12.26** | 278 | 0.6 | **0.50** | 11 |
| 139 | 54,310 | 1.33 | 1.94 | 20.78 | 219 | 0.3 | 0.40 | 13 |
| 89  | 53,327 | 1.25 | 2.75 | 17.83 | 299 | 0.7 | **0.50** | 9 |
| 148 | 52,396 | 1.29 | 3.35 | 14.27 | 262 | 0.6 | **0.50** | 13 |
| 88  | 50,754 | 1.23 | 3.21 | 14.36 | 291 | 0.6 | **0.50** | 9 |
| 149 | 50,746 | 1.28 | 2.85 | 15.92 | 270 | 0.7 | **0.50** | 13 |
| 119 | 50,693 | 1.26 | 3.06 | 15.43 | 287 | 0.7 | **0.50** | 11 |
| 117 | 49,137 | 1.27 | 2.91 | **12.91** | 269 | 0.5 | **0.50** | 11 |
| 81  | 46,254 | 1.23 | 2.93 | **12.03** | 274 | 0.5 | 0.40 | 9 |

## KEY FINDING — parameters railed to the ceiling
- **SLBufATR = 0.50 dominates the entire top board, and 0.50 was the swept MAX.** → true optimum is beyond it; the range was truncated.
- MinSLClamp clusters at 11/13 (13 = max) and EntryATR at 0.6/0.7 (0.7 = max) — same upward-rail signal on all three.
- **Best all-rounder so far: Pass 118** — top profit AND lowest DD (12.3%) with 278 trades. Pass 117 / 81 are the low-DD runners-up.

# Batch 2 — extend the ranges upward (NEXT RUN)

Optimize (checked); keep bos_age=20, ob_age=40, swing=1, atr_per=14, min_sl_flt=4, HTF/session/risk all fixed at defaults.

| Variable | Start | Step | Stop | values |
|---|---|---|---|---|
| `InpEntryATR` | 0.4 | 0.1 | 1.2 | 9 |
| `InpSLBufATR` | 0.40 | 0.10 | 1.00 | 7 |
| `InpMinSLClamp` | 9 | 2 | 21 | 7 |

→ 441 passes (overlap region cached from batch 1). Criterion: **Recovery Factor max**. Same tester (XAUUSD M15, real ticks, Slow complete, forward 1/4).

**Reading rule:** if it rails to the new ceiling AGAIN (SLBuf→1.0, MinSL→21), STOP extending — that's the wide-stop mirage (rarely stopped out, rare huge losses), not a real optimum. Pick the plateau center with healthy DD + 250+ trades, not the edge.

**Confirm first:** (1) `InpServerGMTOffset` matches Exness-MT5Trial8 or sessions are on the wrong clock; (2) the actual tested period (17mo vs 5mo).

---

# Session decision (2026-06-08): ASIA + LONDON ONLY — no NY

**Rationale:** NY sessions cut — too volatile (news whips) + the 00:00 / 01:30–04:00 PHT windows force an early wake. Asia (08:00–12:00 = morning) + London (14:00–17:00 = afternoon) are humane hours, fully automated on the EA, and are the **validated +58R core** (the original config was Asia + London, NY off).

## Locked session inputs
| Input | Value |
|---|---|
| `InpUseSessions` | true |
| `InpUseAsia` | true (08:00–12:00 PHT, DoW Mon/Tue/Thu/Fri) |
| `InpUseLondon` | true (14:00–17:00 PHT, DoW Tue-Fri) |
| `InpUseNYAM` | **false** |
| `InpUseNYLunch` | **false** |
| `InpUseNYPM` | **false** |

If thin: cheapest volume add = turn Asia Wed on (`InpAsiaDowWed=true`) — but verify, don't assume.

## RE-OPTIMIZE on this session set (batch 2 ranges, fresh — no cache carryover)
| Variable | Start | Step | Stop |
|---|---|---|---|
| `InpEntryATR` | 0.4 | 0.1 | 1.2 |
| `InpSLBufATR` | 0.40 | 0.10 | 1.00 |
| `InpMinSLClamp` | 9 | 2 | 21 |

Fixed: bos 20 / ob 40 / swing 1 / atr 14 / min_sl_flt 4 / HTF defaults / risk off.
Tester: XAUUSD M15 · full ~17mo · real ticks · Slow complete · Recovery Factor max · forward 1/4.
Still confirm `InpServerGMTOffset` for Exness before trusting session gating.

---

# Batch 2 — PARTIAL snapshot (120 / 441)

**Captured:** 2026-06-08, run in progress (~09:16 of 34:04 est).
**Config:** Asia + London only (NY off). DoW **broadened to all weekdays** this run — Asia Mon–Fri (Wed turned on), London Mon–Fri (Mon turned on) — so trade counts are higher than the validated Mon/Tue/Thu/Fri + Tue–Fri footprint. Period 2025.01.01→2026.06.04 (~17mo), real ticks, **Recovery Factor max**, forward 1/4.
**Criterion fix:** "Custom max" would NOT launch (no OnTester in the EA — MT5 aborts the run). Switched to Recovery Factor max. The "Result" column now = Recovery Factor.

> Still IN-SAMPLE + PARTIAL. Forward-quarter column not read yet. Do not commit to a config off this.

## Top by profit (partial)

| Pass | Recov | Profit | Trades | PF | DD% | EntryATR | SLBuf | MinSL |
|---|---|---|---|---|---|---|---|---|
| 65 | 5.26 | 119,708 | 351 | 1.40 | 12.09 | 0.6 | **0.4** | 11 |
| 66 | 5.57 | 116,983 | 367 | 1.39 | 12.09 | 0.7 | **0.4** | 11 |
| 11 | 3.64 | 111,198 | 381 | 1.32 | 14.80 | 0.6 | 0.5 | 9 |
| 64 | 3.70 | 104,211 | 335 | 1.38 | 15.49 | 0.5 | **0.4** | 11 |
| 69 | 5.90 | 100,600 | 408 | 1.31 | 13.09 | 1.0 | **0.4** | 11 |
| 68 | **6.06** | 98,398 | 403 | 1.29 | **9.88** | 0.9 | **0.4** | 11 |
| 67 | 5.12 | 88,200 | 393 | 1.28 | 10.74 | 0.8 | **0.4** | 11 |
| 288 | 5.82 | 77,768 | 244 | **1.45** | **9.34** | 0.4 | 0.8 | 17 |
| 279 | 5.70 | 73,438 | 246 | 1.42 | 9.35 | 0.4 | 0.7 | 17 |
| 281 | 5.34 | 76,314 | 271 | 1.38 | 10.01 | 0.6 | 0.7 | 17 |

## KEY FINDINGS
- **SLBuf UN-RAILED.** Free to run to 1.0, the profit-top now prefers **SLBuf 0.4** (not the old 0.50 ceiling). Batch 1's "wider is better" was a capped artifact — **0.4 is the real optimum.** Clean plateau at **SLBuf 0.4 + MinSL 11**, EntryATR 0.6–1.0.
- **Two flavors:**
  - High-volume: SLBuf 0.4 / MinSL 11 / EntryATR 0.6–1.0 → ~350–410 trades, 100–120k, PF 1.3–1.4, DD 10–15%.
  - High-quality: SLBuf 0.7–0.8 / MinSL 17 → ~240–290 trades, PF up to 1.45, DD ~9–10%.
- **Standout for a monthly-income goal: Pass 68** — 403 trades (edge spread across more weeks = fewer dead months), lowest DD (9.88%), highest Recovery (6.06), on the 0.4/11 plateau. EntryATR 0.9 / SLBuf 0.4 / MinSL 11.

## CAUTIONS / TODO when complete
- Only 120/441 — unrun passes include most high-EntryATR / high-SLBuf / high-MinSL combos; picture can shift. Let it finish.
- IN-SAMPLE only — read the **forward-quarter** column before trusting anything.
- Confirm **fixed lots vs % risk**: if % risk, the 100k→220k headline is COMPOUNDED — judge on DD% + PF (sizing-independent), not the $.
- Next: export full XML → plateau center + forward hold + monthly trade distribution → then Batch 3 (management: BE/trailing).

---

# Batch 2 — PARTIAL update (192 / 441) — supersedes the 120/441 snapshot above

**Captured:** 2026-06-08 ~15:18 of 35:09 est. Still IN-SAMPLE + PARTIAL — do not commit.

## Top by profit (partial, 192/441)

| Pass | Recov | Profit | Trades | PF | DD% | EntryATR | SLBuf | MinSL |
|---|---|---|---|---|---|---|---|---|
| **133** | **7.89** | **145,305** | 373 | **1.44** | **9.05** | 1.1 | 0.4 | 13 |
| 78 | 6.45 | 141,252 | 404 | 1.38 | 10.83 | 1.0 | 0.5 | 11 |
| 74 | 5.66 | 140,046 | 354 | 1.43 | 12.05 | 0.6 | 0.5 | 11 |
| 75 | 5.81 | 132,086 | 369 | 1.41 | 12.02 | 0.7 | 0.5 | 11 |
| 77 | 5.88 | 120,258 | 401 | 1.33 | 10.83 | 0.9 | 0.5 | 11 |
| 132 | 5.90 | 119,715 | 375 | 1.37 | 13.95 | 1.0 | 0.4 | 13 |
| 65 | 5.26 | 119,708 | 351 | 1.40 | 12.09 | 0.6 | 0.4 | 11 |
| 70 | 5.29 | 119,602 | 414 | 1.34 | 12.44 | 1.1 | 0.4 | 11 |
| 66 | 5.57 | 116,983 | 367 | 1.39 | 12.09 | 0.7 | 0.4 | 11 |
| 131 | 6.29 | 108,230 | 371 | 1.34 | 12.05 | 0.9 | 0.4 | 13 |
| 71 | 3.62 | 99,690 | 417 | 1.27 | 15.02 | 1.2 | 0.4 | 11 |
| 68 | 6.06 | 98,398 | 403 | 1.29 | 9.88 | 0.9 | 0.4 | 11 |

## Updated findings
- **New leader: Pass 133** — best all-around: top profit (145k) AND near-lowest DD (9.05%) AND top Recovery (7.89), 373 trades, PF 1.44. Params **EntryATR 1.1 / SLBuf 0.4 / MinSL 13**.
- **SLBuf still un-railed and stable at 0.4–0.5** (max was 1.0). MinSL plateau 11–13 (max 21, no rail). Both healthy.
- **WATCH: EntryATR is drifting to the high end (1.0–1.2).** Pass 71 sits at 1.2 = the swept MAX. If the final board keeps favoring 1.1–1.2, EntryATR may be starting to rail → a Batch 2b extending EntryATR to ~1.6 could be warranted. Not conclusive at 192/441 — decide on the full board.
- Plateau is consolidating around **SLBuf 0.4 / MinSL 11–13 / EntryATR 0.9–1.1**. Pass 133 and Pass 68 both strong (133 = profit+DD king; 68 = highest trade count 403 at 9.88% DD).

## Still TODO when complete
- Read the **forward-quarter** column (real test).
- Confirm fixed-lots vs %-risk (compounding inflates the $).
- Decide if EntryATR needs a Batch 2b upward extension.
- Then Batch 3 (BE/trailing management) for monthly consistency.

---

# Batch 2 — PARTIAL update (280 / 441) — supersedes the 192/441 snapshot above

**Captured:** 2026-06-08 ~21:57 of 34:35 est. Still IN-SAMPLE + PARTIAL.

## Top by profit (partial, 280/441)

| Pass | Recov | Profit | Trades | PF | DD% | EntryATR | SLBuf | MinSL |
|---|---|---|---|---|---|---|---|---|
| **79** | 6.73 | **162,171** | 405 | 1.42 | 10.84 | 1.1 | 0.5 | 11 |
| 142 | 7.08 | 159,638 | 367 | **1.46** | 9.97 | 1.1 | 0.5 | 13 |
| 88 | 6.70 | 154,938 | 406 | 1.39 | 10.81 | 1.1 | 0.6 | 11 |
| **141** | **9.75** | 154,727 | 372 | 1.45 | 9.94 | 1.0 | 0.5 | 13 |
| 87 | 6.74 | 145,913 | 403 | 1.39 | 10.81 | 1.0 | 0.6 | 11 |
| 133 | 7.89 | 145,305 | 373 | 1.44 | **9.05** | 1.1 | 0.4 | 13 |
| 78 | 6.45 | 141,252 | 404 | 1.38 | 10.83 | 1.0 | 0.5 | 11 |
| 74 | 5.66 | 140,046 | 354 | 1.43 | 12.05 | 0.6 | 0.5 | 11 |
| 140 | 7.86 | 136,777 | 370 | 1.41 | 9.54 | 0.9 | 0.5 | 13 |
| 80 | 4.94 | 131,808 | 408 | 1.33 | 12.44 | **1.2** | 0.5 | 11 |
| 89 | 5.25 | 129,733 | 407 | 1.32 | 11.72 | **1.2** | 0.6 | 11 |
| 143 | 5.78 | 116,995 | 367 | 1.34 | 9.97 | **1.2** | 0.5 | 13 |

## Updated findings
- **Profit leader: Pass 79** (162k, PF 1.42, DD 10.84%). **Recovery-criterion leader (the actual sort): Pass 141** (Recovery 9.75, 154.7k, PF 1.45, DD 9.94%). **Highest PF: Pass 142** (1.46). All three: EntryATR 1.0–1.1 / SLBuf 0.5 / MinSL 13.
- **EntryATR RAIL CONFIRMED at 1.2.** Three top-12 configs (80, 89, 143) sit at EntryATR = 1.2 = the swept MAX, and the whole top board is 0.9–1.2. The optimum is at/above the ceiling → **Batch 2b required: extend EntryATR upward.**
- **SLBuf optimum nudged up to 0.5** (0.4–0.6 plateau, still mid-range — no rail). MinSL plateau 11–13, drifting to 13 at the very top (max 21 — no rail).
- Consolidated plateau: **EntryATR ≥1.0 (wants more) / SLBuf 0.5 / MinSL 11–13.**

## Batch 2b (queue after this finishes) — find where EntryATR actually peaks
| Variable | Start | Step | Stop |
|---|---|---|---|
| `InpEntryATR` | 1.0 | 0.1 | 1.8 |
| `InpSLBufATR` | 0.4 | 0.1 | 0.7 |
| `InpMinSLClamp` | 11 | 1 | 15 |

Caveat: high EntryATR = looser entry proximity (accept entries further from the OB). If it keeps climbing with no peak, that's not a real optimum — it means the proximity filter has gone non-binding (looser just = more trades in THIS sample). Watch for the plateau where it stops improving; don't chase it to infinity.

## Still TODO when complete
- Read the **forward-quarter** column (real test).
- Confirm fixed-lots vs %-risk (compounding inflates the $).
- Run Batch 2b to resolve the EntryATR rail.
- Then Batch 3 (BE/trailing) for monthly consistency.
