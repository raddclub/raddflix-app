---
name: LocalDb platform-channel testability
description: LocalDb uses Android Keystore platform channel — headless flutter test cannot run it; DI seam or integration test required; never ship fake tests
---

## Rule

`LocalDb` opens its encrypted SQLite database using `sqflite_sqlcipher`, which requires the
Android Keystore platform channel to decrypt the database key. `flutter test` runs in a headless
Dart VM with **no platform channel support**. Any test that directly constructs or calls `LocalDb`
will either throw a `MissingPluginException` at runtime or require mocking so thoroughly that the
test proves nothing about the real implementation.

**Why:** This was the root blocker for Phase H items H2 (LocalDb unit tests) and H3 (provider
unit tests). Rather than shipping fake pass-through tests just to tick a checklist item, both
tasks were marked BLOCKED and the root cause documented here.

**How to apply:** Before writing any `flutter test` that touches `LocalDb` or any provider that
depends on it, choose one of these two legitimate paths:

### Path A — DI seam (preferred for unit tests)
1. Extract an interface: `abstract class LocalDbInterface { ... }` covering the methods you need
   to test against.
2. Make `LocalDb` implement `LocalDbInterface`.
3. Create `FakeLocalDb implements LocalDbInterface` in `test/fakes/` — an in-memory implementation
   with no platform channel dependency (plain Dart `Map` or `List` storage is fine).
4. Inject `LocalDbInterface` into providers/services instead of the concrete `LocalDb` class.
5. Tests can now pass `FakeLocalDb` without needing any platform channel.

This is a deliberate refactor, not a quick fix. Scope it explicitly before starting, and get
user sign-off if it touches the provider layer broadly.

### Path B — Flutter integration tests (required for platform-channel code itself)
Run tests with `flutter test integration_test/` on a real Android device or emulator where
platform channels are supported. This requires a CI runner configured with an Android emulator
(the current headless CI setup does not have one). Do not attempt this path without first
verifying the CI runner supports it.

## What NOT to do

- **Do not write a test that `try/catch`-es the `MissingPluginException` and passes anyway.**
  That test proves nothing and creates false confidence.
- **Do not mock `LocalDb` at the class level** (e.g. `when(mockDb.getMovie(id)).thenReturn(...)`)
  if the mock is injected through a side-channel (static setter, global var swap) — this is
  fragile and violates the DI principle. Use a proper interface injection.
- **Do not mark H2/H3 as ✅ DONE** without implementing one of the two paths above and having CI
  actually run the tests successfully.

## Current status (2026-07-12)
H2 and H3 are BLOCKED. H1/H4/H5 are done. The decision on which path to take (A or B) has not
been made — it requires a deliberate choice by the user/team, as Path A is a refactor that
touches the provider layer and Path B requires CI infrastructure changes.
