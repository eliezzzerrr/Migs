# Date / Time — Functions and Tester Behavior

## The four time functions

| Function | Live | Strategy Tester |
|---|---|---|
| `TimeCurrent()` | Last tick time of any chart symbol | Simulated server time |
| `TimeTradeServer()` | Calculated current server time | Same as `TimeCurrent()` |
| `TimeLocal()` | OS local time | Same as `TimeCurrent()` |
| `TimeGMT()` | OS local time minus DST-adjusted GMT offset | Same as `TimeCurrent()` |

**In the Strategy Tester all four are equal.** Deliberate, because the tester has no server connection. This matters for any session logic — use `TimeGMT()` everywhere consistently rather than mixing.

**Sources:** [TimeGMT](https://www.mql5.com/en/docs/dateandtime/timegmt), [TimeTradeServer](https://www.mql5.com/en/docs/dateandtime/timetradeserver), [Time management in the tester](https://www.mql5.com/en/book/automation/tester/tester_time)

## When to use which

| Use case | Function |
|---|---|
| Logging "now" in journal | `TimeGMT()` (UTC, consistent across tester+live) |
| Session detection (London/NY/Asia) | `TimeGMT()` — define session windows in UTC |
| "Last bar's time" for new-bar detection | `iTime(_Symbol, _Period, 0)` |
| Bar close time | `iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period)` |
| User-facing "trading hours" | `TimeLocal()` (their wall clock) |
| Server-side trade time | `TimeTradeServer()` (broker's clock) |

## `MqlDateTime` struct

**Field names — confirmed at [MqlDateTime docs](https://www.mql5.com/en/docs/constants/structures/mqldatetime):**

```mql5
struct MqlDateTime
{
   int year;          // 4-digit year
   int mon;           // 1-12   ← NOT "month"
   int day;           // 1-31
   int hour;          // 0-23
   int min;           // 0-59   ← NOT "minute"
   int sec;           // 0-59
   int day_of_week;   // 0=Sunday .. 6=Saturday
   int day_of_year;   // 0-365 (Jan 1 = 0)
};
```

**The `.month` / `.minute` typo is a guaranteed "undeclared identifier" compile error.** Hardcode this into muscle memory: `.mon` and `.min`, not the long form.

## TimeToStruct / StructToTime

```mql5
datetime now = TimeGMT();
MqlDateTime dt;
TimeToStruct(now, dt);
PrintFormat("Today is %04d-%02d-%02d %02d:%02d:%02d (UTC), day_of_week=%d",
            dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, dt.day_of_week);

// Round-trip back to datetime:
dt.hour = 0; dt.min = 0; dt.sec = 0;
datetime today_start = StructToTime(dt);
```

`StructToTime` reads the same fields and returns a `datetime` (epoch seconds since 1970-01-01).

**Source:** [TimeToStruct](https://www.mql5.com/en/docs/dateandtime/timetostruct), [StructToTime](https://www.mql5.com/en/docs/dateandtime/structtotime)

## TimeToString and StringToTime

```mql5
datetime t = TimeGMT();

// Default format: "yyyy.mm.dd hh:mi"
string s1 = TimeToString(t);                                   // "2026.05.22 14:30"
string s2 = TimeToString(t, TIME_DATE | TIME_MINUTES | TIME_SECONDS);  // "2026.05.22 14:30:45"
string s3 = TimeToString(t, TIME_DATE);                        // "2026.05.22"
string s4 = TimeToString(t, TIME_MINUTES);                     // "14:30"

// Parse a string back. ONLY accepts "yyyy.mm.dd hh:mi" form.
datetime t2 = StringToTime("2026.05.22 14:30");
```

**Note:** `StringToTime` only accepts the `yyyy.mm.dd hh:mi` format with `.` separators. ISO-style `2026-05-22T14:30:00Z` will NOT parse. Convert manually if you need ISO.

## "Is new bar" pattern

```mql5
bool IsNewBar()
{
   static datetime last_bar = 0;
   datetime cur_bar = iTime(_Symbol, _Period, 0);
   if(cur_bar == last_bar) return false;
   last_bar = cur_bar;
   return true;
}

// In OnTick:
void OnTick()
{
   if(!IsNewBar()) return;
   // ... bar-close logic ...
}
```

Returns `true` exactly once per new bar. First tick after EA start always returns true.

## Session detection (UTC-based)

```mql5
enum ENUM_SESSION { SESS_OFF, SESS_LONDON, SESS_NY, SESS_ASIA };

ENUM_SESSION DetectSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int mins = dt.hour * 60 + dt.min;

   // All windows in UTC:
   if(mins >= 7*60      && mins < 12*60)      return SESS_LONDON;   // 07-12 UTC
   if(mins >= 12*60 + 30 && mins < 17*60)     return SESS_NY;       // 12:30-17 UTC
   if(mins >= 22*60 || mins < 7*60)           return SESS_ASIA;     // 22-07 UTC
   return SESS_OFF;
}
```

## Day-of-week skip

```mql5
MqlDateTime dt;
TimeToStruct(TimeGMT(), dt);
if(dt.day_of_week == 0 || dt.day_of_week == 6) return;   // Sun/Sat
if(InpSkipFriday && dt.day_of_week == 5) return;
```

`day_of_week`: 0=Sunday, 1=Monday, ..., 6=Saturday.

## DST handling

`TimeGMT()` uses the OS DST setting (Windows `TIME_ZONE_INFORMATION`). In the Strategy Tester, DST is ignored entirely — `TimeGMT()` returns the same value as `TimeCurrent()`.

**For session windows, prefer pure UTC offsets** and define windows in UTC. Avoid hardcoding broker-time offsets (different brokers use different server times — GMT+0, GMT+2, GMT+3, EET, etc.).

If you must use broker server time (for end-of-day, holiday detection, etc.), use `TimeTradeServer()` and document the assumption.

## Common pitfalls

- **`StringToTime("2026-05-22 ...")` returns 0** — must use `2026.05.22` (dots not dashes)
- **`PeriodSeconds(_Period)` for current TF**, `PeriodSeconds(PERIOD_M5)` for specific TF — returns seconds in one bar
- **Daylight saving transitions** can shift session windows by an hour — test on March/November dates if your strategy is session-sensitive
- **Tester time on weekends**: `TimeCurrent()` jumps from Friday close to Sunday open; "minutes since last bar" math needs to handle the gap

## Sources

- https://www.mql5.com/en/docs/dateandtime/timegmt
- https://www.mql5.com/en/docs/dateandtime/timecurrent
- https://www.mql5.com/en/docs/dateandtime/timetradeserver
- https://www.mql5.com/en/docs/dateandtime/timelocal
- https://www.mql5.com/en/docs/dateandtime/timetostruct
- https://www.mql5.com/en/docs/dateandtime/structtotime
- https://www.mql5.com/en/docs/constants/structures/mqldatetime
- https://www.mql5.com/en/book/automation/tester/tester_time
