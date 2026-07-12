// Phase H4 — RaddButton widget tests.
//
// Wraps the widget in a plain MaterialApp/Scaffold. RaddColors.t falls back
// to RaddTheme.dark when no RaddThemeExtension is registered on the Theme
// (see lib/core/theme/radd_theme.dart RaddTheme.of), so no app-level theme
// bootstrap is required for these tests to render correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:raddflix/design_system/components/radd_button.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('RaddButton', () {
    testWidgets('renders label for the default (signal) variant', (tester) async {
      await tester.pumpWidget(_wrap(
        RaddButton(label: 'Watch Now', onPressed: () {}),
      ));

      expect(find.text('Watch Now'), findsOneWidget);
    });

    testWidgets('invokes onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        RaddButton(label: 'Play', onPressed: () => tapped = true),
      ));

      await tester.tap(find.text('Play'));
      // onPressed fires immediately; the 400ms minimum-loading-display delay
      // only affects the loading spinner teardown, not the callback itself.
      expect(tapped, isTrue);

      // Drain the pending 400ms loading-latch timer so pumpWidget's dispose
      // doesn't get scheduled after the test tree is torn down.
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('does not invoke onPressed when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        RaddButton(label: 'Play', enabled: false, onPressed: () => tapped = true),
      ));

      await tester.tap(find.text('Play'), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('does not invoke onPressed while loading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        RaddButton(label: 'Play', loading: true, onPressed: () => tapped = true),
      ));

      // Loading state replaces the label with a spinner — label text is gone.
      expect(find.text('Play'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('icon variant renders without a label and requires a tooltip',
        (tester) async {
      await tester.pumpWidget(_wrap(
        RaddButton(
          variant: RaddButtonVariant.icon,
          leadingIcon: PhosphorIcons.heart(),
          tooltip: 'Add to watchlist',
          onPressed: () {},
        ),
      ));

      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    test('icon variant without a tooltip throws an assertion error', () {
      expect(
        () => RaddButton(
          variant: RaddButtonVariant.icon,
          onPressed: () {},
        ),
        throwsAssertionError,
      );
    });

    test('non-icon variant without a label throws an assertion error', () {
      expect(
        () => const RaddButton(),
        throwsAssertionError,
      );
    });
  });
}
