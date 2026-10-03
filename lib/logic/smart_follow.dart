/// Steering for the Smart Follow block, shared by the block runner and the
/// Python that "Convert to Python" generates for it.
///
/// One update per camera frame: the robot drives forward while the target
/// is near the centre of the picture and turns harder the further off-centre
/// it is — on the spot beyond [spinOffset].
class SmartFollowControl {
  /// Turn strength per unit of offset: full turn from |x| = 1 / turnGain.
  static const double turnGain = 1.6;

  /// Forward speed fades to 0 as the target's offset nears this value.
  static const double spinOffset = 0.6;

  /// Left / right wheel speeds (-255..255, negative = backward) to steer
  /// toward a target at horizontal offset [x] (-1 left .. +1 right).
  /// [base] is the cruising speed, [min] the lowest speed that makes a wheel
  /// actually turn (see [wheel]).
  static (int, int) wheelSpeeds(double x, int base, int min) {
    final forward = base * (1 - x.abs() / spinOffset).clamp(0.0, 1.0);
    final turn = base * (turnGain * x).clamp(-1.0, 1.0);
    return (wheel(forward + turn, min), wheel(forward - turn, min));
  }

  /// Gear motors don't move below a certain power: speeds under [min] are
  /// raised to it, and those under half of it are dropped to 0 (stop rather
  /// than hum).
  static int wheel(double v, int min) {
    final a = v.abs();
    if (a < min / 2) return 0;
    final s = (a < min ? min.toDouble() : a).clamp(0.0, 255.0).round();
    return v < 0 ? -s : s;
  }
}
