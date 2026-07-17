---
name: flutter/services.dart import required
description: TextInputFormatter is not re-exported by material.dart in this project's Flutter SDK version; must be imported explicitly.
---

**Rule:** Any Dart file that defines a class extending `TextInputFormatter`, or declares `List<TextInputFormatter>` fields, must add:
```dart
import 'package:flutter/services.dart';
```

**Why:** `material.dart` does NOT re-export `TextInputFormatter` in this Flutter SDK. Using it as a type annotation inside a `TextField` call compiles fine (the type is resolved through TextField's own declaration), but writing `extends TextInputFormatter` or `List<TextInputFormatter>?` as a top-level field triggers `extends_non_class` / ambiguous-import cascade errors in `app.dart`.

**How to apply:** Affected files: `radd_text_field.dart`, `login_screen.dart`, `register_screen.dart`, and any future screen/widget that defines a custom `TextInputFormatter` subclass.
