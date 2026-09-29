import 'package:flutter/material.dart';
import 'dart:math';
import '../logic/block_script_runner.dart'; // Added

class NeuralCoreHeader extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onConnect;

  const NeuralCoreHeader({
    super.key,
    required this.isConnected,
    required this.onConnect,
  });

  @override
  State<NeuralCoreHeader> createState() => _NeuralCoreHeaderState();
}

class _NeuralCoreHeaderState extends State<NeuralCoreHeader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Neuron> _neurons = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    
    _generateNeurons();
  }

  void _generateNeurons() {
    _neurons.clear();
    for (int i = 0; i < 20; i++) {
      _neurons.add(_Neuron(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 3 + 1,
        speed: _random.nextDouble() * 0.05 + 0.01,
        angle: _random.nextDouble() * 2 * pi,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      height: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isConnected 
              ? [const Color(0xFF10B981), const Color(0xFF059669)]
              : [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
        ),
        boxShadow: [
          BoxShadow(
            color: (widget.isConnected ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Stack(
        children: [
          // Animated Background
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _NeuralNetworkPainter(
                      neurons: _neurons,
                      animation: _controller.value,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Content
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isConnected ? Icons.link : Icons.link_off,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.isConnected ? "SYSTEM ONLINE" : "SYSTEM OFFLINE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  "DoRobotics",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                
                // Voice Captions
                StreamBuilder<String>(
                  stream: BlockScriptRunner().voiceStream,
                  initialData: '',
                  builder: (context, snapshot) {
                    final text = snapshot.data ?? '';
                    if (text.isNotEmpty) {
                       return Padding(
                         padding: const EdgeInsets.only(top: 8),
                         child: Container(
                           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                           decoration: BoxDecoration(
                             color: Colors.black.withValues(alpha: 0.3),
                             borderRadius: BorderRadius.circular(16),
                           ),
                           child: Text(
                             "\"$text\"",
                             style: const TextStyle(
                               color: Colors.white,
                               fontSize: 14,
                               fontStyle: FontStyle.italic,
                             ),
                           ),
                         ),
                       );
                    }
                    return Text(
                      widget.isConnected 
                          ? "Ready for commands." 
                          : "Tap to connect your robot brain.",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          
          // Tap anywhere on the header to open the connection menu (switch
          // transport, WiFi setup, disconnect) — also while connected.
          Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onConnect,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Neuron {
  double x, y;
  final double size;
  final double speed;
  final double angle;

  _Neuron({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.angle,
  });
}

class _NeuralNetworkPainter extends CustomPainter {
  final List<_Neuron> neurons;
  final double animation;
  final Color color;

  _NeuralNetworkPainter({
    required this.neurons,
    required this.animation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    for (var neuron in neurons) {
      // Move neurons
      neuron.x += cos(neuron.angle) * neuron.speed * 0.01;
      neuron.y += sin(neuron.angle) * neuron.speed * 0.01;

      // Wrap around
      if (neuron.x < 0) neuron.x = 1;
      if (neuron.x > 1) neuron.x = 0;
      if (neuron.y < 0) neuron.y = 1;
      if (neuron.y > 1) neuron.y = 0;

      final nx = neuron.x * size.width;
      final ny = neuron.y * size.height;

      // Draw connections
      for (var other in neurons) {
        final ox = other.x * size.width;
        final oy = other.y * size.height;
        final dist = sqrt(pow(nx - ox, 2) + pow(ny - oy, 2));

        if (dist < 100) {
          linePaint.color = color.withValues(alpha: 0.3 * (1 - dist / 100));
          canvas.drawLine(Offset(nx, ny), Offset(ox, oy), linePaint);
        }
      }

      // Draw neuron
      canvas.drawCircle(Offset(nx, ny), neuron.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
