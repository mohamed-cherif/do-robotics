import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted vision settings shared by the camera page, the settings page and
/// the block runner.
class VisionPreferences {
  VisionPreferences._();

  static const String _keyEnabledLabels = 'vision_enabled_labels_v2';
  static const String _keyUpsideDown = 'vision_upside_down';
  static const String _keyConfidence = 'vision_confidence';

  /// Curated subset of the COCO labels the bundled SSD-MobileNet model can
  /// return. Huge outdoor classes (train, airplane…) are left out because they
  /// are useless on a desk robot and only add false positives.
  static const List<String> availableLabels = [
    'person', 'bicycle', 'car', 'motorcycle', 'cat', 'dog', 'bird',
    'horse', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase',
    'sports ball', 'bottle', 'cup', 'fork', 'knife', 'spoon', 'bowl',
    'banana', 'apple', 'orange', 'sandwich', 'chair', 'couch', 'potted plant',
    'tv', 'laptop', 'mouse', 'remote', 'keyboard', 'cell phone', 'book',
    'clock', 'vase', 'scissors', 'teddy bear', 'toothbrush',
  ];

  static const double defaultConfidence = 0.35;

  static final StreamController<Set<String>> _labelChanges =
      StreamController.broadcast();
  /// Emits whenever the enabled-label set changes. Empty set = detect everything.
  static Stream<Set<String>> get changesStream => _labelChanges.stream;

  static final StreamController<void> _settingsChanges =
      StreamController.broadcast();
  /// Emits when a non-label setting (orientation, confidence) changes.
  static Stream<void> get settingsStream => _settingsChanges.stream;

  /// Enabled labels. An empty set means "no filter" (all labels pass).
  static Future<Set<String>> getEnabledLabels() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyEnabledLabels) ?? const []).toSet();
  }

  static Future<void> setEnabledLabels(Set<String> labels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyEnabledLabels, labels.toList()..sort());
    _labelChanges.add(labels);
  }

  /// True when the phone is mounted screen-down / inverted on the robot.
  static Future<bool> getUpsideDown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUpsideDown) ?? false;
  }

  static Future<void> setUpsideDown(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUpsideDown, value);
    _settingsChanges.add(null);
  }

  /// Minimum detection score (0..1). Lower = more detections, more noise.
  static Future<double> getConfidenceThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyConfidence) ?? defaultConfidence;
  }

  static Future<void> setConfidenceThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyConfidence, value.clamp(0.1, 0.9));
    _settingsChanges.add(null);
  }
}
