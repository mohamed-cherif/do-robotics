import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:do_robotics/ui/logic_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final defs = BlockFactory.getAllStaticBlocks();
  BlockDefinition def(String id) => defs.firstWhere((d) => d.id == id);

  Future<LogicPageState> pumpEditor(WidgetTester tester) async {
    // A small phone: 360 x 740 dp.
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: LogicPage()));
    await tester.pumpAndSettle();
    return tester.state<LogicPageState>(find.byType(LogicPage));
  }

  Finder canvasFields() => find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(TextField),
      );

  testWidgets('header fits a 360 dp phone without overflow', (tester) async {
    await pumpEditor(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Snippets'), findsOneWidget);
  });

  testWidgets('editing the second block of a chain does not change the first', (tester) async {
    final state = await pumpEditor(tester);
    final first = BlockInstance(instanceId: 'w1', definition: def('logic_wait'), inputValues: {'seconds': 1});
    first.nextBlock = BlockInstance(instanceId: 'w2', definition: def('logic_wait'), inputValues: {'seconds': 1});
    state.addRoot(first, const Offset(40, 40));
    await tester.pumpAndSettle();

    expect(canvasFields(), findsNWidgets(2));
    await tester.enterText(canvasFields().at(1), '3');
    await tester.pumpAndSettle();

    // Before the fix the page copied the edit into the root block as well.
    expect(first.nextBlock!.inputValues['seconds'], 3);
    expect(first.inputValues['seconds'], 1);
  });

  testWidgets('undo restores the canvas before the last edit', (tester) async {
    final state = await pumpEditor(tester);
    final wait = BlockInstance(instanceId: 'w1', definition: def('logic_wait'), inputValues: {'seconds': 1});
    state.addRoot(wait, const Offset(40, 40));
    await tester.pumpAndSettle();
    // Gestures end with a pointer-up, which records a snapshot.
    await tester.tapAt(const Offset(200, 600));
    await tester.pumpAndSettle();

    await tester.enterText(canvasFields().first, '5');
    await tester.pump(const Duration(seconds: 1)); // field edits are debounced
    await tester.pumpAndSettle();
    expect(state.sortedRoots.single.inputValues['seconds'], 5);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(state.sortedRoots.single.inputValues['seconds'], 1);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(state.sortedRoots.single.inputValues['seconds'], 5);
  });
}
