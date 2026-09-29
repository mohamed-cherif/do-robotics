import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DetectionResult {
  final Rect boundingBox;
  final String label;
  final double score;

  DetectionResult({
    required this.boundingBox,
    required this.label,
    required this.score,
  });

  @override
  String toString() => 'DetectionResult(label: $label, score: $score, bbox: $boundingBox)';
}

class LineDetectionResult {
  /// Horizontal offset of the line center: -1.0 (far left) to +1.0 (far right), 0.0 = centered.
  final double offsetX;
  /// True when a clear edge was found in the floor region.
  final bool detected;
  /// Confidence 0.0–1.0 based on edge strength relative to frame average.
  final double confidence;

  const LineDetectionResult({required this.offsetX, required this.detected, required this.confidence});
}

/// Runs object detection in a background isolate to keep the UI smooth.
class ObjectDetectorService {
  static final ObjectDetectorService _instance = ObjectDetectorService._internal();
  factory ObjectDetectorService() => _instance;
  ObjectDetectorService._internal();

  static const String modelAsset = 'assets/ml/1.tflite';
  static const String labelsAsset = 'assets/ml/labelmap.txt';

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription? _receiveSub;

  final StreamController<List<DetectionResult>> _resultsController =
      StreamController.broadcast();
  Stream<List<DetectionResult>> get resultsStream => _resultsController.stream;

  final StreamController<LineDetectionResult> _lineResultsController =
      StreamController.broadcast();
  Stream<LineDetectionResult> get lineResultsStream => _lineResultsController.stream;

  bool _isReady = false;
  bool _isProcessing = false;
  bool lineMode = false;
  /// Minimum score a detection must reach to be reported.
  double confidenceThreshold = 0.35;

  // Simple rolling inference-time stat for the HUD / logs.
  double _avgInferenceMs = 0;
  double get averageInferenceMs => _avgInferenceMs;
  DateTime _frameSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> initialize() async {
    if (_isReady) return;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);

    final completer = Completer<SendPort>();
    _receiveSub = _receivePort!.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is List<DetectionResult>) {
        _recordLatency();
        _resultsController.add(message);
        _isProcessing = false;
      } else if (message is LineDetectionResult) {
        _recordLatency();
        _lineResultsController.add(message);
        _isProcessing = false;
      } else if (message is String) {
        debugPrint('ISOLATE: $message');
      }
    });

    _sendPort = await completer.future;

    debugPrint('Loading model assets for isolate...');
    final modelData = await rootBundle.load(modelAsset);
    final modelBytes = modelData.buffer.asUint8List();
    final labelsStr = await rootBundle.loadString(labelsAsset);

    _sendPort!.send(_InitCommand(modelBytes, labelsStr));
    _isReady = true;
  }

  void _recordLatency() {
    final ms = DateTime.now().difference(_frameSentAt).inMilliseconds.toDouble();
    _avgInferenceMs = _avgInferenceMs == 0 ? ms : _avgInferenceMs * 0.9 + ms * 0.1;
  }

  DateTime _lastProcessTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _throttle = Duration(milliseconds: 40); // ~25 FPS cap

  void processFrame(CameraImage cameraImage, {List<String> activeLabels = const [], int rotation = 90}) {
    if (!_isReady || _isProcessing) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessTime) < _throttle) return;
    _lastProcessTime = now;
    _frameSentAt = now;

    _isProcessing = true;

    // TransferableTypedData moves the pixel buffers into the isolate without
    // a second copy on send (the camera buffer itself is copied exactly once).
    _sendPort!.send(_FrameCmd(
      planes: cameraImage.planes
          .map((p) => _PlaneData(
                data: TransferableTypedData.fromList([p.bytes]),
                bytesPerRow: p.bytesPerRow,
                bytesPerPixel: p.bytesPerPixel,
                height: p.height ?? cameraImage.height,
                width: p.width ?? cameraImage.width,
              ))
          .toList(),
      height: cameraImage.height,
      width: cameraImage.width,
      format: cameraImage.format.raw,
      rotation: rotation,
      activeLabels: activeLabels,
      lineMode: lineMode,
      threshold: confidenceThreshold,
    ));
  }

  void stop() {
    _receiveSub?.cancel();
    _receiveSub = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill();
    _isolate = null;
    _sendPort = null;
    _isReady = false;
    _isProcessing = false;
  }

  // ── Isolate ─────────────────────────────────────────────────────────────────

  static void _isolateEntryPoint(SendPort mainSendPort) async {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    Interpreter? interpreter;
    List<String> labels = [];
    int inputH = 300;
    int inputW = 300;
    int numDetections = 25;
    TensorType inputType = TensorType.uint8;
    // Output tensor indices for the SSD post-process op. Detected from tensor
    // shapes/names at load time; these are the TF-Hub defaults.
    int boxesIdx = 0, classesIdx = 1, scoresIdx = 2, countIdx = 3;

    await for (final message in port) {
      if (message is _InitCommand) {
        try {
          final options = InterpreterOptions();
          final cores = Platform.numberOfProcessors;
          final threads = cores >= 4 ? 4 : (cores > 1 ? cores - 1 : 1);
          options.threads = threads;
          if (Platform.isAndroid) {
            options.addDelegate(
                XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: threads)));
          }

          interpreter = Interpreter.fromBuffer(message.modelBytes, options: options);

          final inputTensor = interpreter.getInputTensor(0);
          final inputShape = inputTensor.shape;
          inputH = inputShape[1];
          inputW = inputShape[2];
          inputType = inputTensor.type;

          // Resolve output tensor roles by shape (boxes = [1,N,4], count = [1]);
          // classes vs scores by name suffix, falling back to the default order.
          final outputs = interpreter.getOutputTensors();
          final remaining = <int>[];
          for (var i = 0; i < outputs.length; i++) {
            final s = outputs[i].shape;
            if (s.length == 3 && s.last == 4) {
              boxesIdx = i;
              numDetections = s[1];
            } else if (s.length == 1) {
              countIdx = i;
            } else {
              remaining.add(i);
            }
          }
          if (remaining.length == 2) {
            final a = outputs[remaining[0]].name, b = outputs[remaining[1]].name;
            if (a.endsWith(':2') || b.endsWith(':1')) {
              scoresIdx = remaining[0];
              classesIdx = remaining[1];
            } else {
              classesIdx = remaining[0];
              scoresIdx = remaining[1];
            }
          }

          labels = message.labels.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          mainSendPort.send(
              'Model loaded. Input: $inputShape ($inputType), detections: $numDetections, '
              'threads: $threads, outputs: boxes=$boxesIdx classes=$classesIdx scores=$scoresIdx count=$countIdx');
        } catch (e) {
          mainSendPort.send('Error loading model: $e');
        }
      } else if (message is _FrameCmd) {
        // ── Line-following mode: Sobel edge detection, skip TFLite ───────────
        if (message.lineMode) {
          try {
            mainSendPort.send(_detectLine(message));
          } catch (e) {
            mainSendPort.send(const LineDetectionResult(offsetX: 0.0, detected: false, confidence: 0.0));
          }
          continue;
        }

        if (interpreter == null) {
          // Always answer, otherwise the main isolate's _isProcessing flag
          // would stay set forever and no further frames would be sent.
          mainSendPort.send(<DetectionResult>[]);
          continue;
        }

        try {
          // ── Fast path: single-pass fused convert + resize + rotate ──────────
          dynamic input = _directToTensor(message, inputW, inputH, inputType);

          if (input == null) {
            // Slow fallback via img package (unusual pixel formats).
            final image = _slowConvert(message);
            if (image == null) {
              mainSendPort.send('Error: frame conversion failed');
              mainSendPort.send(<DetectionResult>[]);
              continue;
            }
            final resized = img.copyResize(image, width: inputW, height: inputH);
            input = _imageToTensor(resized, inputW, inputH, inputType);
          }

          final boxesOut = List<List<List<double>>>.generate(
              1, (_) => List<List<double>>.generate(numDetections, (_) => List<double>.filled(4, 0.0)));
          final classesOut = List<List<double>>.generate(1, (_) => List<double>.filled(numDetections, 0.0));
          final scoresOut = List<List<double>>.generate(1, (_) => List<double>.filled(numDetections, 0.0));
          final countOut = List<double>.filled(1, 0.0);
          final outputs = <int, Object>{
            boxesIdx: boxesOut,
            classesIdx: classesOut,
            scoresIdx: scoresOut,
            countIdx: countOut,
          };

          interpreter.runForMultipleInputs([input], outputs);

          final scores = scoresOut[0];
          final classes = classesOut[0];
          final locations = boxesOut[0];
          final int valid = countOut[0].isFinite && countOut[0] > 0
              ? countOut[0].toInt().clamp(0, numDetections)
              : numDetections;

          final results = <DetectionResult>[];
          for (var i = 0; i < valid; i++) {
            final score = scores[i];
            if (score < message.threshold) continue;

            final classIndex = classes[i].toInt();
            final rawBox = locations[i];
            // TFLite SSD output: [ymin, xmin, ymax, xmax] in rotated-tensor space.
            final double yt = rawBox[0].clamp(0.0, 1.0);
            final double xt = rawBox[1].clamp(0.0, 1.0);
            final double yb = rawBox[2].clamp(0.0, 1.0);
            final double xr = rawBox[3].clamp(0.0, 1.0);

            // CameraPreview always applies 90° rotation (sensorOrientation for portrait).
            // _directToTensor applied message.rotation.
            // Net rotation from tensor space → display space = (90 - rotation + 360) % 360.
            final int net = (90 - message.rotation + 360) % 360;
            final Rect displayBox;
            if (net == 180) {
              displayBox = Rect.fromLTRB(1.0 - xr, 1.0 - yb, 1.0 - xt, 1.0 - yt);
            } else if (net == 90) {
              displayBox = Rect.fromLTRB(yt, 1.0 - xr, yb, 1.0 - xt);
            } else if (net == 270) {
              displayBox = Rect.fromLTRB(1.0 - yb, xt, 1.0 - yt, xr);
            } else {
              displayBox = Rect.fromLTRB(xt, yt, xr, yb);
            }
            if (displayBox.width <= 0 || displayBox.height <= 0) continue;

            // labelmap.txt line 0 is the '???' background placeholder.
            final label = (classIndex + 1 < labels.length)
                ? labels[classIndex + 1]
                : 'Unknown ($classIndex)';
            if (label.startsWith('?')) continue;

            if (message.activeLabels.isNotEmpty &&
                !message.activeLabels.contains(label)) {
              continue;
            }

            results.add(DetectionResult(
              boundingBox: displayBox,
              label: label,
              score: score,
            ));
          }

          mainSendPort.send(results);
        } catch (e, stack) {
          mainSendPort.send('Inference Error: $e\n$stack');
          mainSendPort.send(<DetectionResult>[]);
        }
      }
    }
  }

  // ── Fast single-pass tensor fill ─────────────────────────────────────────────

  /// Fuses YUV→RGB conversion, nearest-neighbour resize, and optional 90° CW
  /// rotation into a single loop — no intermediate full-resolution image.
  ///
  /// Supports 3-plane YUV420 (Android) and single-plane BGRA8888 (iOS).
  /// Returns null for any other format so the caller can fall back to the slow path.
  static dynamic _directToTensor(_FrameCmd cmd, int targetW, int targetH, TensorType tensorType) {
    final srcW = cmd.width;
    final srcH = cmd.height;
    final rotate90CW  = cmd.rotation == 90;
    final rotate270CW = cmd.rotation == 270;
    final flip180     = cmd.rotation == 180;
    final pixelCount = targetW * targetH;
    final isFloat = tensorType != TensorType.uint8;

    // Precompute the source column/row for every target column/row. With a
    // 90°/270° rotation the target x maps to a source row and vice-versa.
    final Int32List mapA = Int32List(targetW); // indexed by tx
    final Int32List mapB = Int32List(targetH); // indexed by ty
    for (int tx = 0; tx < targetW; tx++) {
      if (rotate90CW) {
        mapA[tx] = (srcH - 1 - ((tx * srcH) ~/ targetW)).clamp(0, srcH - 1); // sy
      } else if (rotate270CW) {
        mapA[tx] = ((tx * srcH) ~/ targetW).clamp(0, srcH - 1); // sy
      } else if (flip180) {
        mapA[tx] = (srcW - 1 - ((tx * srcW) ~/ targetW)).clamp(0, srcW - 1); // sx
      } else {
        mapA[tx] = ((tx * srcW) ~/ targetW).clamp(0, srcW - 1); // sx
      }
    }
    for (int ty = 0; ty < targetH; ty++) {
      if (rotate90CW) {
        mapB[ty] = ((ty * srcW) ~/ targetH).clamp(0, srcW - 1); // sx
      } else if (rotate270CW) {
        mapB[ty] = (srcW - 1 - ((ty * srcW) ~/ targetH)).clamp(0, srcW - 1); // sx
      } else if (flip180) {
        mapB[ty] = (srcH - 1 - ((ty * srcH) ~/ targetH)).clamp(0, srcH - 1); // sy
      } else {
        mapB[ty] = ((ty * srcH) ~/ targetH).clamp(0, srcH - 1); // sy
      }
    }
    final bool swapAxes = rotate90CW || rotate270CW;

    final Uint8List? u8 = isFloat ? null : Uint8List(pixelCount * 3);
    final Float32List? f32 = isFloat ? Float32List(pixelCount * 3) : null;
    int out = 0;

    // ── 3-plane YUV420 ───────────────────────────────────────────────────────
    if (cmd.planes.length == 3) {
      final yBytes = cmd.planes[0].bytes;
      final uBytes = cmd.planes[1].bytes;
      final vBytes = cmd.planes[2].bytes;
      final yRow  = cmd.planes[0].bytesPerRow;
      final uvRow = cmd.planes[1].bytesPerRow;
      final uvPx  = cmd.planes[1].bytesPerPixel ?? 1;
      final yLen = yBytes.length, uLen = uBytes.length, vLen = vBytes.length;

      for (int ty = 0; ty < targetH; ty++) {
        final b = mapB[ty];
        for (int tx = 0; tx < targetW; tx++) {
          final a = mapA[tx];
          final int sx = swapAxes ? b : a;
          final int sy = swapAxes ? a : b;
          final yIdx  = sy * yRow + sx;
          final uvIdx = (sy >> 1) * uvRow + (sx >> 1) * uvPx;
          if (yIdx >= yLen || uvIdx >= uLen || uvIdx >= vLen) {
            out += 3;
            continue;
          }
          final cy = yBytes[yIdx] - 16;
          final d  = uBytes[uvIdx] - 128; // Cb
          final e  = vBytes[uvIdx] - 128; // Cr
          final r = ((298 * cy + 409 * e + 128) >> 8).clamp(0, 255);
          final g = ((298 * cy - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
          final bl = ((298 * cy + 516 * d + 128) >> 8).clamp(0, 255);
          if (u8 != null) {
            u8[out++] = r; u8[out++] = g; u8[out++] = bl;
          } else {
            f32![out++] = (r - 127.5) / 127.5;
            f32[out++] = (g - 127.5) / 127.5;
            f32[out++] = (bl - 127.5) / 127.5;
          }
        }
      }
      return u8 != null
          ? u8.reshape([1, targetH, targetW, 3])
          : f32!.reshape([1, targetH, targetW, 3]);
    }

    // ── Single-plane BGRA8888 (iOS) ──────────────────────────────────────────
    if (cmd.planes.length == 1 &&
        cmd.planes[0].bytes.length >= cmd.width * cmd.height * 4) {
      final bytes     = cmd.planes[0].bytes;
      final rowStride = cmd.planes[0].bytesPerRow;
      final len = bytes.length;

      for (int ty = 0; ty < targetH; ty++) {
        final b = mapB[ty];
        for (int tx = 0; tx < targetW; tx++) {
          final a = mapA[tx];
          final int sx = swapAxes ? b : a;
          final int sy = swapAxes ? a : b;
          final idx = sy * rowStride + sx * 4;
          if (idx + 2 >= len) { out += 3; continue; }
          if (u8 != null) {
            u8[out++] = bytes[idx + 2]; // R (from BGRA)
            u8[out++] = bytes[idx + 1]; // G
            u8[out++] = bytes[idx];     // B
          } else {
            f32![out++] = (bytes[idx + 2] - 127.5) / 127.5;
            f32[out++] = (bytes[idx + 1] - 127.5) / 127.5;
            f32[out++] = (bytes[idx]     - 127.5) / 127.5;
          }
        }
      }
      return u8 != null
          ? u8.reshape([1, targetH, targetW, 3])
          : f32!.reshape([1, targetH, targetW, 3]);
    }

    return null; // Unknown format — caller falls back to slow path.
  }

  // ── Sobel line detection ──────────────────────────────────────────────────
  //
  // Uses only the Y (luminance) plane — zero conversion cost. Crops the bottom
  // 40% of the frame (floor region), computes a horizontal Sobel gradient per
  // column, then locates the line as the energy-weighted centroid around the
  // strongest column. The centroid (rather than the raw argmax) makes the
  // offset stable frame-to-frame instead of jumping between the two edges of
  // the tape.

  static LineDetectionResult _detectLine(_FrameCmd cmd) {
    if (cmd.planes.isEmpty) {
      return const LineDetectionResult(offsetX: 0.0, detected: false, confidence: 0.0);
    }
    final srcW = cmd.width;
    final srcH = cmd.height;
    final yBytes = cmd.planes[0].bytes;
    final yRow = cmd.planes[0].bytesPerRow;
    if (srcW < 3 || srcH < 3) {
      return const LineDetectionResult(offsetX: 0.0, detected: false, confidence: 0.0);
    }

    // Process bottom 40% of frame only (floor region)
    final int startY = (srcH * 0.6).round();
    final int endY = srcH - 1;

    final columnEnergy = Float64List(srcW);
    for (int y = startY + 1; y < endY; y++) {
      final rowAbove = (y - 1) * yRow, row = y * yRow, rowBelow = (y + 1) * yRow;
      if (rowBelow + srcW > yBytes.length) break;
      for (int x = 1; x < srcW - 1; x++) {
        final int gx = -yBytes[rowAbove + x - 1] + yBytes[rowAbove + x + 1]
            - 2 * yBytes[row + x - 1] + 2 * yBytes[row + x + 1]
            - yBytes[rowBelow + x - 1] + yBytes[rowBelow + x + 1];
        columnEnergy[x] += gx.abs();
      }
    }

    double maxEnergy = 0;
    double totalEnergy = 0;
    int bestCol = srcW ~/ 2;
    for (int x = 1; x < srcW - 1; x++) {
      totalEnergy += columnEnergy[x];
      if (columnEnergy[x] > maxEnergy) {
        maxEnergy = columnEnergy[x];
        bestCol = x;
      }
    }

    // Confidence: ratio of peak column energy to average.
    final double avgEnergy = totalEnergy / (srcW - 2);
    final double confidence = avgEnergy > 0
        ? ((maxEnergy / avgEnergy - 1.0) / 10.0).clamp(0.0, 1.0)
        : 0.0;
    final bool detected = confidence > 0.15;

    // Energy-weighted centroid in a window around the peak (±12% of width)
    // so a tape with two strong edges resolves to its middle.
    final int half = (srcW * 0.12).round().clamp(2, srcW ~/ 2);
    double weighted = 0, weightSum = 0;
    for (int x = (bestCol - half).clamp(1, srcW - 2); x <= (bestCol + half).clamp(1, srcW - 2); x++) {
      weighted += x * columnEnergy[x];
      weightSum += columnEnergy[x];
    }
    final double centerCol = weightSum > 0 ? weighted / weightSum : bestCol.toDouble();

    final double offsetX = (centerCol / srcW - 0.5) * 2.0;
    return LineDetectionResult(offsetX: offsetX, detected: detected, confidence: confidence);
  }

  // ── Slow fallback (img package) ──────────────────────────────────────────────

  static img.Image? _slowConvert(_FrameCmd cmd) {
    try {
      final w = cmd.width;
      final h = cmd.height;

      img.Image? image;
      if (cmd.planes.length >= 3) {
        final yBytes = cmd.planes[0].bytes;
        final uBytes = cmd.planes[1].bytes;
        final vBytes = cmd.planes[2].bytes;
        final yRow  = cmd.planes[0].bytesPerRow;
        final uvRow = cmd.planes[1].bytesPerRow;
        final uvPx  = cmd.planes[1].bytesPerPixel ?? 1;
        image = img.Image(width: w, height: h);
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final yIdx  = y * yRow + x;
            final uvIdx = (y ~/ 2) * uvRow + (x ~/ 2) * uvPx;
            if (yIdx >= yBytes.length || uvIdx >= uBytes.length || uvIdx >= vBytes.length) continue;
            final cy = yBytes[yIdx] - 16;
            final d  = uBytes[uvIdx] - 128;
            final e  = vBytes[uvIdx] - 128;
            image.setPixelRgb(x, y,
              ((298 * cy + 409 * e + 128) >> 8).clamp(0, 255),
              ((298 * cy - 100 * d - 208 * e + 128) >> 8).clamp(0, 255),
              ((298 * cy + 516 * d + 128) >> 8).clamp(0, 255),
            );
          }
        }
      } else if (cmd.planes.length == 1 && cmd.planes[0].bytes.length >= w * h * 4) {
        final plane = cmd.planes[0];
        image = img.Image.fromBytes(
          width: w, height: h,
          bytes: plane.bytes.buffer,
          rowStride: plane.bytesPerRow,
          order: img.ChannelOrder.bgra,
        );
      }
      if (image == null) return null;
      if (cmd.rotation == 90) return img.copyRotate(image, angle: 90);
      if (cmd.rotation == 180) return img.copyRotate(image, angle: 180);
      if (cmd.rotation == 270) return img.copyRotate(image, angle: 270);
      return image;
    } catch (_) {
      return null;
    }
  }

  static dynamic _imageToTensor(img.Image resized, int w, int h, TensorType tensorType) {
    if (tensorType == TensorType.uint8) {
      final buf = Uint8List(w * h * 3);
      int out = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          buf[out++] = p.r.toInt();
          buf[out++] = p.g.toInt();
          buf[out++] = p.b.toInt();
        }
      }
      return buf.reshape([1, h, w, 3]);
    } else {
      final buf = Float32List(w * h * 3);
      int out = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          buf[out++] = (p.r.toInt() - 127.5) / 127.5;
          buf[out++] = (p.g.toInt() - 127.5) / 127.5;
          buf[out++] = (p.b.toInt() - 127.5) / 127.5;
        }
      }
      return buf.reshape([1, h, w, 3]);
    }
  }
}

class _InitCommand {
  final Uint8List modelBytes;
  final String labels;
  _InitCommand(this.modelBytes, this.labels);
}

class _FrameCmd {
  final List<_PlaneData> planes;
  final int height;
  final int width;
  final int format;
  final int rotation;
  final List<String> activeLabels;
  final bool lineMode;
  final double threshold;

  _FrameCmd({
    required this.planes,
    required this.height,
    required this.width,
    required this.format,
    required this.rotation,
    this.activeLabels = const [],
    this.lineMode = false,
    this.threshold = 0.35,
  });
}

class _PlaneData {
  final TransferableTypedData data;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int height;
  final int width;

  Uint8List? _bytes;
  /// Materializes the transferred buffer (valid once, cached afterwards).
  Uint8List get bytes => _bytes ??= data.materialize().asUint8List();

  _PlaneData({
    required this.data,
    required this.bytesPerRow,
    this.bytesPerPixel,
    required this.height,
    required this.width,
  });
}
