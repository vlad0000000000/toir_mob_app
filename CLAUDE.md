# CLAUDE.md

Guidance for Claude Code when working in `sampo_smart_mobile` — the Flutter app
(package `qr_scan_industry`) of the Sampo Smart / ТОиР system.

## Flutter project context

For every task involving this application, load and follow the
`flutter-project-context` skill before planning or editing.

Use the skill as the index of project architecture, functionality, code
conventions, and UX/UI patterns. Read only the reference files relevant to the
task, then verify the current implementation in the repository.

When a completed task intentionally changes stable project knowledge, update the
affected skill references (see `references/maintenance-guide.md`).

Skill location: `.claude/skills/flutter-project-context/`

## Non-negotiables

These break user data or the build if ignored. Full detail lives in the skill.

- **`.env` in the project root is mandatory** — read both by Dart
  (`lib/main.dart`) and by Gradle (`android/app/build.gradle`, at configuration
  time). Without it, and without the keystore it references, even a debug build
  fails. Values must not be quoted.
- **Hive adapters are hand-written, no codegen.** `read()` must mirror `write()`
  field-for-field. Add new fields only at the end, guarded by `try/catch` on
  read — **and only to a top-level object**, one stored in a box on its own. A
  nested object (`PeriodicTask` inside `Task`, `RepairPhoto` inside `Repair`)
  shares the parent's byte stream: the extra `read()` never hits end-of-record,
  it swallows the parent's next field, `Hive.openBox` then throws while parsing,
  and the app hangs on the splash screen forever. Never change an existing
  field's type. Never reuse a `typeId`.
- **The Hive storage path no longer depends on the app version** — it is an md5
  of appName|packageName, computed by `HiveStorageLocation.resolve`. Do not put
  the version back into it: that is what used to wipe unsent inspections on
  every release.
- **Do not run `build_runner`** — it would overwrite the hand-written adapters.
- **Do not run `dart format` over the whole project** — 38 of 95 files are
  currently unformatted. Format only the files you touch.

## Commands

```bash
flutter pub get
flutter analyze     # baseline: exactly 1 warning; a 2nd is your regression
flutter test        # baseline: green, 22 tests
flutter run -d <device>
```

`flutter test` is green and must stay green. Three suites so far:
`test/feature_flags_test.dart` (PPR feature flag),
`test/scan_error_messages_test.dart` (how the inspection outbox classifies a
failure — retry, reject, or treat as already delivered) and
`test/repair_clipboard_test.dart` (the shared repair-to-clipboard format used by
both the draft card and the conflict screen). The old empty commented-out
`widget_test.dart` template was removed; it had no `main()` and made the whole
run fail.
