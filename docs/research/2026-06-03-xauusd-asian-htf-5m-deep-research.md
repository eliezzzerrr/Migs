# XAUUSD — HTF-bias + 5m Asian-session strategy: deep-research digest

**Date:** 2026-06-03
**Method:** `deep-research` workflow — 104 agents, 22 sources fetched, 102 claims extracted, top 25 put through 3-vote adversarial verification (≥2/3 refutes = killed). 17 confirmed, 8 killed. ~3.9M tokens.
**Purpose:** define the most *evidence-based* design for a new XAUUSD EA — HTF 1H/4H bias, 5m execution, ≤3 trades/day, Asian session to dodge US red-folder news. Timezone target: **PHT (UTC+8)**.

> **Bottom line up front.** The evidence supports a clear, logical *design* — but **not a proven, gold-specific edge.** Every *structural* fact (session behavior, false-breakout tendency, HTF-bias method, news drivers) is strongly multi-source corroborated. Every *performance number* (win rate, expectancy) is **borrowed from other instruments** (crude oil, equity indices, trend-following) — there is **no located backtest of this exact strategy on XAUUSD.** Treat the whole thing as a **hypothesis to forward-test in DEMO**, not a validated money-maker. The one peer-reviewed breakout study even shows the edge is *not time-robust* — it lives in high-volatility regimes.

---

## Evidence-ranked shortlist of approaches

| Rank | Approach | Evidence grade | Verdict |
|---|---|---|---|
| 1 | **HTF-bias + *confirmed* Asian-range breakout (break-and-retest) on 5m** | Structure: **High** · Performance: **Unproven (gold)** | Best-supported design. Build this. Forward-test before trusting numbers. |
| 2 | Raw Asian-range / ORB breakout (first-touch, buy-stop) | Mechanics: High · Fit for gold: **Weak** | Gold fakes breakouts at obvious levels → raw entries get wicked. Inferior to the retest variant for gold. |
| 3 | SMC / ICT (order blocks, liquidity, FVG, kill zones) | Behavior real, **execution unquantified** | The "stop-hunting is a myth" claim was *refuted* (liquidity behavior is real), but SMC execution is subjective with no measured edge. **Use as a lens** (liquidity sits above highs/below lows), not a mechanical system. |
| 4 | Mean-reversion inside the Asian range | Conditional | Legitimate **only** when HTF is ranging (e.g. ADX<25–30). A sub-mode, not the primary. |
| 5 | VWAP / EMA trend-following on 5m | Generic / thin | Not specifically supported for this session/timeframe. Skip for v1. |

---

## Confirmed findings (survived adversarial verification)

**1 — Gold sessions are behaviorally asymmetric (High, 3-0).** Asian/Tokyo (00:00 GMT open) is the quietest, range-based session; London *breaks the Asian range and sets direction*; the NY / London–NY overlap (12:00–16:00 GMT) is the volatility peak. Peer-reviewed corroboration: Iwatsubo, Watkins & Xu (RIETI/Kobe, SSRN 3021533) — gold-futures volatility is L-shaped/low in Tokyo, "relatively high at the open of the London day session." Quant: early-Asian range ~28–35 pips vs ~95–130 pips in the London–NY overlap; London ≈ 2–3× Asian volatility. → **Validates the 00:00–07:00 GMT range-build and the 07:00–09:00 GMT expansion-execution window.**

**2 — The textbook Asian-range breakout model (High).** Mark the Tokyo high/low; buy-stop a few pips above the high (sell-stop below the low); require a **5m candle *body* close outside the box** (breakout candle range > average of prior 5 candles, most of body outside) — not a wick. SL just outside the opposite side. Mechanically sound and codeable. **Caveat:** the source blog's "80% win rate / $34,880 trade" boasts have **zero backtest**; and an SL at the *opposite* range side makes the stop ≈ full range width → drags toward **1:1 R:R**, an expectancy trap.

**3 — Gold frequently produces FALSE breakouts at obvious levels (High, 2-0).** Resting liquidity above prior highs / below prior lows gets swept, then price reverses. Independent sources report "70–80% of breakouts fail on lower timeframes." → **Prefer a confirmed structure shift: break + pullback that HOLDS (higher-low for longs / lower-high for shorts), not a raw first-touch.** This *refines finding 2* — for gold specifically, use the **retest-confirmation** variant; accept fewer/later entries for higher reliability.

**4 — HTF bias = 4H/Daily (+1H) swing structure & BOS/CHoCH (High).** Mark major swing highs/lows for trend; use Break-of-Structure / CHoCH for the decisive shift; drop to 15M/5M for entries. **Trading 5m setups against the 1H/4H trend is a primary, well-documented failure mode.** Caveat: this is *definitional* (not effectiveness-proven), and SMC structure-marking is subjective ("two analysts mark different swings"). Exception: rule-based mean-reversion against a *weak/ranging* HTF (ADX<30) is a legitimate evidenced exception.

**5 — Optimize for EXPECTANCY, not win rate (High, 3-0).** Breakout systems typically win **20–40%** yet stay profitable via a **heavy-tailed R distribution** — losers capped near −1R, winners +3R/+5R/+10R; a few outliers produce ~80–90% of profit. Data points: Turtle system 39% WR; a True-Strength-Index strategy *on gold* 37% WR with avg winner ≈3× avg loser. Breakeven math: 33.3% WR at 2:1, 25% at 3:1. → **Plan for a low win rate and real losing streaks; the edge depends on letting winners run.** Caveat: the "−1R capped loss" idealization breaks under gaps/slippage — acute for XAUUSD near news.

**6 — No time-robust, gold-specific breakout edge exists in the literature (High, 3-0). [THE BIG ONE]** The only peer-reviewed ORB study found (Holmberg, Lönnbark & Lundström, *Finance Research Letters* 2013, on **US crude-oil futures**) states verbatim the result is **"not robust to time and to a large extent explained by the most recent (and most volatile) period."** ORB is "basically long volatility." The widely-quoted "40–60% ORB win rate" is **unsourced marketing** (no sample, period, or methodology). Two relevance gaps: (a) the asset is oil, not gold; (b) *all* located ORB win-rate data is equities/0DTE/oil — **none transfers to XAUUSD without instrument-specific testing.** → **This is the reason to forward-test in DEMO before EA codification.**

**7 — The events that most move gold are US CPI/PCE, NFP, GDP, FOMC (High, 3-0)** — they reprice rates/real-yields/USD and land in the NY session (NFP/CPI ~13:30 GMT, FOMC ~19:00 GMT), exactly what the Asian strategy sidesteps. FXStreet (35 NFP releases): gold +$7.2 avg on misses / −$5.2 on beats; inverse correlation −0.55 to −0.57. Caveat: in 2025–26 gold's long-term trend **decoupled** from yields/dollar (central-bank buying, ~70% annual gain), making any single event's *direction* noisier — but intraday event *volatility* persists.

**8 — Around news, spreads blow out and slippage spikes (High, 3-0).** XAUUSD spread widens from ~20–50 pips to **50–200 pips** during NFP/CPI/FOMC; even "fixed-spread" brokers widen gold. → Hard news blackout on new entries; use stop-orders aware fills can slip; size/stops must account for wide spread. (This also undermines the "−1R capped" assumption.)

---

## Killed claims — do NOT rely on these (refuted in verification)

- ❌ "A peer-reviewed study gives ORB positive academic support" (1-2) — the study actually found the edge **not robust**.
- ❌ "Stop-hunting / liquidity grabs are a myth with no empirical support" (0-3) — **refuted; the behavior is real enough** to design around.
- ❌ "SMC is just price action renamed, no distinct edge" (1-2).
- ❌ "Gold volatility is concentrated at 8 AM NY + COMEX open" (1-2) — too narrow.
- ❌ "Asian session is quiet *only* on China/AU news" (1-2).
- ❌ "**Scale out at fixed 2:1 then 3:1**" (LiteFinance) (0-3) — **refuted; do not hard-code this TP scheme.**
- ❌ "Asian-session ORB is NOT recommended for gold" (1-2) — refuted (i.e., Asian-session ORB for gold is *not* clearly disqualified).
- ❌ take-profit.org hourly gold-volatility table — unverifiable (rendered dynamically, absent from HTML).

---

## Caveats (read before building)

- **Instrument mismatch is the #1 risk.** No gold-specific backtest of this design was found. All WR/expectancy figures are transferred-by-analogy → hypotheses, not inputs.
- **Regime dependence.** The breakout edge concentrates in high-volatility periods. A volatility/ADX regime filter may be essential, not optional.
- **Entry tension, resolved.** Finding 2 (raw buy-stop) vs Finding 3 (break-and-retest): for gold, **retest-confirmation is better supported.** Build both as a toggle and A/B test.
- **Stop precision.** "−1R" fails under gaps/slippage on gold; model max-drawdown with losses that can exceed the planned stop.
- **2025–26 macro decoupling** makes news-reaction direction noisier (volatility still real).
- **European news lands in the execution window.** US news is avoided by design, but UK/EU high-impact prints (UK CPI ~06:00 GMT / 14:00 PHT; German/EU data 07:00–09:00 GMT / 15:00–17:00 PHT; ECB 12:45 GMT) **overlap the 15:00–17:00 PHT execution window** — so a news filter must cover **EUR/GBP**, not just USD.

---

## Open questions → DEMO test plan

1. **Actual WR / expectancy / max consecutive losses** of *this* design on XAUUSD across volatility regimes. (No data exists — fill this first.)
2. **Raw breakout vs break-and-retest** head-to-head on gold 5m, including the cost of missed entries.
3. **Optimal target/management** given the ~1:1 range-stop problem: fixed +2R/+3R vs trail-the-runner vs partial+trail — which maximizes expectancy *net of XAUUSD spread/slippage*? (The one scale-out rec was refuted, so this is genuinely open.)
4. Does a **volatility/ADX regime filter** materially improve expectancy (consistent with the regime-dependence in finding 6)?

---

## Recommended design (v1, to forward-test) — times in PHT (UTC+8)

| Component | Rule |
|---|---|
| **HTF bias** | On 1H + 4H: LONG only if structure = higher-highs/higher-lows with last move a bullish BOS; SHORT mirror. If HTF ranging (ADX<25 on 4H or no clean BOS) → **no trade**. |
| **Asian-range box** | High/low of the Tokyo session **08:00–15:00 PHT** (00:00–07:00 GMT). *(Box window is a test parameter.)* |
| **Execution window** | **15:00–17:00 PHT** (07:00–09:00 GMT, London-open expansion). No new entries outside it. |
| **Entry (gold variant)** | 5m **body** close beyond the box on the HTF-bias side **→ wait for pullback that HOLDS** (higher-low long / lower-high short) → enter on confirmation close. *(Toggle: raw breakout vs retest, for A/B testing.)* |
| **Stop** | Just beyond the **retest swing** (not the far side of the range) + 0.2–0.5× ATR(14, 5m) buffer; enforce a min-stop floor to survive spread. |
| **Target / mgmt** | Partial at +1R to +1.5R, then **trail the runner** behind 5m structure to capture heavy-tail winners. **No blind 1:1; no fixed 2:1/3:1 scale-out.** |
| **≤3 trades/day** | Hard counter, resets daily. Daily max-loss stop (e.g. −2R to −3R) → done for the day. |
| **News filter** | Block new entries ±15–30 min around **USD *and* EUR/GBP** high-impact events. (Mostly redundant for USD given the window; needed for EU morning data.) |
| **Risk / sizing** | 1% per trade via tick-value sizing; **cap at min lot (0.01) and warn** when 0.01 already exceeds 1% (their ~$369 account can't honor 1% on gold with realistic stops). |

**Honest expectancy frame:** expect ~30–40% win rate, occasional 4–6 trade losing streaks, profit carried by a minority of large winners. If you can't tolerate that psychologically, this is the wrong style.
