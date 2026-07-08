---
name: RaddSheet bounded-height for Expanded children
description: Why panels with Column+Expanded (sliders, ListViews, ReorderableListView) work inside RaddSheet.show(style: list) without extra SizedBox/height wrappers.
---

`RaddSheet` constrains its whole body with `ConstrainedBox(maxHeight: fraction * screenHeight)`, then places
the list/tabbed body in `Flexible` + `Padding(all: RaddSpace.md)`. That means any widget passed via
`listBuilder` receives a **finite** max-height constraint, not an unbounded one.

**Why it matters:** a `Column` with `mainAxisSize: MainAxisSize.max` (Flutter's default) inside that finite
constraint will size itself to the full available height, so `Expanded` children inside it (vertical EQ
sliders, `ListView`, `GridView`, `ReorderableListView`) resolve correctly — no "RenderFlex children have
non-zero flex but incoming height constraints are unbounded" errors, and no extra `SizedBox`/fixed-height
wrapper is needed when migrating a panel to `RaddSheet.show`.

**How to apply:** when migrating a legacy full-screen/side panel with `Expanded` to `RaddSheet.show(style: list, ...)`,
just strip the panel's own header (title + back button — RaddSheet already renders these) and drop the panel's
root `Column` straight into `listBuilder`. No layout rework needed for the `Expanded` usage itself.
