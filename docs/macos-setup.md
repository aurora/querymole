<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# macOS (Apple Silicon): first build, checklist

**Deferred (ADR-0039):** no macOS release and no layout work until the widgetset decision of the Qt move
(ADR-0024). This file records where the work stopped.

Status: **first build done** (2026-11-17, macOS 26.4 on Apple Silicon, Apple clang 21, Homebrew glib
2.90 / libxml2 2.15 / pcre 8.45 / Connector/C 3.4.11, FPC 3.2.4rc1, Lazarus 4.8): the backend and
`app/bin/querymole` build, the program starts and `--shot-connect` writes the connect dialog (again on
2026-11-23, after the SSH tunnel's libraries were added, see section 6). A Qt6 build works as well and lays the
dialogs out completely, unlike Cocoa (section 7). Steps 4.3
and later have not been tried. Findings are under "State" at the end. This is the list of steps for a
Mac with an M processor, and of the places where `build.sh` and the backend needed changes.
Write down what you find in `docs/linux-port.md` style (state and open problems), and write an ADR
(see ADR-0027 for the Linux counterpart) once the widgetset and the packaging are decided.

## 1. Tools

`tools/macos-setup.sh` installs the Homebrew packages and checks everything below (`--check` only
checks). By hand:

```bash
xcode-select --install                       # compiler, make, git, SDK
brew install cmake ninja pkgconf python@3 glib libxml2 pcre mariadb-connector-c libssh mingw-w64
```

- `mingw-w64` brings `x86_64-w64-mingw32-windres` for `tools/build_resources.py` (the `.res` files are
  platform neutral, as on Linux). `iconv` comes with the SDK.
- No container: a container on a Mac is a Linux VM and can only build the Linux program (x86_64 under
  emulation on Apple Silicon). A macOS build needs the macOS SDK and the Cocoa LCL on the host. Podman
  (`podman machine`) is still useful for the test servers of `tests/run-matrix.sh`.

- `pcre` is PCRE1 (`pkg_check_modules(PCRE ... libpcre)` in `backend/CMakeLists.txt`). Homebrew has
  deprecated that formula; if it is gone, either build PCRE 8.45 from source into a prefix or move
  the backend to PCRE2 (a separate change with its own ADR, ADR-0003 territory).
- Check `pkg-config --modversion glib-2.0 gthread-2.0 libxml-2.0 libpcre libmariadb`; all five must
  answer. Homebrew installs on arm64 under `/opt/homebrew`; add
  `export PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:/opt/homebrew/opt/libxml2/lib/pkgconfig:/opt/homebrew/opt/mariadb-connector-c/lib/pkgconfig`
  if a `.pc` file is not found.

## 2. Free Pascal and Lazarus

- Lazarus 4.8 for macOS aarch64 from
  <https://sourceforge.net/projects/lazarus/files/Lazarus%20macOS%20aarch64/>: two files. The `.dmg`
  holds the FPC package (3.2.4rc1, installs to `/usr/local/bin` and `/usr/local/lib/fpc`); the zip holds
  Lazarus **and the FPC sources** (`lazarus/fpc/3.2.4/sources`, already set in its
  `config/environmentoptions.xml`). Install the FPC package first, then
  `xattr -cr ~/Downloads/lazarus && mv ~/Downloads/lazarus /Applications/Lazarus` (without `xattr`
  Gatekeeper blocks `lazbuild`). The Lazarus folder is self-contained (`lazarus.cfg`: `--pcp=config`).
  The Homebrew cask `lazarus` is disabled. Check `fpc -iTP -iTO` prints `aarch64 darwin`.
- `tools/winapi_usage.py` needs `FPCSRC=/Applications/Lazarus/fpc/3.2.4/sources
  LAZARUSDIR=/Applications/Lazarus`.
- FPC 3.2.2 is the weak point on arm64: if it fails on the project, use FPC 3.2.3 (fixes branch) or
  3.3.1, the same family as in the Linux distrobox (3.2.3).
- Widgetset **cocoa** (`lazbuild --ws=cocoa`). GTK2/Qt from Homebrew are not an option for a Mac
  program (ADR-0024 lists GTK2 only for the first Linux release).

## 3. Backend

```bash
./build.sh --backend --runtime       # backend into backend/build-macos, resources, runtime files, application
```

or by hand (`build.sh` sets `PKG_CONFIG_PATH` for the keg-only Homebrew formulae):

```bash
cmake -S backend -B backend/build-macos -G Ninja
cmake --build backend/build-macos
```

Expect problems in `backend/compat` (shim headers) and in the old C code (ADR-0003: undefined
behaviour that a newer clang rejects or exposes). The link line for Windows adds `ws2_32` etc.; check
that nothing Linux- or Windows-only is missing for `APPLE`.

## 4. Application

`build.sh` builds on macOS with `--ws=cocoa`, links against `backend/build-macos` and gives the
program that folder as rpath (the backend's dylibs are named `@rpath/lib*.dylib`), so
`app/bin/querymole` starts without `DYLD_LIBRARY_PATH`. `LAZARUS_DIR`, `HOMEBREW_PREFIX` and
`QBR_FPC_OPTS` (extra compiler options) adjust it; see the script header and section 6 for the linker
options it sets. The program is a bare
executable, not yet a `.app` bundle (`UseAppBundle` is off in `qbr.lpi`); whether Cocoa runs it
properly that way is one of the things to find out.

Then, in this order (stop at the first failure and record it):

1. Does `qbr.lpi` compile? Windows-only code outside `{$IFDEF MSWINDOWS}` shows up here;
   `python3 tools/winapi_usage.py --where` lists it (needs the FPC/Lazarus sources).
2. Does it start? `--shot-connect out.png` (a timeout around everything, see AGENTS.md).
3. `--selftest-connect` against a server (`tests/run-matrix.sh` needs podman; a local MariaDB is enough
   for a first run).
4. The ported controls: `laz.VirtualTrees`, the SQL editor (SynEdit) and the result grid are less
   tested on Cocoa; check painting, selection, copy/paste, the menu bar (Cocoa uses the global
   menu) and HiDPI (ADR-0009, ADR-0023 is GTK only).
5. Fonts: ADR-0028 (bundled Tahoma substitute outside Windows) applies; check that it loads.

## 5. Open decisions

- **Architecture:** arm64 first. Intel (x86_64) only on demand, as a second build, not a Universal
  binary (it would need all Homebrew libraries as Universal).
- **Libraries in the bundle:** the `.app` must carry the Homebrew dylibs (`dylibbundler` or
  `install_name_tool`), otherwise it runs only on the build machine. That includes OpenSSL's libcrypto: libssh and
  libmariadb link it by its Homebrew path, so a bundler copies it along into `Contents/Frameworks`. The PuTTY key
  reader (`OpenSSLCrypto.pas`) opens it itself at run time and today knows only the Homebrew paths; it must try the
  bundle's copy first (next to the executable, `../Frameworks/libcrypto.4.dylib`), so that the one copy libssh
  loaded is used. Homebrew's bottles are built for the macOS they run on (26 here); a bundle that should run on
  older versions needs the libraries built with a lower `MACOSX_DEPLOYMENT_TARGET`, as Linux builds its own on
  AlmaLinux 9 (ADR-0027).
- **Packaging:** `.app` inside a `.dmg`. Signing and notarisation need an Apple Developer account;
  without them users must remove the quarantine flag (`xattr -dr com.apple.quarantine QueryMole.app`),
  which belongs in the release notes for an alpha.
- **Password storage:** ADR-0021 defers the Keychain; nothing to do for the first build.
- **Updates:** none in the alpha (ADR-0026); Velopack for macOS is a later question (ADR-0014).

## 6. State (first build)

What had to change:

- **Backend:** clang rejects a string literal directly followed by a macro in C++11 (`"...("RE_NAME")"`,
  read as a user-defined literal suffix; GCC only warns). Fixed in `myx_query.cpp` with spaces. Otherwise
  only warnings (deprecated glib functions, `register`, `sprintf`).
- **Linking the backend:** FPC on Darwin ignores the library named in `external 'libfoo.dylib'`
  (`timportlibdarwin.generatelib` is empty), so nothing from the backend was linked. The bindings now add
  `{$LINKLIB ...}` under `{$IFDEF DARWIN}` (`tools/gen_bindings.py`, `myx_types.pas` for glib).
  `build.sh` adds `-Fl$BREW/lib` for glib and passes Homebrew's `libxml2.dylib` by path for
  `xmlInitParser` in `qbr.lpr` (`-lxml2` would find the SDK's libxml2 first, a second copy next to the
  backend's).
- **Linker:** Apple's current `ld` rejects the Objective-C method lists FPC 3.2.4 writes ("malformed method
  list atom ... cocoawsextctrls.o"); `build.sh` passes `-k-ld_classic`. That linker is deprecated; when it
  is gone, a newer FPC (3.3.1) is the way out. Warnings that the dylibs are built for macOS 26 while the
  program targets 11.0 remain (harmless on the build machine, relevant for a release build).
- **Pascal:** `TThread.Handle` is a `TThreadID` (a pointer on macOS), not a `THandle` (32 bits outside
  Windows): `ConnectToInstance.pas`.
- **Screenshots** (`DevTools.CaptureWindowToPng`): copying the screen area shows whatever window is in
  front (a program started from a terminal does not come to the front); on macOS the form's `PaintTo`
  is used instead.
- **SSH tunnel** (ADR-0048, checked 2026-11-23): the build broke at the link step because `LibSSH.pas` had the
  same `external` problem; it now adds `{$LINKLIB ssh}` under `{$IFDEF DARWIN}` (Homebrew's libssh 0.12.2, in
  `tools/macos-setup.sh`). `OpenSSLCrypto.pas` loads libcrypto at run time: macOS's `dlopen` does not search
  Homebrew's folders for a bare name, nor match it to the copy libssh already loaded, so it names the
  `openssl@4`/`openssl@3` kegs by path. `TCryptoTest` passes (the test runner builds with
  `-Flbackend/build-macos -Fl/opt/homebrew/lib -k-rpath -k<checkout>/backend/build-macos` and the fcl-fpcunit
  path `/usr/local/lib/fpc/3.2.4/units/aarch64-darwin/fcl-fpcunit`). The tunnel itself was not tried.
- The backend libraries still carry the absolute build folder as run path on macOS; `CMAKE_BUILD_RPATH_USE_ORIGIN`
  (`backend/CMakeLists.txt`) has no effect there. Harmless for a build in the checkout, to fix for a bundle.
- macOS has no `timeout` (AGENTS.md, `tests/run-matrix.sh`): `perl -e 'alarm 60; exec @ARGV' ...` works
  for now; Homebrew `coreutils` has `gtimeout`.

Seen in the first screenshot of the connect dialog, not investigated yet: the password row is cut off at
the bottom of the group box, and the button next to "Stored Connection" shows "," instead of "...".

## 7. Cocoa and Qt6 compared (2026-11-23)

The comparison ADR-0044 asks for, on the same Mac. Qt6 build:

```bash
brew install qtbase                                   # Qt 6.12; gui and printsupport are all Qt6Pas needs
mkdir -p tools/cache/qt6pas                           # git-ignored
cp -R /Applications/Lazarus/lcl/interfaces/qt6/cbindings/ tools/cache/qt6pas/src
(cd tools/cache/qt6pas/src && /opt/homebrew/bin/qmake6 Qt6Pas.pro && make -j10)   # Qt6Pas.framework
install_name_tool -id @rpath/Qt6Pas.framework/Versions/6/Qt6Pas tools/cache/qt6pas/src/Qt6Pas.framework/Versions/6/Qt6Pas
codesign --force -s - tools/cache/qt6pas/src/Qt6Pas.framework/Versions/6/Qt6Pas
QBR_WIDGETSET=qt6 QBR_FPC_OPTS="-Ff$PWD/tools/cache/qt6pas/src -k-rpath -k$PWD/tools/cache/qt6pas/src" ./build.sh
```

The binding is version 6.2.10 (Lazarus 4.8) against Qt 6.12; qmake only notes the difference. The program built
without any code change (the LCL links `Qt6Pas` as a framework on Darwin), starts and shows its dialogs; it logs
`QObject::disconnect: No such slot QComboBox::_q_returnPressed()` (Qt 6.12 dropped that private slot; seen to be
harmless so far). Units go to `app/lib/aarch64-darwin-qt6`, next to the Cocoa ones; `app/bin/querymole` is the last
build.

Result, connect and options dialog side by side: under **Qt6 both are complete** (the password row and the "..."
button of the connect dialog, every row of the options' General page, group captions above their frames as on
Linux), with the Fusion style and the layout fixes made for Linux (ADR-0044, ADR-0045). Under **Cocoa** the same
pages are cut off and overlapped (rows outside their group boxes, native controls taller than the original's).
Not compared yet: the main window, menus (Qt on macOS also uses the global menu bar), HiDPI, interaction.
