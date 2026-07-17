---
name: ImageProvider type inference
description: Dart cannot infer ImageProvider<Object>? from a nested ternary that returns FileImage vs MemoryImage.
---

## Rule
When a variable must be typed as `ImageProvider?` and its value comes from either `FileImage` or `MemoryImage`, use an explicit if/else block rather than a nested ternary.

## Why
Dart's type inference fails when a ternary's branches return different concrete subtypes of the same abstract type. The inferred type becomes `Object?` which is unassignable to `ImageProvider<Object>?`.

## How to apply
```dart
// WRONG — Dart infers Object? not ImageProvider?
final ImageProvider? coverArt = _file != null ? FileImage(_file!) : _bytes != null ? MemoryImage(_bytes!) : null;

// CORRECT — explicit block, Dart infers correctly
ImageProvider? coverArt;
if (_file != null) {
  coverArt = FileImage(_file!);
} else if (_bytes != null) {
  coverArt = MemoryImage(_bytes!);
}
```
This pattern applies anywhere you conditionally pick between two different `ImageProvider` subtypes.
