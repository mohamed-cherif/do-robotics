import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class MicrophonePage extends StatefulWidget {
  const MicrophonePage({super.key});

  @override
  State<MicrophonePage> createState() => _MicrophonePageState();
}

class _MicrophonePageState extends State<MicrophonePage> with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _wantsToListen = true;
  String _lastWords = '';

  double _noiseDb = 0.0;
  
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
       vsync: this,
       duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _initAudio();
  }

  Future<void> _initAudio() async {
    // Request permissions first
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.speech,
    ].request();

    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      if (mounted) {
        setState(() {
          _lastWords = "Microphone permission denied. Please enable it in settings.";
        });
      }
      // Note: We continue anyway, as noise meter might still work or speech might have its own fallback, 
      // but it's likely they will fail. Let's just return if microphone is denied.
      return;
    }

    // Removed Noise Meter entirely because it locks the microphone stream and breaks Speech To Text on Android.
    // Instead we will use speech_to_text's onSoundLevelChange.

    // Speech to Text
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
             setState(() {
                _isListening = (status == 'listening');
             });
             if ((status == 'done' || status == 'notListening') && _wantsToListen) {
                // 300 ms lets isListening clear so the restart guard doesn't block it.
                Future.delayed(const Duration(milliseconds: 300), () {
                   if (mounted && _wantsToListen) _startListening();
                });
             }
          }
        },
        onError: (errorNotification) {
          debugPrint("Speech error: ${errorNotification.errorMsg}");
          if (errorNotification.errorMsg != 'error_speech_timeout') {
            if (mounted) {
               setState(() {
                  _lastWords = "Error: ${errorNotification.errorMsg}";
               });
            }
          }
        }
      );
      
      if (mounted) {
        if (available) {
          _startListening();
        } else {
          setState(() {
            _lastWords = "Speech Recognition not available on this device.";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastWords = "Init Ex: $e";
        });
      }
    }
  }

  void _startListening() {
    _wantsToListen = true;
    if (_speech.isListening) return; // Prevent double listen
    try {
      _speech.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _lastWords = result.recognizedWords;
            });
          }
        },
        onSoundLevelChange: (level) {
          if (mounted) {
            setState(() {
              // Android onSoundLevelChange returns EXTRA_RMS_DB: range roughly -2..10.
              // Map that full range to 0..100 for the display bar.
              _noiseDb = ((level + 2) / 12 * 100).clamp(0.0, 100.0);
            });
          }
        },
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false, // Don't kill the session on mic errors
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
        ),
      );
      setState(() {
         _isListening = true;
         if (_lastWords.isEmpty || _lastWords.startsWith("Error")) _lastWords = "Listening now...";
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastWords = "Listen Ex: $e";
          _isListening = false;
        });
      }
    }
  }

  void _stopListening() {
    _wantsToListen = false;
    _speech.stop();
    setState(() {
       _isListening = false;
    });
  }

  @override
  void dispose() {
    _speech.stop();
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
    if (_noiseDb > 85) {
       progressColor = Colors.red;
    } else if (_noiseDb > 65) {
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
    );
  }
}
