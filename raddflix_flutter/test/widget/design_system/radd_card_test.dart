// Phase H4 — RaddCard widget tests.
//
// Image.network has no real network access in the widget-test environment,
// so these tests deliberately avoid asserting on the loaded artwork itself
// and instead cover the parts of RaddCard that don't depend on the image
// actually resolving: semantics, tap handling, and the progress indicator.
// A broken/placeholder image is expected and is not treated as a failure —
// RaddCard's own errorBuilder already handles that gracefully in production.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raddflix/design_system/components/radd_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('RaddCard', () {
    testWidgets('exposes title + variant in its Semantics label', (tester) async {
      await tester.pumpWidget(_wrap(
        RaddCard(
          imageUrl: 'https://example.invalid/poster.jpg',
          title: 'Coke Studio',
          onTap: () {},
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(find.byType(RaddCard));
      expect(semantics.label, contains('Coke Studio'));
      expect(semantics.label, contains('movie'));
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    });

    testWidgets('appends "data-free" to the semantics label when isDataFree', (tester) async {
      await tester.pumpWidget(_wrap(
        RaddCard(
          imageUrl: 'https://example.invalid/poster.jpg',
          title: 'Humsafar',
          isDataFree: true,
          onTap: () {},
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(find.byType(RaddCard));
      expect(semantics.label, contains('data-free'));
    });

    testWidgets('invokes onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        RaddCard(
          imageUrl: 'https://example.invalid/poster.jpg',
          title: 'Tap Test',
          onTap: () => tapped = true,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(RaddCard));
      expect(tapped, isTrue);
    });

    testWidgets('renders a progress indicator bar when progress is supplied', (tester) async {
      await tester.pumpWidget(_wrap(
        RaddCard(
          imageUrl: 'https://example.invalid/poster.jpg',
          title: 'Resume',
          progress: 0.4,
          onTap: () {},
        ),
      ));
      await tester.pump();

      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });

    testWidgets('mini variant hides the title text', (tester) async {
      await tester.pumpWidget(_wrap(
        RaddCard(
          variant: RaddCardVariant.mini,
          imageUrl: 'https://example.invalid/poster.jpg',
          title: 'Hidden Title',
          onTap: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('Hidden Title'), findsNothing);
    });
  });
}
