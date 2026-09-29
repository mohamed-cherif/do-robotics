import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sensor_service.dart';

class AccelerometerPage extends StatefulWidget {
  const AccelerometerPage({super.key});

  @override
  State<AccelerometerPage> createState() => _AccelerometerPageState();
}

class _AccelerometerPageState extends State<AccelerometerPage> {
  final SensorService _sensors = SensorService();
  StreamSubscription? _sub;

  double _x = 0, _y = 0, _z = 0;
  double _pitch = 0, _roll = 0;
  bool _isShaking = false;
  bool _isTilted = false;

  // History for mini graph (last 60 readings)
  final List<double> _xHistory = List.filled(60, 0);
  final List<double> _yHistory = List.filled(60, 0);
  int _historyIndex = 0;

  @override
  void initState() {
    super.initState();
    _sensors.startListening();
    _sub = _sensors.typeFilteredAccelStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _x = e.x; _y = e.y; _z = e.z;
        _pitch = _sensors.tiltX;
        _roll  = _sensors.tiltY;
        // Same definitions the blocks use (SensorService), so what kids see
        // here is exactly what "Phone Shaking" / "Phone Tilted" will do.
        _isShaking = _sensors.isShaking;
        _isTilted  = _sensors.isTilted;
        _xHistory[_historyIndex % 60] = e.x;
        _yHistory[_historyIndex % 60] = e.y;
        _historyIndex++;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Accelerometer"),
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Bubble level
          _card(
            child: Column(
              children: [
                Text("Bubble Level",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 16),
                _BubbleLevel(roll: _roll, pitch: _pitch),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatItem(label: "Pitch", value: "${_pitch.toStringAsFixed(1)}°", color: Colors.orange),
                    _StatItem(label: "Roll",  value: "${_roll.toStringAsFixed(1)}°",  color: Colors.purple),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Axis values
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Raw Axes  (m/s²)",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 16),
                _AxisRow(label: "X", value: _x, color: Colors.red),
                const SizedBox(height: 10),
                _AxisRow(label: "Y", value: _y, color: Colors.green),
                const SizedBox(height: 10),
                _AxisRow(label: "Z", value: _z, color: Colors.blue),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Graph
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Live Graph",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      xData: List.of(_xHistory),
                      yData: List.of(_yHistory),
                      headIndex: _historyIndex % 60,
                    ),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _Legend(color: Colors.red, label: "X"),
                  const SizedBox(width: 16),
                  _Legend(color: Colors.green, label: "Y"),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Status chips
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Block Outputs",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                const SizedBox(height: 14),
                _BlockOutput(
                  emoji: "📳",
                  label: "Phone Shaking",
                  description: "Triggers when shaken harder than 5 m/s² (gravity removed)",
                  active: _isShaking,
                  color: Colors.purple,
                ),
                const SizedBox(height: 10),
                _BlockOutput(
                  emoji: "📐",
                  label: "Phone Tilted",
                  description: "Triggers when tilted more than 25° in any direction",
                  active: _isTilted,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 10),
                _BlockOutput(
                  emoji: "📐",
                  label: "Tilt Pitch°",
                  description: "Numeric: ${_pitch.toStringAsFixed(1)}°  (forward/backward tilt)",
                  active: true,
                  color: Colors.orange,
                ),
                const SizedBox(height: 10),
                _BlockOutput(
                  emoji: "📏",
                  label: "Tilt Roll°",
                  description: "Numeric: ${_roll.toStringAsFixed(1)}°  (− = tilted right, + = tilted left)",
                  active: true,
                  color: Colors.orange,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _BubbleLevel extends StatelessWidget {
  final double pitch, roll;
  const _BubbleLevel({required this.pitch, required this.roll});

  @override
  Widget build(BuildContext context) {
    const size = 160.0;
    final dx = (roll  / 45).clamp(-1.0, 1.0) * (size / 2 - 18);
    final dy = (pitch / 45).clamp(-1.0, 1.0) * (size / 2 - 18);
    final isLevel = roll.abs() < 5 && pitch.abs() < 5;
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[100],
            border: Border.all(color: Colors.grey[300]!, width: 1.5),
          ),
        ),
        // Cross hair
        Container(width: 1, height: size, color: Colors.grey[300]),
        Container(width: size, height: 1, color: Colors.grey[300]),
        // Center target circle
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey[400]!, width: 1),
          ),
        ),
        // Bubble
        Transform.translate(
          offset: Offset(dx, dy),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLevel
                  ? Colors.green.withValues(alpha: 0.85)
                  : Colors.purple.withValues(alpha: 0.75),
              boxShadow: [
                BoxShadow(color: (isLevel ? Colors.green : Colors.purple).withValues(alpha: 0.3),
                    blurRadius: 8, spreadRadius: 2),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> xData, yData;
  final int headIndex;
  _WaveformPainter({required this.xData, required this.yData, required this.headIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final count = xData.length;
    void drawLine(List<double> data, Color color) {
      final paint = Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < count; i++) {
        final idx = (headIndex + i) % count;
        final x = i / (count - 1) * size.width;
        final y = size.height / 2 - (data[idx] / 12) * (size.height / 2);
        if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      }
      canvas.drawPath(path, paint);
    }
    // Zero line
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2),
        Paint()..color = Colors.grey[200]!..strokeWidth = 1);
    drawLine(xData, Colors.red);
    drawLine(yData, Colors.green);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.headIndex != headIndex;
}

class _AxisRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _AxisRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final norm = (value / 10).clamp(-1.0, 1.0);
    return Row(children: [
      SizedBox(width: 20, child: Text(label,
          style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13))),
      const SizedBox(width: 8),
      Expanded(child: LayoutBuilder(builder: (ctx, c) {
        final mid = c.maxWidth / 2;
        final w = (norm.abs() * mid).clamp(0.0, mid);
        return SizedBox(height: 14, child: Stack(children: [
          Container(decoration: BoxDecoration(color: Colors.grey[100],
              borderRadius: BorderRadius.circular(7))),
          Positioned(left: norm >= 0 ? mid : mid - w, width: w, top: 0, bottom: 0,
            child: Container(decoration: BoxDecoration(color: color.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(7)))),
          Positioned(left: mid - 0.5, width: 1, top: 0, bottom: 0,
              child: Container(color: Colors.grey[300])),
        ]));
      })),
      const SizedBox(width: 8),
      SizedBox(width: 52, child: Text(
        "${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}",
        style: TextStyle(fontSize: 12, color: Colors.grey[700],
            fontFeatures: const [FontFeature.tabularFigures()]),
        textAlign: TextAlign.right,
      )),
    ]);
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatItem({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color,
          fontFeatures: const [FontFeature.tabularFigures()])),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ]);
  }
}

class _BlockOutput extends StatelessWidget {
  final String emoji, label, description;
  final bool active;
  final Color color;
  const _BlockOutput({required this.emoji, required this.label,
      required this.description, required this.active, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
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
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 16, height: 3, color: color),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
  ]);
}
