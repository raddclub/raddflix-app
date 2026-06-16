---
name: Dart inline comment semicolon placement
description: Semicolons must precede inline comments in Dart — common mistake when editing
---

## The rule
In Dart, semicolons MUST appear BEFORE any inline `//` comment. Placing the `;` after the comment causes a parse error: `Error: Expected ';' after this`.

**WRONG:**
```dart
: Uri.decodeFull(expr) // FIX comment;
```
**RIGHT:**
```dart
: Uri.decodeFull(expr); // FIX comment
```

**Why:** This caused a broken APK build in TASK-057. A code-gen script placed the `;` after the comment. The Dart compiler sees the `//` comment as consuming the rest of the line, so the `;` terminator for the statement is missing. The compiler reports "Expected ';' after this" pointing to the last token before the comment.

**How to apply:** When editing any Dart line that ends with both a `;` and a `// comment`, always ensure the `;` terminates the statement BEFORE the `//` starts. When generating Dart source programmatically (Node.js templates, Python scripts), never place `;` after a comment token.

**Test:** The error only surfaces at build time (`dart compile` / `flutter build`), not in the editor. Always re-trigger the APK build after multi-file patches.
