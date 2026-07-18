- [RaddTextField custom params](radd-text-field-extension.md) — widget supports textInputAction/inputFormatters/onFieldSubmitted (D4); all forms can use keyboard chains
- [Home AppBar ValueListenableBuilder pattern](home-appbar-pattern.md) — PreferredSize wraps VLB for scroll-reactive AppBar without setState on the whole scaffold
- [flutter/services.dart import required](flutter-services-import.md) — TextInputFormatter is NOT re-exported by material.dart in this SDK; screens that extend/define it must import services.dart explicitly
- [Edit tool truncates new_string at dollar sign](edit-tool-dollar-truncation.md) — never put a bare $ in new_string (e.g. regex r'^...
); use string-method alternatives or write files via Node/ShellExec instead
