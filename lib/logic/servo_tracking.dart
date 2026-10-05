/// Pointing a positional servo at the locked target (the Track X block),
/// shared by the block runner and the Python it converts to.
///
/// Two ways to build it:
/// - phone on the servo: the camera turns with the servo, so the servo is
///   nudged a little toward the target with every new picture until the
///   target is centred. (Setting the angle straight from the picture makes
///   it swing back as soon as the target is centred, and never settle.)
/// - phone fixed: the phone stays still and the servo points on its own, so
///   the target's place in the picture maps to an angle, smoothed so the
///   servo doesn't twitch with every small change of the box.
class ServoTracking {
  static const String onServo = 'PHONE ON SERVO';
  static const String fixed = 'PHONE FIXED';
  static const List<String> modes = [onServo, fixed];

  /// Phone on servo: no nudge while the target is this close to the centre.
  static const double deadband = 0.08;

  /// Phone on servo: degrees per new picture with the target at the edge,
  /// per unit of strength (strength 50 → 6°).
  static const double stepPerStrength = 0.12;

  /// Phone fixed: degrees the servo turns for a target at the edge of the
  /// picture, per unit of strength (strength 50 → 30°, about half of what a
  /// portrait phone camera sees).
  static const double edgePerStrength = 0.6;

  /// Phone fixed: share of the way to the new angle covered per picture.
  static const double smoothing = 0.5;

  /// The next servo angle (degrees, 90 = centre) from [current], for a
  /// target at horizontal offset [x] (-1 left of the picture .. +1 right).
  /// A target on the right lowers the angle unless [reversed].
  static double next(String mode, double current, double x, int strength, {bool reversed = false}) {
    final s = reversed ? -1.0 : 1.0;
    if (mode == fixed) {
      final target = 90 - s * x * edgePerStrength * strength;
      return current + (target - current) * smoothing;
    }
    if (x.abs() < deadband) return current;
    return current - s * x * stepPerStrength * strength;
  }
}
