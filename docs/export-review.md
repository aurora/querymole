<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Result set export: review and measurements (2026-11-20)

Review of the five exporters of the original (CSV, HTML, XML, Excel, PLIST) for speed and correctness, before the
JSON and JSON Lines exporters were added (ADR-0049). Code: `backend/src/base-library/source/myx_exporter.c`, driven
by `myx_export_resultset` in `myx_recordset.c`, called from `TQueryBrowserForm.SaveResultsetAs`
(`app/src/QueryBrowser.pas`). Tests: `tests/test_export.pas`.

## How it works

The export writes the result set that is already in memory (the grid's `MYX_RESULTSET`); the server is not asked
again (except for the master-detail export). Each format is a set of callbacks (`begin`, `table_header`, `columns`
per row, `table_footer`, `end`) that `fprintf` to a buffered `FILE`. Pending grid edits (changed, deleted, added
rows) are applied on the fly.

## Speed

Measured with `TExportTest.TestLargeExportTime` (`SELECT seq, MD5(seq) AS h, NOW() AS t`, 3 columns; the test now
uses `LEFT(SHA2(seq, 256), 32)`, the same 32 hex digits, because MySQL 9.7 no longer has `MD5()`) against
MariaDB 11.4 in a local container, Fedora 44 distrobox, `QBR_EXPORT_ROWS=200000` / `2000000`. Times are for the
export alone (the rows were fetched before: 200k in 0.14 s, 2M in 2.2–3.1 s).

| Format     | 200k before | 200k after | 2M before | 2M after | 2M file size |
|------------|------------:|-----------:|----------:|---------:|-------------:|
| CSV        |       64 ms |      18 ms |    612 ms |   260 ms |       130 MB |
| HTML       |      396 ms |      51 ms |   4094 ms |   695 ms |       192 MB |
| XML        |      260 ms |     105 ms |   2667 ms |  1640 ms |       348 MB |
| Excel      |      235 ms |      77 ms |   2427 ms |  1026 ms |       442 MB |
| PLIST      |      249 ms |     115 ms |   2546 ms |  1467 ms |       451 MB |
| JSON       |           — |      55 ms |         — |   710 ms |       164 MB |
| JSON Lines |           — |      53 ms |         — |   729 ms |       162 MB |

A single value of 2.1 MB that is all markup characters (`TestLongValue`): 11–71 ms before, 9–27 ms after.

Finding: **the exporters were never slow in a way a user would notice** — all linear, and the 2-million-row XML
export takes under 3 s. The time went into one heap copy per cell (`str_g_replace` for CSV, `escape_*_entities` for
the markup formats, which looks every character up in a 250-entry table) and a `fprintf` per cell. The rewrite
writes the values straight to the file, escaping only where needed (speed-up 2–8×). If an export feels slow in the
program, the cause is elsewhere: see "Export while rows are still loading" below, and the row fetch of the grid.

## Correctness findings and fixes

Each of these was wrong in the original (same code in `legacy/`), so they are fixed as bugs (ADR-0047).

| # | Format | Problem | Fix |
|---|---|---|---|
| 1 | Excel | **Crash** (`free(): invalid pointer`, the program exits) on any empty string value: `escape_xml_entities("")` returns NULL, the code substituted the literal `""` and freed it. | Values written directly, no copy. |
| 2 | Excel | Type table missing a comma (`"Number" "String"` concatenated), so a BOOL/DATE column type would have read past the array. Latent (no column got those types). | Comma added. |
| 3 | HTML | Empty string written as `(null)` (glibc's text for a NULL `%s`; on Windows the CRT does the same). | Fixed by 1's rewrite. |
| 4 | HTML | Column names (`<th>`) and the title (`Query <sql>, <date>`) not escaped: a query with `<` or a column alias with `&` broke the page. | Escaped. |
| 5 | XML | NULL written as `<colname/>`: not well-formed for names with spaces, quotes, `<`, leading digits, e.g. `COUNT(*)`; and not allowed by the DTD written beside it. | `<field name="x" xsi:nil="true" />` with the namespace on `<ROOT>` and the attribute in the DTD (the `mysqldump --xml` convention). The file now validates (`xmllint --valid`). |
| 6 | XML | Column name in `name="..."` not escaped (`"` or `&` in an alias broke the file). | Escaped. |
| 7 | PLIST | Empty string written as `<string>(null)</string>`; `<key>` not escaped. | Fixed; loads in Python's `plistlib`. |
| 8 | all | DECIMAL columns arrive as `NEWDECIMAL` (MySQL ≥ 5.0) and were not mapped, so they counted as strings: quoted in CSV, `String` in Excel, `<string>` in PLIST. The old `DECIMAL` type was mapped to *integer*, so PLIST would have written `<integer>1.50</integer>`. | Both are numbers with a fraction: CSV unquoted, Excel `Number`, PLIST `<real>`. |
| 9 | XML, Excel, PLIST, HTML | Bytes that are not UTF-8 (binary columns) copied into a file declared UTF-8; control characters (e.g. `CHAR(1)`) that XML 1.0 forbids even as entities. | Replaced by U+FFFD (markup formats); CSV keeps the raw bytes as before. |
| 10 | (utility) | `escape_entities` stepped over the terminating NUL when a value ended inside a multi-byte sequence (`g_utf8_next_char` on a cut-off lead byte): a read past the end of the value. Also used outside the exporter. | Invalid bytes count as one character. |
| 11 | all | A result without rows to write (all rows deleted in the grid) wrote the table footer without the header (`</table>` alone). | Header written before the footer. |
| 12 | all | The exporter info leaked its option values and column definitions; `option_values_num` was never set, so `$DATE$`/`$QUERY$` in option values were never replaced. | Freed; count set. |
| 13 | all | With pending grid edits, every row searched all edits (rows × edits; 2M rows × 1000 edits = 2·10⁹ steps). | Rows with edits are marked once. |
| 14 | GUI | **Export while rows are still loading** races the fetch thread, which moves the row array (`g_realloc`) while the export reads it: use-after-free, a crash or garbage in the file. | The export takes `WorkWithResultset`, the lock the fetch thread and the grid already use; the fetch waits during the export. |

Checked and correct (unchanged): CSV quoting (strings and dates in `"..."`, quotes doubled, separators and newlines
inside quotes), CSV NULL (empty, unquoted) versus empty string (`""`), the CSV "Separator" option, UTF-8 text,
numbers and dates as the server formats them, very wide rows (300 columns × 1000 characters).

## Open points (not changed)

- **Export while loading writes only the rows fetched so far**, without a notice (2M-row query, export after 4 s:
  40,492 rows in the file). The original did the same (and could crash, see 14). Decided 2026-11-22: the export
  entries are disabled while the query runs (`QueryExecuting`), no new dialog. Not checked by hand yet.
- **The grid fetch of a large result was much slower than the backend fetch** with wide rows: the backend calls back
  after every 10 KB, and each call updated and repainted the grid (2M rows x 8 columns: about 110 s in the program,
  2.6 s in the backend). Fixed on 2026-11-22: the grid is updated at most every 150 ms and once more when the query
  ends (`TExecuteQueryThread`, `GridUpdateMs`); the same query now loads in under 2 s with all 2M rows in the grid.
- **4-byte UTF-8 (emoji)** could not reach any export because the connection used `utf8` (utf8mb3). Fixed on
  2026-11-22: the connection uses `utf8mb4` (ADR-0056).
- **Empty BLOB values arrive as NULL** in the result set (`myx_recordset.c` keeps `""` only for string/text columns),
  so every format exports an empty BLOB as NULL. VARBINARY is not affected.
- **Binary values end at their first zero byte** in every format: the exporter interface passes C strings without
  lengths.
- The CSV separator option exists but the program has no UI for it (see ADR-0049, further formats).

## Test run

`tests/test_export.pas` (13 tests) with the whole suite on MySQL 5.7, 8.0, 8.4, 9 (9.7.4) and MariaDB 10.11, 11.4:
83 tests, 0 errors, 0 failures on every server (the 10 SSH tunnel tests ignored: no SSH server in that run). The
program was cross-built for Win64 (compiles); not run on Windows.
