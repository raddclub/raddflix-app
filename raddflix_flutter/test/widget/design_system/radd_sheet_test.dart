// Phase H4 — RaddSheet widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raddflix/design_system/components/radd_sheet.dart';

void main() {
  group('RaddSheet', () {
    testWidgets('show() presents the title and list content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => RaddSheet.show<void>(
                  context,
                  style: RaddSheetStyle.list,
                  title: 'Playback Speed',
                  listBuilder: (_) => const Text('1.0x'),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Playback Speed'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('close button dismisses a dismissible sheet', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => RaddSheet.show<void>(
                  context,
                  style: RaddSheetStyle.list,
                  title: 'Subtitles',
                  listBuilder: (_) => const Text('Track 1'),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Subtitles'), findsOneWidget);

      await tester.tap(find.byTooltip('Close Subtitles'));
      await tester.pumpAndSettle();

      expect(find.text('Subtitles'), findsNothing);
    });

    testWidgets('tabbed style requires a non-null tabs list', (tester) async {
      expect(
        () => RaddSheet(style: RaddSheetStyle.tabbed, title: 'Broken'),
        throwsAssertionError,
      );
    });

    testWidgets('tabbed style switches body content when a tab is tapped',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => RaddSheet.show<void>(
                  context,
                  style: RaddSheetStyle.tabbed,
                  title: 'Settings',
                  tabs: [
                    RaddSheetTab(label: 'Video', builder: (_) => const Text('Video Panel')),
                    RaddSheetTab(label: 'Audio', builder: (_) => const Text('Audio Panel')),
                  ],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Both panels exist in the IndexedStack; only "Video" tab is initially selected.
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);

      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      expect(find.text('Audio Panel'), findsOneWidget);
    });
  });
}
