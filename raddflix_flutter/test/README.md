# RaddFlix Test Suite

Standard Flutter `test/` layout, added as part of Phase H (Testing Infrastructure)
of `agent-hub/TEN_POINT_PLAN.md`. This directory is separate from the older, smaller
`test_suite/` (custom JS + Dart scripts) at the repo root, which remains in place.

```
test/
  unit/
    db/         - LocalDb method tests (H2)
    providers/  - Riverpod notifier tests (H3)
    services/   - service-layer tests
  widget/
    design_system/ - RaddButton, RaddTextField, RaddSheet, RaddCard, RaddChip (H4)
    screens/        - screen-level widget tests
  integration/      - end-to-end flows
```

No Flutter SDK is available in this Replit environment (Dart-Tools module only), so these
tests cannot be run or verified locally — they run in CI via `flutter test` once added there,
or on a real device/machine with the Flutter SDK installed. Write tests carefully and keep them
self-contained; do not assume they have been executed just because they were added.
