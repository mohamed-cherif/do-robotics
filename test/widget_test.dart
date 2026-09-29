// Widget smoke tests need the platform plugins (camera, BLE, sensors) which
// are not available in the headless test runner. Pure-logic coverage lives in:
//   - robot_protocol_test.dart          (wire packets)
//   - script_utils_test.dart            (voice matching, tree scanning)
//   - block_models_test.dart            (save/load round-trip, code generator)
//   - sensor_and_vision_math_test.dart  (tilt/heading, tracking association)
import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/main.dart';

void main() {
  test('app widget can be constructed', () {
    expect(const NeuralApp(), isA<NeuralApp>());
  });
}
