---
name: Home AppBar ValueListenableBuilder pattern
description: How home_screen.dart isolates AppBar rebuilds from scroll events using ValueNotifier + PreferredSize wrapper.
---

Pattern (UX4-06):
```dart
final _scrolledOffset = ValueNotifier<double>(0.0);

// In scroll listener (no setState):
_scroll.addListener(() { _scrolledOffset.value = _scroll.offset; });

// In dispose:
_scrolledOffset.dispose();

// In _buildAppBar:
return PreferredSize(
  preferredSize: const Size.fromHeight(kToolbarHeight),
  child: ValueListenableBuilder<double>(
    valueListenable: _scrolledOffset,
    builder: (_, offset, __) {
      final opacity = (offset / 200.0).clamp(0.0, 1.0);
      final scrolled = offset > 50;
      return AppBar(
        backgroundColor: t.surface.withOpacity(opacity * 0.96),
        flexibleSpace: scrolled ? null : Container(...gradient...),
        ...
      );
    },
  ),
);
```

**Why:** Binary bool + setState triggered full scaffold rebuild on every scroll pixel. ValueNotifier scopes the rebuild to only the AppBar. PreferredSize is needed to give the VLB widget the PreferredSizeWidget interface that Scaffold.appBar requires.

**How to apply:** Wherever any widget prop changes with scroll, use a ValueNotifier + ValueListenableBuilder. Only works when the reactive widget can be wrapped in PreferredSize (for AppBar) or directly in a builder (for any other Widget).
