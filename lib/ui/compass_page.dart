import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/sensor_service.dart';

class CompassPage extends StatefulWidget {
  const CompassPage({super.key});

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> {
  final SensorService _sensors = SensorService();
  StreamSubscription? _magSub;

  double _heading = 0;

  @override
  void initState() {
    super.initState();
    _sensors.startListening();
    _magSub = _sensors.magnetometerStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _heading = _sensors.compassHeading;
      });
    });
  }

  @override
  void dispose() {
    _magSub?.cancel();
    super.dispose();
  }

  String _headingLabel(double heading) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) % 360) ~/ 45;
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Compass"),
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Compass visual
          _card(
            child: Column(
              children: [
                Text("Magnetic Heading",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 20),
                SizedBox(
                  width: 240,
                  height: 240,
                  child: CustomPaint(
                    painter: _CompassPainter(heading: _heading),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "${_heading.toStringAsFixed(0)}°",
                      style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _headingLabel(_heading),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Calibration tip
          _card(
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.indigo, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "Keep your phone away from strong magnets and metal objects. Move in a figure-8 to calibrate if the compass seems stuck.",
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Block outputs
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Block Outputs",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 14),
                _BlockOutput(
                  emoji: "🧭",
                  label: "Heading Angle",
                  description:
                      "Numeric: ${_heading.toStringAsFixed(0)}°  (0=N, 90=E, 180=S, 270=W)",
                  active: true,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                Text("Is Facing Directions (±22.5°)",
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DirectionChip(label: "N (0°)", active: _sensors.isFacing(0)),
                    _DirectionChip(label: "NE (45°)", active: _sensors.isFacing(45)),
                    _DirectionChip(label: "E (90°)", active: _sensors.isFacing(90)),
                    _DirectionChip(label: "SE (135°)", active: _sensors.isFacing(135)),
                    _DirectionChip(label: "S (180°)", active: _sensors.isFacing(180)),
                    _DirectionChip(label: "SW (225°)", active: _sensors.isFacing(225)),
                    _DirectionChip(label: "W (270°)", active: _sensors.isFacing(270)),
                    _DirectionChip(label: "NW (315°)", active: _sensors.isFacing(315)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4))
      ],
    ),
    child: child,
  );
}

class _DirectionChip extends StatelessWidget {
  final String label;
  final bool active;

  const _DirectionChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? Colors.indigo : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? Colors.indigo : Colors.grey[300]!,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.grey[600],
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _BlockOutput extends StatelessWidget {
  final String emoji, label, description;
  final bool active;
  final Color color;

  const _BlockOutput({
    required this.emoji,
    required this.label,
    required this.description,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              Text(description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        ),
        if (active)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text("TRUE",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text("FALSE",
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double heading;

  _CompassPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFF8FAFC)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.indigo.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Draw ticks and labels
    final tickPaint = Paint()..color = Colors.grey[400]!..strokeWidth = 2;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < 360; i += 15) {
      final angle = (i - 90) * math.pi / 180;
      final innerRadius = (i % 90 == 0)
          ? radius - 24
          : (i % 45 == 0)
              ? radius - 16
              : radius - 8;
      final p1 = Offset(
          center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      final p2 = Offset(center.dx + innerRadius * math.cos(angle),
          center.dy + innerRadius * math.sin(angle));
      canvas.drawLine(p1, p2, tickPaint);

      // Draw N, E, S, W
      if (i % 90 == 0) {
        String label = 'N';
        if (i == 90) label = 'E';
        if (i == 180) label = 'S';
        if (i == 270) label = 'W';

        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            color: i == 0 ? Colors.red : Colors.indigo[900],
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        final labelOffset = Offset(
          center.dx + (radius - 40) * math.cos(angle) - textPainter.width / 2,
          center.dy + (radius - 40) * math.sin(angle) - textPainter.height / 2,
        );
        textPainter.paint(canvas, labelOffset);
      }
    }

    // Draw needle
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);

    final needlePath = Path();

    // North pointing half (Red)
    needlePath.moveTo(0, -radius + 60);
    needlePath.lineTo(12, 0);
    needlePath.lineTo(-12, 0);
    needlePath.close();
    canvas.drawPath(needlePath, Paint()..color = Colors.red);

    // South pointing half (Grey)
    final southPath = Path();
    southPath.moveTo(0, radius - 60);
    southPath.lineTo(12, 0);
    southPath.lineTo(-12, 0);
    southPath.close();
    canvas.drawPath(southPath, Paint()..color = Colors.grey[400]!);

    // Center pivot
    canvas.drawCircle(Offset.zero, 8, Paint()..color = Colors.indigo[900]!);
    canvas.drawCircle(Offset.zero, 4, Paint()..color = Colors.white);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) => oldDelegate.heading != heading;
}
