import 'dart:convert';

import 'package:do_robotics/services/actuator_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one unreadable actuator entry does not wipe the others', () async {
    SharedPreferences.setMockInitialValues({
      'configured_actuators': jsonEncode([
        {'id': 'm1', 'name': 'Left Wheel', 'type': 'motor', 'pin': 5, 'parameters': {}},
        {'id': 'x', 'name': 'From a newer app', 'type': 'laser', 'pin': 9},
        {'id': 'l1', 'name': 'Headlight', 'type': 'led', 'pin': 12},
      ]),
    });
    await ActuatorService().initialize();
    expect(ActuatorService().actuators.map((a) => a.name), ['Left Wheel', 'Headlight']);
  });
}
