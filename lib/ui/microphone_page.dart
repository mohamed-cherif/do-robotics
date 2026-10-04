import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/voice_service.dart';

class MicrophonePage extends StatefulWidget {
  const MicrophonePage({super.key});

  @override
  State<MicrophonePage> createState() => _MicrophonePageState();
}

class _MicrophonePageState extends State<MicrophonePage> with SingleTickerProviderStateMixin {
  // Uses the shared VoiceService: the speech plugin is a process-wide
  // singleton, and driving it directly from this page used to steal it from
  // (or break the auto-restart of) a running voice program.
  final VoiceService _voice = VoiceService();
  bool _isListening = false;
  bool _holdingMic = false;
  String _lastWords = '';

  double _noiseDb = 0.0; // 0..100 display level
  StreamSubscription<String>? _wordsSub;
  StreamSubscription<double>? _levelSub;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
       vsync: this,
       duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _wordsSub = _voice.wordsStream.listen((words) {
      if (words.isNotEmpty && mounted) setState(() => _lastWords = words);
    });
    _levelSub = _voice.levelStream.listen((level) {
      if (mounted) setState(() => _noiseDb = level);
    });
    _startListening();
  }

  Future<void> _startListening() async {
    if (_holdingMic) return;
    _holdingMic = true; // released in _stopListening / dispose
    final ok = await _voice.startListening();
    if (!mounted) return;
    setState(() {
      _isListening = ok;
      _lastWords = ok ? "Listening now..." : "Microphone unavailable.";
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            "Speech recognition couldn't start. Allow the microphone for this app, "
            "and check that a speech service (e.g. Google) is installed."),
        action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
        duration: const Duration(seconds: 6),
        persist: false, // with an action it would otherwise never go away
      ));
    }
  }

  Future<void> _stopListening() async {
    if (!_holdingMic) return;
    _holdingMic = false;
    await _voice.stopListening();
    if (mounted) setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _wordsSub?.cancel();
    _levelSub?.cancel();
    if (_holdingMic) {
      _holdingMic = false;
      _voice.stopListening();
    }
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Microphone Setup"),
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               _buildStatusCard(),
               const SizedBox(height: 24),
               _buildTranscriptCard(),
               const SizedBox(height: 24),
               _buildControlSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
             "Sound Level",
             style: TextStyle(
               fontSize: 16,
               color: Colors.grey[600],
               fontWeight: FontWeight.w600,
             ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
               Text(
                 _noiseDb.toStringAsFixed(1),
                 style: const TextStyle(
                   fontSize: 48,
                   fontWeight: FontWeight.bold,
                   color: Colors.black87,
                 ),
               ),
               const SizedBox(width: 8),
               const Text(
                 "%",
                 style: TextStyle(
                   fontSize: 20,
                   fontWeight: FontWeight.w600,
                   color: Colors.grey,
                 ),
               ),
            ],
          ),
          const SizedBox(height: 24),
          _buildVolumeIndicator(),
        ],
      ),
    );
  }

  Widget _buildVolumeIndicator() {
    // Map 0-100 level to 0.0 - 1.0 progress
    final double normalizedVolume = (_noiseDb / 100).clamp(0.0, 1.0);
    Color progressColor = Colors.green;
    // Red = what the "Loud Noise" block treats as loud (VoiceService.isLoud).
    if (_voice.isLoud) {
       progressColor = Colors.red;
    } else if (_noiseDb > 45) {
       progressColor = Colors.orange;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 12,
          width: constraints.maxWidth,
          decoration: BoxDecoration(
             color: Colors.grey[200],
             borderRadius: BorderRadius.circular(6),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: normalizedVolume,
            child: AnimatedContainer(
               duration: const Duration(milliseconds: 100),
               decoration: BoxDecoration(
                  color: progressColor,
                  borderRadius: BorderRadius.circular(6),
               ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildTranscriptCard() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                 const Icon(Icons.transcribe, color: Colors.blueAccent),
                 const SizedBox(width: 8),
                 Text(
                   "Live Transcript",
                   style: TextStyle(
                     fontSize: 16,
                     color: Colors.grey[600],
                     fontWeight: FontWeight.w600,
                   ),
                 ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _lastWords.isEmpty ? "Waiting for speech..." : _lastWords,
                  style: TextStyle(
                    fontSize: 20,
                    color: _lastWords.isEmpty ? Colors.grey[400] : Colors.black87,
                    fontStyle: _lastWords.isEmpty ? FontStyle.italic : FontStyle.normal,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSection() {
    return Center(
      child: Semantics(
        button: true,
        label: _isListening ? 'Stop listening' : 'Start listening',
        child: GestureDetector(
        onTap: () {
           if (_isListening) {
             _stopListening();
           } else {
             _startListening();
           }
        },
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final double scale = _isListening ? 1.0 + (_pulseController.value * 0.1) : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                   shape: BoxShape.circle,
                   color: _isListening ? Colors.redAccent : Colors.blueAccent,
                   boxShadow: _isListening ? [
                      BoxShadow(
                         color: Colors.redAccent.withValues(alpha: 0.4),
                         blurRadius: 20,
                         spreadRadius: _pulseController.value * 10,
                      )
                   ] : [],
                ),
                child: Icon(
                   _isListening ? Icons.mic : Icons.mic_none,
                   color: Colors.white,
                   size: 36,
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}
