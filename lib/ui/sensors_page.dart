import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/sensor_service.dart';
import 'vision_page.dart';
import 'microphone_page.dart';
import 'accelerometer_page.dart';
import 'gyroscope_page.dart';
import 'compass_page.dart';

class SensorsPage extends StatefulWidget {
  const SensorsPage({super.key});

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
  final SensorService _sensors = SensorService();

  // Live values
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroZ = 0;
  double _heading = 0;
  bool _isShaking = false;
  bool _isRotating = false;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _magSub;

  @override
  void initState() {
    super.initState();
    _sensors.startListening();

    _accelSub = _sensors.typeFilteredAccelStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _accelX = e.x;
        _accelY = e.y;
        _accelZ = e.z;
        final mag = (e.x.abs() + e.y.abs() + e.z.abs()) / 3;
        _isShaking = mag > 5.0;
      });
    });

    _gyroSub = _sensors.gyroStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _gyroZ = e.z * 180 / math.pi;
        _isRotating = e.z.abs() > 1.0;
      });
    });

    _magSub = _sensors.magnetometerStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _heading = _sensors.compassHeading;
      });
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sensors"),
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Live Sensor Preview",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            "Tap any sensor to open full detail view",
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),

          // ── Camera ──────────────────────────────────────────────────────────
          _SensorCard(
            title: "Camera",
            subtitle: "Object Detection · Vision AI",
            icon: Icons.camera_alt_rounded,
            color: Colors.blue,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VisionPage())),
            preview: _StatusBadge(label: "TFLite Active", color: Colors.blue),
          ),

          // ── Microphone ───────────────────────────────────────────────────────
          _SensorCard(
            title: "Microphone",
            subtitle: "Sound Level · Voice Recognition",
            icon: Icons.mic_rounded,
            color: Colors.orange,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MicrophonePage())),
            preview: _StatusBadge(label: "Tap to test", color: Colors.orange),
          ),

          // ── Accelerometer ────────────────────────────────────────────────────
          _SensorCard(
            title: "Accelerometer",
            subtitle: "Motion · Shake · Tilt",
            icon: Icons.vibration_rounded,
            color: Colors.purple,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AccelerometerPage())),
            preview: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AxisBar(label: "X", value: _accelX, range: 10, color: Colors.red),
                const SizedBox(height: 6),
                _AxisBar(label: "Y", value: _accelY, range: 10, color: Colors.green),
                const SizedBox(height: 6),
                _AxisBar(label: "Z", value: _accelZ, range: 10, color: Colors.blue),
                const SizedBox(height: 8),
                Row(children: [
                  _Chip(label: "SHAKE", active: _isShaking, color: Colors.purple),
                  const SizedBox(width: 6),
                  _Chip(
                    label: "TILT",
                    active: _sensors.tiltX.abs() > 20 || _sensors.tiltY.abs() > 20,
                    color: Colors.deepPurple,
                  ),
                ]),
              ],
            ),
          ),

          // ── Gyroscope ────────────────────────────────────────────────────────
          _SensorCard(
            title: "Gyroscope",
            subtitle: "Rotation Rate · Spin Detection",
            icon: Icons.rotate_90_degrees_ccw_rounded,
            color: Colors.teal,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GyroscopePage())),
            preview: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _gyroZ.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(width: 4),
                    Text("°/s",
                        style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
                const SizedBox(height: 8),
                _AxisBar(
                    label: "Spin",
                    value: _gyroZ,
                    range: 200,
                    color: Colors.teal),
                const SizedBox(height: 8),
                _Chip(
                    label: "SPINNING",
                    active: _isRotating,
                    color: Colors.teal),
              ],
            ),
          ),

          // ── Compass ──────────────────────────────────────────────────────────
          _SensorCard(
            title: "Compass",
            subtitle: "Magnetic Heading · Direction",
            icon: Icons.explore_rounded,
            color: Colors.indigo,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CompassPage())),
            preview: Row(
              children: [
                _CompassNeedle(heading: _heading, size: 64),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${_heading.toStringAsFixed(0)}°",
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    Text(
                      _headingLabel(_heading),
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _headingLabel(double h) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    return dirs[((h + 22.5) / 45).floor().clamp(0, 8)];
  }
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Widget preview;

  const _SensorCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.grey[400], size: 22),
                ],
              ),
              const SizedBox(height: 14),
              preview,
            ],
          ),
        ),
      ),
    );
  }
}

class _AxisBar extends StatelessWidget {
  final String label;
  final double value;
  final double range;
  final Color color;

  const _AxisBar(
      {required this.label,
      required this.value,
      required this.range,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final normalized = (value / range).clamp(-1.0, 1.0);
    return Row(
      children: [
        SizedBox(
            width: 24,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600]))),
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            final mid = constraints.maxWidth / 2;
            final barW = (normalized.abs() * mid).clamp(0.0, mid);
            final isPos = normalized >= 0;
            return SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(5))),
                  Positioned(
                    left: isPos ? mid : mid - barW,
                    width: barW,
                    top: 0,
                    bottom: 0,
                    child: Container(
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(5))),
                  ),
                  Positioned(
                    left: mid - 0.5,
                    width: 1,
                    top: 0,
                    bottom: 0,
                    child: Container(color: Colors.grey[300]),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          child: Text(
            value.toStringAsFixed(1),
            style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: Colors.grey[700]),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _Chip({required this.label, required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: active ? color : Colors.grey[300]!, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? color : Colors.grey[400],
            letterSpacing: 0.5),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _CompassNeedle extends StatelessWidget {
  final double heading;
  final double size;

  const _CompassNeedle({required this.heading, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _NeedlePainter(heading)),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  final double heading;
  _NeedlePainter(this.heading);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    canvas.drawCircle(
        center, radius, Paint()..color = const Color(0xFFF3F4F6));
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.indigo.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Cardinal tick marks
    final tickPaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1.0;
    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final inner = Offset(
          center.dx + (radius - 6) * math.cos(angle),
          center.dy + (radius - 6) * math.sin(angle));
      final outer = Offset(center.dx + (radius - 1) * math.cos(angle),
          center.dy + (radius - 1) * math.sin(angle));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Needle — rotated by heading
    final needleAngle = heading * math.pi / 180 - math.pi / 2;
    final northTip = Offset(
        center.dx + (radius - 8) * math.cos(needleAngle),
        center.dy + (radius - 8) * math.sin(needleAngle));
    final southTip = Offset(
        center.dx + (radius - 8) * math.cos(needleAngle + math.pi),
        center.dy + (radius - 8) * math.sin(needleAngle + math.pi));

    canvas.drawLine(
        southTip,
        northTip,
        Paint()
          ..color = Colors.red
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        center,
        southTip,
        Paint()
          ..color = Colors.grey[400]!
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);

    // Center dot
    canvas.drawCircle(center, 4, Paint()..color = Colors.indigo);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.heading != heading;
}
