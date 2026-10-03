import 'dart:math' as math;

/// How the phone is attached to the robot. Only affects which way the camera
/// picture is turned before the AI sees it; steering values are always in
/// the robot's own left/right, whatever the mount.
enum PhoneMount {
  /// Decide from gravity (upright vs. upside down), recommended.
  auto('Automatic', 'Detects whether the phone is upright or upside down.'),
  /// Screen upright, top edge up.
  upright('Upright', 'Top edge of the phone points up.'),
  /// Screen upside down, top edge pointing at the floor.
  upsideDown('Upside down', 'Top edge of the phone points down.');

  const PhoneMount(this.label, this.description);
  final String label;
  final String description;
}

/// Decides from gravity whether a portrait phone is upright or upside down,
/// with hysteresis so a bump or a moment of tilting doesn't flip it.
///
/// The accelerometer reads +g along the axis pointing up (the reaction to
/// gravity): +Y when the phone stands upright, −Y when it is upside down.
/// Only the part of gravity in the screen's plane matters, so a phone
/// leaning back against a support (up to ~70° from vertical) is still
/// recognised. Lying nearly flat or on its side keeps the last decision.
class MountDetector {
  MountDetector({this.holdTime = const Duration(milliseconds: 800)});

  /// A new reading must persist this long before the decision changes.
  final Duration holdTime;

  bool _upsideDown = false;
  bool? _candidate;
  DateTime _candidateSince = DateTime.fromMillisecondsSinceEpoch(0);

  bool get upsideDown => _upsideDown;

  /// Feeds one accelerometer sample (device frame) and returns the decision.
  bool update(double gx, double gy, double gz, DateTime now) {
    final g = math.sqrt(gx * gx + gy * gy + gz * gz);
    bool? reading;
    if (g > 3) {
      // Gravity in the screen's plane: big enough when the phone is more
      // than ~20° from lying flat (sin 20° ≈ 0.34). Then it is upright or
      // upside down if that pull is closer to the long axis than to the
      // short one (within 45° of portrait). An earlier rule needed the
      // phone within ~53° of vertical, so a phone leaning on the robot was
      // taken as upright and steering came out mirrored.
      final inPlane = math.sqrt(gx * gx + gy * gy);
      if (inPlane > 0.34 * g && gy.abs() > gx.abs()) {
        reading = gy < 0;
      }
    }
    if (reading == null || reading == _upsideDown) {
      _candidate = null;
      return _upsideDown;
    }
    if (_candidate != reading) {
      _candidate = reading;
      _candidateSince = now;
    } else if (now.difference(_candidateSince) >= holdTime) {
      _upsideDown = reading;
      _candidate = null;
    }
    return _upsideDown;
  }
}
