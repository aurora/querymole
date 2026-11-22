<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# ADR-0056 — The connection uses utf8mb4

- Status: Accepted
- Date: 2026-11-22
- Deciders: Harald Lapp (project owner)

## Context

The original connects with the character set `utf8`, which was the only UTF-8 the servers of its time had. On
current servers `utf8` is an alias for `utf8mb3`: it has no 4-byte characters. Emoji and other characters above
U+FFFF written in the editor reached the server as `?`, and values already stored in `utf8mb4` columns came back
as `?` as well. Nothing in the user interface hints at it (found 2026-11-20 while reviewing the exporters,
`docs/export-review.md`).

The supported servers (MySQL 5.7 to 9, MariaDB 10.11 and later, ADR-0004) all have `utf8mb4`.

## Decision

- The backend connects with `MYSQL_SET_CHARSET_NAME` `utf8mb4` and sends `SET NAMES utf8mb4` after connecting
  (`myx_library.c`). If a server rejects it (before MySQL 5.5.3), the old `SET NAMES utf8` is used.
- After saving a BLOB edit the connection is put back with `SET NAMES utf8mb4` (it was `SET CHARACTER SET utf8`).
- The names `utf8mb3` and `utf8mb4` are known to the character set conversion (`myx_util_functions.c`) and to the
  column check of the result set editor (`myx_recordset.c`) as UTF-8.
- Everything the program shows and exports stays UTF-8 as before.

## Consequences

- Characters above U+FFFF survive the round trip: `tests/test_connect.pas` (`TestFourByteCharactersSurvive`) sends
  U+1F600 and expects it back and counted as one character.
- `character_set_connection` and `character_set_results` are `utf8mb4`. A server with a collation default that
  differs (e.g. MariaDB's `utf8mb4_uca1400_ai_ci`) now applies to comparisons of literals in the editor, as it does in
  the other clients.
- Files an older release wrote stay readable; nothing is stored differently.

## Alternatives

- **Keep `utf8`**: loses data silently on current servers.
- **A connection option**: another setting for something nobody wants off.

## Related

ADR-0004 (supported servers), ADR-0001 (the original's behaviour; this fixes a loss, it adds nothing visible).
