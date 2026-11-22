<p align="center">
  <img src="app/images/about.png" alt="QueryMole: Explore. Query. Understand." width="666">
</p>

<p align="center">
  <b>The classic MySQL Query Browser, revived for current MySQL and MariaDB.</b><br>
  Windows · Linux · (macOS later)
</p>

<p align="center">
  <img alt="Status: beta" src="https://img.shields.io/badge/status-beta-yellow">
  <img alt="Version 1.0.0-beta.2" src="https://img.shields.io/badge/version-1.0.0--beta.2-blue">
  <img alt="Licence: GPL-2.0-or-later" src="https://img.shields.io/badge/licence-GPL--2.0--or--later-green">
  <img alt="Free Pascal / Lazarus" src="https://img.shields.io/badge/built%20with-Free%20Pascal%20%2F%20Lazarus-informational">
</p>

---

**QueryMole** brings back the **MySQL Query Browser** (2006): the original Windows user interface, rebuilt with
Free Pascal and Lazarus so that it runs on Windows and Linux, against MySQL 5.7 to 9 and MariaDB 10.11 and 11.4.
The look and behaviour are those of the original (ADR-0001); new features are added on top, off by default (ADR-0047).

> [!WARNING]
> **Beta of 1.0.0.** All functions of the original work, and the features are complete for 1.0.0 (ADR-0055); what is
> left is testing and fixing. Expect faults (see [Known problems](#known-problems)), use a test account or a test
> server for anything important, and keep your own backups.

> [!NOTE]
> QueryMole is not affiliated with or endorsed by Oracle. "MySQL" is a trademark of Oracle and names only the
> product this project is based on (ADR-0030).

## Contents

- [Features](#features)
- [Download and run](#download-and-run)
- [Known problems](#known-problems)
- [Reporting problems](#reporting-problems)
- [Building from source](#building-from-source)
- [How it is made](#how-it-is-made)
- [Repository layout](#repository-layout)
- [Licence](#licence)

## Features

Checked against **MySQL 5.7, 8.0, 8.4, 9** and **MariaDB 10.11, 11.4**: an automated test suite and the
application's self-tests run against all six servers in throw-away containers.

| Area | What works |
|---|---|
| **Connecting** | connect dialog with stored connections, in groups; TLS "preferred" with fallback to an unencrypted connection; SSH tunnel with OpenSSH or PuTTY keys, ssh-agent, Pageant or a password (ADR-0048); a "Test" button in the connection manager (ADR-0051); Cancel at start opens the program without a connection (ADR-0052) |
| **Browsing** | schema tree with search |
| **Querying** | SQL editor with highlighting, several result tabs, EXPLAIN, stopping a running query on the server |
| **Results** | result grid with editing (apply and discard) |
| **Scripts** | scripts with breakpoints |
| **Tables** | table editor that keeps tables intact on current servers; data types and storage engines follow the server (ADR-0034) |
| **Export** | CSV (with settings for separator, header, quoting, line ending), TSV, JSON, JSON Lines, HTML, XML, Excel and PLIST (ADR-0049, ADR-0050) |
| **Help** | help panel whose SQL reference comes from the connected server |
| **More** | options dialog, text search, regular expression importer |
| **Updates** | Windows (installer) and the Linux AppImage update themselves: Help > Check for Updates, or on request at every start (ADR-0037, ADR-0052) |

## Download and run

Releases are published on GitHub: **<https://github.com/aurora/querymole/releases>**. Until 1.0.0 they are
pre-releases (betas and release candidates of 1.0.0, ADR-0055).

<table>
<tr><th>Platform</th><th>How</th></tr>
<tr><td><b>Windows</b><br>64 bit</td><td>

Run `QueryMole-win-Setup.exe`: it installs for the current user (no administrator rights) into
`%LOCALAPPDATA%\QueryMole` and updates itself. The installer is not signed yet, so Windows SmartScreen may warn ("More
info", then "Run anyway"). There is also a portable zip: unpack it and run `querymole.exe`; it does not update itself.

Settings and connections are kept in `%APPDATA%\QueryMole\`. On the first start, the settings of the original MySQL
Query Browser are copied from `%APPDATA%\MySQL\` (that folder is left as it is).

</td></tr>
<tr><td><b>Linux</b><br>x86_64</td><td>

```bash
chmod +x QueryMole-*.AppImage
./QueryMole-*.AppImage
```

The AppImage brings Qt 6 and the other libraries it needs and runs on distributions with **glibc 2.34 or newer**
(RHEL 9, Ubuntu 22.04, Debian 12, Fedora 35 and newer). It takes libstdc++, OpenGL (libglvnd) and the font libraries
(fontconfig, freetype, harfbuzz) from the system, which every desktop has, and runs on Wayland and on X11. Without
FUSE 2 on the system, start it with `--appimage-extract-and-run`.

Settings are kept in `~/.config/querymole/` (`$XDG_CONFIG_HOME`); on the first start, those of the original Linux
version are copied from `~/.mysqlgui/`. `QueryMole.AppImage` updates itself in place (ADR-0037); the AppImage with
the version in its name has no updater. Keep it in a folder you can write to (for example `~/Applications`).

</td></tr>
<tr><td><b>macOS</b></td><td>Not yet. A first build runs but needs layout work; macOS follows with the move to Qt (ADR-0039, <a href="docs/macos-setup.md">docs/macos-setup.md</a>).</td></tr>
</table>

## Known problems

- **Linux, earlier GTK2 versions (up to 0.1.0-alpha.5):** a crash after connecting was seen once (heap corruption),
  and the window froze once while scrolling the schema tree of a database with many tables. Neither has been
  reproduced, nor seen with Qt 6; if it happens to you, see [Reporting problems](#reporting-problems).
- **Linux on Wayland:** started from a terminal, the program prints messages from the Qt toolkit about combo boxes and
  mouse grabbing; they are harmless. If dragging (splitters, column widths, drag and drop) misbehaves, start it with
  `QT_QPA_PLATFORM=xcb` (XWayland) and tell us.
- **Not worked through on a desktop yet:** real mouse and keyboard use, drag and drop, bookmarks and history, the
  field viewer; the checklist is in [docs/linux-manual-test.md](docs/linux-manual-test.md).
- **Table editor:** generated columns, `ON UPDATE`, `INVISIBLE` and CHECK constraints are kept when a table is
  edited, but not shown or editable yet (ADR-0035).
- **Linux on a scaled (HiDPI) desktop:** the layouts are in pixels for 96 dpi; Qt scales the whole window with the
  desktop's scale factor. Real HiDPI support comes later (ADR-0009).
- **Linux:** no "OS specific" password storage, only "Plaintext" and "Obscured" (ADR-0021); no global hot keys
  (ADR-0022). From 0.1.0-alpha.6 on the Linux version uses Qt 6 with Qt's Fusion style instead of GTK2 (ADR-0044,
  ADR-0045): it looks the same on every desktop and does not follow the desktop's theme or dark mode.
- **Windows:** the installer is not signed yet (SmartScreen warns once). SSH with Pageant and PuTTY keys has been
  tested less on Windows than on Linux.
- The user interface is the original's, including its look and its English texts; some parts look different
  under Qt on Linux than on Windows.

Details and the state of the Linux port: [docs/linux-port.md](docs/linux-port.md).

## Reporting problems

Please open an issue at **<https://github.com/aurora/querymole/issues>** with:

- the version (Help > About), the operating system and, on Linux, the desktop;
- the server and its version;
- what you did in the last seconds before the problem;
- if the program ended: the file `querymole.error.txt` next to the program, if there is one, and, if you can, a run with
  `QBR_TRACE=1` (this writes `qbr.trace.txt` next to the program).

## Building from source

The full instructions are in [AGENTS.md](AGENTS.md) ("Toolchain" and "Everyday commands"). In short:

- **Windows:** Lazarus 4.8 / FPC 3.2.2, MSYS2 with the mingw64 toolchain, Python 3.
- **Linux:** the Fedora distrobox created by `tools/distrobox-setup.sh` (Lazarus, FPC, the backend libraries,
  Python), entered with `distrobox enter freepascal`.

```bash
git submodule update --init      # once, for third_party/velopack-pas
./build.sh --backend --runtime   # C backend, application, data files next to the program
./build.sh --run                 # build and start
tests/run-matrix.sh              # test suite against all six servers (Linux; needs podman)
```

Packages: `tools/package.sh` (Windows zip) and `tools/package-appimage.sh [--velopack]` (Linux AppImage).

## How it is made

QueryMole is a port of the original sources, which are kept unchanged in `legacy/`: the C libraries are built
again with CMake, the Delphi user interface is converted to Lazarus forms and ported unit by unit. It is done by
Harald Lapp **with the help of Claude Code** (Anthropic), an AI coding assistant, which wrote and changed a large
part of the code and documentation under the owner's direction.

- Decisions: [docs/adr/](docs/adr/README.md) (Architecture Decision Records; they are binding)
- Plan and backlog: [ROADMAP.md](ROADMAP.md)
- The original authors are credited in the About dialog.

A thin database-driver interface is planned so that other databases (e.g. PostgreSQL) can follow later
(ADR-0010).

## Repository layout

| Directory | Purpose |
|---|---|
| `legacy/` | original sources (GPL), kept unchanged as reference |
| `backend/` | CMake build of the C libraries of the original Query Browser |
| `bindings/` | Pascal bindings for the backend (mostly generated) |
| `app/` | the Lazarus / Free Pascal application (ported from the Delphi UI) |
| `tests/` | FPCUnit tests that run against real servers |
| `tools/` | generators, form converter, packaging and analysis scripts |
| `assets/` | QueryMole artwork |
| `third_party/` | the Velopack binding (git submodule) |
| `docs/` | decisions, porting notes, screenshots of the converted forms |

## Licence

GPL-2.0-or-later, like the original MySQL Query Browser; see [LICENSE](LICENSE) and [NOTICE](NOTICE) (inherited
PCRE exception, third-party components). "MySQL" is a trademark of Oracle; this project is not affiliated with it.
