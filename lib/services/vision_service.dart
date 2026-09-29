import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/shared_lease.dart';
import 'mount_detector.dart';
import 'object_detector_service.dart';
import 'sensor_service.dart';
import 'vision_preferences.dart';

class DetectedObjectData {
  /// Screen (preview) coordinates, 0..1 — for drawing and tap-to-lock.
  final Rect boundingBox;
  /// Upright-picture coordinates, 0..1 — the robot's frame, for steering.
  final Rect uprightBox;
  final List<String> labels;
  final double confidence;

  DetectedObjectData(this.boundingBox, this.labels, [this.confidence = 0.0, Rect? uprightBox])
      : uprightBox = uprightBox ?? boundingBox;

  String get label => labels.isNotEmpty ? labels.first : 'unknown';
}

/// Camera ownership + object tracking on top of [ObjectDetectorService].
///
/// Bounding boxes are normalized (0..1): `boundingBox` in screen space (the
/// portrait preview), `uprightBox` in the upright picture the model saw.
/// `targetOffsetX/Y` (-1..+1, 0 = centre) and `targetArea` (% of the frame,
/// a "closeness" proxy) come from the upright box, so they are in the
/// robot's own frame whether the phone is mounted upright or upside down.
class VisionService {
  static final VisionService _instance = VisionService._internal();
  factory VisionService() => _instance;
  VisionService._internal();

  final StreamController<List<DetectedObjectData>> _resultsController =
      StreamController<List<DetectedObjectData>>.broadcast();
  Stream<List<DetectedObjectData>> get resultsStream => _resultsController.stream;

  String get loadedModelName => 'EfficientDet-Lite0 int8 (COCO)';
  double get averageInferenceMs => _detector.averageInferenceMs;

  // Camera management
  CameraController? _camera;
  CameraController? get cameraController => _camera;
  bool _isInitialized = false;

  /// How the phone is attached to the robot (from [VisionPreferences]).
  PhoneMount mount = PhoneMount.auto;
  final MountDetector _mountDetector = MountDetector();
  /// Whether the camera picture is currently treated as upside down.
  bool get upsideDown => switch (mount) {
        PhoneMount.upright => false,
        PhoneMount.upsideDown => true,
        PhoneMount.auto => _mountDetector.upsideDown,
      };
  /// When true, run Sobel line detection instead of TFLite.
  bool lineMode = false;

  /// Users of the camera stream (pages, the runners). The camera is only torn
  /// down when the last user releases it, so leaving the camera page while a
  /// script is running no longer kills the script's vision. Opens and closes
  /// are serialized, so STOP during camera start-up cannot leak the camera.
  late final SharedLease _cameraLease =
      SharedLease(open: _openCamera, close: _closeCamera);
  Future<void>? _initFuture;

  /// Results older than this are treated as "nothing seen". Safety net for a
  /// camera that silently stops delivering frames (app backgrounded, camera
  /// taken by another app): without it the robot kept steering toward the
  /// last target it saw.
  static const Duration staleAfter = Duration(milliseconds: 1500);
  @visibleForTesting
  DateTime Function() clock = DateTime.now;
  DateTime _lastResultAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLineAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _fresh => clock().difference(_lastResultAt) < staleAfter;
  bool get _lineFresh => clock().difference(_lastLineAt) < staleAfter;

  // Line detection state
  double _lineOffsetX = 0.0;
  bool _lineDetected = false;
  double get lineOffsetX => _lineFresh ? _lineOffsetX : 0.0;
  bool get lineDetected => _lineDetected && _lineFresh;
  StreamSubscription? _prefSubscription;
  StreamSubscription? _settingsSubscription;
  StreamSubscription? _lineSub;
  StreamSubscription? _detectionSub;

  final ObjectDetectorService _detector = ObjectDetectorService();

  bool get isObjectDetected => _lastDetections.isNotEmpty && _fresh;

  // Active label filters (empty means all)
  List<String> _activeFilters = [];
  List<String> get activeFilters => List.unmodifiable(_activeFilters);

  // Tracking State
  DetectedObjectData? _trackedObject;
  int _lostFrames = 0;
  /// Frames a locked target may be missing before the lock is dropped.
  static const int lostFrameTolerance = 4;
  bool get isLocked => _trackedObject != null && _fresh;
  DetectedObjectData? get trackedObject => _fresh ? _trackedObject : null;

  String get targetLabel => trackedObject?.label ?? "None";

  /// -1.0 (robot's left) .. +1.0 (robot's right), 0 = centred.
  double get targetOffsetX {
    final t = trackedObject;
    if (t == null) return 0.0;
    return (t.uprightBox.center.dx - 0.5) * 2;
  }

  /// -1.0 (top) .. +1.0 (bottom), in the upright picture.
  double get targetOffsetY {
    final t = trackedObject;
    if (t == null) return 0.0;
    return (t.uprightBox.center.dy - 0.5) * 2;
  }

  /// Tracked box area as a percentage (0..100) of the frame.
  double get targetArea {
    final t = trackedObject;
    if (t == null) return 0.0;
    final r = t.uprightBox;
    return (r.width * r.height) * 100.0;
  }

  void setActiveFilters(List<String> filters) {
    _activeFilters = List.from(filters);
  }

  Future<void> refreshFilters() async {
    final enabled = await VisionPreferences.getEnabledLabels();
    _activeFilters = enabled.toList();
  }

  Future<void> _refreshSettings() async {
    mount = await VisionPreferences.getMount();
    _detector.confidenceThreshold = await VisionPreferences.getConfidenceThreshold();
    // Frame rate applies immediately; the thread count on the next camera start.
    _detector.performance = await VisionPreferences.getPerformance();
  }

  List<DetectedObjectData> _lastDetections = [];
  List<DetectedObjectData> get lastDetections =>
      _fresh ? List.unmodifiable(_lastDetections) : const [];

  /// Lock on the detection closest to a tapped point (normalized coordinates).
  void lockOn(Rect touchRect) {
    if (_lastDetections.isEmpty) return;

    DetectedObjectData? bestCandidate;
    double minDist = double.infinity;
    for (final obj in _lastDetections) {
      final dist = (obj.boundingBox.center - touchRect.center).distance;
      if (dist < minDist) {
        minDist = dist;
        bestCandidate = obj;
      }
    }
    if (bestCandidate != null) {
      _trackedObject = bestCandidate;
      _lostFrames = 0;
      debugPrint("VisionService: Locked on ${bestCandidate.label}");
    }
  }

  /// Lock on the most confident detection carrying [label].
  void autoLockOnLabel(String label) {
    if (_lastDetections.isEmpty) return;

    DetectedObjectData? bestCandidate;
    double maxConfidence = -1.0;
    for (final obj in _lastDetections) {
      if (obj.labels.contains(label) && obj.confidence > maxConfidence) {
        maxConfidence = obj.confidence;
        bestCandidate = obj;
      }
    }
    if (bestCandidate != null) {
      _trackedObject = bestCandidate;
      _lostFrames = 0;
      debugPrint("VisionService: Auto-locked on ${bestCandidate.label}");
    }
  }

  /// Locks on the highest-confidence detection regardless of label.
  void autoLockOnBestDetection() {
    if (_lastDetections.isEmpty) return;
    final best = _lastDetections.reduce((a, b) => a.confidence > b.confidence ? a : b);
    _trackedObject = best;
    _lostFrames = 0;
    debugPrint("VisionService: Auto-locked on ${best.label} (best confidence)");
  }

  void unlock() {
    _trackedObject = null;
    _lostFrames = 0;
  }

  /// Intersection-over-union of two rects (0..1). Public for tests.
  static double computeIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    final interArea = intersection.width * intersection.height;
    final unionArea = (a.width * a.height) + (b.width * b.height) - interArea;
    return unionArea > 0 ? interArea / unionArea : 0.0;
  }

  /// Tracking association score: IoU plus proximity (0..2). Public for tests.
  static double trackingScore(Rect previous, Rect candidate) {
    final iou = computeIoU(previous, candidate);
    final dist = (candidate.center - previous.center).distance;
    // Max distance in normalized [0,1] space is sqrt(2) ≈ 1.414.
    return iou + (1.0 - (dist / 1.414).clamp(0.0, 1.0));
  }

  /// Given the previous tracked object and the new frame's detections, pick the
  /// detection to follow, or null if the target vanished. Public for tests.
  static DetectedObjectData? associate(
      DetectedObjectData tracked, List<DetectedObjectData> detections) {
    final trackedLabel = tracked.label;
    DetectedObjectData? bestMatch;
    double bestScore = -1.0;
    for (final candidate in detections) {
      if (!candidate.labels.contains(trackedLabel)) continue;
      final score = trackingScore(tracked.boundingBox, candidate.boundingBox);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = candidate;
      }
    }
    if (bestMatch != null && bestScore > 0.2) return bestMatch;

    // Spatial match failed — the target may have moved fast across the frame.
    // If the same label is still detected anywhere, snap to the most confident
    // instance rather than holding a stale position.
    DetectedObjectData? fallback;
    for (final c in detections) {
      if (c.labels.contains(trackedLabel) &&
          (fallback == null || c.confidence > fallback.confidence)) {
        fallback = c;
      }
    }
    return fallback;
  }

  /// Loads preferences and the detector. Safe to call concurrently; callers
  /// share one in-flight initialization.
  Future<void> initialize() {
    return _initFuture ??= () async {
      try {
        await _initialize();
      } catch (_) {
        _initFuture = null;
        rethrow;
      }
    }();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    try {
      await refreshFilters();
      await _refreshSettings();

      _prefSubscription?.cancel();
      _prefSubscription = VisionPreferences.changesStream.listen((newFilters) {
        _activeFilters = newFilters.toList();
      });
      _settingsSubscription?.cancel();
      _settingsSubscription = VisionPreferences.settingsStream.listen((_) {
        _refreshSettings();
      });

      await _detector.initialize();

      _lineSub?.cancel();
      _lineSub = _detector.lineResultsStream.listen((result) {
        _lastLineAt = clock();
        _lineOffsetX = result.offsetX;
        _lineDetected = result.detected;
      });

      _detectionSub?.cancel();
      _detectionSub = _detector.resultsStream.listen(_onDetections);

      _isInitialized = true;
      debugPrint('✅ VisionService initialized');
    } catch (e) {
      debugPrint('❌ Vision service init error: $e');
      rethrow;
    }
  }

  @visibleForTesting
  void debugOnDetections(List<DetectionResult> results) => _onDetections(results);

  void _onDetections(List<DetectionResult> results) {
    _lastResultAt = clock();
    final mapped = results
        .map((r) => DetectedObjectData(r.boundingBox, [r.label], r.score, r.uprightBox))
        .toList();
    _lastDetections = mapped;

    final tracked = _trackedObject;
    if (tracked != null) {
      final next = associate(tracked, mapped);
      if (next != null) {
        _trackedObject = next;
        _lostFrames = 0;
      } else if (++_lostFrames > lostFrameTolerance) {
        // Hold the last position briefly, then clear. Never decay toward the
        // centre — that made the robot "slide" toward a phantom target.
        _trackedObject = null;
      }
    }

    _resultsController.add(mapped);
  }

  /// Acquires the camera stream for one user. Every call — including one that
  /// throws — must be balanced by exactly one [stopStream].
  Future<void> startStream() => _cameraLease.acquire();

  Future<void> _openCamera() async {
    await initialize();
    if (_camera?.value.isStreamingImages ?? false) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No camera available on this device');
    }
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      description,
      // 320x240 on most devices: the model input is 320x320 so anything
      // larger is wasted work in the YUV→tensor loop.
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420 // reliable separate U/V planes
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
      // The app is portrait-only; pin the preview to portrait too, so the
      // screen boxes line up whatever the phone's physical orientation.
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (e) {
        debugPrint('Camera: could not lock capture orientation: $e');
      }
      // Automatic mount detection reads gravity from the IMU.
      SensorService().startListening();
      _camera = controller;
      await controller.startImageStream(_onCameraImage);
      debugPrint('✅ Camera stream started');
    } catch (e) {
      debugPrint('❌ Camera start error: $e');
      _camera = null;
      try {
        await controller.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  void _onCameraImage(CameraImage cameraImage) {
    if (!_isInitialized) return;
    if (mount == PhoneMount.auto) {
      final g = SensorService().gravity;
      _mountDetector.update(g[0], g[1], g[2], DateTime.now());
    }
    final sensorOrientation = _camera?.description.sensorOrientation ?? 90;
    final rotation = frameRotation(sensorOrientation, upsideDown);
    _detector.lineMode = lineMode;
    _detector.processFrame(
      cameraImage,
      activeLabels: _activeFilters,
      rotation: rotation,
      // The preview shows the sensor picture turned by sensorOrientation.
      displayNet: (sensorOrientation - rotation + 360) % 360,
    );
  }

  /// Clockwise rotation that turns a camera frame upright for the model.
  /// The UI is portrait-only, so this depends only on the camera sensor's
  /// mounting in the phone and on whether the phone is upside down on the
  /// robot. Public for tests.
  static int frameRotation(int sensorOrientation, bool upsideDown) =>
      (sensorOrientation + (upsideDown ? 180 : 0)) % 360;

  /// Completes once the next camera frame has been processed (object
  /// detections, or a line result in [lineMode]), or after [timeout].
  Future<void> nextFrame({Duration timeout = const Duration(seconds: 2)}) {
    final next = lineMode
        ? _detector.lineResultsStream.first
        : _detector.resultsStream.first;
    return next.then<void>((_) {}).timeout(timeout, onTimeout: () {});
  }

  /// Releases one stream user. The camera is only disposed when nobody needs
  /// it; [force] releases every user.
  Future<void> stopStream({bool force = false}) =>
      _cameraLease.release(force: force);

  Future<void> _closeCamera() async {
    _lineSub?.cancel();
    _lineSub = null;
    _detectionSub?.cancel();
    _detectionSub = null;
    _prefSubscription?.cancel();
    _prefSubscription = null;
    _settingsSubscription?.cancel();
    _settingsSubscription = null;

    final cam = _camera;
    _camera = null;
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
        await cam.dispose();
      } catch (e) {
        debugPrint('❌ Camera stop error: $e');
      }
    }
    _detector.stop();
    _lastDetections = [];
    _trackedObject = null;
    _lineDetected = false;
    _lineOffsetX = 0.0;
    _isInitialized = false;
    _initFuture = null;
  }

  void dispose() {
    stopStream(force: true);
    _resultsController.close();
  }
}
