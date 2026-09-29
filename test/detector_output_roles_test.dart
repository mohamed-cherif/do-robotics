import 'package:do_robotics/services/object_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two [1, N] outputs of the detection post-process op are class ids and
/// scores. The values below are the first six of each, recorded by running
/// the bundled assets/ml/1.tflite on COCO val2017 image 39769 (two cats and
/// two remotes) with TensorFlow Lite 2.21 on a PC.
void main() {
  const classes = [16.0, 16.0, 16.0, 74.0, 16.0, 74.0]; // cat, cat, cat, remote...
  const scores = [0.688, 0.668, 0.477, 0.148, 0.102, 0.086];

  test('class ids are recognised in either position', () {
    expect(ObjectDetectorService.resolveClassScoreRoles(classes, scores), isTrue);
    expect(ObjectDetectorService.resolveClassScoreRoles(scores, classes), isFalse);
  });

  test('a frame where only people are seen (class 0) still resolves', () {
    expect(ObjectDetectorService.resolveClassScoreRoles(
        const [0.0, 0.0, 34.0, 0.0], const [0.898, 0.227, 0.227, 0.172]), isTrue);
  });

  test('ambiguous frames (all zeros) wait for a better frame', () {
    expect(ObjectDetectorService.resolveClassScoreRoles(
        const [0.0, 0.0, 0.0], const [0.0, 0.0, 0.0]), isNull);
  });
}
