# Workflow — Weekly Review

Run every Sunday (or on request: "weekly review"). Output goes to `reviews/YYYY-Www.md`.

## Inputs

- All `journal/*.md` entries from the last 7 calendar days
- `patterns/stats.json` (current state)
- All `patterns/*.md` files
- Last week's review file (if exists)

## Procedure

### Step 1 — Recompute stats

`Bash python scripts/update_stats.py` to regenerate `patterns/stats.json` from journal. This is the source of truth for the week.

### Step 2 — Pattern audit

For each pattern with ≥1 new trade this week:

- WR this week vs. all-time
- Avg R this week
- Did it cross the 40%/5-trade WR gate threshold either way?
- Are there clusters of LOSSES with shared features? (session, OB freshness, FVG position, DOL distance, news context)
- Are there clusters of WINS with shared features?

### Step 3 — Novel-tag clustering (data-driven only)

Pull all journal entries tagged `pattern: novel`. Cluster them by features that actually appear in those entries — never by features you'd expect to find. Look at:

- What direction, session, OB-FVG arrangement, DOL distance, BOS strength actually recur across the novel entries?

If a cluster of ≥3 entries shares a coherent rule that emerges from the data itself, **propose a new pattern**:

- New ID (next sequential)
- Match rule (described in plain English from observed features)
- Initial stats from the clustered novel entries (retag those entries to the new ID)

If no cluster emerges, leave them as `novel` and check again next week.

### Step 4 — Pattern splits

For each existing pattern with ≥10 trades, look for sub-clusters where WR differs from parent by ≥15pp. If found, propose split (per `workflows/pattern-tagging.md`).

### Step 5 — Doctrine adjustments

If the user's own trade data suggests a rule change, propose it (don't enact unilaterally). Proposals must cite specific journal entries as evidence — never general trading intuition.

Format every proposal as: "Observed: [count] trades [feature X], outcome [Y]. Doctrine currently says [Z]. Suggest considering [change]."

User reviews and either accepts (edits doctrine files) or rejects.

### Step 6 — Write review file

`reviews/YYYY-Www.md`:

```markdown
---
week: YYYY-Www
range_pht: YYYY-MM-DD → YYYY-MM-DD
generated: YYYY-MM-DD HH:MM PHT
phase: DEMO
---

# Weekly Review — Week NN

## Headline numbers

- Trades resolved this week: N
- Wins / Losses / BE: W / L / B
- Win rate this week: X%
- Total R this week: ±Y.Y
- Cumulative trades: K / 30 (graduation target)
- Cumulative WR: X%
- Cumulative R: ±Z.Z

## Pattern performance (this week)

| Pattern | Trades | W/L/BE | WR | Avg R | Status |
|---|---|---|---|---|---|
| buy  | … | … | … | … | active |
| sell | … | … | … | … | active |

## Pattern changes proposed

(Populate from Step 3 + Step 4. Each proposal must cite specific journal entry IDs as evidence. Leave empty if no data-supported changes.)

## Doctrine change proposals (require user approval)

- [ ] …

## Behavioral observations

- 3 setups skipped due to news gate (saved ~X R based on adverse moves)
- … 

## Action items for next week

- [ ] …
```

### Step 7 — Apply approved changes

After user confirms, agent:
- Renames retagged journal entries' frontmatter pattern field
- Creates new `patterns/NN-slug.md` files for promoted patterns
- Updates `patterns/stats.json`
- Edits doctrine files only on explicit approval

## Cadence

- **Default:** Sunday evening (PHT)
- **Mid-week interim:** allowed if >10 trades in 3 days, agent should suggest one
