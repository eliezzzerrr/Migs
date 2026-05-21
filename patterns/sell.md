---
id: "sell"
name: "Hybrid SELL"
parent: null
created: 2026-05-21
status: active
match_rule: "Any SELL trade following the Migs Hybrid Strategy — see doctrine/migs-hybrid-strategy.md"
---

## What this is

The **SELL direction** of the Migs Hybrid Strategy. Same rules as the master doctrine — see `doctrine/migs-hybrid-strategy.md`.

This is not a separate setup type. It's the SELL-side bucket for journal/stats tracking.

## Entry contexts observed (across journaled SELL trades)

The Hybrid strategy doesn't prescribe a single entry trigger. SELL entries to date have come from:

- Supply OB retest (trades #0004, #0005)
- Internal breaker retest after 5m BOS (trade #7 / 0010 pending journal)

All share the same management: 3-TP ladder, thirds, 1R/2R/3R.

## Stats snapshot

Pulled from `patterns/stats.json`. See that file for the live tally.

## Notes

- A Hybrid SELL can win or lose on any of the above structural contexts — the structure is for entry identification, not for separate doctrine.
- WR gate: if this pattern reaches ≥5 closed trades AND WR <40%, gate triggers and no SELLs accepted until structurally reviewed.
