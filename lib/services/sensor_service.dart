import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

/// Pure sensor math, kept static so it can be unit-tested without a device.
class SensorMath {
  SensorMath._();

  /// Pitch in degrees from a gravity vector (accelerometer, device frame).
  /// 0° = flat; negative = top edge lowered (tilted forward, away from you),
  /// positive = top edge raised.
  static double pitchDeg(double gx, double gy, double gz) =>
      math.atan2(gy, gz) * 180 / math.pi;

  /// Roll in degrees from a gravity vector. 0° = flat; negative = right edge
  /// lowered (tilted right), positive = tilted left.
  static double rollDeg(double gx, double gy, double gz) =>
      math.atan2(gx, gz) * 180 / math.pi;

  /// Compass heading 0..360 from raw magnetometer (device flat, +Y = top).
  static double headingDeg(double mx, double my) {
    double heading = math.atan2(-mx, my) * 180 / math.pi;
    if (heading < 0) heading += 360;
    return heading;
  }

  /// Tilt-compensated compass heading (0..360, 0 = magnetic north) of the
  /// direction the robot faces, from gravity (accelerometer, device frame)
  /// and the magnetometer. A phone lying flat faces its top edge (+Y); a
  /// phone standing upright — the usual robot mount, camera forward — faces
  /// where its back camera looks (−Z). [headingDeg] only handled the flat
  /// case and read an upright phone's heading as nonsense.
  static double facingHeadingDeg(
      double ax, double ay, double az, double mx, double my, double mz) {
    // East = field × gravity, North = gravity × East (as in Android's
    // SensorManager.getRotationMatrix).
    double hx = my * az - mz * ay, hy = mz * ax - mx * az, hz = mx * ay - my * ax;
    final hn = math.sqrt(hx * hx + hy * hy + hz * hz);
    final an = math.sqrt(ax * ax + ay * ay + az * az);
    if (hn < 1e-6 || an < 1e-6) return headingDeg(mx, my); // free fall / no field
    hx /= hn;
    hy /= hn;
    hz /= hn;
    final ux = ax / an, uy = ay / an, uz = az / an;
    final ny = uz * hx - ux * hz, nz = ux * hy - uy * hx;
    final flat = uz.abs() > 0.7071; // within 45° of lying flat
    final east = flat ? hy : -hz;
    final north = flat ? ny : -nz;
    double deg = math.atan2(east, north) * 180 / math.pi;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// Rotation rate about the vertical (gravity) axis, whatever way the phone
  /// is mounted. Counter-clockwise seen from above is positive.
  static double yawRateRadS(
      double gx, double gy, double gz, double ax, double ay, double az) {
    final an = math.sqrt(ax * ax + ay * ay + az * az);
    if (an < 1e-6) return gz;
    return (gx * ax + gy * ay + gz * az) / an;
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

  // 20 ms sampling while a program runs: the platform default ("normal",
  // ~200 ms on Android) makes tilt steering and shake detection feel laggy.
  // While idle the UI rate (~66 ms) is plenty and saves battery.
  static const Duration _programRate = SensorInterval.gameInterval;
  static const Duration _idleRate = SensorInterval.uiInterval;
  Duration _samplingPeriod = _idleRate;

  /// Switches between program-rate (true) and idle-rate sampling.
  void setHighRate(bool high) {
    final period = high ? _programRate : _idleRate;
    if (period == _samplingPeriod) return;
    _samplingPeriod = period;
    if (isListening) {
      // sensors_plus fixes the rate per subscription: re-subscribe.
      stopListening();
      startListening();
    }
  }

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

  /// Pitch angle in degrees. 0° = flat. Negative = tilted forward (top edge down).
  double get tiltX => SensorMath.pitchDeg(_gravX, _gravY, _gravZ);

  /// Roll angle in degrees. 0° = flat. Negative = tilted right, positive = left.
  double get tiltY => SensorMath.rollDeg(_gravX, _gravY, _gravZ);

  /// True when the phone is tilted more than [tiltThresholdDeg] on either axis.
  bool get isTilted =>
      tiltX.abs() > tiltThresholdDeg || tiltY.abs() > tiltThresholdDeg;

  /// True when linear acceleration exceeds [shakeThreshold].
  bool get isShaking =>
      SensorMath.shakeMagnitude(_lastX, _lastY, _lastZ) > shakeThreshold;

  double get _yawRadS =>
      SensorMath.yawRateRadS(_gyroX, _gyroY, _gyroZ, _gravX, _gravY, _gravZ);

  /// Turning rate about the vertical axis (yaw) in deg/s, for a phone lying
  /// flat or standing upright. Positive = counter-clockwise seen from above
  /// (turning left).
  double get rotationRateDegS => _yawRadS * 180 / math.pi;

  /// True when the device is turning quickly (≈ 57 deg/s).
  bool get isRotating => _yawRadS.abs() > rotatingThresholdRadS;

  /// Compass heading 0-360° (0 = North, 90 = East) of the direction the robot
  /// faces: the top edge of a flat phone, or the back camera of an upright
  /// one. Tilt-compensated. Requires a magnetometer.
  double get compassHeading =>
      SensorMath.facingHeadingDeg(_gravX, _gravY, _gravZ, _magX, _magY, _magZ);

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

  /// Low-pass filtered accelerometer (gravity reaction, device frame, m/s²).
  List<double> get gravity => [_gravX, _gravY, _gravZ];

  // For telemetry
  List<double> get currentValues => [_lastX, _lastY, _lastZ];
  List<double> get gyroValues => [_gyroX, _gyroY, _gyroZ];
  List<double> get magValues => [_magX, _magY, _magZ];
}
