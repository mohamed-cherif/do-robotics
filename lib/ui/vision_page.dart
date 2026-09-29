import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/vision_service.dart';
import '../services/vision_preferences.dart';
import 'painters/inference_painter.dart';
import 'vision_settings_page.dart';

class VisionPage extends StatefulWidget {
  const VisionPage({super.key});

  @override
  State<VisionPage> createState() => _VisionPageState();
}

class _VisionPageState extends State<VisionPage> {
  final VisionService _visionService = VisionService();
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _startVision();
  }

  Future<void> _startVision() async {
    try {
      await _visionService.initialize();
      await _visionService.startStream();
      if (mounted) {
        setState(() {
           _isReady = true;
           _activeFilters = List.from(_visionService.activeFilters);
        });
      }
    } catch (e) {
      if (mounted) {
        showDialog(context: context, builder: (c) => AlertDialog(
          title: const Text("Initialization Failed"),
          content: Text("Error: $e\nCheck Camera Permissions."),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
        ));
      }
    }
  }

  @override
  void dispose() {
    // Note: We might NOT want to dispose the service entirely if we want to keep it warm,
    // but for now, let's stop the stream to save battery.
    _visionService.stopStream(); 
    super.dispose();
  }

  // Filter State
  // Active filters (empty means all)
  List<String> _activeFilters = [];
  
  BoxFit _fit = BoxFit.contain; // Default to contain (Letterboxed) to see full FOV

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _visionService.cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00FFCC))),
      );
    }

    final controller = _visionService.cameraController!;
    // In Portrait, the PreviewSize (Landscape) means:
    // Display Width = Preview Height
    // Display Height = Preview Width
    final double previewW = controller.value.previewSize!.height;
    final double previewH = controller.value.previewSize!.width;
    final Size imageSize = Size(previewW, previewH);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview with Fit Control + Tap to Lock
          FittedBox(
            fit: _fit,
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: GestureDetector(
                onTapDown: (details) {
                  // Convert tap coordinates to normalized 0..1 space or image space
                  // detailed.localPosition is within the SizedBox (previewW, previewH)
                  // TFLite/VisionService detections are usually normalized 0..1 in ObjectDetectorService
                  // BUT previous code in InferencePainter handles raw bounding boxes or normalized?
                  // Let's check InferencePainter. Rect is typically normalized [0,1].
                  // ObjectDetectorService uses SSD MobileNet which outputs normalized coords [0,1].
                  
                  final dx = details.localPosition.dx / previewW;
                  final dy = details.localPosition.dy / previewH;
                  
                  // Use a small rect around the tap for intersection check
                  final tapRect = Rect.fromCenter(center: Offset(dx, dy), width: 0.1, height: 0.1);
                  
                  // Lock/Unlock Logic
                  if (!_visionService.isLocked) {
                    _visionService.lockOn(tapRect);
                  } else {
                    // Check if tap is near any detected object — if so, switch lock.
                    // Otherwise unlock (tap on empty space).
                    final hadLock = _visionService.targetLabel;
                    _visionService.unlock();
                    _visionService.lockOn(tapRect);
                    // If lockOn didn't find anything new, stay unlocked.
                    // If it locked onto the same object, treat as toggle-off.
                    if (_visionService.isLocked && _visionService.targetLabel == hadLock) {
                      _visionService.unlock();
                    }
                  }
                  setState(() {}); // Rebuild to show lock status
                },
                child: CameraPreview(controller),
              ),
            ),
          ),
          
          // 2. Inference Overlay
          LayoutBuilder(
            builder: (context, constraints) {
              return StreamBuilder<List<DetectedObjectData>>(
                stream: _visionService.resultsStream,
                initialData: const [],
                builder: (context, snapshot) {
                  var objects = snapshot.data ?? [];
                  
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                       CustomPaint(
                        painter: InferencePainter(
                          objects: objects,
                          absoluteImageSize: imageSize, 
                          widgetSize: Size(constraints.maxWidth, constraints.maxHeight),
                          fit: _fit,
                          lockedData: _visionService.isLocked ? _visionService.trackedObject : null, // Need to expose trackedObject
                        ),
                      ),
                      
                      // Tracking Debug Text
                      if (_visionService.isLocked)
                        Positioned(
                          top: 100,
                          left: 20,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.black54,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("LOCKED: ${_visionService.targetLabel}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                Text("Offset X: ${_visionService.targetOffsetX.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white)),
                                Text("Offset Y: ${_visionService.targetOffsetY.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        )
                    ],
                  );
                },
              );
            }
          ),
          
          // 3. UI Overlays (Back button)
          Positioned(
            top: 40,
            left: 20,
            child: FloatingActionButton.small(
              backgroundColor: Colors.black54,
              child: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                 _visionService.unlock();
                 Navigator.pop(context);
              },
            ),
          ),
          
          // 4. Fit Toggle Button
          Positioned(
             bottom: 100,
             right: 20,
             child: FloatingActionButton(
               backgroundColor: const Color(0xFF00FFCC),
               child: Icon(_fit == BoxFit.cover ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.black),
               onPressed: () {
                 setState(() {
                   _fit = _fit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
                 });
               },
             ),
          ),
          
          // 5. Model Indicator + settings shortcut
          Positioned(
            top: 50,
            right: 20,
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VisionSettingsPage()),
                );
                if (mounted) {
                  setState(() => _activeFilters = List.from(_visionService.activeFilters));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00FFCC), width: 1),
                ),
                child: StreamBuilder<List<DetectedObjectData>>(
                  stream: _visionService.resultsStream,
                  builder: (context, _) {
                    final ms = _visionService.averageInferenceMs;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.psychology, color: Color(0xFF00FFCC), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          ms > 0 ? "${ms.round()} ms" : _visionService.loadedModelName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.settings, color: Colors.white70, size: 16),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          
          // 6. Filter Selection Button
          Positioned(
            bottom: 30,
            left: 20, 
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF00FFCC),
                  icon: const Icon(Icons.filter_list, color: Colors.black),
                  label: Text(
                    _activeFilters.isEmpty ? "Detecting Everything" : "Detecting ${_activeFilters.length} Items",
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _showFilterDialog,
                ),
                if (_activeFilters.isNotEmpty) ...[
                   const SizedBox(width: 10),
                   FloatingActionButton.small(
                     backgroundColor: Colors.redAccent,
                     child: const Icon(Icons.clear, color: Colors.white),
                     onPressed: () async {
                        setState(() {
                          _activeFilters.clear();
                          _visionService.setActiveFilters([]);
                        });
                        await VisionPreferences.setEnabledLabels({});
                     },
                   )
                ]
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- Filter Dialog Logic ---

  // Curated list of useful tracking objects (shared with the settings page).
  final List<String> _allLabels = VisionPreferences.availableLabels;

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _FilterSheet(
            allLabels: _allLabels,
            selectedLabels: _activeFilters,
            onChanged: (newSelection) async {
               setState(() {
                 _activeFilters = newSelection;
                 _visionService.setActiveFilters(_activeFilters);
               });
               // Persist the filters so they don't reset!
               await VisionPreferences.setEnabledLabels(_activeFilters.toSet());
            },
          );
        }
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final List<String> allLabels;
  final List<String> selectedLabels;
  final ValueChanged<List<String>> onChanged;

  const _FilterSheet({required this.allLabels, required this.selectedLabels, required this.onChanged});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late List<String> _currentSelection;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedLabels);
  }

  @override
  Widget build(BuildContext context) {
    final filteredLabels = widget.allLabels.where((l) => l.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Column(
      children: [
        // Handle
        Container(
          height: 5, width: 40,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(5)),
        ),
        
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search objects...",
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00FFCC)),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        
        // List
        Expanded(
          child: ListView.builder(
            itemCount: filteredLabels.length,
            itemBuilder: (context, index) {
               final label = filteredLabels[index];
               final isSelected = _currentSelection.contains(label);
               return CheckboxListTile(
                 title: Text(label, style: const TextStyle(color: Colors.white)),
                 value: isSelected,
                 activeColor: const Color(0xFF00FFCC),
                 checkColor: Colors.black,
                 onChanged: (val) {
                   setState(() {
                     if (val == true) {
                       _currentSelection.add(label);
                     } else {
                       _currentSelection.remove(label);
                     }
                   });
                   widget.onChanged(_currentSelection);
                 },
               );
            },
          ),
        ),
      ],
    );
  }
}
