<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# ADR-0057 — A memory guard for large result sets

- Status: Proposed (planned for 1.1.0)
- Date: 2026-11-22
- Deciders: Harald Lapp (project owner)

## Context

Like the original, QueryMole loads every row of a result into memory, and there is no query timeout (wanted, ADR-0043).
Measured: about 1 KB per row (the backend's rows with a structure per field, plus the grid's node per row), so 2
million rows are about 2 GB. A query without a filter on a table of tens of millions of rows ends in swapping or the
operating system's out-of-memory killer; the whole machine can become unusable. Stop works, but only if the user
notices in time.

The backend has a limit that the program does not use: `myx_mysql_limit_resultset_size` sets
`resultset_memory_limit` (in MB), and `myx_query_execute` ends the fetch with `MYX_MEMORY_LIMIT_EXCEEDED` when
`memory_used` passes it. That is a hard stop without a question, counts only the field values and the row array (not the
grid), and has no option in the user interface.

The result grid updates at most every 150 ms while rows are fetched (2026-11-22), so a check at each progress callback
is cheap.

## Decision

1. **Pause and ask, never cut off silently.** While rows are fetched, the program compares its memory use with a
   threshold. When it is passed, the fetch pauses and a message asks: "N rows (X MB) have been loaded so far. The
   computer has Y MB of free memory. Continue loading?" with **Continue** and **Stop**. Stop is the existing Stop
   (ADR-0020): the rows loaded so far stay, the status line says the result is incomplete. Continue loads on; the next
   question comes when the use has doubled.
2. **The threshold follows the machine, not a fixed number.** Default: the program's use of memory for result sets
   passes half of the memory that was available when the query started (`MemAvailable` in `/proc/meminfo` on Linux,
   `GlobalMemoryStatusEx` on Windows), but at least 512 MB. The estimate is the backend's `memory_used` plus a constant
   per row for the grid (measured, in a named constant).
3. **An option on the Browser options page** switches the guard off and sets a fixed limit in MB instead of the
   automatic one. The option is stored in the options file as a new entry that 1.0.x ignores and keeps (ADR-0055).
4. **Mechanism.** The backend's progress callback already runs every 10 KB; the program's `progress_row_fetch` checks
   the estimate there. The fetch thread waits on an event while the main thread shows the question; the lock
   discipline is the one of Stop (no LCL access from the thread, `Synchronize` only). `myx_mysql_limit_resultset_size`
   stays unused.
5. **No automatic `LIMIT`, no paging.** The SQL the user sees and runs is not changed. Fetching on demand while
   scrolling is a separate, larger question (ROADMAP, "Large result sets").

## Consequences

- A query that would have taken the machine down pauses instead; the user decides. Nothing is lost that fitted before.
- A guard that is **on by default** is a deviation from ADR-0047's "off by default". It is proposed because it only
  acts where the machine would otherwise run out of memory; for every result that fits comfortably, nothing changes.
  The owner decides this (open question 1).
- Result sets that are slow to fetch (a server that sends 100 rows per second) are not affected: the guard counts
  memory, not time.
- The estimate for the grid is a measured average, not exact; very wide rows (BLOB, long text) are covered by the
  backend's `memory_used`, which counts the field values.
- Windows needs a check by hand (`GlobalMemoryStatusEx`), as with other platform code.

## Open questions

1. On by default (recommended) or off by default as ADR-0047 asks?
2. Wording of the question, in the style of the original's dialogs (to be mocked up before building).
3. Whether the threshold should also consider the swap, since a machine with a large swap file hangs before it runs
   out of memory.

## Alternatives

- **Compress the rows in memory.** The data compresses well, but the per-field and per-node overhead stays, every
  access (paint, sort, search, edit, export) must unpack, and the backend works on the row pointers directly. Less
  memory per row (compact field structures, shared buffers) is worth doing on its own and moves the limit; it does not
  remove it, so the guard is still needed.
- **The backend's hard limit.** Exists, but cuts off without a question and ignores the grid.
- **An automatic `LIMIT` on double click** (as Workbench, DBeaver): changes the SQL the user expects.
- **Fetching on demand while scrolling:** `LIMIT/OFFSET` is slow at deep offsets and inconsistent when data changes;
  keyset paging needs a primary key; a streaming cursor blocks the connection; sorting, searching and editing assume
  all rows are loaded. Possible later, a different decision.

## Related

ADR-0020 (Stop), ADR-0043 (no query timeout), ADR-0047 (features after parity), ADR-0055 (1.1.0 is a minor release),
ROADMAP ("Large result sets").
