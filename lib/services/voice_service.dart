import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../utils/execution_logger.dart';

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

  /// Bumped by [stopListening]. A [startListening] that is still waiting for
  /// the permission dialog or engine start-up compares against it and backs
  /// out, so STOP during start-up can no longer leave the mic listening.
  int _session = 0;

  /// Consecutive recognizer errors, for restart back-off.
  int _errorStreak = 0;

  /// Errors that will not fix themselves by restarting the recognizer.
  static const Set<String> _fatalErrors = {
    'error_permission',
    'error_insufficient_permissions',
    'error_language_not_supported',
    'error_language_unavailable',
  };

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

  /// Voice messages go to the shared program log (visible to both the block
  /// and the Python runner) and to [logStream].
  void _log(String s) {
    ExecutionLogger().log(s);
    _logController.add(s);
  }

  /// Requests the mic permission and starts continuous recognition.
  /// Returns false if unavailable, denied, or stopped while starting.
  Future<bool> startListening() async {
    if (_wantListening) return _available;
    final session = ++_session;
    if (!await Permission.microphone.request().isGranted) {
      _log("⚠️ Microphone permission denied — allow it in the phone's Settings › Apps");
      return false;
    }
    if (session != _session) return false;
    try {
      if (!_initialized) {
        _available = await _speech.initialize(
          onError: _onError,
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              // Loudness only updates while a session is live; don't leave a
              // stale "loud" reading between sessions.
              _isLoud = false;
              if (_wantListening) _scheduleRestart();
            }
          },
        );
        _initialized = true;
      }
    } catch (e) {
      _log("Speech Init Error: $e");
      _available = false;
    }
    if (session != _session) return false;
    if (!_available) {
      _log("⚠️ Voice: speech recognition unavailable on this phone");
      return false;
    }
    _wantListening = true;
    _errorStreak = 0;
    _log("🎙️ Voice: listening");
    await _listen();
    return true;
  }

  void _onError(SpeechRecognitionError e) {
    _errorStreak++;
    if (_fatalErrors.contains(e.errorMsg)) {
      _log("⚠️ Voice stopped: ${e.errorMsg}");
      _wantListening = false;
      return;
    }
    // no_match / speech_timeout happen every few seconds of silence — normal.
    if (e.errorMsg != 'error_no_match' && e.errorMsg != 'error_speech_timeout') {
      _log("Speech Error: ${e.errorMsg}");
    }
  }

  /// Restarts the recognizer after a session ends. Backs off on repeated
  /// errors (e.g. offline with no on-device model) instead of hammering the
  /// engine every 100 ms.
  void _scheduleRestart() {
    final session = _session;
    final delayMs = _errorStreak <= 1 ? 100 : math.min(5000, 250 * (1 << math.min(_errorStreak, 5)));
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (session == _session) _listen();
    });
  }

  Future<void> _listen() async {
    if (!_wantListening || !_available) return;
    if (_speech.isListening) return;
    try {
      final started = await _speech.listen(
        onResult: (result) {
          _errorStreak = 0;
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
    _session++;
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
