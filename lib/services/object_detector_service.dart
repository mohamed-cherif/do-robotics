import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'vision_preferences.dart';

/// The part of the model input that holds the upright picture: its top-left
/// [width]×[height] input pixels. The rest is grey padding.
typedef PictureArea = ({int width, int height});

class DetectionResult {
  /// Normalized box in *screen* coordinates (the camera preview as shown), for
  /// drawing and tap-to-lock.
  final Rect boundingBox;
  /// Normalized box in the *upright* picture the model saw — the robot's own
  /// left/right/up/down whatever the phone mount. Used for steering.
  final Rect uprightBox;
  final String label;
  final double score;

  DetectionResult({
    required this.boundingBox,
    Rect? uprightBox,
    required this.label,
    required this.score,
  }) : uprightBox = uprightBox ?? boundingBox;

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
  /// Minimum score for a detection to count as "seen" (drawn, detected,
  /// lockable). Filtering happens in [VisionService].
  double confidenceThreshold = 0.35;

  /// Weaker detections, down to this score, are also reported, so a target
  /// that is already locked survives a few uncertain frames (blur, partly
  /// out of view). VisionService uses them only for that.
  static const double trackingFloor = 0.2;

  /// Frame-rate cap and thread budget (see [VisionPerformance]).
  VisionPerformance performance = VisionPerformance.fast;

  // Simple rolling inference-time stat for the HUD / logs.
  double _avgInferenceMs = 0;
  double get averageInferenceMs => _avgInferenceMs;
  DateTime _frameSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void>? _initFuture;
  /// Bumped by [stop] so an initialization that is still in flight knows it
  /// was cancelled and tears down what it created.
  int _generation = 0;

  /// Spawns the inference isolate and waits until the model is loaded. Safe
  /// to call concurrently. Throws [StateError] when the model cannot load, so
  /// callers can tell the user instead of silently never detecting anything.
  Future<void> initialize() {
    if (_isReady) return Future.value();
    return _initFuture ??= () async {
      try {
        await _initialize();
      } finally {
        _initFuture = null;
      }
    }();
  }

  Future<void> _initialize() async {
    final generation = _generation;
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);

    final portReady = Completer<SendPort>();
    final modelReady = Completer<String?>(); // null = OK, else the error
    final sub = receivePort.listen((message) {
      if (message is SendPort) {
        if (!portReady.isCompleted) portReady.complete(message);
      } else if (message is _ModelStatus) {
        debugPrint('ISOLATE: ${message.info}');
        if (!modelReady.isCompleted) modelReady.complete(message.error);
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

    void abandon() {
      sub.cancel();
      receivePort.close();
      isolate.kill(priority: Isolate.immediate);
    }

    try {
      final sendPort = await portReady.future.timeout(const Duration(seconds: 10));
      final modelData = await rootBundle.load(modelAsset);
      final labelsStr = await rootBundle.loadString(labelsAsset);
      sendPort.send(_InitCommand(
          modelData.buffer.asUint8List(), labelsStr, performance.maxThreads));
      final error = await modelReady.future.timeout(const Duration(seconds: 20),
          onTimeout: () => 'timed out loading the model');
      if (error != null) {
        throw StateError('Vision model failed to load: $error');
      }
      if (generation != _generation) {
        // stop() ran while we were loading.
        abandon();
        return;
      }
      _isolate = isolate;
      _receivePort = receivePort;
      _receiveSub = sub;
      _sendPort = sendPort;
      _isProcessing = false;
      _isReady = true;
    } catch (_) {
      abandon();
      rethrow;
    }
  }

  void _recordLatency() {
    final ms = DateTime.now().difference(_frameSentAt).inMilliseconds.toDouble();
    _avgInferenceMs = _avgInferenceMs == 0 ? ms : _avgInferenceMs * 0.9 + ms * 0.1;
  }

  DateTime _lastProcessTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// [rotation]: clockwise turn that makes the frame upright for the model.
  /// [displayNet]: clockwise turn from that upright picture to the screen
  /// preview (0 when the phone and the screen are turned the same way, e.g.
  /// upright in portrait; 180 for an upside-down phone in portrait).
  void processFrame(CameraImage cameraImage,
      {List<String> activeLabels = const [], int rotation = 90, int displayNet = 0}) {
    if (!_isReady || _isProcessing) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessTime) < performance.frameInterval) return;
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
      displayNet: displayNet,
      activeLabels: activeLabels,
      lineMode: lineMode,
      threshold: confidenceThreshold < trackingFloor ? confidenceThreshold : trackingFloor,
    ));
  }

  void stop() {
    _generation++;
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
    // Output tensor indices of the TFLite_Detection_PostProcess op, whose
    // output order is boxes, classes, scores, count. Boxes/count are found by
    // shape at load time; classes vs scores are confirmed from the values of
    // the first frames (see resolveClassScoreRoles).
    int boxesIdx = 0, classesIdx = 1, scoresIdx = 2, countIdx = 3;
    bool rolesConfirmed = false;
    // Timing summary in the log every [timedBatch] frames.
    const timedBatch = 50;
    int timedFrames = 0, modelUs = 0, frameUs = 0;

    await for (final message in port) {
      if (message is _InitCommand) {
        try {
          final cores = Platform.numberOfProcessors;
          final threads = (cores >= 4 ? 4 : (cores > 1 ? cores - 1 : 1))
              .clamp(1, message.maxThreads);
          // XNNPack is created WITHOUT options: tflite_flutter 0.12.1 declares
          // XNNPack's options struct with fewer fields than the LiteRT 1.4
          // library it ships reads, so passing XNNPackDelegateOptions made the
          // library read past it (a weight-cache path) and crash the app with
          // SIGSEGV in TfLiteXNNPackDelegateCreateWithThreadpool on most
          // camera starts. With null, LiteRT fills in its own defaults
          // (int8 kernels on). Without XNNPack this int8 model falls back to
          // slow kernels (seconds per frame on an x86 emulator).
          var accel = 'CPU';
          Interpreter? created;
          if (Platform.isAndroid) {
            try {
              created = Interpreter.fromBuffer(message.modelBytes,
                  options: InterpreterOptions()
                    ..threads = threads
                    ..addDelegate(XNNPackDelegate()));
              accel = 'XNNPack';
            } catch (e) {
              mainSendPort.send('XNNPack unavailable ($e); using plain CPU');
            }
          }
          interpreter = created ??
              Interpreter.fromBuffer(message.modelBytes,
                  options: InterpreterOptions()..threads = threads);

          final inputTensor = interpreter.getInputTensor(0);
          final inputShape = inputTensor.shape;
          inputH = inputShape[1];
          inputW = inputShape[2];
          inputType = inputTensor.type;

          // Resolve output tensor roles by shape (boxes = [1,N,4], count = [1]).
          // Tensor *names* are not reliable: the bundled TF2 model names its
          // class tensor "...:2" and its score tensor "...:1".
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
            // Post-process op order until the values say otherwise.
            classesIdx = remaining[0];
            scoresIdx = remaining[1];
          }
          rolesConfirmed = false;

          labels = message.labels.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          mainSendPort.send(_ModelStatus(null,
              'Model loaded. Input: $inputShape ($inputType), detections: $numDetections, '
              'threads: $threads ($accel), outputs: boxes=$boxesIdx classes=$classesIdx scores=$scoresIdx count=$countIdx'));
        } catch (e) {
          interpreter?.close();
          interpreter = null;
          mainSendPort.send(_ModelStatus('$e', 'Error loading model: $e'));
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
          final frameWatch = Stopwatch()..start();
          final area = _areaFor(message, inputW, inputH);
          // ── Fast path: single-pass fused convert + resize + rotate ──────────
          Uint8List? input = _directToTensor(message, inputW, inputH, inputType, area);

          if (input == null) {
            // Slow fallback via img package (unusual pixel formats).
            final image = _slowConvert(message);
            if (image == null) {
              mainSendPort.send('Error: frame conversion failed');
              mainSendPort.send(<DetectionResult>[]);
              continue;
            }
            input = _imageToTensor(image, inputW, inputH, inputType, area);
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
          modelUs += interpreter.lastNativeInferenceDurationMicroSeconds;

          var scores = scoresOut[0];
          var classes = classesOut[0];
          if (!rolesConfirmed) {
            final classesFirst = resolveClassScoreRoles(classes, scores);
            if (classesFirst != null) {
              rolesConfirmed = true;
              if (!classesFirst) {
                final t = classesIdx;
                classesIdx = scoresIdx;
                scoresIdx = t;
                final tmp = classes;
                classes = scores;
                scores = tmp;
              }
              mainSendPort.send('Output roles confirmed: classes=$classesIdx scores=$scoresIdx');
            }
          }
          final locations = boxesOut[0];
          final int valid = countOut[0].isFinite && countOut[0] > 0
              ? countOut[0].toInt().clamp(0, numDetections)
              : numDetections;

          final results = <DetectionResult>[];
          for (var i = 0; i < valid; i++) {
            final score = scores[i];
            if (score < message.threshold) continue;

            final classIndex = classes[i].toInt();
            // The tensor was rotated upright, so once the padding is taken
            // off the box is in the robot's frame; the screen preview may be
            // turned from it.
            final uprightBox = modelBoxToUpright(locations[i], area, inputW, inputH);
            if (uprightBox == null) continue;
            final displayBox = uprightToDisplay(uprightBox, message.displayNet);
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
              uprightBox: uprightBox,
              label: label,
              score: score,
            ));
          }

          mainSendPort.send(results);
          frameUs += frameWatch.elapsedMicroseconds;
          if (++timedFrames == timedBatch) {
            mainSendPort.send('Timing (last $timedBatch frames): model '
                '${(modelUs / timedBatch / 1000).toStringAsFixed(1)} ms, whole frame '
                '${(frameUs / timedBatch / 1000).toStringAsFixed(1)} ms');
            timedFrames = 0;
            modelUs = 0;
            frameUs = 0;
          }
        } catch (e, stack) {
          mainSendPort.send('Inference Error: $e\n$stack');
          mainSendPort.send(<DetectionResult>[]);
        }
      }
    }
  }

  /// Maps a normalized box from the upright picture to the screen preview,
  /// which is turned [net] degrees clockwise from it. Public for tests.
  static Rect uprightToDisplay(Rect b, int net) {
    switch (net % 360) {
      case 180:
        return Rect.fromLTRB(1.0 - b.right, 1.0 - b.bottom, 1.0 - b.left, 1.0 - b.top);
      case 90:
        return Rect.fromLTRB(1.0 - b.bottom, b.left, 1.0 - b.top, b.right);
      case 270:
        return Rect.fromLTRB(b.top, 1.0 - b.right, b.bottom, 1.0 - b.left);
      default:
        return b;
    }
  }

  /// Decides which of the two [1,N] detector outputs holds class ids: class
  /// ids are whole numbers, scores are fractions in [0, 1]. Returns true if
  /// [a] is the class tensor, false if [b] is, null when it can't tell yet
  /// (e.g. every value is 0). Public for tests.
  static bool? resolveClassScoreRoles(List<double> a, List<double> b) {
    bool integral(List<double> v) =>
        v.every((x) => x.isFinite && x >= 0 && (x - x.roundToDouble()).abs() < 1e-6);
    final aInt = integral(a), bInt = integral(b);
    if (aInt == bInt) return null;
    return aInt;
  }

  // ── Model input geometry ─────────────────────────────────────────────────────

  /// Grey written where the model input holds no picture. EfficientDet-Lite
  /// normalizes pixels as (x − 127) / 128, so 127 reads as 0 — what its own
  /// training padding looks like.
  static const int padValue = 127;

  /// Where an upright picture of [w]×[h] goes in the [targetW]×[targetH]
  /// model input: always at the top-left corner, as in the model's training
  /// pipeline. A picture taller than the input (phone upright) is stretched
  /// to fill it, as before; a wider one (phone on its side) keeps its
  /// proportions at full width with grey padding below. Stretching that one
  /// taller made people thinner than the model knows them: −2.7 person AP
  /// on COCO (docs/MODELS.md). Public for tests.
  static PictureArea pictureArea(int w, int h, int targetW, int targetH) {
    if (w * targetH > h * targetW) {
      return (width: targetW, height: (h * targetW / w).round().clamp(1, targetH));
    }
    return (width: targetW, height: targetH);
  }

  /// Maps a model box ([ymin, xmin, ymax, xmax], normalized to the model
  /// input) to the upright picture in [area], normalized 0..1 and clamped.
  /// Null when nothing of it lies on the picture. Public for tests.
  static Rect? modelBoxToUpright(List<double> box, PictureArea area, int targetW, int targetH) {
    final sx = targetW / area.width, sy = targetH / area.height;
    final r = Rect.fromLTRB(
      (box[1] * sx).clamp(0.0, 1.0),
      (box[0] * sy).clamp(0.0, 1.0),
      (box[3] * sx).clamp(0.0, 1.0),
      (box[2] * sy).clamp(0.0, 1.0),
    );
    return r.width > 0 && r.height > 0 ? r : null;
  }

  static PictureArea _areaFor(_FrameCmd cmd, int targetW, int targetH) {
    final swap = cmd.rotation == 90 || cmd.rotation == 270;
    return pictureArea(swap ? cmd.height : cmd.width, swap ? cmd.width : cmd.height,
        targetW, targetH);
  }

  /// The uint8 or float32 model input a camera frame becomes, for tests:
  /// [planes] are (bytes, bytesPerRow, bytesPerPixel) as the camera hands
  /// them over (3 planes YUV420, or 1 plane BGRA8888).
  @visibleForTesting
  static Uint8List? debugFrameToTensor(
      List<(Uint8List, int, int?)> planes, int width, int height, int rotation,
      int targetW, int targetH, {TensorType type = TensorType.uint8}) {
    final cmd = _FrameCmd(
      planes: [
        for (final (bytes, bytesPerRow, bytesPerPixel) in planes)
          _PlaneData(
            data: TransferableTypedData.fromList([bytes]),
            bytesPerRow: bytesPerRow,
            bytesPerPixel: bytesPerPixel,
            height: height,
            width: width,
          ),
      ],
      height: height,
      width: width,
      format: 0,
      rotation: rotation,
    );
    return _directToTensor(cmd, targetW, targetH, type, _areaFor(cmd, targetW, targetH));
  }

  /// The slow path's model input for an already upright [image], for tests.
  @visibleForTesting
  static Uint8List debugImageToTensor(img.Image image, int targetW, int targetH,
          {TensorType type = TensorType.uint8}) =>
      _imageToTensor(image, targetW, targetH, type,
          pictureArea(image.width, image.height, targetW, targetH));

  // ── Fast single-pass tensor fill ─────────────────────────────────────────────

  /// Fuses YUV→RGB conversion, rotation upright and nearest-neighbour resize
  /// into [area] (see [pictureArea]) in a single loop — no intermediate
  /// full-resolution image. The rest of the input is [padValue] grey.
  ///
  /// Supports 3-plane YUV420 (Android) and single-plane BGRA8888 (iOS).
  /// Returns null for any other format so the caller can fall back to the slow path.
  ///
  /// Returns the tensor's raw bytes (uint8 values, or float32 bytes), not a
  /// nested [1][h][w][3] list: tflite_flutter copies a Uint8List into the
  /// tensor in one go but converts nested lists element by element, which
  /// took ~0.4 s per frame for this 320×320×3 input.
  static Uint8List? _directToTensor(_FrameCmd cmd, int targetW, int targetH,
      TensorType tensorType, PictureArea area) {
    final srcW = cmd.width;
    final srcH = cmd.height;
    final rotate90CW  = cmd.rotation == 90;
    final rotate270CW = cmd.rotation == 270;
    final flip180     = cmd.rotation == 180;
    final areaW = area.width, areaH = area.height;
    final isFloat = tensorType != TensorType.uint8;

    // Precompute the source column/row for every picture column/row. With a
    // 90°/270° rotation the target x maps to a source row and vice-versa.
    final Int32List mapA = Int32List(areaW); // indexed by tx
    final Int32List mapB = Int32List(areaH); // indexed by ty
    for (int tx = 0; tx < areaW; tx++) {
      if (rotate90CW) {
        mapA[tx] = (srcH - 1 - ((tx * srcH) ~/ areaW)).clamp(0, srcH - 1); // sy
      } else if (rotate270CW) {
        mapA[tx] = ((tx * srcH) ~/ areaW).clamp(0, srcH - 1); // sy
      } else if (flip180) {
        mapA[tx] = (srcW - 1 - ((tx * srcW) ~/ areaW)).clamp(0, srcW - 1); // sx
      } else {
        mapA[tx] = ((tx * srcW) ~/ areaW).clamp(0, srcW - 1); // sx
      }
    }
    for (int ty = 0; ty < areaH; ty++) {
      if (rotate90CW) {
        mapB[ty] = ((ty * srcW) ~/ areaH).clamp(0, srcW - 1); // sx
      } else if (rotate270CW) {
        mapB[ty] = (srcW - 1 - ((ty * srcW) ~/ areaH)).clamp(0, srcW - 1); // sx
      } else if (flip180) {
        mapB[ty] = (srcH - 1 - ((ty * srcH) ~/ areaH)).clamp(0, srcH - 1); // sy
      } else {
        mapB[ty] = ((ty * srcH) ~/ areaH).clamp(0, srcH - 1); // sy
      }
    }
    final bool swapAxes = rotate90CW || rotate270CW;

    final (u8, f32) = _paddedInput(targetW, targetH, isFloat, area);
    final rowStep = targetW * 3; // a picture row may be narrower than the input

    // ── 3-plane YUV420 ───────────────────────────────────────────────────────
    if (cmd.planes.length == 3) {
      final yBytes = cmd.planes[0].bytes;
      final uBytes = cmd.planes[1].bytes;
      final vBytes = cmd.planes[2].bytes;
      final yRow  = cmd.planes[0].bytesPerRow;
      final uvRow = cmd.planes[1].bytesPerRow;
      final uvPx  = cmd.planes[1].bytesPerPixel ?? 1;
      final yLen = yBytes.length, uLen = uBytes.length, vLen = vBytes.length;

      for (int ty = 0; ty < areaH; ty++) {
        final b = mapB[ty];
        int out = ty * rowStep;
        for (int tx = 0; tx < areaW; tx++) {
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
      return u8 ?? f32!.buffer.asUint8List();
    }

    // ── Single-plane BGRA8888 (iOS) ──────────────────────────────────────────
    if (cmd.planes.length == 1 &&
        cmd.planes[0].bytes.length >= cmd.width * cmd.height * 4) {
      final bytes     = cmd.planes[0].bytes;
      final rowStride = cmd.planes[0].bytesPerRow;
      final len = bytes.length;

      for (int ty = 0; ty < areaH; ty++) {
        final b = mapB[ty];
        int out = ty * rowStep;
        for (int tx = 0; tx < areaW; tx++) {
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
      return u8 ?? f32!.buffer.asUint8List();
    }

    return null; // Unknown format — caller falls back to slow path.
  }

  // ── Sobel line detection ──────────────────────────────────────────────────
  //
  // Uses only the Y (luminance) plane — zero conversion cost. Works in the
  // *upright* frame (the same rotation the object detector applies), crops the
  // bottom 40% (floor region), computes a horizontal Sobel gradient per
  // column, then locates the line as the energy-weighted centroid around the
  // strongest column. The centroid (rather than the raw argmax) makes the
  // offset stable frame-to-frame instead of jumping between the two edges of
  // the tape.
  //
  // Camera frames arrive in sensor orientation (landscape on most phones).
  // Without applying the rotation, a phone in portrait measured the "floor"
  // band along one side of the picture and the offset along the vertical axis.

  static LineDetectionResult _detectLine(_FrameCmd cmd) {
    if (cmd.planes.isEmpty) {
      return const LineDetectionResult(offsetX: 0.0, detected: false, confidence: 0.0);
    }
    return detectLineInLuma(cmd.planes[0].bytes, cmd.planes[0].bytesPerRow,
        cmd.width, cmd.height, cmd.rotation);
  }

  /// Line detection on a raw luminance plane. [rotation] is the clockwise
  /// rotation (0/90/180/270) that makes the sensor frame upright, exactly as
  /// passed to the object detector. The offset is in the robot's frame
  /// (−1 = tape on the robot's left), whatever the phone mount. Public for
  /// tests.
  static LineDetectionResult detectLineInLuma(
      Uint8List luma, int bytesPerRow, int srcW, int srcH, int rotation) {
    const none = LineDetectionResult(offsetX: 0.0, detected: false, confidence: 0.0);
    final swap = rotation == 90 || rotation == 270;
    final uW = swap ? srcH : srcW; // upright width
    final uH = swap ? srcW : srcH; // upright height
    final startY = (uH * 0.6).round();
    final bandH = uH - startY;
    if (uW < 3 || bandH < 3) return none;

    // Copy the floor band of the upright image into a compact buffer. The
    // sensor↔upright mapping matches _directToTensor.
    final band = Uint8List(uW * bandH);
    final len = luma.length;
    for (int by = 0; by < bandH; by++) {
      final uy = startY + by;
      for (int ux = 0; ux < uW; ux++) {
        int sx, sy;
        if (rotation == 90) {
          sx = uy;
          sy = srcH - 1 - ux;
        } else if (rotation == 270) {
          sx = srcW - 1 - uy;
          sy = ux;
        } else if (rotation == 180) {
          sx = srcW - 1 - ux;
          sy = srcH - 1 - uy;
        } else {
          sx = ux;
          sy = uy;
        }
        final idx = sy * bytesPerRow + sx;
        band[by * uW + ux] = idx < len ? luma[idx] : 0;
      }
    }

    final columnEnergy = Float64List(uW);
    for (int y = 1; y < bandH - 1; y++) {
      final rowAbove = (y - 1) * uW, row = y * uW, rowBelow = (y + 1) * uW;
      for (int x = 1; x < uW - 1; x++) {
        final int gx = -band[rowAbove + x - 1] + band[rowAbove + x + 1]
            - 2 * band[row + x - 1] + 2 * band[row + x + 1]
            - band[rowBelow + x - 1] + band[rowBelow + x + 1];
        columnEnergy[x] += gx.abs();
      }
    }

    double maxEnergy = 0;
    double totalEnergy = 0;
    int bestCol = uW ~/ 2;
    for (int x = 1; x < uW - 1; x++) {
      totalEnergy += columnEnergy[x];
      if (columnEnergy[x] > maxEnergy) {
        maxEnergy = columnEnergy[x];
        bestCol = x;
      }
    }

    // Confidence: ratio of peak column energy to average.
    final double avgEnergy = totalEnergy / (uW - 2);
    final double confidence = avgEnergy > 0
        ? ((maxEnergy / avgEnergy - 1.0) / 10.0).clamp(0.0, 1.0)
        : 0.0;
    final bool detected = confidence > 0.15;

    // Energy-weighted centroid in a window around the peak (±12% of width)
    // so a tape with two strong edges resolves to its middle.
    final int half = (uW * 0.12).round().clamp(2, uW ~/ 2);
    double weighted = 0, weightSum = 0;
    for (int x = (bestCol - half).clamp(1, uW - 2); x <= (bestCol + half).clamp(1, uW - 2); x++) {
      weighted += x * columnEnergy[x];
      weightSum += columnEnergy[x];
    }
    final double centerCol = weightSum > 0 ? weighted / weightSum : bestCol.toDouble();

    final double offsetX = (centerCol / uW - 0.5) * 2.0;
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

  /// Same input as [_directToTensor], from an upright image: resized
  /// (nearest neighbour) into [area], grey padding elsewhere.
  static Uint8List _imageToTensor(
      img.Image upright, int w, int h, TensorType tensorType, PictureArea area) {
    final resized = upright.width == area.width && upright.height == area.height
        ? upright
        : img.copyResize(upright, width: area.width, height: area.height);
    final (u8, f32) = _paddedInput(w, h, tensorType != TensorType.uint8, area);
    for (int y = 0; y < area.height; y++) {
      int out = y * w * 3;
      for (int x = 0; x < area.width; x++) {
        final p = resized.getPixel(x, y);
        if (u8 != null) {
          u8[out++] = p.r.toInt();
          u8[out++] = p.g.toInt();
          u8[out++] = p.b.toInt();
        } else {
          f32![out++] = (p.r.toInt() - 127.5) / 127.5;
          f32[out++] = (p.g.toInt() - 127.5) / 127.5;
          f32[out++] = (p.b.toInt() - 127.5) / 127.5;
        }
      }
    }
    return u8 ?? f32!.buffer.asUint8List();
  }

  /// A [w]×[h]×3 input buffer (uint8, or float32 normalized like the
  /// pixels), pre-filled with [padValue] when [area] leaves part of it empty.
  static (Uint8List?, Float32List?) _paddedInput(
      int w, int h, bool isFloat, PictureArea area) {
    final n = w * h * 3;
    final padded = area.width < w || area.height < h;
    if (isFloat) {
      final f32 = Float32List(n);
      if (padded) f32.fillRange(0, n, (padValue - 127.5) / 127.5);
      return (null, f32);
    }
    final u8 = Uint8List(n);
    if (padded) u8.fillRange(0, n, padValue);
    return (u8, null);
  }
}

class _ModelStatus {
  /// null when the model loaded, otherwise the error text.
  final String? error;
  final String info;
  const _ModelStatus(this.error, this.info);
}

class _InitCommand {
  final Uint8List modelBytes;
  final String labels;
  final int maxThreads;
  _InitCommand(this.modelBytes, this.labels, this.maxThreads);
}

class _FrameCmd {
  final List<_PlaneData> planes;
  final int height;
  final int width;
  final int format;
  final int rotation;
  final int displayNet;
  final List<String> activeLabels;
  final bool lineMode;
  final double threshold;

  _FrameCmd({
    required this.planes,
    required this.height,
    required this.width,
    required this.format,
    required this.rotation,
    this.displayNet = 0,
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
