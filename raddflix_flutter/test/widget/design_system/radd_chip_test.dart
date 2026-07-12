// Phase H4 — RaddChip widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raddflix/design_system/components/radd_chip.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('RaddChip', () {
    testWidgets('renders its label', (tester) async {
      await tester.pumpWidget(_wrap(const RaddChip(label: 'Action')));
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('invokes onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        RaddChip(label: 'Comedy', onTap: () => tapped = true),
      ));

      await tester.tap(find.text('Comedy'));
      expect(tapped, isTrue);
    });

    testWidgets('exposes selected state via Semantics when active', (tester) async {
      await tester.pumpWidget(_wrap(
        const RaddChip(label: 'Horror', active: true),
      ));

      final semantics = tester.getSemantics(find.byType(RaddChip));
      expect(semantics.label, 'Horror');
      expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
    });

    testWidgets('is not selected by default', (tester) async {
      await tester.pumpWidget(_wrap(
        const RaddChip(label: 'Drama'),
      ));

      final semantics = tester.getSemantics(find.byType(RaddChip));
      expect(semantics.hasFlag(SemanticsFlag.isSelected), isFalse);
    });
  });
}
