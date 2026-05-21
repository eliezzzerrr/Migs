# Grading Rubric — 12-point Migs Quality Grade

**Purpose:** assign a quality letter grade (A+ → F) to every signal *that has already passed the §9 binary acceptance* in `doctrine/migs-hybrid-strategy.md`. The grade is a **journaling and analysis tag**. It does **not** veto a trade.

> Trade/no-trade is decided by §9 acceptance (mirrored in `doctrine/checklists.md`). If §9 fails ⇒ NO TRADE. If §9 passes ⇒ TRADE, and this rubric assigns the conviction-quality letter.

The grade lives in `grade: { letter: X, score: N }` in journal frontmatter and feeds weekly reviews + future conviction-sizing experiments.

## Scoring table

Score each of the 6 criteria 0/1/2. Sum to 12 max.

| # | Criterion | 0 pts | 1 pt | 2 pts |
|---|---|---|---|---|
| 1 | **1H bias alignment** | Counter to `htf_bias_1h` (would have failed §9 anyway) | Ranging / unclear 1H | Clean 1H trend in trade direction |
| 2 | **Structural anchor** | No clean OB or level at entry | Minor level (internal breaker, range edge) | Major OB or swept HTF support/resistance |
| 3 | **Entry trigger** | Anticipatory fade, no confirmation | Reaction visible (wick rejection) but no BOS through the level | Confirmation candle **and** 5m BOS through the level |
| 4 | **DOL runway** | Opposing DOL inside 3R blocks TP3 | TP3 reachable, but a level sits between TP2 and TP3 | Clean path to TP3, no opposing DOL inside 3R |
| 5 | **SL anchor** | Arbitrary distance from price | Beyond level edge, no wick anchor | Beyond level **and** anchored by sweep wick or pivot |
| 6 | **Invalidation discipline** | 0–1 reasons, narrative only | 2–3 reasons, mixed quality | 3 reasons, ≥1 quantitative and price-testable |

## Score → Grade

| Score | Grade |
|---|---|
| 12 | A+ |
| 11 | A |
| 10 | A- |
| 9 | B+ |
| 7–8 | B |
| 5–6 | C |
| 3–4 | D |
| 0–2 | F |

**No hard floor.** A trade that passes §9 is taken. The letter records quality, not permission. Future doctrine may layer a "grade floor" rule once enough data exists — until then, journal everything.

## Modifiers (applied to letter after scoring)

| Modifier | Effect |
|---|---|
| 3rd+ consecutive Migs loss (from `patterns/stats.json`) | –1 letter on the journal grade (records that the read was made under streak pressure) |

Counter-1H-bias does not appear as a modifier here because §9 already rejects counter-bias trades — no signal that reaches grading can be counter-bias.

## Letter-grade ladder (for modifier math)

```
F < D < C < B- < B < B+ < A- < A < A+
```

## Calibration reference

Back-graded against the 7 closed trades in `journal/` on 2026-05-22 (5W / 2L, +10R, 71% WR through trade #0010):

| ID | Outcome | Score | Grade | Discriminator |
|---|---|---|---|---|
| 0004 | TP2_HIT +2R | 9 | B+ | back-fill, OB/BOS/sweep not captured (C2/C3/C5 = 1) |
| 0005 | SL_HIT –1R | 9 | B+ | back-fill |
| 0006 | TP2_HIT +2R | 9 | B+ | back-fill |
| 0007 | TP2_HIT +2R | 9 | B+ | back-fill |
| 0008 | TP3_HIT +3R | 10 | A- | swept HTF support + reclaim, sweep-anchored SL (C2 = 2, C5 = 2) |
| 0009 | SL_HIT –1R | 7 | B | criterion 3 = 0 ("aggressive fade, no confirmation" per user's own note) |
| 0010 | TP3_HIT +3R | 10 | A- | decisive BOS + sweep-anchored SL (C3 = 2, C5 = 2); C2 = 1 because internal breaker is "minor" by definition |

Notes:
- The grade is informational. #0005 graded B+ and still lost — that's expected. Letter ≠ outcome forecast; the rubric measures *setup quality*, not future R.
- #0009 grades B (7) — sits in the "watchlist" tier. Under the coexist model the trade was still permitted because §9 passed; the rubric correctly downgraded it via criterion 3 (entry trigger). A future doctrine layer may eventually skip B-tier signals once N is larger.
- The four back-fills cluster at B+ because criterion 2/3/5 inputs (OB bounds, BOS strength, sweep-wick anchor) were not captured at entry. Going forward, full Pass-1 extraction should lift typical winners to A- / A.
- No A+ in the dataset yet — A+ requires 12/12, i.e. major OB **and** decisive BOS confirmation **and** sweep-anchored SL **and** ≥1 quantitative invalidation. Worth tracking which future setups earn it.

## Rewrite history

- **2026-05-22:** rewrite from 18-point rubric. Old rubric referenced FVG, session caps, SL bands, DXY confluence, TP1 ≥3R floor — all removed by the unified-strategy consolidation. New criteria reference only fields the journal schema actually captures (`htf_bias_1h`, `ob`, `bos`, `sweep_wick`, `dol_tp1/tp2/tp3`, `risk_pips`, `invalidation_conditions`). Scoped as a quality tag layered on top of §9 binary acceptance; does not gate trades.
