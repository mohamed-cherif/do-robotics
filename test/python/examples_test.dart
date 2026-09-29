import 'package:do_robotics/logic/python_script_runner.dart';
import 'package:do_robotics/ui/python_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every built-in Python example parses', () {
    final sources = pythonExampleSources();
    expect(sources, isNotEmpty);
    for (final src in sources) {
      expect(PythonScriptRunner.check(src), isNull, reason: src);
    }
  });
}
