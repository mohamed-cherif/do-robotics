import 'package:do_robotics/ui/python_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Python tab fits a 360 dp phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PythonPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
