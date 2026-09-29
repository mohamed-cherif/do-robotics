import 'package:flutter/material.dart';
import '../../services/vision_service.dart';

class InferencePainter extends CustomPainter {
  final List<DetectedObjectData> objects;
  final Size absoluteImageSize;
  final Size widgetSize; 
  final BoxFit fit;
  final DetectedObjectData? lockedData;

  InferencePainter({
    required this.objects,
    required this.absoluteImageSize, 
    required this.widgetSize,
    this.fit = BoxFit.contain,
    this.lockedData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Calculate Actual Video Position
    final FittedSizes sizes = applyBoxFit(fit, absoluteImageSize, widgetSize);
    final Rect inputRect = Alignment.center.inscribe(sizes.destination, Offset.zero & widgetSize);
    
    // Paints
    final Paint paintNormal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFF00FFCC); // Cyan (Normal)

    final Paint paintLocked = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..color = Colors.greenAccent; // Green (Locked)
      
    final Paint bgPaint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.fill;
      
    final Paint textBgPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    for (var object in objects) {
      final Rect scaledRect = Rect.fromLTRB(
        inputRect.left + object.boundingBox.left * inputRect.width,
        inputRect.top + object.boundingBox.top * inputRect.height,
        inputRect.left + object.boundingBox.right * inputRect.width,
        inputRect.top + object.boundingBox.bottom * inputRect.height,
      );
      
      // Check if this detection matches the locked/tracked object.
      // Use label match + tight distance threshold to avoid highlighting the
      // wrong object when multiple instances of the same class are visible.
      final bool match = lockedData != null &&
          lockedData!.labels.isNotEmpty && object.labels.isNotEmpty &&
          lockedData!.labels.first == object.labels.first &&
          (lockedData!.boundingBox.center - object.boundingBox.center).distance < 0.1;
      
      final activePaint = match ? paintLocked : paintNormal;
      
      canvas.drawRect(scaledRect, activePaint);
      if (match) {
         // Draw crosshair or extra highlight
         canvas.drawCircle(scaledRect.center, 5, Paint()..color = Colors.green);
      } else {
         canvas.drawRect(scaledRect, bgPaint);
      }
      
      // Draw Label
      if (object.labels.isNotEmpty) {
        String labelText = object.labels.first;
        if (object.confidence > 0) {
           labelText += ' ${(object.confidence * 100).toInt()}%';
        }
         
        final textStyle = TextStyle(
          color: match ? Colors.greenAccent : const Color(0xFF00FFCC),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        );
        
        final textSpan = TextSpan(
          text: labelText,
          style: textStyle,
        );
        
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        
        textPainter.layout();
        
        canvas.drawRect(
          Rect.fromLTWH(scaledRect.left, scaledRect.top - 20, textPainter.width + 10, 20),
          textBgPaint,
        );
        
        textPainter.paint(canvas, Offset(scaledRect.left + 5, scaledRect.top - 18));
      }
    }
  }

  @override
  bool shouldRepaint(covariant InferencePainter oldDelegate) {
    return oldDelegate.objects != objects || 
           oldDelegate.widgetSize != widgetSize || 
           oldDelegate.fit != fit ||
           oldDelegate.lockedData != lockedData;
  }
}
