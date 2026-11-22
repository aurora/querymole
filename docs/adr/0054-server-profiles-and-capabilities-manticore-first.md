<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# ADR-0054 — Server profiles and capabilities for MySQL-protocol servers, Manticore first

- Status: Proposed
- Date: 2026-11-22
- Deciders: Harald Lapp (project owner)

## Context

More and more servers speak the MySQL protocol without being MySQL: Manticore Search (and Sphinx before it),
TiDB, Vitess (and PlanetScale, which is hosted Vitess), SingleStore, ClickHouse (through its MySQL interface),
Doris/StarRocks, OceanBase, Dolt. The owner wants QueryMole to work with them, Manticore first, and in the long run
with PostgreSQL, SQL Server and SQLite too.

The program connects to any of them, because it uses the same client library (Connector/C). Behind that it assumes
MySQL or MariaDB everywhere: the backend and the program write MySQL SQL and decide by the server's version what
the server can do (45 version checks in 4 Pascal units, 23 in the C backend).

**Manticore, as tested on 2026-11-22** (Docker images 6.0.4, 6.3.8, 9.2.14, 13.2.3, 27.1.5, 28.4.4, 28.6.6, 29.0.2,
32.1.3; the program against 13.2.3 and 32.1.3):

- Works: connecting, the schemata tree (`information_schema` and `Manticore` with their tables, columns through
  `SHOW COLUMNS`), queries and the result grid. The menu smoke test (143 entries) finds no crash.
- Table aliases (`SELECT * FROM products p`, also with `AS`) fail up to 27.1.5 and work from 28.4.4 on.
- Columns qualified by the table name (`products.title`, also quoted, also with the schema) fail in every version,
  32.1.3 included; from 28 on, a column can be qualified by an alias (`p.title`).
- `SHOW FULL COLUMNS` fails in every version, so the program cannot find the key column of a result; editing a
  result probably fails (not tried). `SHOW COLLATION LIKE ...` fails, so "Create New Table" ends with "Cannot fetch
  charset information".
- `VERSION()` and the handshake report the Manticore version with build data ("32.1.3 9d4cd4df2@26112010 ..."):
  the program takes it for MySQL 32, so every check "MySQL 8 or later" passes. `SHOW VERSION` (a row "Daemon")
  exists only on Manticore.

The program writes the failing SQL itself in several places: dragging or double clicking a table writes
`SELECT * FROM <table> <first letter>` (`QueryBrowser.pas`), and the query builder of the backend
(`myx_query.cpp`, adding tables and columns to the statement in the editor) creates aliases and qualifies columns
with them.

ADR-0010 plans other databases (PostgreSQL first) behind a driver seam; `docs/multi-database-inventory.md` puts
that seam into Pascal, above the `myx_*` calls, and the main window's enabling and hiding of functions "by driver
capabilities". Servers that speak the MySQL protocol need no new driver: they differ in dialect and features, not in
how the program talks to them.

## Decision

1. **A server profile per connection.** When a connection is made, the program determines the server's kind
   (MySQL, MariaDB, Manticore; later others) and the kind's own version, and keeps them with the connection.
   - The kind is found by a table of rules, evaluated in order: first the version string of the handshake (no extra
     round trip; Manticore's form "<version> <build>@<date>", the suffixes other servers add); where that is not
     certain, one confirming query of that kind (`SHOW VERSION` for Manticore). Supporting another server adds a
     rule.
   - **Unknown means MySQL,** as today: a server that is not recognised is treated as now, never worse.
   - MariaDB keeps its current detection (ADR-0004, the version read through Connector/C); it becomes the kind
     MariaDB of the profile.
2. **Capabilities derived from the profile.** A fixed set of named capabilities, each with a value per kind and
   version range, for example "table aliases" (MySQL, MariaDB: yes; Manticore: from 28), "columns qualified by
   table name" (Manticore: no), "column details" (`SHOW FULL COLUMNS`; Manticore: no), "table editor", "editing
   results". Code that writes SQL or enables a function asks for a capability, never for the kind or version
   directly. The set starts with what Manticore needs and grows with each server that is tested; a capability is
   added when a test shows a difference, not in advance.
3. **The backend gets the capabilities it needs from the program.** After connecting, the program passes them for the
   connection's `MYSQL` handle to the backend (one new backend function), so that the query builder writes no alias
   and no qualified column where the server cannot read them. The version checks of the backend and the program
   that decide features apply to MySQL and MariaDB only; for other kinds the capabilities decide.
4. **Manticore is the first server done this way:**
   - before 28: generated statements without table aliases and with unqualified columns; from 28: as for MySQL,
     but columns qualified by alias only, never by table name;
   - functions that need what Manticore lacks (table editor and "Create New Table", editing results, charsets and
     collations, stored routines, users) are disabled or hidden as the original does it for servers that lack a
     feature, instead of ending with an error;
   - a Manticore container joins the test matrix (an older and a current version, on both sides of 28) with the
     program's self-tests; the FPCUnit tests that need MySQL features are skipped there.
   - The connect dialog, the stored connections and their file stay as they are: the kind is detected, not chosen.
5. **Further MySQL-protocol servers follow as small steps,** each with a container in the (optional) test matrix, a
   detection rule and the capabilities the tests show; they need no ADR of their own as long as they only add rules
   and capabilities. Candidates, with the expected distance from MySQL (to be confirmed by testing):

   | Server | Expected distance | Test locally |
   |---|---|---|
   | TiDB | small: reports MySQL 8.0 with its own name in the version; no stored routines, triggers, events | container |
   | Vitess | small to medium: proxy before MySQL; limits on catalog queries and across shards | `vttestserver` |
   | PlanetScale | as Vitess (hosted Vitess), TLS required | hosted only; covered by the Vitess profile |
   | SingleStore | medium: own table types, parts of the catalog missing | container with a free licence key |
   | Sphinx 2/3 | as Manticore or further (Manticore's ancestor) | container |
   | Doris, StarRocks, OceanBase, Dolt | unknown | containers |
   | ClickHouse | large: own SQL dialect and types, the MySQL protocol only as an entry | container |

   ClickHouse is the border case: its dialect differs so much that it may belong to the driver seam (own catalog
   and type logic) rather than to a profile; decided when it has been tested. MySQL forks and hosted MySQL (Percona
   Server, Amazon Aurora, Azure Database for MySQL) behave as MySQL and need no profile.
6. **This is the dialect half of the later driver seam (ADR-0010).** The interfaces for connections, result sets and catalogs of
   databases that do not speak the MySQL protocol (PostgreSQL, SQL Server, SQLite) get their own ADR; they use the
   same profile and capabilities, with a driver as a further part of the profile.

## Consequences

Positive:
- Manticore becomes usable for querying (generated statements that work, no error dialogs for missing features) with
  limited work, since connecting and results already work.
- Further MySQL-protocol servers are added rule by rule, each tested; no server is treated worse than today.
- The capability set is the piece the later driver seam needs anyway; the main window's enabling and hiding is
  decided in one place.

Negative:
- The version checks in the program and the backend have to be gone through once and routed through the profile
  (68 places), with the risk of changing a MySQL path by mistake; the server matrix guards it.
- One more piece of state per connection that the threads of result tabs and the query cancel connection must
  share (they open their own connections to the same server).
- A confirming query at connect for servers whose version string is not clear (one round trip, only for those).
- Manticore and later servers stay partly supported: querying works, much of the rest is off. The UI does not say
  why beyond the disabled entries.
- The test matrix grows; the optional servers make a full run longer.

## Alternatives considered

- **Check the version only** ("Manticore 28 and later" as a version number): the version numbers of different
  servers overlap (Manticore 32 is not MySQL 32); without the kind no version means anything.
- **Choose the server kind in the connection** (a field in the connect dialog and the stored connection): a change
  to a dialog of the original and to the file format, and a wrong choice would break a working connection; the
  kind can be detected reliably.
- **Try and fall back** (send the statement with aliases, retry without on error): hides the problem, sends wrong
  statements to the server, and does not work for functions that should not be offered at all.
- **Together with the driver seam for PostgreSQL and others:** the seam is a large rebuild over several steps;
  Manticore would wait for all of it, though it only needs the dialect half.

## Related

- ADR-0010 — other databases behind a driver seam; this ADR is its dialect half, for MySQL-protocol servers.
- ADR-0047 — the rules for features after parity (additive, off for servers that do not need it).
- ADR-0004 — client library and server support matrix (where MariaDB's version reading is settled); the profile
  extends the matrix by kind.
- ADR-0003 — the C backend as transitional; capabilities are passed into it, not decided there.
- ADR-0036 — the table editor's model with dialects.
- `docs/multi-database-inventory.md` — the inventory for other databases and the seam above `myx_*`.
