# Workflow — Pattern Tagging

Patterns are how we learn. Every trade gets exactly one pattern tag. The taxonomy starts coarse and refines at weekly review.

## Starting taxonomy (Phase 1)

| ID | Name | Match rule |
|---|---|---|
| `01` | BUY baseline | Demand OB + bullish 15m BOS, any session, any FVG position |
| `02` | SELL baseline | Supply OB + bearish 15m BOS, any session, any FVG position |
| `novel` | Novel | Setup that doesn't cleanly map (rare in Phase 1) |

At weekly review, if a sub-cluster discovered from actual trade data shows a statistically distinct WR, split it out into a new pattern (`03`, `04`, …) and tag prospectively. Never invent sub-patterns from hypothesis — only from observed clusters in the journal.

## Tag selection (during signal-gen)

1. Determine direction → `01` or `02` baseline.
2. Check `patterns/*.md` for any refined patterns whose match rule fits exactly. If one matches, use that ID instead.
3. If the setup has features that no pattern covers cleanly, tag `novel` and note the features in the journal entry's `notes` field. Weekly review will decide if it deserves a new ID.

## When to split a pattern (weekly review only)

Split pattern `X` into a new sub-pattern when ALL of these hold (data-driven, not hypothesis-driven):

- A specific sub-cluster within `X`'s actual journal entries has **≥10 trades**, AND
- The sub-cluster's WR differs from parent `X` by **≥15 percentage points**, AND
- The sub-cluster has a clean, describable rule that emerges from the trades themselves (shared session, OB type, DOL distance band, etc.)

Otherwise leave it. Do not propose splits based on what *should* work in theory — only on what has worked or failed in the journal.

## When to retire / merge a pattern

- WR-gated patterns (<40% over ≥5 trades) stay in the library but are auto-skipped by `signal-generation` step 5. They're not deleted — they're learning material.
- Two patterns with overlapping rules and statistically indistinguishable WR (after ≥20 trades each) can be merged at weekly review.

## Pattern file schema

`patterns/NN-slug.md`:

```yaml
---
id: "NN"
name: "Short name"
parent: null | "NN"  # if split from another
created: YYYY-MM-DD
status: active | gated | retired
match_rule: "Plain-English rule the agent checks"
---

## Stats snapshot (mirrored from stats.json; weekly review updates)

- Trades: 0
- Wins: 0
- Losses: 0
- BE: 0
- WR: —
- Avg R: —
- Last 5 outcomes: []

## Notes

(Hypothesis, observations, when this pattern works/doesn't.)
```
