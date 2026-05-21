# Workflow — News Check (DISABLED)

**Status: DISABLED as of 2026-05-21** per user directive.

The agent no longer runs a deterministic ForexFactory news gate. Trader handles news awareness manually outside the system.

## What changed

- `CLAUDE.md` rule #2 — disabled
- `.claude/agents/migs-trader.md` hard rule #3 — disabled, Step B of signal-gen replaced with no-op
- `doctrine/checklists.md` killflag bullet — struck through
- `doctrine/grading-rubric.md` criterion #10 — repurposed to DXY-only confluence
- `workflows/signal-generation.md` Step 1 — replaced with disabled notice
- Journal `news_window` field — set to `disabled` for all new entries

## How to re-enable

1. Restore each of the files above to its pre-2026-05-21 state (see git history if tracked, or rewrite from the original ForexFactory procedure below).
2. Restore the original procedure documented in commit prior to 2026-05-21.
3. Update `CLAUDE.md` rule #2 wording back to "News gate is deterministic — high-impact USD/Gold event within T-30min to T+15min ⇒ killflag, regardless of grade."

## Why this was disabled

ForexFactory WebFetch was returning HTTP 403, causing all signals to fail the "WebFetch error ⇒ NO TRADE" defensive rule. Rather than block every trade on infrastructure flakiness, the user opted to remove the gate and self-manage news.

The gate can be re-enabled trivially when a more reliable news source is wired up.
