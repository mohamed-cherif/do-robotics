import 'dart:math' as math;

/// How the phone is attached to the robot. Only affects which way the camera
/// picture is turned before the AI sees it; steering values are always in
/// the robot's own left/right, whatever the mount.
///
/// "Left" and "right" for the sideways mounts are as seen from the screen.
enum PhoneMount {
  /// Decide from gravity, recommended.
  auto('Automatic', 'Detects whether the phone is upright, upside down or on its side.'),
  /// Screen upright, top edge up.
  upright('Upright', 'Top edge of the phone points up.'),
  /// Screen upside down, top edge pointing at the floor.
  upsideDown('Upside down', 'Top edge of the phone points down.'),
  /// On its side, top edge pointing left (seen from the screen).
  topLeft('On its side, top to the left', 'Seen from the screen, the top edge points left.'),
  /// On its side, top edge pointing right (seen from the screen).
  topRight('On its side, top to the right', 'Seen from the screen, the top edge points right.');

  const PhoneMount(this.label, this.description);
  final String label;
  final String description;

  /// The phone's turn for a fixed mount (see [MountDetector.rotation]), or
  /// null for [auto].
  int? get fixedRotation => switch (this) {
        PhoneMount.auto => null,
        PhoneMount.upright => 0,
        PhoneMount.topLeft => 90,
        PhoneMount.upsideDown => 180,
        PhoneMount.topRight => 270,
      };
}

/// Decides from gravity how the phone is turned (upright, on its side or
/// upside down), with hysteresis so a bump or a moment of tilting doesn't
/// change it.
///
/// The accelerometer reads +g along the axis pointing up (the reaction to
/// gravity): +Y when the phone stands upright, −Y when it is upside down,
/// +X when it lies on its side with the top edge to the left (seen from the
/// screen), −X with the top edge to the right. Only the part of gravity in
/// the screen's plane matters, so a phone leaning back against a support (up
/// to ~70° from vertical) is still recognised. Lying nearly flat keeps the
/// last decision.
class MountDetector {
  MountDetector({this.holdTime = const Duration(milliseconds: 800)});

  /// A new reading must persist this long before the decision changes.
  final Duration holdTime;

  int _rotation = 0;
  int? _candidate;
  DateTime _candidateSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// How far the phone is turned counter-clockwise from upright, seen from
  /// the screen: 0 upright, 90 top edge left, 180 upside down, 270 top edge
  /// right. The same convention as Android's display rotation.
  int get rotation => _rotation;

  bool get upsideDown => _rotation == 180;

  /// Reads the turn from one gravity sample, or null when it can't tell
  /// (no clear pull, or the phone is nearly flat). Public for tests.
  static int? reading(double gx, double gy, double gz) {
    final g = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (g <= 3) return null;
    // Gravity in the screen's plane: big enough when the phone is more than
    // ~20° from lying flat (sin 20° ≈ 0.34). The axis it pulls along most
    // (within 45°) gives the turn. An earlier rule needed the phone within
    // ~53° of vertical, so a phone leaning on the robot was taken as
    // upright and steering came out mirrored.
    final inPlane = math.sqrt(gx * gx + gy * gy);
    if (inPlane <= 0.34 * g) return null;
    if (gy.abs() > gx.abs()) return gy > 0 ? 0 : 180;
    return gx > 0 ? 90 : 270;
  }

  /// Feeds one accelerometer sample (device frame) and returns the decision.
  int update(double gx, double gy, double gz, DateTime now) {
    final r = reading(gx, gy, gz);
    if (r == null || r == _rotation) {
      _candidate = null;
      return _rotation;
    }
    if (_candidate != r) {
      _candidate = r;
      _candidateSince = now;
    } else if (now.difference(_candidateSince) >= holdTime) {
      _rotation = r;
      _candidate = null;
    }
    return _rotation;
  }

  /// Plain-language name of a turn, for the log.
  static String describe(int rotation) => switch (rotation) {
        90 => 'on its side (top to the left)',
        180 => 'upside down',
        270 => 'on its side (top to the right)',
        _ => 'upright',
      };
}
