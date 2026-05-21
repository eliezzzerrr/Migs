# On-Chart Objects — OBJ_LABEL Panel Pattern

## The standard label

```mql5
string nm = "MyEA_Status_HeaderLine";

if(ObjectFind(0, nm) < 0)
   ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   //          ^chart_id ^name  ^type     ^subwindow ^time ^price (last two unused for OBJ_LABEL)

ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  10);
ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  20);
ObjectSetInteger(0, nm, OBJPROP_COLOR,      clrBlack);
ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   10);
ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
ObjectSetInteger(0, nm, OBJPROP_ZORDER,     1000);
ObjectSetString (0, nm, OBJPROP_FONT,       "Consolas");
ObjectSetString (0, nm, OBJPROP_TEXT,       "WR: 71% (5/7)  R: +10.0");

ChartRedraw(0);
```

## Which property uses which setter

| Setter | Properties |
|---|---|
| `ObjectSetInteger` | `OBJPROP_CORNER`, `OBJPROP_ANCHOR`, `OBJPROP_XDISTANCE`, `OBJPROP_YDISTANCE`, `OBJPROP_COLOR`, `OBJPROP_FONTSIZE`, `OBJPROP_SELECTABLE`, `OBJPROP_HIDDEN`, `OBJPROP_ZORDER`, `OBJPROP_BACK`, `OBJPROP_TIMEFRAMES` |
| `ObjectSetString` | `OBJPROP_TEXT`, `OBJPROP_FONT`, `OBJPROP_TOOLTIP` |
| `ObjectSetDouble` | Not applicable to `OBJ_LABEL` |

**Sources:** [ObjectCreate](https://www.mql5.com/en/docs/objects/objectcreate), [ObjectSetInteger](https://www.mql5.com/en/docs/objects/objectsetinteger), [Object Properties enum](https://www.mql5.com/en/docs/constants/objectconstants/enum_object_property), [OBJ_LABEL](https://www.mql5.com/en/docs/constants/objectconstants/enum_object/obj_label)

## `OBJPROP_CORNER` values

```
CORNER_LEFT_UPPER    (default; top-left)
CORNER_RIGHT_UPPER   (top-right)
CORNER_LEFT_LOWER    (bottom-left)
CORNER_RIGHT_LOWER   (bottom-right)
```

The X/Y distance is measured from this corner. With `CORNER_RIGHT_UPPER`, increasing `XDISTANCE` moves the label LEFT.

## `OBJPROP_ANCHOR` values

```
ANCHOR_LEFT_UPPER   (the label's top-left aligns to X,Y)
ANCHOR_RIGHT_UPPER  (the label's top-right aligns to X,Y)
ANCHOR_LEFT_LOWER, ANCHOR_RIGHT_LOWER
ANCHOR_LEFT, ANCHOR_RIGHT, ANCHOR_UPPER, ANCHOR_LOWER, ANCHOR_CENTER
```

For corner panels, match anchor to corner: `CORNER_LEFT_UPPER` + `ANCHOR_LEFT_UPPER` is the typical combination.

## Defensive properties

- `OBJPROP_SELECTABLE = false` → user can't click and drag the label away
- `OBJPROP_HIDDEN = true` → object doesn't appear in the chart's Object List (Ctrl+B)
- `OBJPROP_BACK = false` → label sits in front of price (don't set true for panels)
- `OBJPROP_ZORDER = 1000` → high z-order so it's on top of everything

## `ChartRedraw` is mandatory

`ObjectCreate` and `ObjectSet*` are **asynchronous** — they enqueue chart commands. The label doesn't appear until:
- The chart redraws on its own (next tick triggers redraw)
- OR you call `ChartRedraw(0)`

**Don't call `ChartRedraw` after every property change.** Batch all property changes for the panel, then redraw once at the end:

```mql5
void UpdatePanel()
{
   // ... many ObjectSetString/Integer calls ...

   ChartRedraw(0);   // ONE redraw at the very end
}
```

Limit `ChartRedraw` to roughly 1Hz to keep CPU usage low. Some panel implementations gate redraws on a timer:

```mql5
void OnTimer()
{
   UpdatePanel();   // EventSetTimer(1) → fires once per second
}
```

**Source:** [ChartRedraw docs](https://www.mql5.com/en/docs/chart_operations/chartredraw)

## Multi-line panel pattern

Use a name prefix to group all panel objects, so cleanup is one call:

```mql5
#define PANEL_PREFIX "MyEA_Panel_"

void EnsureLabel(string suffix, int x, int y, string text, color clr)
{
   string nm = PANEL_PREFIX + suffix;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1000);
      ObjectSetString(0, nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 10);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
}

void DrawPanel()
{
   int y = 20;
   EnsureLabel("hdr",  10, y, "=== MyEA Status ===", clrBlack);  y += 15;
   EnsureLabel("wr",   10, y, "WR: 71% (5/7)",       clrBlack);  y += 15;
   EnsureLabel("r",    10, y, "Total R: +10.0",      clrBlack);  y += 15;
   ChartRedraw(0);
}

void OnDeinit(const int reason)
{
   // Remove all our panel objects at once
   ObjectsDeleteAll(0, PANEL_PREFIX);
}
```

**Source:** [ObjectsDeleteAll](https://www.mql5.com/en/docs/objects/objectsdeleteall)

## Colors

For black-text panel on default chart background:
```mql5
input color InpStatusColor    = clrBlack;
input color InpStatusGood     = clrDarkGreen;   // readable on white
input color InpStatusBad      = clrFireBrick;
input color InpStatusMuted    = clrDimGray;
input color InpStatusWarn     = clrDarkOrange;
```

For white text on dark chart background:
```mql5
input color InpStatusColor    = clrWhite;
input color InpStatusGood     = clrLimeGreen;
input color InpStatusBad      = clrTomato;
input color InpStatusMuted    = clrSilver;
input color InpStatusWarn     = clrOrange;
```

Always make colors `input` so the user can flip them based on their chart theme.

## Other useful chart objects

| Type | Purpose |
|---|---|
| `OBJ_RECTANGLE_LABEL` | Filled rectangle anchored to chart corner (panel background) |
| `OBJ_TREND` | Trendline for marking levels |
| `OBJ_RECTANGLE` | Price-anchored rectangle (OB visualization) |
| `OBJ_VLINE` | Vertical line at a datetime |
| `OBJ_HLINE` | Horizontal line at a price |
| `OBJ_TEXT` | Price-anchored text label |
| `OBJ_ARROW_BUY`, `OBJ_ARROW_SELL` | Entry markers |

## Performance notes

- 200+ chart objects start to slow down rendering
- Always reuse existing objects (`ObjectFind` first) rather than create/delete cycles
- `ObjectsDeleteAll(0, PREFIX)` is cheap; delete + recreate full panel per tick is fine for ~20 objects
- For high-frequency updates, **only update the OBJPROP_TEXT** of existing objects — don't reset every property

## Sources

- https://www.mql5.com/en/docs/objects/objectcreate
- https://www.mql5.com/en/docs/objects/objectsetinteger
- https://www.mql5.com/en/docs/objects/objectsetstring
- https://www.mql5.com/en/docs/objects/objectsdeleteall
- https://www.mql5.com/en/docs/constants/objectconstants/enum_object_property
- https://www.mql5.com/en/docs/constants/objectconstants/enum_object/obj_label
- https://www.mql5.com/en/docs/chart_operations/chartredraw
