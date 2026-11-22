# Roadmap

Where the project is, what comes next, and ideas that are written down so they
are not lost. Decisions live in [`docs/adr/`](docs/adr/README.md); this file is
the plan and the backlog and changes often.

Guiding rule (ADR-0001): **the first milestone is the original Query Browser,
unchanged, on current platforms and servers.** It is reached with 0.1.0-alpha.7
(ADR-0047); new features now follow, each with its own ADR, additive and off by
default, in the original's style.

## Done

- Repo layout; original sources preserved unchanged in `legacy/`.
- **Backend:** C libraries built with CMake/MinGW-w64 against MariaDB Connector/C;
  legacy bugs fixed (ADR-0003). Connection, catalogs, indices, table status,
  routines, recordsets work.
- **Server matrix:** MySQL 5.7, 8.0, 8.4, 9 and MariaDB 10.11, 11.4 pass the test
  suite (`tests/run-matrix.ps1`) (ADR-0004, ADR-0005).
- **Pascal interface layer:** generated under the original names, layout verified
  against C (ADR-0006).
- **Forms:** 12 Query Browser forms converted and reviewed (ADR-0008);
  `docs/reconstructed/` has screenshots of every form and tab.
- **Third-party replacements:** TNT aliases, PNG, gettext `.po` reader
  (ADR-0007); PNG and other resources embedded and loadable.
- **Connect dialog ported and running:** `ConnectToInstance`, `MySQLConnection`, `Options`,
  `OptionsEditor`, `AuxFuncs` (pruned to what the Query Browser uses), `CommonFuncs`, `About`,
  `MyxError`, `AuxApplicationFuncs`. The dialog shows with the original banner and translations,
  and the original code path connects to all six matrix servers, both from the command line and by
  driving the dialog (`querymole --selftest-connect/--selftest-dialog`, part of `tests/run-matrix.ps1`).
- **Main window ported and running** (`querymole -h ... --shot-main file.png` writes a screenshot):
  all units of the main window compile (`LexicalTools` without its x86 assembler, `ScriptPanel`,
  `SqlCmdPanel`, `QueryBrowser`, `Main`, `TableDrag`, `StringContainers`), the editor layer on SynEdit
  has per-line data/states/styles/gutter markers, and the schema tree, tabs, toolbar and help pane
  placeholder show against a live server. Queries run and fill the result grid (`--sql "..."` dev mode);
  toolbar icons/labels and SQL token colours work. Known gaps: line-number font and gutter width,
  token colours for embedded commands/variables, script toolbar labels touch each other with the German texts (probably as in the original). Checked by
  screenshot: query run on 5.7 and 8.x, schema tree expansion, script tab with breakpoint stop and
  progress bar (`--script`, `--expand`, `--sql` dev hooks). Also checked by screenshot or file output: EXPLAIN panel, edit/apply with server error, all five result exporters (CSV, HTML, XML, Excel, PLIST), table double click and drop, the edit/error message dialogs, options pages, text search, schema selection, RegEx importer. Not yet checked: real keyboard/mouse
  interaction, bookmarks, history, the console tab (`SqlCmdPanel` is not used by the Query Browser).

## Road to 1.0.0

Planned on 2026-11-22 (ADR-0055): 1.0.0 through `1.0.0-beta.N` (feature freeze) and `1.0.0-rc.N`; other databases,
the modern icon set and further features come in minor releases after it.

**Before 1.0.0-beta.1** (done and released 2026-11-22)
- ~~ADR statuses~~: ADR-0014, 0016, 0048 to 0053 and 0055 accepted, with what is still to check by hand in their
  status lines; ADR-0029 (search fields) is not built and waits for a minor release after 1.0.0.
- ~~`README.md`~~ for the beta (status, version badge, features, Windows installer).
- ~~Release notes~~ `docs/release-notes/1.0.0-beta.1.md`; ~~`VERSION`~~ `1.0.0-beta.1`. Tagged and released (`v1.0.0-beta.1`).

**During the beta (owner's manual tests)**
- Windows: SSH tunnel with Pageant and with `.ppk` keys (OpenSSL 4), stored SSH password, the exports (CSV options,
  TSV, JSON), the update question at the first start, starting without a connection, the connection manager's Test
  and groups (context menu, drag and drop).
- Linux: the desktop checklist of ADR-0044 (`docs/linux-manual-test.md`), the same items as on Windows where they
  apply.
- The update from 0.1.0-alpha.9 to 1.0.0-beta.1 on both platforms (the alpha.9 program has to find it).
- Faults found: fixed on `master` and in the next beta or candidate.

**1.0.0-rc.1 and 1.0.0**
- No open fault that blocks the release; release notes for 1.0.0 summarise everything since 0.1.0-alpha.9.
- `README.md` without the beta warning.

**After 1.0.0 (minor releases)**
- A memory guard for large result sets: pause and ask before the machine runs out of memory (ADR-0057, proposed).
- Other MySQL-protocol servers, Manticore first (ADR-0054).
- The modern icon set (branch `design/modern-icons`; its ADR needs a free number before it is merged, master uses
  0053 to 0055).
- macOS (ADR-0039), PostgreSQL and others behind the driver seam (ADR-0010).

## Next

The port is complete (connect dialog, main window, editor, dialogs, packaging for Windows and Linux; ADR-0047), so
the old step list is gone; the git history has it. What comes next is "Road to 1.0.0" above. State of the platforms:
Linux builds with Qt6 and ships as a self-updating AppImage (ADR-0027, 0037, 0044; `docs/linux-port.md`), Windows as
an installer (ADR-0014); macOS is deferred (ADR-0039; `docs/macos-setup.md`).

## Backlog and ideas

**Compatibility and quality**
- CI: releases are built and published by `.github/workflows/release.yml` (ADR-0040, in use since 0.1.0-alpha.3); every
  push is built and tested by `.github/workflows/test.yml` (ADR-0046: `tests/ci.sh`, server matrix on Linux, build
  check on Windows). Open: tests on Windows (servers there), screenshot comparison in CI.
- Idle CPU on Linux: `TMainForm.HandleIdle` (`Main.pas`) asks the clipboard for text on every idle pass to
  enable Paste; under GTK2 each call is an X round trip with a nested main loop. Under Qt6 (2026-11-20): connected
  and idle about 1 % CPU, 3.5 % while the mouse moves (Xvfb); Qt's xcb clipboard keeps a foreign owner's format list
  until the owner changes. Was a GTK2 problem only; GTK2 was removed after 0.1.0-alpha.9 (ADR-0044).
  Loading ~2 million rows (the unresponsive instance of 2026-11-17) was slow for another reason, fixed on 2026-11-20:
  the result grid sorted all rows after every fetched block (laz.VirtualTrees' default `toAutoSort`, see
  `VTCompat`); 2 million rows now load in about a minute with the window answering throughout. That this was the
  cause of that freeze is likely, not proven (its stack samples showed HandleIdle and GLib, not the sort).
- Dead connections (standby, VPN gone) no longer freeze the window (ADR-0043): TCP timeouts on the socket, keep-alive
  ping in a thread. The Windows backend build with the socket options compiles (it is in the CI builds since 1.0.0-beta.1); how
  it behaves on Windows is a manual test. Open by design: `Ping` before a query still blocks during an outage (ADR-0043).
- Look for further undefined behaviour in the C backend with sanitizers; more
  tests per `myx_*` area (query analysis, editable result sets, import/export).
- `myx_pdf.c` (needs the "panda" library) and `myx_live_profiling.c` (POSIX
  sockets) are not built; decide whether the features are needed.
- Review each of the 29 `char*`-returning functions for the `g_free` contract
  (ADR-0006).
- **Table editor on current servers.** `tests/test_table_editor.pas` reads a table through the editor's model
  (`myx_database_model.c` and the Pascal class) and checks on the matrix that an unchanged table gives no SQL, that
  editing the table comment and a comment on every column has the same effect as plain `ALTER TABLE` on a twin
  table, and that the table written as a new one (`CREATE TABLE`) equals the twin. It covers InnoDB, MyISAM,
  MEMORY, Aria, foreign keys with actions, many data types, JSON, generated, invisible and `ON UPDATE` columns,
  CHECK, column collations and functional indices; all pass on the six servers since 2026-11-15 (fixes in the
  backend, marked `revival:`). Still open:
  - the model has no table CHECK constraints: edits keep them, the editor cannot create them;
  - generated expressions, `ON UPDATE`, `INVISIBLE` and column CHECKs are kept but not shown or editable in the
    editor; expression defaults (`DEFAULT (expr)`) and defaults with a quote are kept since 2026-11-22 (they were
    written back as a wrong string; `TestExpressionDefault`); an expression in parentheses typed into the Default cell of the column grid stays an
    expression (it was quoted as a string);
  - editing indices (new, columns, prefix, rename, remove) and foreign keys (new, actions, remove) through the model
    is tested on the matrix (`TestEditIndices`, `TestEditForeignKeys`, 2026-11-22);
  - data types and engines: ADR-0034 (JSON, YEAR, BINARY, VARBINARY added; engines from `SHOW ENGINES`).
    Server-specific types (MariaDB UUID, INET4/6; MySQL 9 VECTOR) wait for the dialects of ADR-0010.
    `myx_dbm_get_default_storage_engine` still reads `storage_engine` (gone since 5.7) but is not used;
  - the editor itself was checked by opening a table, not by editing through its grid; the Windows backend build
    with these changes is not checked yet.
  The model is the natural seam for other databases later (ADR-0010). Showing and editing the newer features is
  stage 2 (ADR-0035), the Pascal model with dialects stage 3 (ADR-0036), both after parity (see "Product").

**Fidelity**
- Reference screenshots from a user who still runs the original, for side by
  side review (ADR-0008).
- Rebuild what the conversion drops: SQL editor configuration, `TAnimate`
  connect animation, menu owner draw, toolbar image lists (from PNGs), form
  icons, version info and manifest.

**Product (after parity; each needs a decision)**
- Large result sets: as in the original, every row is loaded into memory (backend row array plus grid; about
  1 KB per row was measured, 2 million rows ≈ 2 GB), with no query timeout. A table of tens of millions of rows
  without a filter ends in swapping or the OOM killer; Stop works. Keeping "no timeout" is wanted. Options, in
  the order to consider them:
  - safety net (ADR-0057, planned for 1.1.0): pause at a threshold (rows or memory, set in the options, can be switched off) and ask
    "continue / stop"; small, takes nothing away;
  - fetching on demand while scrolling: `LIMIT/OFFSET` gets slow at deep offsets and is inconsistent when data
    changes, keyset paging needs a primary key and a plain table, a streaming cursor (`mysql_use_result`) blocks
    the connection; sorting, searching and editing in the result assume all rows are loaded;
  - less memory per row (moves the limit, does not remove it).
  An automatic `LIMIT` on double click (as Workbench, DBeaver) would change the SQL users see and expect;
  least preferred.
- **Start and updates** (ADR-0052, proposed): the banner animation while connecting; Cancel at start opens the program
  without a connection; an opt-in update check at start (asked once) with "development versions" in the update dialogs.
- **Connection manager** (ADR-0051, proposed): a "Test" button and groups of stored connections (folders in the tree,
  kept in `storage_path`); the groups also in the connect dialog's list (ADR-0053).
- **SSH tunnel** for connections (ADR-0048, proposed): libssh in the program, OpenSSH and PuTTY keys, agent and
  Pageant, `known_hosts` and `~/.ssh/config`; mock-up in the ADR; Pageant pipe name known; libssh 0.12.2 builds for the AppImage (`tools/appimage/build-libssh.sh`). The tunnel itself works and is
  tested on the matrix against an OpenSSH container (`app/src/SSHTunnel.pas`, `tests/test_ssh_tunnel.pas`). The program
  connects through it when a stored connection has `SSH_TUNNEL=Yes` and the `SSH_*` advanced options (matrix self-test
  proves the SSH login). The UI follows the mock-up
  (`app/src/SSHTunnelDialog.pas`; screenshots with `--shot-connect`, `--shot-ssh`, `--shot-options`). `.ppk` keys
  (formats 2 and 3) work and are tested; Pageant is implemented for Windows. The SSH password can be stored (ADR-0053). Next: a
  test on Windows (Pageant, libssh.dll).
- TLS mode in the connection dialog: required / preferred / off (ADR-0005).
- Result export: JSON and JSON Lines added (ADR-0049), the five original exporters reviewed and fixed
  (`docs/export-review.md`, 2026-11-20); CSV settings on the Browser options page (separator, quotes, line breaks,
  header, BOM) and a TSV format in `LOAD DATA`'s format (ADR-0050). Candidates, each with its own ADR: SQL INSERT
  statements, Markdown table, real XLSX. The export entries are disabled while rows still load.
  The grid's fetch of large results is as fast as the backend's since 2026-11-22 (updates every 150 ms at most).
- HiDPI scaling, then optional vector-rendered icon set (ADR-0009).
- Servers that speak the MySQL protocol (ADR-0054, proposed): a server profile (kind and version, detected at
  connect) and capabilities that generated SQL and the menus follow. Manticore first (tested 2026-11-22: connecting,
  tree and queries work; table aliases only from 28, never `table.column`, no `SHOW FULL COLUMNS`, "Create New
  Table" fails, taken for MySQL 32). Then, each tested in a container: TiDB, Vitess/PlanetScale, SingleStore, Sphinx,
  others; ClickHouse may need the driver seam.
- PostgreSQL, SQLite and SQL Server via a driver seam (ADR-0010); what is MySQL-specific today and a suggested order:
  `docs/multi-database-inventory.md` (2026-11-20). Candidate libraries: libpq, sqlite3, FreeTDS, or FPC's SQLDB.
- Replace C pieces by Pascal behind that seam, SQL parser last (ADR-0003).
- Table editor, stage 3 (ADR-0036): a Pascal table model with a dialect per server family (reading, `CREATE`/
  `ALTER` generation, capabilities incl. server-specific types such as UUID, INET6, VECTOR) replaces
  `myx_database_model.c` for the editor; `tests/test_table_editor.pas` must pass on it on the whole matrix first.
- Table editor, stage 2 (ADR-0035): controls for generated columns, `ON UPDATE`, `INVISIBLE`, CHECK (column and
  table), expression defaults and functional index parts, shown by server capability. Needs a mock-up and an
  amending ADR for the layout; preferably built on the stage 3 model.
- Show what the connection is to in the picture top right of the main window (where the original had the
  dolphin): server type and version as text or tooltip ("MariaDB 11.4"). Not the databases' logos: the MySQL
  logo needs a written agreement with Oracle outside websites; the MariaDB sea lion is CC BY-SA 4.0 as a picture
  but a trademark of MariaDB Corporation, and CC BY-SA 4.0 does not combine with GPL-2.0 (checked 2026-11-14).
- Dark mode; MySQL 8 specifics the original never had (JSON, CTEs and window
  functions in highlighting and statement splitting; `utf8mb4` collations).

## Open questions

- ~~**Name.**~~ Decided: **QueryMole** (ADR-0030). The About dialog shows the QueryMole artwork (ADR-0032), the
  icon replaces the lightning bolt everywhere (ADR-0033), the QueryMole animation the busy dolphin. Open:
  renaming the GitHub repository to `querymole` (the program already links there).
- Where the project is hosted; copyright holder line and contribution policy
  (licence is decided: ADR-0011).
- Whether to ship an installer that bundles glib/libxml2/PCRE/Connector DLLs or
  link statically.
- **Licence decisions before a public release** (`docs/licenses.md`): three SynEdit units are MPL-1.1 only
  (not GPL-compatible by the FSF's reading; ask the Lazarus maintainers); "or later" in GPL-2.0-or-later must stay (OpenSSL is Apache-2.0); legal review and code
  signing.
