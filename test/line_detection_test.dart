import 'dart:typed_data';

import 'package:do_robotics/services/object_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a sensor-orientation luminance frame (as the camera delivers it)
/// from a picture described in the *upright* frame the user sees.
Uint8List sensorFrame({
  required int srcW,
  required int srcH,
  required int rotation,
  required int bytesPerRow,
  required bool Function(int ux, int uy, int uW, int uH) isLine,
}) {
  final swap = rotation == 90 || rotation == 270;
  final uW = swap ? srcH : srcW, uH = swap ? srcW : srcH;
  final out = Uint8List(bytesPerRow * srcH);
  for (int sy = 0; sy < srcH; sy++) {
    for (int sx = 0; sx < srcW; sx++) {
      int ux, uy;
      if (rotation == 90) {
        ux = srcH - 1 - sy;
        uy = sx;
      } else if (rotation == 270) {
        ux = sy;
        uy = srcW - 1 - sx;
      } else if (rotation == 180) {
        ux = srcW - 1 - sx;
        uy = srcH - 1 - sy;
      } else {
        ux = sx;
        uy = sy;
      }
      out[sy * bytesPerRow + sx] = isLine(ux, uy, uW, uH) ? 20 : 210;
    }
  }
  return out;
}

/// Dark tape, ~6% of the width, centred at [frac] of the upright width.
bool Function(int, int, int, int) tapeAt(double frac) =>
    (ux, uy, uW, uH) => (ux - frac * uW).abs() < uW * 0.03;

void main() {
  const w = 320, h = 240; // ResolutionPreset.low on most Android phones

  test('portrait phone (rotation 90): tape on the right reads as right', () {
    // Before the fix the detector ignored rotation, scanned a side strip of
    // the picture and saw no vertical edges at all.
    final luma = sensorFrame(srcW: w, srcH: h, rotation: 90, bytesPerRow: w, isLine: tapeAt(0.75));
    final r = ObjectDetectorService.detectLineInLuma(luma, w, w, h, 90);
    expect(r.detected, isTrue);
    expect(r.offsetX, closeTo(0.5, 0.05));
  });

  test('portrait phone: tape on the left reads as left', () {
    final luma = sensorFrame(srcW: w, srcH: h, rotation: 90, bytesPerRow: w, isLine: tapeAt(0.25));
    final r = ObjectDetectorService.detectLineInLuma(luma, w, w, h, 90);
    expect(r.detected, isTrue);
    expect(r.offsetX, closeTo(-0.5, 0.05));
  });

  test('landscape (rotation 0) keeps working as before', () {
    final luma = sensorFrame(srcW: w, srcH: h, rotation: 0, bytesPerRow: w, isLine: tapeAt(0.25));
    final r = ObjectDetectorService.detectLineInLuma(luma, w, w, h, 0);
    expect(r.detected, isTrue);
    expect(r.offsetX, closeTo(-0.5, 0.05));
  });

  test('upside-down mount (rotation 270) uses the display convention of object boxes', () {
    final luma = sensorFrame(srcW: w, srcH: h, rotation: 270, bytesPerRow: w, isLine: tapeAt(0.75));
    final r = ObjectDetectorService.detectLineInLuma(luma, w, w, h, 270);
    expect(r.detected, isTrue);
    // Object boxes are mapped to display space with a 180° flip for this
    // mount, so the line offset flips too.
    expect(r.offsetX, closeTo(-0.5, 0.05));
  });

  test('only the floor band counts: a line in the top half is ignored', () {
    final luma = sensorFrame(
        srcW: w, srcH: h, rotation: 90, bytesPerRow: w,
        isLine: (ux, uy, uW, uH) => uy < uH * 0.5 && (ux - 0.8 * uW).abs() < uW * 0.03);
    final r = ObjectDetectorService.detectLineInLuma(luma, w, w, h, 90);
    expect(r.detected, isFalse);
  });

  test('uniform floor is not a line', () {
    final luma = Uint8List(w * h)..fillRange(0, w * h, 128);
    final r = ObjectDetectorService.detectLineInLuma(luma, w, w, h, 90);
    expect(r.detected, isFalse);
    expect(r.offsetX, 0.0);
  });

  test('row padding (bytesPerRow > width) is respected', () {
    const stride = 384;
    final luma = sensorFrame(srcW: w, srcH: h, rotation: 90, bytesPerRow: stride, isLine: tapeAt(0.25));
    final r = ObjectDetectorService.detectLineInLuma(luma, stride, w, h, 90);
    expect(r.detected, isTrue);
    expect(r.offsetX, closeTo(-0.5, 0.05));
  });
}
