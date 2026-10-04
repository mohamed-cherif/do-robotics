import 'package:do_robotics/logic/actuator_driver.dart';
import 'package:do_robotics/models/actuator_config.dart';
import 'package:do_robotics/ui/actuator_settings_page.dart';
import 'package:do_robotics/utils/execution_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ActuatorConfig motor({int? in1, int? in2, bool inverted = false}) => ActuatorConfig(
      id: 'm${in1}_$in2',
      name: 'Left Wheel',
      type: ActuatorType.motor,
      pin: 32,
      parameters: {
        if (in1 != null) 'in1': in1,
        if (in2 != null) 'in2': in2,
        if (inverted) 'inverted': true,
      },
    );

void main() {
  group('Invert direction in the motor driver', () {
    final logs = ExecutionLogger();
    String lastMotorLine() => logs.logs.lastWhere((l) => l.contains('Left Wheel:'));

    test('with IN1 and IN2, FORWARD runs the motor backward', () async {
      logs.clear();
      await ActuatorDriver().driveMotor(motor(in1: 25, in2: 26, inverted: true), 'FORWARD', 150);
      expect(lastMotorLine(), contains('BACKWARD @ 150'));
    });

    test('without IN2 it is ignored instead of stopping the motor', () async {
      // Regression: an inverted single-pin motor turned every FORWARD into a
      // stop (IN1 LOW), so "Invert direction" made the wheel not turn.
      logs.clear();
      await ActuatorDriver().driveMotor(motor(in1: 27, inverted: true), 'FORWARD', 150);
      expect(lastMotorLine(), contains('FORWARD @ 150'));
    });
  });

  group('Motor settings dialog', () {
    Future<List<ActuatorConfig>> open(WidgetTester tester, ActuatorConfig existing) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final saved = <ActuatorConfig>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ActuatorDialog(existing: existing, onSave: saved.add)),
      ));
      await tester.pumpAndSettle();
      return saved;
    }

    SwitchListTile invertSwitch(WidgetTester tester) => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Invert direction'));

    ButtonStyleButton button(WidgetTester tester, String label) =>
        tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));

    testWidgets('Invert direction and Backward need both IN1 and IN2', (tester) async {
      await open(tester, motor(in1: 27, inverted: true));
      expect(invertSwitch(tester).onChanged, isNull);
      expect(invertSwitch(tester).value, isFalse);
      expect(find.textContaining('Needs IN1 and IN2'), findsOneWidget);
      expect(button(tester, 'Backward 1 s').onPressed, isNull);
      expect(button(tester, 'Forward 1 s').onPressed, isNotNull);
    });

    testWidgets('with IN1 and IN2 both can be used', (tester) async {
      await open(tester, motor(in1: 25, in2: 26));
      expect(invertSwitch(tester).onChanged, isNotNull);
      expect(button(tester, 'Backward 1 s').onPressed, isNotNull);
    });

    testWidgets('IN2 without IN1 cannot be saved', (tester) async {
      final saved = await open(tester, motor(in2: 26));
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Set IN1 too'), findsOneWidget);
      expect(saved, isEmpty);
    });

    testWidgets('testing a motor without a robot connected says so', (tester) async {
      await open(tester, motor(in1: 25, in2: 26));
      await tester.ensureVisible(find.text('Forward 1 s'));
      await tester.tap(find.text('Forward 1 s'));
      await tester.pump();
      expect(find.textContaining('Connect the robot first'), findsOneWidget);
    });

    testWidgets('unusable ESP32 pins are labelled in the IN lists', (tester) async {
      await open(tester, motor(in1: 25, in2: 26));
      await tester.ensureVisible(find.text('IN2 Pin'));
      await tester.tap(find.text('Pin 26').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Pin 34 · ESP32 input only').last, 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Pin 34 · ESP32 input only'), findsWidgets);
    });
  });
}
