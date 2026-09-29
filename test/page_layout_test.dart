import 'package:do_robotics/ui/accelerometer_page.dart';
import 'package:do_robotics/ui/actuator_settings_page.dart';
import 'package:do_robotics/ui/compass_page.dart';
import 'package:do_robotics/ui/gyroscope_page.dart';
import 'package:do_robotics/ui/sensors_page.dart';
import 'package:do_robotics/ui/vision_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every page must lay out on a small (360 x 740 dp) phone without overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // sensors_plus sets sampling rates over a method channel.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/method'), (_) async => null);

  final pages = <String, Widget Function()>{
    'Configure Hardware': () => const ActuatorSettingsPage(),
    'Vision Settings': () => const VisionSettingsPage(),
    'Sensors': () => const SensorsPage(),
    'Compass': () => const CompassPage(),
    'Accelerometer': () => const AccelerometerPage(),
    'Gyroscope': () => const GyroscopePage(),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key} fits a 360 dp phone', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(home: entry.value()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      // Stop page timers/animations before the test ends.
      await tester.pumpWidget(const SizedBox());
    });
  }
}
