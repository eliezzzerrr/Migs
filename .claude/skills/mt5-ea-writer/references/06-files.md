# File I/O — FileOpen flags, FolderCreate, FileFind

## `FileOpen` flag matrix

From [File Opening Flags](https://www.mql5.com/en/docs/constants/io_constants/fileflags):

| Flag | Value | Purpose |
|---|---|---|
| `FILE_READ` | 1 | Read mode |
| `FILE_WRITE` | 2 | Write mode |
| `FILE_BIN` | 4 | Binary, no string conversion |
| `FILE_CSV` | 8 | CSV with delimiter |
| `FILE_TXT` | 16 | Text, no delimiter |
| `FILE_ANSI` | 32 | Single-byte chars |
| `FILE_UNICODE` | 64 | 2-byte UTF-16 (default!) |
| `FILE_SHARE_READ` | 128 | Allow concurrent read |
| `FILE_SHARE_WRITE` | 256 | Allow concurrent write |
| `FILE_REWRITE` | 512 | Allow overwrite via FileCopy/FileMove |
| `FILE_COMMON` | 4096 | Use shared terminal folder, not MQL5\\Files |

**Defaults if not specified:**
- Type: `FILE_CSV`
- Encoding: `FILE_UNICODE` (UTF-16!)

These defaults catch people: writing "plain text" without explicitly passing `FILE_TXT | FILE_ANSI` produces UTF-16 CSV files that Notepad/Excel render with weird BOM behavior.

**Source:** [Selecting an encoding](https://www.mql5.com/en/book/common/files/files_txt_codepage)

## Recipe choices

```mql5
// Plain-text human-readable journal (markdown, YAML, .txt)
int fh = FileOpen(path, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);

// CSV with comma delimiter
int fh = FileOpen(path, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');

// CSV with tab delimiter (default delimiter for FILE_CSV)
int fh = FileOpen(path, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI);

// Binary cache
int fh = FileOpen(path, FILE_WRITE | FILE_READ | FILE_BIN);
```

**Common bug:** opening with `FILE_CSV` and forgetting to pass the delimiter. Defaults to `\t` (tab), not comma. Always pass delimiter as the 5th argument when you want a non-tab CSV.

## `FileOpen` full signature

```mql5
int FileOpen(const string file_name,
             int          open_flags,
             short        delimiter = '\t',
             uint         codepage  = CP_ACP);
```

Returns the file handle, or `INVALID_HANDLE` on failure. Check with `GetLastError()`:

```mql5
int fh = FileOpen("journal.csv", FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
if(fh == INVALID_HANDLE)
{
   PrintFormat("FileOpen failed: %d", GetLastError());
   return false;
}
FileClose(fh);
```

## Always paired

```mql5
int fh = FileOpen(path, ...);
if(fh == INVALID_HANDLE) return;
// ... read/write ...
FileClose(fh);   // mandatory; missing close leaks handles
```

## `FolderCreate` — creates intermediates

```mql5
bool FolderCreate(string folder_name, int common_flag = 0);
```

Documented behavior: creates the full path including missing parent directories. Defensive code can iterate:

```mql5
bool EnsureNestedDir(const string path)
{
   string parts[];
   int n = StringSplit(path, '\\', parts);
   string accum = "";
   for(int i = 0; i < n; i++)
   {
      if(StringLen(parts[i]) == 0) continue;
      accum = (accum == "") ? parts[i] : accum + "\\" + parts[i];
      FolderCreate(accum);   // idempotent; no-op if exists
   }
   return true;
}
```

**Source:** [FolderCreate](https://www.mql5.com/en/docs/files/foldercreate)

## File search

```mql5
long FileFindFirst(const string file_filter, string &returned_filename, int common_flag = 0);
bool FileFindNext (long  search_handle,      string &returned_filename);
void FileFindClose(long  search_handle);
```

Returns `INVALID_HANDLE` (-1 as long) on no match.

**Canonical loop:**
```mql5
string fname;
long h = FileFindFirst("journal\\2026\\05\\*.md", fname);
if(h == INVALID_HANDLE)
{
   Print("No journal entries found.");
   return;
}
do {
   PrintFormat("Found: %s", fname);
} while(FileFindNext(h, fname));
FileFindClose(h);
```

**Source:** [FileFindFirst](https://www.mql5.com/en/docs/files/filefindfirst)

## Path conventions on Windows

- Use `\\` (escaped backslash) in MQL5 string literals: `"Migs\\journal\\trade.md"`
- Or use `/`: `"Migs/journal/trade.md"` — MQL5 accepts both
- Paths are relative to `MQL5\Files\` unless `FILE_COMMON` is passed

## Reading line-by-line (text mode)

```mql5
int fh = FileOpen("log.txt", FILE_READ | FILE_TXT | FILE_ANSI);
if(fh != INVALID_HANDLE)
{
   while(!FileIsEnding(fh))
   {
      string line = FileReadString(fh);
      if(StringLen(line) == 0) continue;
      // process line
   }
   FileClose(fh);
}
```

## Reading CSV field-by-field

```mql5
int fh = FileOpen("trades.csv", FILE_READ | FILE_CSV | FILE_ANSI, ',');
if(fh != INVALID_HANDLE)
{
   while(!FileIsEnding(fh))
   {
      string col1 = FileReadString(fh);   // reads up to next delimiter
      string col2 = FileReadString(fh);
      string col3 = FileReadString(fh);
      // ... continue per column count
      if(FileIsLineEnding(fh)) {
         // end of row
      }
   }
   FileClose(fh);
}
```

`FileReadString` automatically advances past the delimiter or newline.

## Writing CSV

```mql5
int fh = FileOpen("trades.csv", FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
if(fh != INVALID_HANDLE)
{
   FileWrite(fh, "id", "direction", "entry", "sl", "tp", "outcome");
   FileWrite(fh, 1, "BUY", 4500.0, 4490.0, 4530.0, "TP_HIT");
   FileClose(fh);
}
```

`FileWrite` with multiple args produces a CSV row with auto-delimiter between fields. Each call adds a newline at the end.

## Resource embedding (ship data inside the .ex5)

```mql5
#resource "\\Files\\news.csv" as string g_news_csv;
// Now g_news_csv is a global string containing the file contents at compile time.
```

Useful for shipping a calendar CSV fallback that doesn't depend on the user copying files.

## Common mistakes to avoid

- **Opening for write without `FILE_REWRITE`** when you intend to overwrite — pre-existing file content is preserved, you end up appending instead of replacing.
- **Forgetting `FILE_ANSI`** — file ends up as UTF-16 and other tools see it as binary.
- **Mixing read and write modes** — `FILE_READ | FILE_WRITE` opens for r+w; without both flags you can only do one direction.
- **Not checking `INVALID_HANDLE`** — file open can fail (permissions, path doesn't exist) and subsequent `FileWrite` is a silent no-op.

## Sources

- https://www.mql5.com/en/docs/constants/io_constants/fileflags
- https://www.mql5.com/en/docs/files/fileopen
- https://www.mql5.com/en/docs/files/foldercreate
- https://www.mql5.com/en/docs/files/filefindfirst
- https://www.mql5.com/en/book/common/files/files_txt_codepage
- https://www.mql5.com/en/book/common/files/files_open_close
