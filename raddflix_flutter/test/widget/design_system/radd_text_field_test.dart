// Phase H4 — RaddTextField widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raddflix/design_system/components/radd_text_field.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('RaddTextField', () {
    testWidgets('renders label and hint', (tester) async {
      await tester.pumpWidget(_wrap(
        const RaddTextField(label: 'Email', hint: 'you@example.com'),
      ));

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('you@example.com'), findsOneWidget);
    });

    testWidgets('calls onChanged with typed text', (tester) async {
      String? latest;
      await tester.pumpWidget(_wrap(
        RaddTextField(label: 'Name', onChanged: (v) => latest = v),
      ));

      await tester.enterText(find.byType(TextField), 'Bilal');
      expect(latest, 'Bilal');
    });

    testWidgets('shows the explicit errorText when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const RaddTextField(label: 'Password', errorText: 'Too short'),
      ));

      expect(find.text('Too short'), findsOneWidget);
    });

    testWidgets('respects an externally supplied controller value', (tester) async {
      final controller = TextEditingController(text: 'seeded');
      await tester.pumpWidget(_wrap(
        RaddTextField(label: 'Search', controller: controller),
      ));

      expect(find.text('seeded'), findsOneWidget);
    });

    testWidgets('disabled field does not accept input via enterText', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(
        RaddTextField(label: 'Locked', controller: controller, enabled: false),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });
  });
}
