import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech recognition (continuous dictation with auto-restart), loudness,
/// and text-to-speech. One instance shared by the block and Python runners.
class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final SpeechToText _speech = SpeechToText();
  FlutterTts? _tts;
  bool _initialized = false;
  bool _available = false;
  bool _wantListening = false;

  final StreamController<String> _wordsController = StreamController<String>.broadcast();
  /// Latest recognized text ('' after a phrase is consumed or on stop).
  Stream<String> get wordsStream => _wordsController.stream;
  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  String _lastWords = '';
  String get lastWords => _lastWords;
  bool _isLoud = false;
  bool get isLoud => _isLoud;
  bool get isListening => _wantListening;

  void _log(String s) => _logController.add(s);

  /// Requests the mic permission and starts continuous recognition.
  /// Returns false if unavailable.
  Future<bool> startListening() async {
    if (_wantListening) return _available;
    if (!await Permission.microphone.request().isGranted) {
      _log("⚠️ Microphone permission denied");
      return false;
    }
    try {
      if (!_initialized) {
        _available = await _speech.initialize(
          onError: (e) => _log("Speech Error: ${e.errorMsg}"),
          onStatus: (status) {
            if ((status == 'done' || status == 'notListening') && _wantListening) {
              // Short delay lets isListening clear before we restart.
              Future.delayed(const Duration(milliseconds: 100), _listen);
            }
          },
        );
        _initialized = true;
      }
    } catch (e) {
      _log("Speech Init Error: $e");
      _available = false;
    }
    if (!_available) {
      _log("⚠️ Voice: speech recognition unavailable");
      return false;
    }
    _wantListening = true;
    _log("🎙️ Voice: listening");
    await _listen();
    return true;
  }

  Future<void> _listen() async {
    if (!_wantListening || !_available) return;
    if (_speech.isListening) return;
    try {
      final started = await _speech.listen(
        onResult: (result) {
          if (!result.finalResult && result.recognizedWords.trim().length < 3) return;
          _lastWords = result.recognizedWords;
          _wordsController.add(_lastWords);
        },
        onSoundLevelChange: (level) {
          // Android: EXTRA_RMS_DB roughly -2..10; iOS: dBFS -160..0.
          _isLoud = Platform.isAndroid ? level > 5.0 : level > -40.0;
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 8),
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          partialResults: true,
        ),
      );
      if (!started) _log("⚠️ Voice: failed to start listening session");
    } catch (e) {
      _log("Speech Listen Error: $e");
    }
  }

  /// Clears the last recognized phrase (after a command matched).
  void consume() {
    _lastWords = '';
    _wordsController.add('');
  }

  Future<void> stopListening() async {
    _wantListening = false;
    _isLoud = false;
    _lastWords = '';
    _wordsController.add('');
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
  }

  /// Speaks [text] and waits until done.
  Future<void> say(String text) async {
    try {
      _tts ??= FlutterTts()..awaitSpeakCompletion(true);
      await _tts!.speak(text);
    } catch (e) {
      debugPrint("TTS error: $e");
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
