import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ColorTracker {
  Color? targetColor;
  double tolerance = 30.0; // HSV hue tolerance in degrees
  
  List<Rect> trackColor(CameraImage cameraImage) {
    if (targetColor == null) return [];
    
    try {
      // Convert camera image to analyzable format
      final image = _convertToImage(cameraImage);
      if (image == null) return [];
      
      // Find regions matching the target color
      return _findColorRegions(image);
    } catch (e) {
      debugPrint('Color tracking error: $e');
      return [];
    }
  }
  
  img.Image? _convertToImage(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
      
      // Use simplified conversion for speed (sample every 4th pixel)
      final image = img.Image(width: width ~/ 4, height: height ~/ 4);
      
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      
      for (int y = 0; y < height; y += 4) {
        for (int x = 0; x < width; x += 4) {
          final int yIndex = y * yPlane.bytesPerRow + x;
          final int uvIndex = (y >> 1) * uPlane.bytesPerRow + (x >> 1) * (uPlane.bytesPerPixel ?? 1);
          
          if (yIndex >= yPlane.bytes.length || uvIndex >= uPlane.bytes.length) continue;
          
          final int yValue = yPlane.bytes[yIndex];
          final int uValue = uPlane.bytes[uvIndex] - 128;
          final int vValue = vPlane.bytes[uvIndex] - 128;
          
          final int r = (yValue + (vValue * 1436) >> 10).clamp(0, 255);
          final int g = (yValue - (uValue * 352 + vValue * 731) >> 10).clamp(0, 255);
          final int b = (yValue + (uValue * 1814) >> 10).clamp(0, 255);
          
          image.setPixelRgb(x ~/ 4, y ~/ 4, r, g, b);
        }
      }
      
      return image;
    } catch (e) {
      return null;
    }
  }
  
  List<Rect> _findColorRegions(img.Image image) {
    final matches = <Point>[];
    final targetHSV = _rgbToHSV(targetColor!);
    
    // Find all pixels matching the color
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final pixelColor = Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
        
        if (_colorsMatch(pixelColor, targetHSV)) {
          matches.add(Point(x * 4, y * 4)); // Scale back to original coords
        }
      }
    }
    
    if (matches.isEmpty) return [];
    
    // Create bounding box around color regions
    return _createBoundingBoxes(matches);
  }
  
  List<double> _rgbToHSV(Color color) {
    final r = (color.r * 255).round() / 255.0;
    final g = (color.g * 255).round() / 255.0;
    final b = (color.b * 255).round() / 255.0;
    
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    final delta = max - min;
    
    double h = 0;
    if (delta != 0) {
      if (max == r) {
        h = 60 * (((g - b) / delta) % 6);
      } else if (max == g) {
        h = 60 * (((b - r) / delta) + 2);
      } else {
        h = 60 * (((r - g) / delta) + 4);
      }
    }
    if (h < 0) h += 360;
    
    final s = max == 0 ? 0.0 : delta / max;
    final v = max;
    
    return [h, s, v];
  }
  
  bool _colorsMatch(Color pixel, List<double> targetHSV) {
    final pixelHSV = _rgbToHSV(pixel);
    
    // Check hue difference (circular)
    double hueDiff = (pixelHSV[0] - targetHSV[0]).abs();
    if (hueDiff > 180) hueDiff = 360 - hueDiff;
    
    // Match if hue is within tolerance and saturation/value are reasonable
    return hueDiff < tolerance && 
           pixelHSV[1] > 0.2 && // Minimum saturation
           pixelHSV[2] > 0.2;   // Minimum brightness
  }
  
  List<Rect> _createBoundingBoxes(List<Point> points) {
    if (points.isEmpty) return [];
    
    // Simple approach: create one large box
    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;
    
    for (var point in points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    
    // Add padding
    const padding = 20.0;
    return [
      Rect.fromLTRB(
        (minX - padding).clamp(0, double.infinity),
        (minY - padding).clamp(0, double.infinity),
        maxX + padding,
        maxY + padding,
      )
    ];
  }
}

class Point {
  final double x;
  final double y;
  Point(this.x, this.y);
}
