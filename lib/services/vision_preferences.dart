import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'mount_detector.dart';

/// How much CPU (and battery) object detection may use.
enum VisionPerformance {
  /// ~5 frames/s, 1 inference thread. Coolest and longest battery life.
  batterySaver(Duration(milliseconds: 200), 1, 'Battery saver', 'About 5 checks per second'),
  /// ~10 frames/s, 2 threads.
  balanced(Duration(milliseconds: 100), 2, 'Balanced', 'About 10 checks per second'),
  /// Up to ~25 frames/s, up to 4 threads (the original behaviour).
  fast(Duration(milliseconds: 40), 4, 'Fast', 'Up to 25 checks per second');

  const VisionPerformance(this.frameInterval, this.maxThreads, this.label, this.description);

  /// Minimum time between two frames sent to the model.
  final Duration frameInterval;
  /// Upper bound on inference threads (also limited by the CPU core count).
  final int maxThreads;
  final String label;
  final String description;
}

/// Persisted vision settings shared by the camera page, the settings page and
/// the block runner.
class VisionPreferences {
  VisionPreferences._();

  static const String _keyEnabledLabels = 'vision_enabled_labels_v2';
  static const String _keyUpsideDown = 'vision_upside_down'; // legacy bool
  static const String _keyMount = 'vision_mount';
  static const String _keyConfidence = 'vision_confidence';
  static const String _keyPerformance = 'vision_performance';

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

  /// How the phone is attached to the robot. Defaults to automatic; a
  /// previously saved "mounted upside down" switch is honoured.
  static Future<PhoneMount> getMount() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyMount);
    if (name != null) {
      return PhoneMount.values.firstWhere((m) => m.name == name, orElse: () => PhoneMount.auto);
    }
    return (prefs.getBool(_keyUpsideDown) ?? false) ? PhoneMount.upsideDown : PhoneMount.auto;
  }

  static Future<void> setMount(PhoneMount value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMount, value.name);
    await prefs.remove(_keyUpsideDown);
    _settingsChanges.add(null);
  }

  /// CPU budget for detection. Defaults to [VisionPerformance.fast] (the
  /// behaviour before this setting existed).
  static Future<VisionPerformance> getPerformance() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyPerformance);
    return VisionPerformance.values.firstWhere((p) => p.name == name,
        orElse: () => VisionPerformance.fast);
  }

  static Future<void> setPerformance(VisionPerformance value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPerformance, value.name);
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
