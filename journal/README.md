# Journal

One markdown file per signal. Schema is in `doctrine/migs-hybrid-strategy.md` §10.

## Layout

```
journal/
  YYYY/
    MM/
      NNNN-YYYY-MM-DD-buy.md
      NNNN-YYYY-MM-DD-sell.md
      NNNN-YYYY-MM-DD-no-trade.md
```

## Filename rules

- `NNNN` is zero-padded sequential ID across all journal entries (TRADE + NO-TRADE share the same counter).
- Date in filename is **entry date in PHT** (UTC+8).
- Suffix is one of `buy`, `sell`, `no-trade`.

## Frontmatter is canonical

Body notes are optional commentary. The YAML frontmatter is what `scripts/update_stats.py` reads. Keep field names exactly as in the doctrine schema — the script is strict.

## Open vs resolved

- `outcome: OPEN` — counted in pattern's `open` field, NOT in WR
- `outcome: TP1_HIT | TP2_HIT | BE | SL_HIT` — counted in WR
- `outcome: NA` — used for NO-TRADE entries; never affects stats

## Don't backdate or rewrite

Treat entries as append-only. If a setup needs reinterpretation after the fact, add a `## Notes` section update; never silently rewrite frontmatter (except for outcome resolution via `workflows/outcome-update.md`).
