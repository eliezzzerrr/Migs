# Workflow — Outcome Update

User reports a closed trade. Agent updates the journal entry and recomputes stats.

## Triggers

User says something like:
- "Trade #0007 hit TP1, runner stopped at BE"
- "0014 SL hit"
- "Close trade 22 at BE"

Or supplies a screenshot showing the closed position.

## Procedure

1. **Find the journal file.** `Glob journal/**/NNNN-*.md` → load it.
2. **Update the YAML frontmatter:**
   - `outcome:` set to `TP1_HIT | TP2_HIT | SL_HIT | BE | NA`
   - `r_realized:` numeric (account for partials — default Migs partial: 50% closed at TP1 + 50% runner)
     - TP1 hit + runner BE → `+0.5 * tp1_rr + 0.5 * 0 = +0.5 * tp1_rr` (approximately)
     - TP1 hit + runner TP2 → `+0.5 * tp1_rr + 0.5 * tp2_rr`
     - Full SL → `-1.0`
   - `mfe_r:` if known, otherwise leave 0.0 and ask user
   - `mae_r:` same
   - `exit_reason:` short string
3. **Append closing notes** to the `## Notes` section.
4. **Run stats update:** `Bash python scripts/update_stats.py` (recomputes `patterns/stats.json` from all journal files — idempotent).
5. **Report back** to user:
   - "Updated #NNNN: outcome X, R realized Y"
   - "Pattern #NN now: WR Z% over N trades, total R T"
   - "Graduation progress: K/30 resolved trades"
   - If pattern just crossed WR-gate threshold (≥5 trades, WR <40%), flag it: "**Pattern #NN now gated** — future signals matching this will auto-NO-TRADE"

## R-realized cheat sheet

| Outcome | Partials (default) | R formula |
|---|---|---|
| TP1 hit, runner BE | 50% at TP1, 50% at BE | `0.5 × tp1_rr` |
| TP1 hit, runner TP2 | 50% at TP1, 50% at TP2 | `0.5 × tp1_rr + 0.5 × tp2_rr` |
| SL hit before TP1 | — | `-1.0` |
| BE (moved SL too early or no TP1 hit) | — | `0.0` |
| TP1 hit, runner SL after BE move | 50% at TP1, 50% BE | `0.5 × tp1_rr` (same as runner BE) |
| Manually closed mid-move | partial at price | compute from actual exit |

If user used non-default partial sizing, ask before computing.

## Edge case — NO-TRADE entries

NO-TRADE journal entries are immutable. Don't add outcomes to them. They exist for pattern study only.
