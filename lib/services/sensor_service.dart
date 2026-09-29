import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

/// Pure sensor math, kept static so it can be unit-tested without a device.
class SensorMath {
  SensorMath._();

  /// Pitch in degrees from a gravity vector. 0° = flat, positive = tilted forward.
  static double pitchDeg(double gx, double gy, double gz) =>
      math.atan2(gy, gz) * 180 / math.pi;

  /// Roll in degrees from a gravity vector. 0° = flat, positive = tilted right.
  static double rollDeg(double gx, double gy, double gz) =>
      math.atan2(gx, gz) * 180 / math.pi;

  /// Compass heading 0..360 from raw magnetometer (device flat, +Y = top).
  static double headingDeg(double mx, double my) {
    double heading = math.atan2(-mx, my) * 180 / math.pi;
    if (heading < 0) heading += 360;
    return heading;
  }

  /// Signed shortest angular difference a - b in (-180, 180].
  static double angleDiff(double a, double b) => ((a - b + 540) % 360) - 180;

  /// Mean absolute linear acceleration (gravity removed), used for shake.
  static double shakeMagnitude(double x, double y, double z) =>
      (x.abs() + y.abs() + z.abs()) / 3;
}

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  /// Tilt beyond this angle (either axis) counts as "Phone Tilted".
  static const double tiltThresholdDeg = 25.0;
  /// Linear acceleration above this counts as "Phone Shaking".
  static const double shakeThreshold = 5.0;
  /// Yaw rate above this (rad/s) counts as "Phone Spinning".
  static const double rotatingThresholdRadS = 1.0;

  // 20 ms sampling. The platform default ("normal", ~200 ms on Android) makes
  // tilt steering and shake detection feel laggy.
  static const Duration _samplingPeriod = SensorInterval.gameInterval;

  // ── Accelerometer (gravity removed) ───────────────────────────────────────
  final StreamController<UserAccelerometerEvent> _filteredAccelController =
      StreamController.broadcast();
  Stream<UserAccelerometerEvent> get typeFilteredAccelStream =>
      _filteredAccelController.stream;

  StreamSubscription? _accelSubscription;
  double _lastX = 0, _lastY = 0, _lastZ = 0;
  final double _alpha = 0.8;

  // ── Gyroscope ──────────────────────────────────────────────────────────────
  final StreamController<GyroscopeEvent> _gyroController =
      StreamController.broadcast();
  Stream<GyroscopeEvent> get gyroStream => _gyroController.stream;

  StreamSubscription? _gyroSubscription;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;

  // ── Gravity accelerometer (for tilt angles) ───────────────────────────────
  // userAccelerometerEventStream removes gravity — useless for tilt.
  // accelerometerEventStream includes gravity — correct for orientation angles.
  StreamSubscription? _gravSubscription;
  double _gravX = 0, _gravY = 0, _gravZ = 9.8; // default: flat face-up

  // ── Magnetometer/Compass ───────────────────────────────────────────────────
  final StreamController<MagnetometerEvent> _magController =
      StreamController.broadcast();
  Stream<MagnetometerEvent> get magnetometerStream => _magController.stream;

  StreamSubscription? _magSubscription;
  double _magX = 0, _magY = 0, _magZ = 0;

  // ── Public computed values ─────────────────────────────────────────────────

  /// Pitch angle in degrees. 0° = flat/horizontal. Positive = tilted forward.
  double get tiltX => SensorMath.pitchDeg(_gravX, _gravY, _gravZ);

  /// Roll angle in degrees. 0° = flat/horizontal. Positive = tilted right.
  double get tiltY => SensorMath.rollDeg(_gravX, _gravY, _gravZ);

  /// True when the phone is tilted more than [tiltThresholdDeg] on either axis.
  bool get isTilted =>
      tiltX.abs() > tiltThresholdDeg || tiltY.abs() > tiltThresholdDeg;

  /// True when linear acceleration exceeds [shakeThreshold].
  bool get isShaking =>
      SensorMath.shakeMagnitude(_lastX, _lastY, _lastZ) > shakeThreshold;

  /// Gyroscope Z-axis rotation rate (yaw) in deg/s. Positive = clockwise.
  double get rotationRateDegS => _gyroZ * 180 / math.pi;

  /// True when the device is rotating quickly (≈ 57 deg/s).
  bool get isRotating => _gyroZ.abs() > rotatingThresholdRadS;

  /// Compass heading 0-360° (0 = North, 90 = East). Requires magnetometer.
  double get compassHeading => SensorMath.headingDeg(_magX, _magY);

  /// True when compass heading is within ±22.5° of [targetDegrees].
  bool isFacing(double targetDegrees) =>
      SensorMath.angleDiff(compassHeading, targetDegrees).abs() < 22.5;

  bool get isListening => _gravSubscription != null;

  void startListening() {
    // Gravity-inclusive accelerometer — used for tilt angle computation.
    _gravSubscription ??=
        accelerometerEventStream(samplingPeriod: _samplingPeriod).listen((event) {
      // Low-pass: 0.6 old + 0.4 new reaches 90% in ~4 samples — responsive
      // enough for tilt steering while still filtering vibration noise.
      _gravX = 0.6 * _gravX + 0.4 * event.x;
      _gravY = 0.6 * _gravY + 0.4 * event.y;
      _gravZ = 0.6 * _gravZ + 0.4 * event.z;
    });

    // Gravity-removed accelerometer — used for shake/motion detection.
    _accelSubscription ??=
        userAccelerometerEventStream(samplingPeriod: _samplingPeriod)
            .listen((event) {
      _lastX = _alpha * event.x + (1 - _alpha) * _lastX;
      _lastY = _alpha * event.y + (1 - _alpha) * _lastY;
      _lastZ = _alpha * event.z + (1 - _alpha) * _lastZ;
      _filteredAccelController
          .add(UserAccelerometerEvent(_lastX, _lastY, _lastZ, DateTime.now()));
    });

    // Gyroscope
    _gyroSubscription ??=
        gyroscopeEventStream(samplingPeriod: _samplingPeriod).listen((event) {
      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;
      _gyroController.add(event);
    });

    // Magnetometer (compass does not need game-rate sampling)
    _magSubscription ??= magnetometerEventStream().listen((event) {
      _magX = event.x;
      _magY = event.y;
      _magZ = event.z;
      _magController.add(event);
    });
  }

  void stopListening() {
    _gravSubscription?.cancel();
    _gravSubscription = null;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _gyroSubscription?.cancel();
    _gyroSubscription = null;
    _magSubscription?.cancel();
    _magSubscription = null;
  }

  // For telemetry
  List<double> get currentValues => [_lastX, _lastY, _lastZ];
  List<double> get gyroValues => [_gyroX, _gyroY, _gyroZ];
  List<double> get magValues => [_magX, _magY, _magZ];
}
