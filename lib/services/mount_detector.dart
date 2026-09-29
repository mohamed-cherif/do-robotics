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
/// gravity): +Y when the phone stands upright, −Y when it is upside down,
/// ≈0 on Y when it lies flat (then the last decision is kept).
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
      // Clearly vertical-ish only (within ~53° of upright / upside down).
      if (gy < -0.6 * g) {
        reading = true;
      } else if (gy > 0.6 * g) {
        reading = false;
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
