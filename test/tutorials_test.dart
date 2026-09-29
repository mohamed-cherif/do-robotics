import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/models/tutorial_data.dart';
import 'package:do_robotics/ui/python_bus.dart';
import 'package:do_robotics/ui/tutorial_detail_page.dart';

const _goBuildIt = 'Go Build It! 🚀';

/// A 360 × 740 dp phone (1080 × 2220 px at 3×).
void _useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  const tutorials = TutorialRepository.tutorials;

  group('tutorial data', () {
    test('ids are unique', () {
      final ids = tutorials.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate ids in $ids');
    });

    test('every tutorial has at least one step and one required part', () {
      for (final t in tutorials) {
        expect(t.steps, isNotEmpty, reason: '${t.id} has no steps');
        expect(t.requiredParts, isNotEmpty, reason: '${t.id} has no parts');
      }
    });

    test('the first tutorial is Connect & Hello LED', () {
      expect(tutorials.first.id, 'tutorial_hello_led');
      expect(tutorials.first.difficulty, Difficulty.easy);
    });
  });

  group('TutorialDetailPage renders without overflow at 360 dp', () {
    for (final tutorial in tutorials) {
      testWidgets(tutorial.id, (tester) async {
        _useSmallPhone(tester);
        await tester.pumpWidget(
          MaterialApp(home: TutorialDetailPage(tutorial: tutorial)),
        );
        expect(tester.takeException(), isNull);

        final position =
            tester.state<ScrollableState>(find.byType(Scrollable).first).position;
        for (var i = 0; i < 400; i++) {
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo(math.min(position.pixels + 250, position.maxScrollExtent));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '${tutorial.id} overflowed near offset ${position.pixels}');
        }

        expect(position.pixels, position.maxScrollExtent);
        expect(find.text(_goBuildIt), findsOneWidget);
      });
    }
  });

  testWidgets('"Go Build It!" asks the dashboard for the Blocks tab and pops',
      (tester) async {
    _useSmallPhone(tester);
    PythonBus.requestedTab.value = -1;
    addTearDown(() => PythonBus.requestedTab.value = -1);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TutorialDetailPage(tutorial: tutorials.first),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // hitTestable(): the list builds items ahead of the viewport, so "found"
    // alone can still mean just off-screen.
    await tester.scrollUntilVisible(find.text(_goBuildIt).hitTestable(), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(_goBuildIt));
    await tester.pumpAndSettle();

    expect(PythonBus.requestedTab.value, 1);
    expect(find.byType(TutorialDetailPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
