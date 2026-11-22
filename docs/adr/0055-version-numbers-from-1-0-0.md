<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# ADR-0055 — Version numbers from 1.0.0 on

- Status: Proposed
- Date: 2026-11-22
- Deciders: Harald Lapp (project owner)

## Context

All releases so far are `0.1.0-alpha.N` (nine of them), GitHub pre-releases built from the `VERSION` file
(ADR-0014, ADR-0040). The update check offers pre-releases to a program that is a pre-release itself and only
releases to a release (ADR-0037); the update dialog lets the user change that (ADR-0052).

Functional parity is reached (ADR-0047), the program runs on Windows and Linux (macOS is deferred, ADR-0039), every
push is tested against six server versions (ADR-0046), and updates work. The owner wants a finished version before
other databases (ADR-0054) are added, and asked which number it should get: a final 0.1.0 or 1.0.0.

Under Semantic Versioning, which the version numbers follow, 0.x means "anything may change"; a final 0.1.0 would say
little. 1.0.0 is where a project starts promising compatibility, which ADR-0047 already practises for stored files.
What is not done: manual tests on Windows (Pageant, `.ppk` keys with OpenSSL 4, the exports, the update question at
start), the desktop checklist of ADR-0044 (`docs/linux-manual-test.md`), and no release carries the changes since
0.1.0-alpha.9.

## Decision

1. **The next release line is 1.0.0,** reached through pre-releases:
   - **`1.0.0-beta.N`**: feature freeze. From beta.1 on, `master` takes only fixes, documentation and tests for the
     1.0 line; features wait.
   - **`1.0.0-rc.N`**: release candidate, only fixes for faults that block the release.
   - **`1.0.0`**: the first release that is not a GitHub pre-release.
   A pre-release is cut when there is something to test; there is no fixed number of betas.
2. **Semantic Versioning from 1.0.0 on:**
   - **Patch** (1.0.x): fixes only, no new options, no change to stored files.
   - **Minor** (1.x.0): new features, each with its ADR and under ADR-0047's rules (additive, off by default, in the
     original's style); new server kinds (ADR-0054) and new platforms; new entries in stored files that earlier 1.x
     releases ignore and keep.
   - **Major** (2.0.0): what breaks users of 1.x: stored files that a 1.x release cannot read any more, a removed
     feature, a changed default that changes the behaviour of existing installations.
3. **Compatibility promise of 1.x:** the files the program keeps (stored connections, options, bookmarks, history,
   the settings of ADR-0052) written by any 1.x release are read by every other 1.x release, older ones keeping
   what they do not know (ADR-0047's rule, extended from "the previous release" to the whole major version). Server
   versions leave the supported list only when their vendor has ended support, announced in the release notes of
   the minor release before.
4. **Branches:** releases are cut from `master` as now. When fixes for a released version are needed while `master`
   already holds features for the next minor, a branch `release/1.0` is made from the release tag and the patch
   release is cut from it; the fixes go to `master` as well.
5. **Updates:** a 1.x release is offered releases only, unless the user turns on development versions in the update
   dialog (ADR-0037, ADR-0052); a pre-release is offered both. A user of 0.1.0-alpha.9 is offered 1.0.0-beta.1 and
   later 1.0.0, since both are newer.
6. **Release notes** stay one file per version in `docs/release-notes/`; a release's notes list what changed since
   the previous release (not since the previous pre-release), so 1.0.0's notes summarise the betas and candidates.
7. What is left for 1.0.0 and what moves after it is kept in `ROADMAP.md` ("Road to 1.0.0").

## Consequences

Positive:
- Users can tell finished releases from test versions, and know what a minor or patch update may change.
- The feature freeze gives the manual tests a stable target.
- Other databases, the modern icon set and further features have a place: minor releases after 1.0.0.

Negative:
- Features wait during the beta and candidate phase.
- The compatibility promise binds stored files for all of 1.x; a reorganisation of the settings needs 2.0.
- A patch release after a minor needs a release branch and fixes applied twice.
- 1.0.0 covers Windows and Linux only; macOS (ADR-0039) comes in a later minor release, or with its own decision.

## Alternatives considered

- **A final 0.1.0:** under Semantic Versioning still "unstable"; it would need its own rules for what 0.2 may
  break, and 1.0 would follow anyway.
- **1.0.0 directly after alpha.9, without betas:** the manual tests on Windows and the desktop checklist would happen
  on a version already called finished.
- **Calendar versions** (2026.12): no statement about compatibility; Velopack and the update rules work with
  Semantic Versioning already.

## Related

- ADR-0014 — packaging and the `VERSION` file; ADR-0040 — the release workflow (pre-release when the version has a
  pre-release part).
- ADR-0037, ADR-0052 — which releases the update check offers.
- ADR-0047 — parity reached, the rules for features after it, readable stored files.
- ADR-0054 — other MySQL-protocol servers, planned for a minor release after 1.0.0.
