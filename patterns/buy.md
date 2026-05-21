---
id: "buy"
name: "Hybrid BUY"
parent: null
created: 2026-05-21
status: active
match_rule: "Any BUY trade following the Migs Hybrid Strategy — see doctrine/migs-hybrid-strategy.md"
---

## What this is

The **BUY direction** of the Migs Hybrid Strategy. Same rules as the master doctrine — see `doctrine/migs-hybrid-strategy.md`.

This is not a separate setup type. It's the BUY-side bucket for journal/stats tracking.

## Entry contexts observed (across journaled BUY trades)

The Hybrid strategy doesn't prescribe a single entry trigger. BUY entries to date have come from:

- Demand OB retest (trades #0006, #0007)
- HTF support sweep + reclaim + base + HL launch (trade #5 / pending journal)
- Range-high retest after failed breakout (trade #6 / pending journal — note: this one lost)

All share the same management: 3-TP ladder, thirds, 1R/2R/3R.

## Stats snapshot

Pulled from `patterns/stats.json`. See that file for the live tally.

## Notes

- A Hybrid BUY can win or lose on any of the above structural contexts — the structure is for entry identification, not for separate doctrine.
- WR gate: if this pattern reaches ≥5 closed trades AND WR <40%, gate triggers and no BUYs accepted until structurally reviewed.
