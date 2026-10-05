import 'dart:typed_data';
import 'dart:ui';

import 'package:do_robotics/services/object_detector_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// How the upright camera picture is placed in the model input: a portrait
/// picture is stretched to fill it, a sideways one keeps its proportions at
/// the top with grey padding below, and boxes are mapped back to the
/// picture.
void main() {
  const pad = ObjectDetectorService.padValue;

  group('pictureArea', () {
    test('portrait (phone upright) fills the whole input, as before', () {
      expect(ObjectDetectorService.pictureArea(240, 320, 320, 320), (width: 320, height: 320));
    });

    test('landscape (phone on its side) keeps its proportions', () {
      expect(ObjectDetectorService.pictureArea(320, 240, 320, 320), (width: 320, height: 240));
      expect(ObjectDetectorService.pictureArea(640, 480, 320, 320), (width: 320, height: 240));
      expect(ObjectDetectorService.pictureArea(352, 288, 320, 320), (width: 320, height: 262));
    });

    test('a square picture fills the input', () {
      expect(ObjectDetectorService.pictureArea(320, 320, 320, 320), (width: 320, height: 320));
      expect(ObjectDetectorService.pictureArea(100, 100, 320, 320), (width: 320, height: 320));
    });
  });

  group('modelBoxToUpright', () {
    const sideways = (width: 320, height: 240);

    void expectRect(Rect? r, Rect want) {
      expect(r, isNotNull);
      expect(r!.left, closeTo(want.left, 1e-9));
      expect(r.top, closeTo(want.top, 1e-9));
      expect(r.right, closeTo(want.right, 1e-9));
      expect(r.bottom, closeTo(want.bottom, 1e-9));
    }

    test('portrait: the model box is the upright box', () {
      expectRect(
          ObjectDetectorService.modelBoxToUpright(
              [0.1, 0.2, 0.6, 0.9], (width: 320, height: 320), 320, 320),
          const Rect.fromLTRB(0.2, 0.1, 0.9, 0.6));
    });

    test('landscape: a box round-trips through the padded input', () {
      const upright = Rect.fromLTRB(0.25, 0.1, 0.75, 0.9);
      // Where the model sees it: same x, y squeezed into the top 240 rows.
      const k = 240 / 320;
      final model = [upright.top * k, upright.left, upright.bottom * k, upright.right];
      expectRect(ObjectDetectorService.modelBoxToUpright(model, sideways, 320, 320), upright);
    });

    test('a box running into the padding is clipped to the picture', () {
      expectRect(ObjectDetectorService.modelBoxToUpright([0.5, 0.0, 0.9, 0.5], sideways, 320, 320),
          const Rect.fromLTRB(0.0, 0.5 * 4 / 3, 0.5, 1.0));
    });

    test('a box only on the padding is dropped', () {
      expect(ObjectDetectorService.modelBoxToUpright([0.8, 0.1, 0.95, 0.4], sideways, 320, 320),
          isNull);
    });
  });

  group('tensor bytes', () {
    // Neutral chroma and a studio-swing Y per pixel, so every pixel decodes
    // to a distinct grey and its position in the tensor can be checked.
    int luma(int sx, int sy, int w) => 16 + 4 * (sy * w + sx);
    int grey(int y) => ((298 * (y - 16) + 128) >> 8).clamp(0, 255);

    List<(Uint8List, int, int?)> yuvFrame(int w, int h) {
      final y = Uint8List(w * h);
      for (var sy = 0; sy < h; sy++) {
        for (var sx = 0; sx < w; sx++) {
          y[sy * w + sx] = luma(sx, sy, w);
        }
      }
      final uv = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
      return [(y, w, 1), (uv, w ~/ 2, 1), (Uint8List.fromList(uv), w ~/ 2, 1)];
    }

    // Sensor pixel shown at upright (ux, uy) — the same turn as the line
    // detector's, written out independently of _directToTensor.
    (int, int) sensorAt(int ux, int uy, int w, int h, int rotation) => switch (rotation) {
          90 => (uy, h - 1 - ux),
          180 => (w - 1 - ux, h - 1 - uy),
          270 => (w - 1 - uy, ux),
          _ => (ux, uy),
        };

    /// Expected 8×8 input: the upright picture resized (nearest neighbour)
    /// into its area at the top-left, [pad] elsewhere.
    Uint8List expected(int w, int h, int rotation, PictureArea area) {
      final swap = rotation == 90 || rotation == 270;
      final uw = swap ? h : w, uh = swap ? w : h;
      final out = Uint8List(8 * 8 * 3)..fillRange(0, 8 * 8 * 3, pad);
      for (var ty = 0; ty < area.height; ty++) {
        for (var tx = 0; tx < area.width; tx++) {
          final (sx, sy) = sensorAt(tx * uw ~/ area.width, ty * uh ~/ area.height, w, h, rotation);
          final v = grey(luma(sx, sy, w));
          out.setRange((ty * 8 + tx) * 3, (ty * 8 + tx) * 3 + 3, [v, v, v]);
        }
      }
      return out;
    }

    for (final (w, h) in [(8, 6), (6, 8)]) {
      for (final rotation in [0, 90, 180, 270]) {
        final swap = rotation == 90 || rotation == 270;
        final sideways = (swap ? h : w) > (swap ? w : h);
        test('$w×$h sensor frame, rotation $rotation: '
            '${sideways ? 'top 6 rows of picture, grey below' : 'stretched to fill'}', () {
          final area = sideways ? (width: 8, height: 6) : (width: 8, height: 8);
          final t = ObjectDetectorService.debugFrameToTensor(yuvFrame(w, h), w, h, rotation, 8, 8)!;
          expect(t, expected(w, h, rotation, area));
          if (sideways) {
            expect(t.sublist(6 * 8 * 3), everyElement(pad));
            // Upright top-left pixel lands at the input's top-left.
            final (sx, sy) = sensorAt(0, 0, w, h, rotation);
            expect(t.sublist(0, 3), everyElement(grey(luma(sx, sy, w))));
          }
        });
      }
    }

    test('iOS BGRA frames and the slow path give the same input as YUV', () {
      const w = 8, h = 6;
      final yuv = ObjectDetectorService.debugFrameToTensor(yuvFrame(w, h), w, h, 90, 8, 8)!;
      final yuvSideways = ObjectDetectorService.debugFrameToTensor(yuvFrame(w, h), w, h, 0, 8, 8)!;

      final bgra = Uint8List(w * h * 4);
      final image = img.Image(width: w, height: h);
      for (var sy = 0; sy < h; sy++) {
        for (var sx = 0; sx < w; sx++) {
          final v = grey(luma(sx, sy, w));
          bgra.setRange((sy * w + sx) * 4, (sy * w + sx) * 4 + 4, [v, v, v, 255]);
          image.setPixelRgb(sx, sy, v, v, v);
        }
      }
      expect(ObjectDetectorService.debugFrameToTensor([(bgra, w * 4, 4)], w, h, 90, 8, 8), yuv);
      expect(ObjectDetectorService.debugFrameToTensor([(bgra, w * 4, 4)], w, h, 0, 8, 8),
          yuvSideways);
      expect(ObjectDetectorService.debugImageToTensor(img.copyRotate(image, angle: 90), 8, 8), yuv);
      expect(ObjectDetectorService.debugImageToTensor(image, 8, 8), yuvSideways);
    });

    test('float inputs are padded with the same grey, normalized', () {
      final t = ObjectDetectorService.debugFrameToTensor(yuvFrame(8, 6), 8, 6, 0, 8, 8,
          type: TensorType.float32)!;
      final f = t.buffer.asFloat32List();
      expect(f.sublist(6 * 8 * 3), everyElement(closeTo((pad - 127.5) / 127.5, 1e-6)));
      expect(f[0], closeTo((grey(luma(0, 0, 8)) - 127.5) / 127.5, 1e-6));
    });
  });
}
