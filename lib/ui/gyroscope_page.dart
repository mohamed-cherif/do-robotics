import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/sensor_service.dart';

class GyroscopePage extends StatefulWidget {
  const GyroscopePage({super.key});

  @override
  State<GyroscopePage> createState() => _GyroscopePageState();
}

class _GyroscopePageState extends State<GyroscopePage>
    with SingleTickerProviderStateMixin {
  final SensorService _sensors = SensorService();
  StreamSubscription? _sub;

  double _x = 0, _y = 0, _z = 0;
  double _rateDegS = 0;
  bool _isRotating = false;

  // Simulated rotation angle for the visual dial
  double _dialAngle = 0;

  // History for graph
  final List<double> _zHistory = List.filled(80, 0);
  int _historyIndex = 0;

  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();

    _sensors.startListening();
    _sub = _sensors.gyroStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _x = e.x * 180 / math.pi;
        _y = e.y * 180 / math.pi;
        _z = e.z * 180 / math.pi;
        _rateDegS = _z;
        _isRotating = e.z.abs() > 1.0;
        _dialAngle += e.z * 0.04; // integrate for visual
        _zHistory[_historyIndex % 80] = _z;
        _historyIndex++;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gyroscope"),
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Spin dial
          _card(child: Column(children: [
            Text("Rotation Rate",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const SizedBox(height: 16),
            _SpinDial(angleDeg: _dialAngle, rateDegS: _rateDegS),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _StatChip(label: "Z-Axis", value: "${_rateDegS.toStringAsFixed(1)}°/s", color: Colors.teal),
              _StatChip(label: "Status", value: _isRotating ? "SPINNING" : "STILL",
                  color: _isRotating ? Colors.orange : Colors.grey),
            ]),
          ])),

          const SizedBox(height: 14),

          // All axes
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("All Axes  (°/s)",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              const SizedBox(height: 14),
              _GyroAxisRow(label: "X  (pitch)", value: _x, color: Colors.red),
              const SizedBox(height: 8),
              _GyroAxisRow(label: "Y  (roll)",  value: _y, color: Colors.green),
              const SizedBox(height: 8),
              _GyroAxisRow(label: "Z  (yaw)",   value: _z, color: Colors.teal),
            ],
          )),

          const SizedBox(height: 14),

          // Z-axis graph
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Z-Axis Live Graph  (yaw)",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              const SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: CustomPaint(
                  painter: _GyroWaveformPainter(
                      data: List.of(_zHistory), headIndex: _historyIndex % 80),
                  size: Size.infinite,
                ),
              ),
            ],
          )),

          const SizedBox(height: 14),

          // Block outputs
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Block Outputs",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              const SizedBox(height: 14),
              _BlockOutput(
                emoji: "🌀",
                label: "Phone Spinning",
                description: "Triggers when Z rotation > 57°/s (1 rad/s)",
                active: _isRotating,
                color: Colors.teal,
              ),
              const SizedBox(height: 10),
              _BlockOutput(
                emoji: "🔃",
                label: "Rotation Rate°/s",
                description: "Numeric: ${_rateDegS.toStringAsFixed(1)}°/s  (positive = clockwise)",
                active: true,
                color: Colors.teal,
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
  );
}

// ── Spin dial ─────────────────────────────────────────────────────────────────

class _SpinDial extends StatelessWidget {
  final double angleDeg, rateDegS;
  const _SpinDial({required this.angleDeg, required this.rateDegS});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160, height: 160,
      child: CustomPaint(painter: _DialPainter(angleDeg: angleDeg, rateDegS: rateDegS)),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double angleDeg, rateDegS;
  _DialPainter({required this.angleDeg, required this.rateDegS});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    final speed = (rateDegS.abs() / 200).clamp(0.0, 1.0);
    final dialColor = Color.lerp(Colors.teal[200], Colors.orange, speed)!;

    // Background
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF3F4F6));
    canvas.drawCircle(c, r, Paint()
      ..color = dialColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke..strokeWidth = 3);

    // Tick marks (every 30°)
    final tickPaint = Paint()..color = Colors.grey[300]!..strokeWidth = 1;
    for (int i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        Offset(c.dx + (r - 10) * math.cos(a), c.dy + (r - 10) * math.sin(a)),
        Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a)),
        tickPaint,
      );
    }

    // Rotating pointer (integrated angle)
    final pointerAngle = angleDeg * math.pi / 180;
    final tip = Offset(c.dx + (r - 12) * math.cos(pointerAngle),
                       c.dy + (r - 12) * math.sin(pointerAngle));
    canvas.drawLine(c, tip, Paint()
      ..color = dialColor..strokeWidth = 3..strokeCap = StrokeCap.round);

    // Rate arc
    final sweepAngle = (rateDegS / 200).clamp(-1.0, 1.0) * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 6),
      -math.pi / 2, sweepAngle,
      false,
      Paint()
        ..color = dialColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // Center dot
    canvas.drawCircle(c, 5, Paint()..color = Colors.teal);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.angleDeg != angleDeg || old.rateDegS != rateDegS;
}

// ── Waveform ──────────────────────────────────────────────────────────────────

class _GyroWaveformPainter extends CustomPainter {
  final List<double> data;
  final int headIndex;
  _GyroWaveformPainter({required this.data, required this.headIndex});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2),
        Paint()..color = Colors.grey[200]!..strokeWidth = 1);
    final paint = Paint()..color = Colors.teal..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final idx = (headIndex + i) % data.length;
      final x = i / (data.length - 1) * size.width;
      final y = size.height / 2 - (data[idx] / 200).clamp(-1.0, 1.0) * (size.height / 2);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GyroWaveformPainter old) => old.headIndex != headIndex;
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _GyroAxisRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _GyroAxisRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final norm = (value / 200).clamp(-1.0, 1.0);
    return Row(children: [
      SizedBox(width: 80,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
      Expanded(child: LayoutBuilder(builder: (ctx, c) {
        final mid = c.maxWidth / 2;
        final w = (norm.abs() * mid).clamp(0.0, mid);
        return SizedBox(height: 12, child: Stack(children: [
          Container(decoration: BoxDecoration(color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6))),
          Positioned(left: norm >= 0 ? mid : mid - w, width: w, top: 0, bottom: 0,
              child: Container(decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6)))),
          Positioned(left: mid - 0.5, width: 1, top: 0, bottom: 0,
              child: Container(color: Colors.grey[300])),
        ]));
      })),
      const SizedBox(width: 8),
      SizedBox(width: 60, child: Text(
        "${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}",
        style: TextStyle(fontSize: 11, color: Colors.grey[700],
            fontFeatures: const [FontFeature.tabularFigures()]),
        textAlign: TextAlign.right,
      )),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
        color: color, fontFeatures: const [FontFeature.tabularFigures()])),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
  ]);
}

class _BlockOutput extends StatelessWidget {
  final String emoji, label, description;
  final bool active;
  final Color color;
  const _BlockOutput({required this.emoji, required this.label,
      required this.description, required this.active, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(emoji, style: const TextStyle(fontSize: 20)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      Text(description, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ])),
    AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color : Colors.grey[300]!),
      ),
      child: Text(active ? "TRUE" : "FALSE",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: active ? color : Colors.grey[400])),
    ),
  ]);
}
