import 'dart:async';

import 'package:do_robotics/services/connectivity/bluetooth_strategy.dart';
import 'package:do_robotics/ui/robot_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scan the test drives by hand.
class _FakeScan {
  final List<StreamController<List<FoundRobot>>> scans = [];
  Completer<void>? stopping; // when set, stopping the scan waits for it
  int cancels = 0;

  StreamController<List<FoundRobot>> get current => scans.last;

  Stream<List<FoundRobot>> start() {
    final c = StreamController<List<FoundRobot>>(onCancel: () {
      cancels++;
      return stopping?.future;
    });
    scans.add(c);
    return c.stream;
  }
}

const _near = FoundRobot(id: 'AA:01', name: 'ESP32 Robot E5F6', rssi: -48);
const _far = FoundRobot(id: 'AA:02', name: 'ESP32 Robot 1A2B', rssi: -85);

void main() {
  late _FakeScan scan;
  FoundRobot? picked;
  bool closed = false;

  Future<void> open(WidgetTester tester, {String? rememberedId}) async {
    picked = null;
    closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              picked = await showDialog<FoundRobot>(
                context: context,
                builder: (_) => RobotPickerDialog(rememberedId: rememberedId, scan: scan.start),
              );
              closed = true;
            },
            child: const Text('home'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('home'));
    await tester.pump();
  }

  setUp(() => scan = _FakeScan());

  testWidgets('lists robots closest first and marks the last used one', (tester) async {
    await open(tester, rememberedId: _far.id);
    expect(find.textContaining('Looking for robots'), findsOneWidget);

    scan.current.add([_far, _near]);
    await tester.pump();

    final near = tester.getTopLeft(find.text(_near.name));
    final far = tester.getTopLeft(find.text(_far.name));
    expect(near.dy, lessThan(far.dy));
    expect(find.text('Very close'), findsOneWidget);
    expect(find.text('Far away · last used'), findsOneWidget);
  });

  testWidgets('choosing a robot stops the scan first, then closes with it', (tester) async {
    await open(tester);
    scan.current.add([_near]);
    await tester.pump();

    scan.stopping = Completer<void>();
    await tester.tap(find.text(_near.name));
    await tester.pump();
    expect(scan.cancels, 1);
    expect(closed, isFalse, reason: 'must wait until the scan has stopped');

    scan.stopping!.complete();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked?.id, _near.id);
  });

  testWidgets('a double tap does not also close the page underneath', (tester) async {
    await open(tester);
    scan.current.add([_near]);
    await tester.pump();

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    tile.onTap!();
    tile.onTap!(); // second tap before the dialog is gone
    await tester.pumpAndSettle();
    expect(picked?.id, _near.id);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('nothing found: says what to check and can search again', (tester) async {
    await open(tester);
    await scan.current.close();
    await tester.pump();

    expect(find.textContaining('No robots found'), findsOneWidget);
    await tester.tap(find.text('Search again'));
    await tester.pump();
    expect(scan.scans.length, 2);
    expect(find.textContaining('Looking for robots'), findsOneWidget);

    scan.current.add([_near]);
    await tester.pump();
    expect(find.text(_near.name), findsOneWidget);
  });

  testWidgets('a failed scan explains how to fix it', (tester) async {
    await open(tester);
    scan.current.addError(StateError('Bluetooth off'));
    await scan.current.close();
    await tester.pump();
    expect(find.textContaining('Turn Bluetooth on'), findsOneWidget);
    expect(find.text('Search again'), findsOneWidget);
  });

  testWidgets('Cancel stops the scan and closes with no robot', (tester) async {
    await open(tester);
    scan.current.add([_near]);
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(scan.cancels, 1);
    expect(closed, isTrue);
    expect(picked, isNull);
  });

  test('robot names', () {
    expect(BluetoothStrategy.isRobotName('ESP32 Robot E5F6'), isTrue);
    expect(BluetoothStrategy.isRobotName('Robot bench-bot'), isTrue); // after NAME
    expect(BluetoothStrategy.isRobotName('ESP32 Robot'), isTrue); // firmware 2.0
    expect(BluetoothStrategy.isRobotName('JBL Flip 5'), isFalse);
  });
}
