# Economic Calendar API + CSV Fallback

## The big gotcha

**`CalendarValueHistory()` returns 0 in the Strategy Tester.** No exceptions, no workarounds without falling back to a CSV resource. Production EAs that skip this end up with a different signal set in backtest vs live.

**Sources:** [forum 470081](https://www.mql5.com/en/forum/470081), [forum 326554](https://www.mql5.com/en/forum/326554), [article 17603 part 7](https://www.mql5.com/en/articles/17603)

## API signatures

```mql5
int  CalendarValueHistory(MqlCalendarValue &values[],
                          datetime datetime_from,
                          datetime datetime_to=0,
                          const string country_code=NULL,    // e.g. "US" "EU" "JP"
                          const string currency=NULL);       // e.g. "USD" "EUR" "JPY"

bool CalendarEventById(ulong event_id, MqlCalendarEvent &event);
bool CalendarCountryById(ulong country_id, MqlCalendarCountry &country);
```

**Return semantics for `CalendarValueHistory`:**
- `-1` → error (check `GetLastError()`)
- `0` → no events in window (NOT an error — common in tester)
- `N > 0` → N events copied to `values[]`

**Don't conflate 0 with -1.** A 0 return in the tester is normal; aborting on 0 silently disables your news gate in backtests.

**Source:** [CalendarValueHistory docs](https://www.mql5.com/en/docs/calendar/calendarvaluehistory)

## The mandatory gate pattern

```mql5
bool IsHighImpactNewsWindow(datetime utc_now, int mins_before, int mins_after)
{
   if(MQLInfoInteger(MQL_TESTER))
      return IsNewsWindowFromCSV(utc_now, mins_before, mins_after);
   else
      return IsNewsWindowFromAPI(utc_now, mins_before, mins_after);
}
```

**Source for `MQL_TESTER` detection:** [forum 227207](https://www.mql5.com/en/forum/227207)

## Live API path

```mql5
bool IsNewsWindowFromAPI(datetime utc_now, int mins_before, int mins_after)
{
   datetime from = utc_now - mins_before * 60;
   datetime to   = utc_now + mins_after  * 60;

   MqlCalendarValue values[];
   int got = CalendarValueHistory(values, from, to);
   if(got < 0)
   {
      PrintFormat("Calendar API error: %d", GetLastError());
      return true;   // fail closed
   }
   for(int i = 0; i < got; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      MqlCalendarCountry cc;
      if(!CalendarCountryById(ev.country_id, cc)) continue;
      if(cc.currency != "USD" && cc.currency != "XAU") continue;
      datetime t = values[i].time;
      if(t >= from && t <= to) return true;
   }
   return false;
}
```

## CSV fallback for the Strategy Tester

Bundle a CSV as an embedded resource so it ships with the `.ex5`:

```mql5
#resource "\\Files\\news.csv" as string g_news_csv_raw;
```

Or read from `MQL5\Files\news.csv` at runtime (less portable but easier to update):

```csv
datetime_utc,impact,currency,event
2026-05-21 12:30,High,USD,Core CPI m/m
2026-05-23 14:30,High,USD,FOMC Press Conference
```

```mql5
bool IsNewsWindowFromCSV(datetime utc_now, int mins_before, int mins_after)
{
   int fh = FileOpen("news.csv", FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return false;   // no news data; don't block trades

   datetime from = utc_now - mins_before * 60;
   datetime to   = utc_now + mins_after  * 60;
   bool found = false, header_skipped = false;

   while(!FileIsEnding(fh))
   {
      string ts  = FileReadString(fh);
      string imp = FileReadString(fh);
      string ccy = FileReadString(fh);
      string evn = FileReadString(fh);
      if(!header_skipped) { header_skipped = true; continue; }
      if(StringFind(imp, "High") < 0 && StringFind(imp, "Red") < 0) continue;
      if(ccy != "USD" && ccy != "XAU") continue;
      datetime t = StringToTime(ts);
      if(t >= from && t <= to) { found = true; break; }
   }
   FileClose(fh);
   return found;
}
```

## `MqlCalendarValue` / `MqlCalendarEvent` / `MqlCalendarCountry` fields

From [MqlCalendarValue](https://www.mql5.com/en/docs/constants/structures/mqlcalendarvalue), [MqlCalendarEvent](https://www.mql5.com/en/docs/constants/structures/mqlcalendarevent), [MqlCalendarCountry](https://www.mql5.com/en/docs/constants/structures/mqlcalendarcountry):

```mql5
struct MqlCalendarValue {
   ulong    id;
   ulong    event_id;
   datetime time;
   datetime period;
   int      revision;
   long     actual_value;     // raw scaled by 1,000,000
   long     prev_value;
   long     revised_prev_value;
   long     forecast_value;
   ENUM_CALENDAR_EVENT_IMPACT impact_type;
};

struct MqlCalendarEvent {
   ulong  id;
   ENUM_CALENDAR_EVENT_TYPE      type;
   ENUM_CALENDAR_EVENT_SECTOR    sector;
   ENUM_CALENDAR_EVENT_FREQUENCY frequency;
   ENUM_CALENDAR_EVENT_TIMEMODE  time_mode;
   ulong country_id;
   ENUM_CALENDAR_EVENT_UNIT       unit;
   ENUM_CALENDAR_EVENT_IMPORTANCE importance;
   ENUM_CALENDAR_EVENT_MULTIPLIER multiplier;
   uint   digits;
   string source_url;
   string event_code;
   string name;
};

struct MqlCalendarCountry {
   ulong  id;
   string name;
   string code;            // ISO 2-letter, e.g. "US"
   string currency;        // e.g. "USD"
   string currency_symbol;
   string url_name;
};
```

**`ENUM_CALENDAR_EVENT_IMPORTANCE`:**
- `CALENDAR_IMPORTANCE_NONE` (0)
- `CALENDAR_IMPORTANCE_LOW` (1)
- `CALENDAR_IMPORTANCE_MODERATE` (2)
- `CALENDAR_IMPORTANCE_HIGH` (3) — what most EAs gate on

## Broker dependency

Not all brokers populate `CalendarValueHistory`. MetaQuotes demo accounts usually do; some real brokers don't ship calendar data through the terminal. Test with a small script:

```mql5
void OnStart() {
   MqlCalendarValue v[];
   int n = CalendarValueHistory(v, TimeGMT() - 86400, TimeGMT() + 86400);
   PrintFormat("Calendar returned %d events", n);
}
```

If you see 0 on live, your broker doesn't push calendar data — fall back to CSV always.

## Sources

- https://www.mql5.com/en/docs/calendar/calendarvaluehistory
- https://www.mql5.com/en/docs/constants/structures/mqlcalendarvalue
- https://www.mql5.com/en/docs/constants/structures/mqlcalendarevent
- https://www.mql5.com/en/docs/constants/structures/mqlcalendarcountry
- https://www.mql5.com/en/forum/470081 — Calendar returns 0 in tester
- https://www.mql5.com/en/forum/227207 — MQL_TESTER detection
- https://www.mql5.com/en/articles/17603 — Article 17603 part 7 (calendar fallback patterns)
- https://www.mql5.com/en/articles/22231 — Article 22231 part 4
