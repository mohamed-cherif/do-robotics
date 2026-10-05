import '../models/actuator_config.dart';
import '../services/actuator_service.dart';
import '../services/connectivity/connectivity_manager.dart';
import '../services/sensor_service.dart';
import '../services/vision_service.dart';
import '../services/voice_service.dart';
import 'actuator_driver.dart';
import 'block_script_runner.dart' show ScriptUtils;

/// Everything a program can do with the robot, behind one interface so the
/// Python runtime can be tested with a fake and run against real hardware.
abstract class RobotApi {
  List<ActuatorConfig> get actuators;
  ActuatorDriver get driver;
  bool get connected;

  Future<void> ensureVision({bool lineMode = false});
  Future<void> ensureMic();

  // vision
  bool get visionDetected;
  bool visionLock(String label);
  bool get visionLocked;
  /// Count of processed camera pictures (changes with every new picture).
  int get visionFrame;
  String get visionLabel;
  double get offsetX;
  double get offsetY;
  double get size;
  List<String> get objects;
  bool get lineVisible;
  double get lineOffset;
  void visionUnlock();

  // imu / compass
  double get pitch;
  double get roll;
  double get yawRate;
  bool get shaking;
  bool get tilted;
  bool get spinning;
  double get heading;
  bool facing(double degrees);

  // mic
  bool get micLoud;
  bool heard(String phrase);
  String get words;

  Future<void> say(String text);

  /// Release camera / mic at program end.
  Future<void> shutdown();
}

/// Real implementation over the app services.
class LiveRobotApi implements RobotApi {
  final VisionService _vision = VisionService();
  final SensorService _sensors = SensorService();
  final VoiceService _voice = VoiceService();
  final ActuatorService _actuatorService = ActuatorService();
  final ConnectivityManager _connectivity = ConnectivityManager();
  bool _visionStarted = false;
  bool _micStarted = false;
  bool _micRequested = false;

  @override
  List<ActuatorConfig> get actuators => _actuatorService.actuators;
  @override
  ActuatorDriver get driver => ActuatorDriver();
  @override
  bool get connected => _connectivity.isConnected;

  @override
  Future<void> ensureVision({bool lineMode = false}) async {
    if (lineMode) _vision.lineMode = true;
    if (_visionStarted) return;
    // Held from here on: shutdown() releases it even if the start fails or
    // STOP arrives while the camera is still opening.
    _visionStarted = true;
    _sensors.startListening();
    await _vision.startStream();
    await _vision.nextFrame();
  }

  @override
  Future<void> ensureMic() async {
    // Ask once per run. Program loops read robot.mic every few ms; retrying
    // after a denial re-requested the permission on every read.
    if (_micRequested) return;
    _micRequested = true;
    _micStarted = true; // shutdown() releases it even if STOP comes mid-start
    await _voice.startListening();
  }

  @override
  bool get visionDetected => _vision.isObjectDetected;
  @override
  bool visionLock(String label) {
    final l = label.toLowerCase();
    if (!_vision.isLocked || _vision.targetLabel.toLowerCase() != l) {
      _vision.autoLockOnLabel(l);
    }
    return _vision.isLocked && _vision.targetLabel.toLowerCase() == l;
  }

  @override
  bool get visionLocked => _vision.isLocked;
  @override
  int get visionFrame => _vision.frameCount;
  @override
  String get visionLabel => _vision.isLocked ? _vision.targetLabel : '';
  @override
  double get offsetX => _vision.targetOffsetX;
  @override
  double get offsetY => _vision.targetOffsetY;
  @override
  double get size => _vision.targetArea;
  @override
  List<String> get objects => _vision.lastDetections.map((d) => d.label).toList();
  @override
  bool get lineVisible => _vision.lineDetected;
  @override
  double get lineOffset => _vision.lineOffsetX;
  @override
  void visionUnlock() => _vision.unlock();

  @override
  double get pitch => _sensors.tiltX;
  @override
  double get roll => _sensors.tiltY;
  @override
  double get yawRate => _sensors.rotationRateDegS;
  @override
  bool get shaking => _sensors.isShaking;
  @override
  bool get tilted => _sensors.isTilted;
  @override
  bool get spinning => _sensors.isRotating;
  @override
  double get heading => _sensors.compassHeading;
  @override
  bool facing(double degrees) => _sensors.isFacing(degrees);

  @override
  bool get micLoud => _voice.isLoud;
  @override
  bool heard(String phrase) {
    if (ScriptUtils.matchesPhrase(_voice.lastWords, phrase)) {
      _voice.consume();
      return true;
    }
    return false;
  }

  @override
  String get words => _voice.lastWords;

  @override
  Future<void> say(String text) => _voice.say(text);

  @override
  Future<void> shutdown() async {
    await _voice.stopSpeaking();
    if (_micStarted) {
      _micStarted = false;
      await _voice.stopListening();
    }
    _micRequested = false;
    if (_visionStarted) {
      _visionStarted = false;
      _vision.unlock();
      _vision.lineMode = false;
      await _vision.stopStream();
    }
  }
}
